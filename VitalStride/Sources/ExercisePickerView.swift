// swiftlint:disable no_hardcoded_chinese
import DesignKit
import os
import SwiftData
import SwiftUI
import VitalModels
#if canImport(UIKit)
import UIKit
#endif

private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "ExercisePicker")

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var selectedExercises: [Exercise] = []
    @State private var visibleEquipment: Equipment?
    @State private var draggedEquipment: Equipment?
    @State private var cachedEquipmentGroups: [(Equipment, [Exercise])]?
    @FocusState private var isSearchFocused: Bool
    // MY-1249 + MY-1250 reconciliation: MY-1250 previously reset the card-grid
    // scroll to the top on filter/search change by writing `visibleEquipment`
    // and letting `.scrollPosition(id:)` push the offset. MY-1249 removed
    // that binding (its update lag caused the index-bar sync bug), so a
    // dedicated trigger is needed to keep the scroll-reset intent. Bumping
    // this token drives an `.onChange` inside the ScrollViewReader that calls
    // `gridProxy.scrollTo(...)` — decoupling scroll-reset from the (now
    // observation-only) `visibleEquipment` highlight state.
    @State private var scrollResetToken: Int = 0
    let selectionMode: SelectionMode

    private static let searchDebounceNanoseconds: UInt64 = 200_000_000

    enum SelectionMode {
        case single(onSelect: (Exercise) -> Void)
        case multiple(onConfirm: ([Exercise]) -> Void)
    }

    init(
        initialMuscleGroup: MuscleGroup? = nil,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.selectionMode = .single(onSelect: onSelect)
        self._selectedMuscleGroup = State(initialValue: initialMuscleGroup)
    }

    init(onConfirm: @escaping ([Exercise]) -> Void) {
        self.selectionMode = .multiple(onConfirm: onConfirm)
    }

    private var isMultiSelect: Bool {
        if case .multiple = selectionMode { return true }
        return false
    }

    private var equipmentGroups: [(Equipment, [Exercise])] {
        cachedEquipmentGroups ?? Self.computeEquipmentGroups(
            from: exercises,
            muscleGroup: selectedMuscleGroup,
            searchText: debouncedSearchText
        )
    }

    static nonisolated func computeEquipmentGroups(
        from exercises: [Exercise],
        muscleGroup: MuscleGroup?,
        searchText: String
    ) -> [(Equipment, [Exercise])] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !trimmed.isEmpty
        var buckets: [Equipment: [Exercise]] = [:]
        buckets.reserveCapacity(Equipment.allCases.count)

        for exercise in exercises {
            if let group = muscleGroup, exercise.muscleGroup != group { continue }
            if hasSearch {
                let matches = exercise.nameEn.localizedCaseInsensitiveContains(trimmed) ||
                    exercise.nameZh.localizedCaseInsensitiveContains(trimmed)
                if !matches { continue }
            }
            buckets[exercise.equipment, default: []].append(exercise)
        }

        return Equipment.allCases.compactMap { equipment in
            guard let items = buckets[equipment], !items.isEmpty else { return nil }
            return (equipment, items)
        }
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        String(localized: "动作库为空", comment: "Empty exercise library title"),
                        systemImage: "tray",
                        description: Text(String(localized: "请先导入预置动作库", comment: "Empty exercise library description"))
                    )
                } else {
                    exerciseCardGrid
                        .frame(maxWidth: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            floatingSearchAndFilterPanel
                        }
                }
            }
            .navigationTitle(String(localized: "选择动作", comment: "Exercise picker navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", comment: "Cancel button")) { dismiss() }
                }
                if isMultiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        confirmButton
                    }
                }
            }
            .onAppear {
                if cachedEquipmentGroups == nil {
                    cachedEquipmentGroups = Self.computeEquipmentGroups(
                        from: exercises,
                        muscleGroup: selectedMuscleGroup,
                        searchText: debouncedSearchText
                    )
                }
            }
            .onChange(of: exercises) { _, newExercises in
                cachedEquipmentGroups = Self.computeEquipmentGroups(
                    from: newExercises,
                    muscleGroup: selectedMuscleGroup,
                    searchText: debouncedSearchText
                )
            }
            .onChange(of: selectedMuscleGroup) { _, newGroup in
                let newGroups = Self.computeEquipmentGroups(
                    from: exercises,
                    muscleGroup: newGroup,
                    searchText: debouncedSearchText
                )
                cachedEquipmentGroups = newGroups
                // Unconditionally reset scroll to top when muscle group changes,
                // even if the new list still contains the current visibleEquipment
                // (e.g. both "全部" and "胸部" have "哑铃"). Otherwise the ScrollView
                // keeps the old offset and shows blank space at the bottom (MY-1250).
                visibleEquipment = newGroups.first?.0
                scrollResetToken &+= 1
            }
            .onChange(of: debouncedSearchText) { _, newText in
                let newGroups = Self.computeEquipmentGroups(
                    from: exercises,
                    muscleGroup: selectedMuscleGroup,
                    searchText: newText
                )
                cachedEquipmentGroups = newGroups
                // Same reasoning as muscle-group change: search-driven content
                // shrinks can strand the scroll offset past the new content end.
                visibleEquipment = newGroups.first?.0
                scrollResetToken &+= 1
            }
            .task(id: searchText) {
                let pending = searchText
                if pending == debouncedSearchText { return }
                try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
                if Task.isCancelled { return }
                debouncedSearchText = pending
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        let count = selectedIDs.count
        Button {
            if case .multiple(let onConfirm) = selectionMode {
                signposter.emitEvent("exercise_picker_confirm", "count=\(count)")
                onConfirm(selectedExercises)
                dismiss()
            }
        } label: {
            Text(String(localized: "添加 (\(count))", comment: "Confirm multi-select button with count"))
        }
        .disabled(count == 0)
        .accessibilityLabel(String(localized: "添加 \(count) 个动作", comment: "Confirm multi-select a11y label"))
    }

    // MARK: - Floating Search + Muscle Filter Panel (MY-1260)
    //
    // A single floating glass panel that combines the search input and the
    // muscle-group filter chips. Replaces the prior split layout (system
    // `.searchable` at the top + a separate `.liquidGlassBar` chip strip
    // at the bottom) that felt like two disconnected surfaces. The panel:
    //
    // - Sits above the safe-area with symmetric horizontal padding so it
    //   reads as a floating slab, not a bar glued to the edges.
    // - Uses the existing `.liquidGlassBar` helper for the material (gated
    //   `.glassEffect` on iOS 26+, DesignKit card fallback below) and
    //   respects Reduce Transparency by dropping to an opaque card.
    // - Hosts two rows separated by a 1pt hairline: search input on top,
    //   muscle-group chips on the bottom. The chips row remains horizontal
    //   scroll but the whole panel is one hit surface.
    //
    // Debounce + `debouncedSearchText` (`.task(id: searchText)`) is
    // preserved verbatim — only the outer chrome changes.

    private static let panelHorizontalInset: CGFloat = 12
    private static let panelBottomInset: CGFloat = 8
    private static let panelInnerHPadding: CGFloat = 14
    private static let panelInnerVPadding: CGFloat = 10

    private var floatingSearchAndFilterPanel: some View {
        VStack(spacing: 8) {
            searchRow
            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: 1)
                .accessibilityHidden(true)
            muscleGroupChipsRow
        }
        .padding(.horizontal, Self.panelInnerHPadding)
        .padding(.vertical, Self.panelInnerVPadding)
        .modifier(PanelSurfaceModifier(theme: theme, opaque: reduceTransparency))
        .padding(.horizontal, Self.panelHorizontalInset)
        .padding(.bottom, Self.panelBottomInset)
    }

    // MARK: Search row (self-drawn — replaces system `.searchable`)

    @ViewBuilder
    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(theme.neutrals.text3)
                .accessibilityHidden(true)

            TextField(
                String(localized: "搜索动作", comment: "Exercise search prompt"),
                text: $searchText
            )
            // Use `.body` text style (dynamic-type scaled) instead of
            // `TypeScale.body` (fixed 14pt) so the search input honors the
            // user's preferred Content Size Category. This is the only
            // field in the panel that accepts free-form text input and
            // reviewer feedback flagged fixed sizing as an accessibility
            // regression versus the prior system `.searchable` field.
            .font(.system(.body))
            .foregroundStyle(theme.neutrals.text1)
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            #if canImport(UIKit)
            .textInputAutocapitalization(.never)
            #endif
            .submitLabel(.search)
            .focused($isSearchFocused)
            .accessibilityLabel(String(localized: "搜索动作", comment: "Exercise search prompt"))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debouncedSearchText = ""
                } label: {
                    // Icon renders at its intrinsic size but the button's hit
                    // frame is 44×44pt so it satisfies Constitution §H (44pt
                    // minimum hit target) even when the visible glyph is
                    // smaller.
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body))
                        .foregroundStyle(theme.neutrals.text3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "清除搜索", comment: "Clear search a11y label"))
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: Muscle-group chips row (segmented-like, native-feel)

    private var muscleGroupChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                muscleChip(
                    label: String(localized: "全部", comment: "All muscle groups filter chip label"),
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    muscleChip(
                        label: group.localizedName,
                        isSelected: selectedMuscleGroup == group
                    ) {
                        selectedMuscleGroup = group
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func muscleChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(TypeScale.meta)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? theme.primary.onPrimary : theme.neutrals.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(theme.primary.primary)
                        } else {
                            // Transparent capsule keeps the row visually
                            // lighter (segmented-like) instead of the prior
                            // dense inner-fill chip strip. A hairline stroke
                            // keeps each pill legible against the glass.
                            Capsule().stroke(theme.neutrals.border, lineWidth: 1)
                        }
                    }
                )
                // Extend the tap area vertically beyond the ~32pt visual
                // capsule so the *hit* target satisfies Constitution §H
                // (≥44pt). `contentShape` picks up the padded frame so a
                // finger landing on the invisible top/bottom band above/below
                // the capsule still hits this chip.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Card Grid
    //
    // Horizontal insets are kept stable regardless of index-bar visibility so
    // that switching muscle groups between multi-section and single-section
    // states does not reflow `LazyVGrid` column widths (MY-1251). The trailing
    // reserve equals the space the index bar physically occupies
    // (`EquipmentIndexBar.hitWidth` + its trailing padding) and is applied
    // whether or not the bar is currently rendered.
    static let cardGridHorizontalInset: CGFloat = 16
    static let cardGridVerticalInset: CGFloat = 16
    static let cardGridIndexBarReserve: CGFloat = EquipmentIndexBar.hitWidth + 4

    /// Leading inset used by the card grid. Independent of index-bar
    /// visibility by design (MY-1251 / MY-1258): the parameter exists so the
    /// invariant is expressible and testable, not because the value varies.
    static func cardGridLeadingInset(showsIndexBar _: Bool) -> CGFloat {
        cardGridHorizontalInset
    }

    /// Trailing inset used by the card grid. Always reserves space for the
    /// index bar whether or not the bar is currently rendered, so that
    /// switching between multi-section and single-section muscle groups
    /// cannot reflow `LazyVGrid` column widths.
    static func cardGridTrailingInset(showsIndexBar _: Bool) -> CGFloat {
        cardGridHorizontalInset + cardGridIndexBarReserve
    }

    /// Width available to the `LazyVGrid` columns after the fixed horizontal
    /// insets are removed from `containerWidth`. Must be invariant across
    /// `showsIndexBar` transitions.
    static func cardGridAvailableWidth(containerWidth: CGFloat, showsIndexBar: Bool) -> CGFloat {
        let used = cardGridLeadingInset(showsIndexBar: showsIndexBar)
            + cardGridTrailingInset(showsIndexBar: showsIndexBar)
        return max(0, containerWidth - used)
    }

    @ViewBuilder
    private var exerciseCardGrid: some View {
        if equipmentGroups.isEmpty {
            emptyState
        } else {
            let equipments = equipmentGroups.map { $0.0 }
            let showsIndexBar = equipments.count >= 2
            ScrollViewReader { gridProxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(equipmentGroups, id: \.0) { equipment, items in
                                equipmentSection(equipment: equipment, exercises: items)
                                    .id(equipment)
                            }
                        }
                        .padding(.vertical, Self.cardGridVerticalInset)
                        .padding(.leading, Self.cardGridLeadingInset(showsIndexBar: showsIndexBar))
                        .padding(.trailing, Self.cardGridTrailingInset(showsIndexBar: showsIndexBar))
                        .scrollTargetLayout()
                    }
                    // MY-1249: use onScrollTargetVisibilityChange (iOS 18) instead
                    // of .scrollPosition(id:anchor:.top) — the latter's binding
                    // updates lagged during finger scroll with lazy sections, so
                    // the right-side index bar highlight fell out of sync.
                    //
                    // Threshold MUST stay low (see `visibilityThreshold`). Each
                    // scroll target is a whole equipment section, and sections
                    // can be viewport-taller (dumbbell alone has ≥200 exercises);
                    // the default 0.5 threshold would omit any section that never
                    // reaches 50% visibility, hiding the actual top-visible
                    // section from `visibleIds`. Locked by
                    // `ExercisePickerIndexSyncTests.visibilityThresholdIsLowEnoughForTallSections`.
                    .onScrollTargetVisibilityChange(
                        idType: Equipment.self,
                        threshold: Self.visibilityThreshold
                    ) { visibleIds in
                        Self.applyVisibleIds(
                            visibleIds,
                            in: equipments,
                            using: applyVisibleEquipment
                        )
                    }

                    if showsIndexBar {
                        indexBarSlot(equipments: equipments, gridProxy: gridProxy)
                    }
                }
                .overlay(alignment: .center) {
                    if let dragged = draggedEquipment {
                        sectionPreviewPopup(equipment: dragged)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: draggedEquipment)
                .onChange(of: equipmentGroups.map(\.0)) { _, newEquipments in
                    if let current = visibleEquipment, !newEquipments.contains(current) {
                        visibleEquipment = newEquipments.first
                    } else if visibleEquipment == nil {
                        visibleEquipment = newEquipments.first
                    }
                }
                // MY-1250 reconciliation: filter/search change bumps
                // `scrollResetToken`; here we imperatively scroll the grid to
                // the top of the first section. This restores the "reset to
                // top on filter change" behavior that MY-1250 originally got
                // from `.scrollPosition(id: $visibleEquipment)` (removed by
                // MY-1249 to fix index-bar sync lag).
                .onChange(of: scrollResetToken) { _, _ in
                    guard let first = equipmentGroups.first?.0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        gridProxy.scrollTo(first, anchor: .top)
                    }
                }
            }
        }
    }

    // MY-1249: index bar wrapper anchoring the bar in the middle-bottom band
    // of the vertical column instead of stretching the full column height.
    // Top spacer is unbounded; bottom spacer capped at `indexBarBottomInset`
    // so the compact bar drifts toward — but does not touch — the bottom.
    @ViewBuilder
    private func indexBarSlot(equipments: [Equipment], gridProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            EquipmentIndexBar(
                equipments: equipments,
                activeEquipment: visibleEquipment ?? draggedEquipment,
                onSelect: { equipment in
                    withAnimation(.easeOut(duration: 0.2)) {
                        gridProxy.scrollTo(equipment, anchor: .top)
                    }
                    visibleEquipment = equipment
                },
                onDragChanged: { equipment in
                    draggedEquipment = equipment
                },
                onDragEnded: {
                    draggedEquipment = nil
                }
            )
            .padding(.trailing, 4)
            Spacer(minLength: 0)
                .frame(maxHeight: Self.indexBarBottomInset)
        }
    }

    /// Bottom-spacer cap that biases the index bar toward the middle-bottom
    /// band of the column. The top spacer is unbounded and consumes the rest.
    private static let indexBarBottomInset: CGFloat = 96

    /// MY-1249: `onScrollTargetVisibilityChange` threshold, expressed as the
    /// fraction of the target that must be on-screen for it to enter
    /// `visibleIds`. Kept intentionally near-zero because each scroll target
    /// here is a whole `equipmentSection`, and a single section (e.g. dumbbell,
    /// ≥200 exercises) can be far taller than the viewport. With the default
    /// `0.5`, such a section can never cross 50% visibility and would be
    /// silently omitted from the callback — leaving the highlight stale on
    /// the previous section. `0.01` = "any pixel visible → include".
    static let visibilityThreshold: Double = 0.01

    /// Test-facing accessor for the index-bar hit-target lane width so
    /// `ExercisePickerIndexSyncTests` can lock Constitution §H without
    /// piercing the `private` scope of `EquipmentIndexBar`.
    static var equipmentIndexBarHitWidth: CGFloat { EquipmentIndexBar.hitWidth }

    /// Callback bridge used by the SwiftUI `onScrollTargetVisibilityChange`
    /// closure. `MainActor`-isolated because it writes `@State`.
    @MainActor
    private func applyVisibleEquipment(_ equipment: Equipment?) {
        visibleEquipment = equipment
    }

    /// MY-1249: pure entry-point mirroring what
    /// `onScrollTargetVisibilityChange` does in production — takes the raw
    /// visible-ids callback payload plus the current equipment order, picks
    /// the highlight, and applies it via the supplied setter. Extracted so
    /// tests can exercise the full callback path (not just the ordering
    /// helper) with representative inputs, including the tall-section case
    /// (single id reported) that motivates the low `visibilityThreshold`.
    static func applyVisibleIds(
        _ visibleIds: [Equipment],
        in order: [Equipment],
        using setter: (Equipment?) -> Void
    ) {
        setter(firstVisibleEquipment(from: visibleIds, in: order))
    }

    /// MY-1249: pick the section that should own the index-bar highlight
    /// given the set of currently visible section ids. Prefer the first
    /// visible section in equipment order (i.e. the top-most on-screen).
    /// Falls back to `nil` when no ids are reported (empty content).
    static func firstVisibleEquipment(
        from visibleIds: [Equipment],
        in order: [Equipment]
    ) -> Equipment? {
        guard !visibleIds.isEmpty else { return nil }
        let visibleSet = Set(visibleIds)
        return order.first(where: visibleSet.contains) ?? visibleIds.first
    }

    private func sectionPreviewPopup(equipment: Equipment) -> some View {
        VStack(spacing: 8) {
            Image(systemName: equipment.sfSymbol)
                .font(.system(size: 48, weight: .light))
            Text(equipment.localizedName)
                .font(.title3)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(minWidth: 140, minHeight: 140)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !debouncedSearchText.isEmpty {
            ContentUnavailableView.search(text: debouncedSearchText)
        } else if let group = selectedMuscleGroup {
            ContentUnavailableView(
                String(localized: "没有动作", comment: "No exercises found title"),
                systemImage: "dumbbell",
                description: Text(String(localized: "\(group.localizedName)分类下暂无动作", comment: "No exercises in muscle group description"))
            )
        } else {
            ContentUnavailableView(
                String(localized: "没有动作", comment: "No exercises found title"),
                systemImage: "dumbbell",
                description: Text(String(localized: "暂无可用动作", comment: "No exercises available description"))
            )
        }
    }

    private func equipmentSection(equipment: Equipment, exercises: [Exercise]) -> some View {
        let color = categoryColor(categoryColorIndex(for: equipment), theme: theme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: equipment.sfSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(equipment.localizedName.uppercased())
                    .font(TypeScale.meta)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.neutrals.text2)
                Text("\(exercises.count)")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text3)
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(exercises) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isSelected: selectedIDs.contains(exercise.persistentModelID),
                        showsSelectionIndicator: isMultiSelect
                    ) {
                        handleCardTap(exercise)
                    }
                }
            }
        }
    }

    private func handleCardTap(_ exercise: Exercise) {
        switch selectionMode {
        case .single(let onSelect):
            onSelect(exercise)
            dismiss()
        case .multiple:
            toggleSelection(exercise)
        }
    }

    private func toggleSelection(_ exercise: Exercise) {
        let id = exercise.persistentModelID
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            selectedExercises.removeAll { $0.persistentModelID == id }
        } else {
            selectedIDs.insert(id)
            selectedExercises.append(exercise)
        }
    }
}

// MARK: - Panel Surface Modifier

/// Wraps the floating search + filter panel with the shared Liquid Glass
/// material, a hairline border, and the DesignKit card corner radius. When
/// `Reduce Transparency` is enabled the material collapses to an opaque
/// DesignKit card fill so the panel remains legible.
private struct PanelSurfaceModifier: ViewModifier {
    let theme: Theme
    let opaque: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if opaque {
            content
                .background(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(theme.neutrals.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(theme.neutrals.border, lineWidth: 1)
                )
        } else {
            content
                .liquidGlassBar(theme: theme, cornerRadius: Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(theme.neutrals.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    @Environment(\.theme) private var theme
    let exercise: Exercise
    let isSelected: Bool
    let showsSelectionIndicator: Bool
    let onTap: () -> Void

    private var equipmentColor: Color {
        categoryColor(categoryColorIndex(for: exercise.equipment), theme: theme)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: exercise.equipment.sfSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(equipmentColor)
                        .frame(width: 34, height: 34)
                        .background(equipmentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Spacer(minLength: 0)
                    if showsSelectionIndicator {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? theme.primary.primary : theme.neutrals.text3)
                            .accessibilityHidden(true)
                    }
                }

                mediaPreview

                Text(exercise.localizedName)
                    .font(TypeScale.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                muscleTag
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(12)
            .background(theme.neutrals.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        isSelected ? theme.primary.primary : theme.neutrals.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var muscleTag: some View {
        if let muscle = exercise.primaryMuscles.first {
            Text(MuscleTranslation.chineseName(for: muscle))
                .font(TypeScale.meta)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(theme.neutrals.inner)
                .foregroundStyle(theme.neutrals.text2)
                .clipShape(Capsule())
        }
    }

    // Media display point reserved for future authorized media assets. When
    // `mediaKey` is nil (the current default for every seeded exercise), the
    // ViewBuilder returns nothing — no placeholder frame, no image fetch.
    @ViewBuilder
    private var mediaPreview: some View {
        if exercise.mediaKey != nil {
            EmptyView()
        }
    }
}

// MARK: - Equipment Index Bar

private struct EquipmentIndexBar: View {
    @Environment(\.theme) private var theme
    let equipments: [Equipment]
    let activeEquipment: Equipment?
    let onSelect: (Equipment) -> Void
    let onDragChanged: (Equipment) -> Void
    let onDragEnded: () -> Void

    private static let verticalPadding: CGFloat = 8
    private static let barWidth: CGFloat = 28
    private static let iconSize: CGFloat = 22
    private static let iconSpacing: CGFloat = 2
    // Constitution §H: interactive hit targets must be at least 44pt.
    static let hitWidth: CGFloat = 44

    /// MY-1249: intrinsic (icons * iconSize + gaps + padding) so the bar
    /// no longer stretches to fill the column — outer VStack + spacers
    /// position it in the middle-bottom band.
    private var intrinsicHeight: CGFloat {
        let iconCount = CGFloat(max(equipments.count, 1))
        let gaps = max(iconCount - 1, 0) * Self.iconSpacing
        return iconCount * Self.iconSize + gaps + Self.verticalPadding * 2
    }

    var body: some View {
        let height = intrinsicHeight
        return ZStack(alignment: .trailing) {
            VStack(spacing: Self.iconSpacing) {
                ForEach(equipments, id: \.self) { equipment in
                    let active = activeEquipment == equipment
                    Image(systemName: equipment.sfSymbol)
                        .font(.system(size: 11, weight: active ? .bold : .medium))
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .foregroundStyle(active ? theme.primary.onPrimary : theme.neutrals.text2)
                        .background(active ? theme.primary.primary : Color.clear)
                        .clipShape(Circle())
                        .accessibilityLabel(equipment.localizedName)
                }
            }
            .frame(width: Self.barWidth)
            .padding(.vertical, Self.verticalPadding)
            .liquidGlassCapsule(theme: theme)
        }
        .frame(width: Self.hitWidth, height: height, alignment: .trailing)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let equipment = equipmentAt(
                        y: value.location.y,
                        totalHeight: height
                    ) else { return }
                    if equipment != activeEquipment {
                        onSelect(equipment)
                        triggerSelectionHaptic()
                    }
                    onDragChanged(equipment)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "器械分区索引", comment: "Equipment section index bar a11y label"))
    }

    private func equipmentAt(y: CGFloat, totalHeight: CGFloat) -> Equipment? {
        guard !equipments.isEmpty else { return nil }
        let usable = max(totalHeight - Self.verticalPadding * 2, 1)
        let clamped = min(max(y - Self.verticalPadding, 0), usable - 0.001)
        let rowHeight = usable / CGFloat(equipments.count)
        let index = Int(clamped / rowHeight)
        let bounded = min(max(index, 0), equipments.count - 1)
        return equipments[bounded]
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit) && !os(watchOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
