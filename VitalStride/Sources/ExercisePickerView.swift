// swiftlint:disable no_hardcoded_chinese
import DesignKit
import os
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
#if canImport(UIKit)
import UIKit
#endif

private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "ExercisePicker")

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedEquipmentFilter: Equipment?
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var selectedExercises: [Exercise] = []
    @State private var visibleEquipment: ExerciseSection?
    @State private var presentedSheet: PickerSheet?
    @State private var pendingDeletion: Exercise?
    @State private var saveFailed = false
    @State private var indexHUD: ExerciseSection?
    @State private var draggedEquipment: ExerciseSection?
    /// MY-1338: number of distinct equipment sections the current drag
    /// gesture has visited. Reset on drag start, reported via
    /// `exercisePickerIndexScrubbed(count:)` on drag end, so we can watch
    /// for high-count bursts that indicate the highlight is racing through
    /// neighbours instead of settling on the finger's target.
    @State private var dragScrubCount: Int = 0
    @State private var cachedEquipmentGroups: [(ExerciseSection, [Exercise])]?
    // MY-1249 + MY-1250 reconciliation: MY-1250 previously reset the card-grid
    // scroll to the top on filter/search change by writing `visibleEquipment`
    // and letting `.scrollPosition(id:)` push the offset. MY-1249 removed
    // that binding (its update lag caused the index-bar sync bug), so a
    // dedicated trigger is needed to keep the scroll-reset intent. Bumping
    // this token drives an `.onChange` inside the ScrollViewReader that calls
    // `gridProxy.scrollTo(...)` — decoupling scroll-reset from the (now
    // observation-only) `visibleEquipment` highlight state.
    @State private var scrollResetToken: Int = 0
    // MY-1272: scroll target for the next `scrollResetToken` bump. Search
    // resets always anchor to the first section; muscle-group changes
    // prefer the current `visibleEquipment` when it survives (see
    // `resolveMuscleGroupScrollAnchor`). Captured at the moment the token
    // bumps so the `.onChange(scrollResetToken)` handler picks the correct
    // section without re-deriving intent.
    @State private var pendingScrollAnchor: ExerciseSection?
    // Measured height of the floating search+filter panel, used ONLY on the
    // iOS 18 fallback path. There the panel is a non-layout `.overlay` (NOT
    // `.safeAreaInset`) so it cannot feed back into the scroll grid's
    // safe-area during placement — that feedback produced a non-convergent
    // `LazyVGrid`/`SafeAreaInsets.resolve` relayout that pinned the main
    // thread at 100% CPU. We instead reserve an equivalent STATIC bottom
    // scroll margin from this measured height. The chain is convergent: panel
    // height is intrinsic (does not depend on the margin it drives). On iOS 26
    // the panel is a `.safeAreaBar` and this stays 0.
    @State private var panelHeight: CGFloat = 0

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

    private var equipmentGroups: [(ExerciseSection, [Exercise])] {
        cachedEquipmentGroups ?? Self.computeEquipmentGroups(
            from: exercises,
            muscleGroup: selectedMuscleGroup,
            searchText: debouncedSearchText
        )
    }

    private var filteredEquipmentGroups: [(ExerciseSection, [Exercise])] {
        filteredEquipmentGroups(for: selectedEquipmentFilter)
    }

    private func filteredEquipmentGroups(
        for equipmentFilter: Equipment?
    ) -> [(ExerciseSection, [Exercise])] {
        guard let equipmentFilter else { return equipmentGroups }
        return equipmentGroups.compactMap { section, exercises in
            let filtered = exercises.filter { $0.equipment == equipmentFilter }
            return filtered.isEmpty ? nil : (section, filtered)
        }
    }

    private var availableEquipmentFilters: [Equipment] {
        let available = equipmentGroups.flatMap { $0.1.map(\.equipment) }
        return Equipment.allCases.filter { available.contains($0) }
    }

    static nonisolated func computeEquipmentGroups(
        from exercises: [Exercise],
        muscleGroup: MuscleGroup?,
        searchText: String
    ) -> [(ExerciseSection, [Exercise])] {
        ExercisePickerSectionGrouping.groupedSections(
            from: exercises,
            muscleGroup: muscleGroup,
            searchText: searchText
        )
    }

    // Keep existing unlabeled trailing-closure calls resolving to onConfirm.
    @_disfavoredOverload
    init(onSelectMultiple: @escaping ([Exercise]) -> Void) {
        self.selectionMode = .multiple(onConfirm: onSelectMultiple)
    }

    static let gridColumnCount = 2
    static let muscleSidebarWidth: CGFloat = 64

    private var exerciseRevisions: [ExercisePickerRevision] {
        exercises.map { ExercisePickerRevision(id: $0.persistentModelID, nameEn: $0.nameEn,
                                              nameZh: $0.nameZh, muscle: $0.muscleGroup, equipment: $0.equipment) }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.gridColumnCount)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                muscleSidebar
                exerciseCardGrid
                    .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .modifier(FloatingPanelAttachment(panelHeight: $panelHeight, panel: floatingSearchAndFilterPanel))
            .navigationTitle(String(localized: "选择动作", comment: "Exercise picker navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", comment: "Cancel button")) { dismiss() }
                        .foregroundStyle(theme.foreground)
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .create:
                    PickerExerciseEditor(exercise: nil, initialGroup: selectedMuscleGroup) { refreshGroups() }
                case .edit(let exercise):
                    PickerExerciseEditor(exercise: exercise, initialGroup: nil) { refreshGroups() }
                case .detail(let exercise):
                    exerciseDetail(exercise)
                }
            }
            .confirmationDialog(String(localized: "picker.delete.title", comment: "Delete custom exercise confirmation"),
                                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
                Button(String(localized: "picker.delete", comment: "Delete custom exercise"), role: .destructive) {
                    if let exercise = pendingDeletion { deleteCustomExercise(exercise) }
                    pendingDeletion = nil
                }
            } message: {
                Text(String(localized: "picker.delete.message", comment: "Delete custom exercise explanation"))
            }
            .alert(String(localized: "picker.save.failed", comment: "Exercise save failure"), isPresented: $saveFailed) {
                Button(String(localized: "picker.ok", comment: "Dismiss exercise error"), role: .cancel) {}
            }
            .onAppear { refreshGroups() }
            .task(id: indexHUD) {
                guard indexHUD != nil else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                indexHUD = nil
            }
            .onChange(of: exerciseRevisions) { _, _ in
                let newExercises = exercises
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
                // MY-1272: on muscle-group change, prefer scrolling to the
                // user's currently-visible equipment section when it
                // survives the filter. Falls back to the first section of
                // the new list (preserving the MY-1250 fallback) when the
                // equipment is gone. See `resolveMuscleGroupScrollAnchor`.
                let anchor = Self.resolveMuscleGroupScrollAnchor(
                    previouslyVisible: visibleEquipment,
                    in: newGroups.map(\.0)
                )
                visibleEquipment = anchor
                pendingScrollAnchor = anchor
                scrollResetToken &+= 1
            }
            .onChange(of: selectedEquipmentFilter) { _, newFilter in
                let newGroups = filteredEquipmentGroups(for: newFilter)
                let anchor = newGroups.first?.0
                visibleEquipment = anchor
                pendingScrollAnchor = anchor
                scrollResetToken &+= 1
            }
            .onChange(of: debouncedSearchText) { _, newText in
                let newGroups = Self.computeEquipmentGroups(
                    from: exercises,
                    muscleGroup: selectedMuscleGroup,
                    searchText: newText
                )
                cachedEquipmentGroups = newGroups
                // MY-1272: search-driven content changes keep the historical
                // "reset to first section" behavior — the user changed
                // intent, so returning to the top is correct (search bar +
                // parent MY-1271 acceptance criteria explicitly preserve
                // this path). MY-1259: routed through
                // `resolveSearchScrollAnchor` so the policy (including
                // empty-result `nil`) is directly testable, mirroring the
                // muscle-group path.
                let anchor = Self.resolveSearchScrollAnchor(
                    in: newGroups.map(\.0)
                )
                visibleEquipment = anchor
                pendingScrollAnchor = anchor
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

    private func refreshGroups() {
        cachedEquipmentGroups = Self.computeEquipmentGroups(
            from: exercises, muscleGroup: selectedMuscleGroup, searchText: debouncedSearchText
        )
    }

    static let panelHorizontalInset: CGFloat = 12
    // Retained for clients checking the historical search hit-target contract.
    static let collapsedSearchDiameter: CGFloat = 44

    private var floatingSearchAndFilterPanel: some View {
        PickerBottomBar(searchText: $searchText, selectedCount: selectedIDs.count,
                        isMultiSelect: isMultiSelect, onCreate: { presentedSheet = .create }, onConfirm: {
            if case .multiple(let onConfirm) = selectionMode {
                signposter.emitEvent("exercise_picker_confirm", "count=\(selectedIDs.count)")
                onConfirm(selectedExercises)
            }
            dismiss()
        })
        .padding(.horizontal, Self.panelHorizontalInset)
        .padding(.bottom, 8)
    }

    private var equipmentFilterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                equipmentFilterChip(
                    label: String(localized: "全部器械", comment: "All equipment filters"),
                    value: nil
                )
                ForEach(availableEquipmentFilters, id: \.self) { equipment in
                    equipmentFilterChip(
                        label: equipment.localizedName,
                        value: equipment
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func equipmentFilterChip(
        label: String,
        value: Equipment?
    ) -> some View {
        let isSelected = selectedEquipmentFilter == value
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                selectedEquipmentFilter = value
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(
                    isSelected ? theme.onInteractiveAccent : theme.neutrals.text1
                )
                .background(
                    isSelected ? theme.interactiveAccent : theme.neutrals.inner,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var muscleSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                muscleButton(nil)
                ForEach(MuscleGroup.allCases, id: \.self) { muscleButton($0) }
            }.padding(.vertical, 12)
        }
        .frame(width: Self.muscleSidebarWidth)
        .contentMargins(.bottom, panelHeight, for: .scrollContent)
        .background(theme.inner.opacity(0.5))
        .accessibilityIdentifier("exercise_picker_muscle_sidebar")
    }

    private func muscleButton(_ group: MuscleGroup?) -> some View {
        let selected = selectedMuscleGroup == group
        let count = selectedExercises.filter { group == nil || $0.muscleGroup == group }.count
        let label = group?.localizedName ?? String(localized: "全部", comment: "All muscle groups")
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                selectedMuscleGroup = group
            }
        } label: {
            VStack(spacing: 3) {
                Text(label).font(.caption.weight(selected ? .bold : .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: false)
                if count > 0 {
                    Text("\(count)").font(.caption2.bold()).monospacedDigit()
                        .padding(.horizontal, 6).background(theme.accentSubtle, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? theme.accent : theme.foreground)
            .background(selected ? theme.accentSubtle : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(label)
        .accessibilityValue(String(localized: "picker.selected.count \(count)", comment: "Selected exercise count in muscle group"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func exerciseContextMenu(_ exercise: Exercise) -> some View {
        Button(String(localized: "picker.details", comment: "Exercise details"), systemImage: "info.circle") {
            presentedSheet = .detail(exercise)
        }
        Button(String(localized: "picker.select", comment: "Choose or toggle exercise"), systemImage: "checkmark.circle") {
            handleCardTap(exercise)
        }
        if exercise.isCustom {
            Button(String(localized: "picker.edit", comment: "Edit custom exercise"), systemImage: "pencil") {
                presentedSheet = .edit(exercise)
            }
            Button(String(localized: "picker.delete", comment: "Delete custom exercise"), systemImage: "trash", role: .destructive) {
                pendingDeletion = exercise
            }
            .disabled(!PickerExerciseEditor.canDelete(exercise))
        }
    }

    private func exerciseDetail(_ exercise: Exercise) -> some View {
        NavigationStack {
            Form {
                LabeledContent(String(localized: "picker.name.en", comment: "English exercise name"), value: exercise.nameEn)
                LabeledContent(String(localized: "picker.name.zh", comment: "Chinese exercise name"), value: exercise.nameZh)
                Text(exercise.muscleGroup.localizedName)
                Text(exercise.equipment.localizedName)
                ForEach(exercise.primaryMuscles, id: \.self) { Text(MuscleTranslation.chineseName(for: $0)) }
                DesignButton(String(localized: "picker.select", comment: "Select exercise"), fullWidth: true) {
                    presentedSheet = nil
                    handleCardTap(exercise)
                }
            }
            .navigationTitle(exercise.localizedName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "picker.done", comment: "Close exercise details")) { presentedSheet = nil }
                }
            }
        }
    }

    private func deleteCustomExercise(_ exercise: Exercise) {
        guard PickerExerciseEditor.canDelete(exercise) else { return }
        modelContext.delete(exercise)
        do {
            try modelContext.save()
            selectedIDs.remove(exercise.persistentModelID)
            selectedExercises.removeAll { $0.persistentModelID == exercise.persistentModelID }
            refreshGroups()
        } catch {
            modelContext.insert(exercise)
            saveFailed = true
        }
    }

    // MARK: - Card Grid
    //
    // Horizontal insets are kept stable regardless of index-bar visibility so
    // that switching muscle groups between multi-section and single-section
    // states does not reflow `LazyVGrid` column widths (MY-1251). The trailing
    // reserve equals the space the index bar physically occupies
    // (`EquipmentIndexBar.hitWidth` + its trailing padding) and is applied
    // whether or not the bar is currently rendered.
    static let cardGridHorizontalInset: CGFloat = 8
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

    /// MY-1418/MY-1419: the grid keeps a SINGLE `ScrollView` mounted for both
    /// the populated and the zero-result state; only the *content* inside it
    /// swaps. Previously this was an
    /// `if equipmentGroups.isEmpty { emptyState } else { ScrollView { … } }`
    /// pair of mutually exclusive subtrees, so filtering the search down to
    /// zero matches tore the whole `ScrollView` — and with it the
    /// `.scrollDismissesKeyboard(.immediately)` modifier below — out of the
    /// hierarchy. UIKit resigned the search field's first responder as part
    /// of that teardown, dismissing the keyboard without the user ever
    /// making a drag gesture. Keeping the container stable means
    /// `.scrollDismissesKeyboard` only ever fires for its documented reason
    /// (a user drag), so a query that matches nothing now leaves the search
    /// field focused and the keyboard up while the user keeps editing.
    private var exerciseCardGrid: some View {
        let groups = filteredEquipmentGroups
        let equipments = groups.map { $0.0 }
        let showsIndexBar = equipments.count >= 2
        return VStack(alignment: .leading, spacing: 0) {
            equipmentFilterRail
            ScrollViewReader { gridProxy in
                ZStack(alignment: .trailing) {
                ScrollView {
                    if groups.isEmpty {
                        // Sized to the scroll container so the placeholder
                        // stays vertically centred exactly as it did when
                        // it was the grid's direct child, while remaining
                        // a scrollable target — a user drag over the empty
                        // state still dismisses the keyboard.
                        emptyState
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.vertical)
                    } else {
                        // NOTE: this outer stack is eager `VStack`, NOT
                        // `LazyVStack`. Each section already contains a
                        // `LazyVGrid` (the layer that virtualizes the hundreds
                        // of exercise cards). Nesting a lazy grid inside a lazy
                        // stack is a pathological SwiftUI combination: the outer
                        // lazy container cannot derive a stable intrinsic size
                        // for the inner lazy grid, so every prefetch-phase
                        // update (`LazyLayoutViewCache.updatePrefetchPhases`)
                        // re-expands the inner grid in full, recursing through
                        // `ModifiedViewList.applyNodes` and pinning the main
                        // thread at 100% CPU. Section count is bounded (≤18
                        // equipment kinds), so an eager outer stack is cheap and
                        // leaves exactly one lazy layer doing the virtualization.
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(groups, id: \.0) { equipment, items in
                                equipmentSection(equipment: equipment, exercises: items)
                                    .id(equipment)
                            }
                        }
                        .padding(.vertical, Self.cardGridVerticalInset)
                        .padding(.leading, Self.cardGridLeadingInset(showsIndexBar: showsIndexBar))
                        .padding(.trailing, Self.cardGridTrailingInset(showsIndexBar: showsIndexBar))
                        .scrollTargetLayout()
                    }
                }
                // Short search results and the empty state must still
                // accept drags when their content fits in the viewport.
                .scrollBounceBehavior(.always)
                // iOS 18 fallback: the panel floats as an overlay, so
                // reserve matching bottom space with a STATIC margin driven
                // by the intrinsic `panelHeight`. On iOS 26 the panel is a
                // `.safeAreaBar` (see `FloatingPanelAttachment`) which
                // reserves its own space, so `panelHeight` stays 0 here and
                // this margin is an inert no-op.
                .contentMargins(.bottom, panelHeight, for: .scrollContent)
                // MY-1272: dismiss the search keyboard as soon as the
                // card grid scrolls. `.immediately` mirrors
                // `ActiveWorkoutView`'s existing choice: any drag
                // gesture on the grid dismisses the keyboard, and the
                // search field remains mounted as keyboard focus changes.
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { _ in
                        #if canImport(UIKit)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        #endif
                    }
                )
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
                    idType: ExerciseSection.self,
                    threshold: Self.visibilityThreshold
                ) { visibleIds in
                    Self.applyVisibleIds(
                        visibleIds,
                        in: equipments,
                        current: visibleEquipment,
                        isDragging: draggedEquipment != nil,
                        using: applyVisibleEquipment
                    )
                }

                if showsIndexBar {
                    indexBarSlot(equipments: equipments, gridProxy: gridProxy)
                }
            }
            .overlay(alignment: .trailing) {
                if let equipment = draggedEquipment ?? indexHUD {
                    sectionPreviewPopup(equipment: equipment)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                        .padding(.trailing, Self.cardGridIndexBarReserve)
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
                value: draggedEquipment
            )
            .onChange(of: equipments) { _, newEquipments in
                if let current = visibleEquipment, !newEquipments.contains(current) {
                    visibleEquipment = newEquipments.first
                } else if visibleEquipment == nil {
                    visibleEquipment = newEquipments.first
                }
            }
            // MY-1250 reconciliation: filter/search change bumps
            // `scrollResetToken`; here we imperatively scroll the grid to
            // the top of the resolved anchor section. MY-1272 refined
            // "anchor" to `pendingScrollAnchor` so muscle-group changes
            // can target the current `visibleEquipment` when it
            // survives (see `resolveMuscleGroupScrollAnchor`), while
            // search resets still fall back to the first section.
                .onChange(of: scrollResetToken) { _, _ in
                    let target = pendingScrollAnchor ?? groups.first?.0
                    guard let anchor = target else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        gridProxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
        }
    }

    // Reserve a stable lane; the compact character rail centers within it.
    @ViewBuilder
    private func indexBarSlot(equipments: [ExerciseSection], gridProxy: ScrollViewProxy) -> some View {
        EquipmentIndexBar(
            equipments: equipments,
            activeEquipment: draggedEquipment ?? visibleEquipment,
            onSelect: { equipment, animated in
                if animated {
                    withAnimation(.easeOut(duration: 0.2)) {
                        gridProxy.scrollTo(equipment, anchor: .top)
                    }
                } else {
                    // Drag scrub: jump immediately with no per-frame
                    // animation so rapid equipment changes don't stack
                    // competing 0.2s scroll animations to tall sections.
                    gridProxy.scrollTo(equipment, anchor: .top)
                }
                // MY-1338: drag owns the highlight while
                // `draggedEquipment != nil` — the scroll-derived
                // callback path is suppressed via `isDragging: true`
                // in the reducer, and writing `visibleEquipment` here
                // (in addition to the drag overlay's own
                // `draggedEquipment` state) keeps the index-bar's
                // fallback source coherent for reconciliation on
                // drag-end.
                if visibleEquipment != equipment {
                    emitSectionJumpTelemetry(
                        from: visibleEquipment,
                        to: equipment,
                        source: Self.sectionJumpSourceDrag
                    )
                    visibleEquipment = equipment
                }
            },
            onDragChanged: { equipment in
                // MY-1338: count distinct sections visited within one
                // scrub gesture — reported on drag-end via
                // `exercisePickerIndexScrubbed(count:)`.
                if draggedEquipment != equipment {
                    dragScrubCount &+= 1
                }
                draggedEquipment = equipment
            },
            onDragEnded: {
                let count = dragScrubCount
                dragScrubCount = 0
                indexHUD = draggedEquipment
                draggedEquipment = nil
                // MY-1338: emit the scrub-count telemetry regardless of
                // whether the scrub visited any sections; a zero-count
                // scrub (drag started but never crossed a row boundary)
                // is itself a signal worth aggregating.
                TelemetryService.shared.trackNonisolated(
                    .exercisePickerIndexScrubbed(count: count)
                )
            }
        )
        .padding(.trailing, 4)
    }

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
    ///
    /// Dedup guard: `onScrollTargetVisibilityChange` fires at a very high
    /// rate during a finger scroll (the low `visibilityThreshold` makes it
    /// fire for any pixel change across ≥1000 exercises). Writing
    /// `visibleEquipment` unconditionally re-published `@State` on nearly
    /// every frame even when the top-visible section had not changed,
    /// forcing redundant SwiftUI re-evaluation of the whole grid and
    /// starving the main thread mid-scroll. Only writing on a genuine
    /// section change removes that per-frame churn.
    ///
    /// MY-1338: also emits `exercisePickerSectionJump` telemetry tagged
    /// with the `"scroll"` source identifier so we can observe how often
    /// the scroll-derived highlight jumps sections vs the drag-derived one.
    @MainActor
    private func applyVisibleEquipment(_ equipment: ExerciseSection?) {
        guard visibleEquipment != equipment else { return }
        let hadVisibleEquipment = visibleEquipment != nil
        emitSectionJumpTelemetry(
            from: visibleEquipment,
            to: equipment,
            source: Self.sectionJumpSourceScroll
        )
        visibleEquipment = equipment
        if hadVisibleEquipment {
            indexHUD = equipment
        }
    }

    /// MY-1338: canonical `TelemetryIdentifier` values for the
    /// `exercisePickerSectionJump.source` field. `TelemetryIdentifier`
    /// literals are validated at construction time (canonical ASCII), so
    /// they cannot silently leak free-form strings into telemetry.
    static let sectionJumpSourceScroll: TelemetryIdentifier = "scroll"
    static let sectionJumpSourceDrag: TelemetryIdentifier = "drag"
    /// Sentinel used when the pre-transition section is unknown (initial
    /// mount, or after the grid cleared). Kept canonical for the same
    /// aggregation-cleanliness reason as the two source identifiers.
    static let sectionJumpNone: TelemetryIdentifier = "none"

    /// MY-1338: send the strongly typed jump event through TelemetryKit.
    /// Both endpoints are mapped to canonical `TelemetryIdentifier`
    /// values — `ExerciseSection.rawValue` is already ASCII lowercase
    /// so it satisfies the identifier character set by construction.
    /// Falls back to `sectionJumpNone` when either endpoint is `nil`.
    @MainActor
    private func emitSectionJumpTelemetry(
        from: ExerciseSection?,
        to: ExerciseSection?,
        source: TelemetryIdentifier
    ) {
        let fromID = Self.telemetryIdentifier(for: from)
        let toID = Self.telemetryIdentifier(for: to)
        TelemetryService.shared.trackNonisolated(
            .exercisePickerSectionJump(from: fromID, to: toID, source: source)
        )
    }

    /// Maps an optional `ExerciseSection` to a canonical `TelemetryIdentifier`.
    /// Non-nil sections serialize via their raw case name; nil serializes to
    /// `sectionJumpNone`.
    static func telemetryIdentifier(for section: ExerciseSection?) -> TelemetryIdentifier {
        guard let raw = section?.rawValue,
              let identifier = TelemetryIdentifier(validating: raw)
        else {
            return sectionJumpNone
        }
        return identifier
    }

    /// MY-1249: pure entry-point mirroring what
    /// `onScrollTargetVisibilityChange` does in production — takes the raw
    /// visible-ids callback payload plus the current section order, picks
    /// the highlight, and applies it via the supplied setter.
    static func applyVisibleIds(
        _ visibleIds: [ExerciseSection],
        in order: [ExerciseSection],
        using setter: (ExerciseSection?) -> Void
    ) {
        setter(firstVisibleEquipment(from: visibleIds, in: order))
    }

    /// Dedup-aware variant of `applyVisibleIds`.
    @discardableResult
    static func applyVisibleIds(
        _ visibleIds: [ExerciseSection],
        in order: [ExerciseSection],
        current: ExerciseSection?,
        using setter: (ExerciseSection?) -> Void
    ) -> ExerciseSection? {
        applyVisibleIds(
            visibleIds,
            in: order,
            current: current,
            isDragging: false,
            using: setter
        )
    }

    /// MY-1338: drag-aware variant of the scroll-callback bridge.
    @discardableResult
    static func applyVisibleIds(
        _ visibleIds: [ExerciseSection],
        in order: [ExerciseSection],
        current: ExerciseSection?,
        isDragging: Bool,
        using setter: (ExerciseSection?) -> Void
    ) -> ExerciseSection? {
        if isDragging {
            return current
        }
        let resolved = firstVisibleEquipment(from: visibleIds, in: order)
        if resolved != current {
            setter(resolved)
        }
        return resolved
    }

    /// MY-1249: pick the section that should own the index-bar highlight.
    static func firstVisibleEquipment(
        from visibleIds: [ExerciseSection],
        in order: [ExerciseSection]
    ) -> ExerciseSection? {
        guard !visibleIds.isEmpty else { return nil }
        let visibleSet = Set(visibleIds)
        return order.first(where: visibleSet.contains) ?? visibleIds.first
    }

    /// MY-1272: pick the equipment section to scroll to when the muscle
    /// group filter changes.
    static func resolveMuscleGroupScrollAnchor(
        previouslyVisible: ExerciseSection?,
        in newOrder: [ExerciseSection]
    ) -> ExerciseSection? {
        if let previous = previouslyVisible, newOrder.contains(previous) {
            return previous
        }
        return newOrder.first
    }

    /// MY-1259: pick the equipment section to scroll to when the search
    /// text changes.
    static func resolveSearchScrollAnchor(
        in newOrder: [ExerciseSection]
    ) -> ExerciseSection? {
        newOrder.first
    }

    /// MY-1338: fixed section-preview popup dimensions.
    static let sectionPreviewPopupWidth: CGFloat = 160
    static let sectionPreviewPopupHeight: CGFloat = 56

    private func sectionPreviewPopup(equipment: ExerciseSection) -> some View {
        Label(equipment.localizedName, systemImage: equipment.sfSymbol)
            .lineLimit(1).minimumScaleFactor(0.7)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.foreground)
            .padding(16)
            .frame(width: Self.sectionPreviewPopupWidth, height: Self.sectionPreviewPopupHeight)
            .designSurface(style: .solid, cornerRadius: 16)
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

    private func sectionPaletteIndex(for section: ExerciseSection) -> Int {
        (ExerciseSection.allCases.firstIndex(of: section) ?? 0) % 5
    }

    private func equipmentSection(equipment: ExerciseSection, exercises: [Exercise]) -> some View {
        let color = categoryColor(sectionPaletteIndex(for: equipment), theme: theme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: equipment.sfSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 16, alignment: .center)
                Text(equipment.localizedName.uppercased())
                    .font(TypeScale.meta)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.neutrals.text2)
                Text("\(exercises.count)")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text3)
            }

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(exercises) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isSelected: selectedIDs.contains(exercise.persistentModelID),
                        showsSelectionIndicator: true
                    ) {
                        handleCardTap(exercise)
                    }
                    .contextMenu { exerciseContextMenu(exercise) }
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

// MARK: - Floating Panel Attachment

/// Attaches the floating search + filter panel to the card grid without letting
/// it drive a layout-feedback loop.
///
/// The picker previously used a bottom safe-area inset, whose resolved inset
/// is recomputed *inside* the grid's `LazySubviewPlacements.placeSubviews`
/// pass. Because the panel sits over that same lazy grid, its measured height
/// and the grid's placement never reached a fixed point, and the main thread
/// spun at 100% CPU in an endless `SafeAreaInsets.resolve` / `LazyVGridLayout`
/// relayout.
///
/// - iOS 26+: use the purpose-built `.safeAreaBar`, which reserves space for a
///   floating bar without the recursive inset resolution.
/// - iOS 18: render the panel as a non-layout `.overlay` and reserve matching
///   bottom space with a STATIC `contentMargins` driven by the panel's
///   intrinsic height (measured via `onGeometryChange` into `panelHeight`).
private struct FloatingPanelAttachment<Panel: View>: ViewModifier {
    @Binding var panelHeight: CGFloat
    let panel: Panel

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) {
                panel
            }
        } else {
            content.overlay(alignment: .bottom) {
                panel
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        if abs(newHeight - panelHeight) > 0.5 {
                            panelHeight = newHeight
                        }
                    }
            }
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
                        .frame(width: 32, height: 32)
                        .background(equipmentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Spacer(minLength: 0)
                    if showsSelectionIndicator {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(isSelected ? theme.primary.primary : theme.neutrals.text3)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                    }
                }

                mediaPreview

                Text(exercise.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(exercise.muscleGroup.localizedName)
                        .lineLimit(1)
                    Text("·")
                        .accessibilityHidden(true)
                    Text(exercise.equipment.localizedName)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(theme.secondaryForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 118,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(10)
            .designSurface(style: .solid, cornerRadius: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? theme.primary.primary : theme.neutrals.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    let equipments: [ExerciseSection]
    let activeEquipment: ExerciseSection?
    /// `animated == false` during a finger drag: the drag scrubs across many
    /// equipments and each triggers a `scrollTo`, so stacking a 0.2s animated
    /// scroll per frame to a tall section (e.g. 201-item machine) makes the
    /// animations fight and spikes the main thread. A tap sets `animated ==
    /// true` for a single smooth jump.
    let onSelect: (_ equipment: ExerciseSection, _ animated: Bool) -> Void
    let onDragChanged: (ExerciseSection) -> Void
    let onDragEnded: () -> Void

    static let hitWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let height = min(geometry.size.height, CGFloat(equipments.count) * 28)
            VStack(spacing: 0) {
                ForEach(equipments, id: \.self) { equipment in
                    Text(ExercisePickerSectionGrouping.indexCharacter(for: equipment))
                        .font(.caption2.weight(activeEquipment == equipment ? .heavy : .medium))
                        .foregroundStyle(activeEquipment == equipment ? theme.accent : theme.secondaryForeground)
                        .frame(width: 16, height: height / CGFloat(max(equipments.count, 1)))
                }
            }
            .frame(width: Self.hitWidth, height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard let equipment = ExercisePickerSectionGrouping.indexSection(
                        at: value.location.y, height: height, sections: equipments
                    ) else { return }
                    if equipment != activeEquipment {
                        onSelect(equipment, false)
                        triggerSelectionHaptic()
                    }
                    onDragChanged(equipment)
                }
                .onEnded { _ in onDragEnded() })
            // One adjustable 44pt-wide control: the tiny glyphs are visual
            // markers, not overlapping sub-44pt buttons. VoiceOver also gets
            // a named action for every equipment section.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "器械分区索引", comment: "Equipment section index"))
            .accessibilityValue(activeEquipment?.localizedName ?? "")
            .accessibilityAdjustableAction { direction in
                let current = equipments.firstIndex { $0 == activeEquipment } ?? 0
                let step = direction == .increment ? 1 : -1
                guard !equipments.isEmpty else { return }
                selectAccessible(equipments[min(max(current + step, 0), equipments.count - 1)])
            }
            .accessibilityActions {
                ForEach(equipments, id: \.self) { equipment in
                    Button(equipment.localizedName) { selectAccessible(equipment) }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: Self.hitWidth)
    }

    private func selectAccessible(_ equipment: ExerciseSection) {
        onSelect(equipment, true)
        onDragChanged(equipment)
        onDragEnded()
        triggerSelectionHaptic()
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit) && !os(watchOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

private struct ExercisePickerRevision: Equatable {
    let id: PersistentIdentifier
    let nameEn: String
    let nameZh: String
    let muscle: MuscleGroup
    let equipment: Equipment
}

private enum PickerSheet: Identifiable {
    case create
    case edit(Exercise)
    case detail(Exercise)

    var id: String {
        switch self {
        case .create: "create"
        case .edit: "edit"
        case .detail: "detail"
        }
    }
}

/// The actual production dock is also hosted by the layout regression tests.
/// All three controls stay mounted in one horizontal row while typing or filtering.
struct PickerBottomBar: View {
    @Environment(\.theme) private var theme
    @Binding var searchText: String
    @FocusState private var isSearchFocused: Bool
    let selectedCount: Int
    let isMultiSelect: Bool
    let onCreate: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let isConfirmDisabled = isMultiSelect && selectedCount == 0
        HStack(spacing: 4) {
            searchField
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            Button(action: onCreate) {
                ViewThatFits(in: .horizontal) {
                    Text(String(localized: "picker.create", comment: "Create custom exercise"))
                        .font(.caption.weight(.semibold)).fixedSize()
                    Image(systemName: "plus").font(.body.weight(.semibold))
                }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityLabel(String(localized: "picker.create", comment: "Create custom exercise"))
            .accessibilityIdentifier("exercise_picker_create")
            Button(action: onConfirm) {
                HStack(spacing: 3) {
                    Text(String(localized: "picker.done", comment: "Confirm exercise selection"))
                    if isMultiSelect && selectedCount > 0 {
                        Text("\(selectedCount)").monospacedDigit()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    isConfirmDisabled ? theme.inner : theme.interactiveAccent,
                    in: RoundedRectangle(cornerRadius: Radius.control)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(isConfirmDisabled ? theme.secondaryForeground : theme.onInteractiveAccent)
            .disabled(isConfirmDisabled)
            .accessibilityLabel(String(localized: "picker.done", comment: "Confirm exercise selection"))
            .accessibilityValue(String(localized: "picker.selected.count \(selectedCount)", comment: "Selected exercise count"))
            .accessibilityIdentifier("exercise_picker_confirm")
        }
        .padding(8)
        .designSurface(style: .glass, cornerRadius: 16)
    }

    // Own the native field here so its identifier belongs only to the input,
    // and clearing/submitting can dismiss focus without replacing the dock.
    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryForeground)
                .accessibilityHidden(true)
            TextField(String(localized: "搜索动作", comment: "Exercise search prompt"), text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    isSearchFocused = false
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
                .accessibilityIdentifier("exercise_picker_search_field")
            if !searchText.isEmpty {
                Button {
                    isSearchFocused = false
                    #if canImport(UIKit)
                    // Resign before clearing removes this button from the view tree.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 20, height: 20)
                        .frame(width: Space.minTapTarget, height: Space.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "清除搜索", comment: "Clear search a11y label"))
                .accessibilityIdentifier("exercise_picker_search_clear")
            }
        }
        .padding(.leading, Space.sm)
        .padding(.trailing, searchText.isEmpty ? Space.sm : 0)
        .frame(minHeight: Space.minTapTarget)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control)
            .stroke(isSearchFocused ? theme.accent : theme.border, lineWidth: 1))
    }
}

struct PickerExerciseEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise?
    let onSaved: () -> Void
    @State private var nameEn: String
    @State private var nameZh: String
    @State private var muscleGroup: MuscleGroup
    @State private var equipment: Equipment
    @State private var saveFailed = false

    init(exercise: Exercise?, initialGroup: MuscleGroup?, onSaved: @escaping () -> Void) {
        self.exercise = exercise
        self.onSaved = onSaved
        _nameEn = State(initialValue: exercise?.nameEn ?? "")
        _nameZh = State(initialValue: exercise?.nameZh ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? initialGroup ?? .chest)
        _equipment = State(initialValue: exercise?.equipment ?? .barbell)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "picker.name.en", comment: "English exercise name"), text: $nameEn)
                TextField(String(localized: "picker.name.zh", comment: "Chinese exercise name"), text: $nameZh)
                Picker(String(localized: "picker.muscle", comment: "Exercise muscle group"), selection: $muscleGroup) {
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
                Picker(String(localized: "picker.equipment", comment: "Exercise equipment"), selection: $equipment) {
                    ForEach(Equipment.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                }
            }
            .navigationTitle(exercise == nil
                             ? String(localized: "picker.create", comment: "Create custom exercise")
                             : String(localized: "picker.edit", comment: "Edit custom exercise"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", comment: "Cancel exercise editor")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "picker.save", comment: "Save custom exercise")) {
                        do {
                            _ = try Self.save(exercise: exercise, nameEn: nameEn, nameZh: nameZh,
                                              muscleGroup: muscleGroup, equipment: equipment, context: modelContext)
                            onSaved()
                            dismiss()
                        } catch { saveFailed = true }
                    }
                    .disabled(!Self.validName(nameEn, nameZh))
                }
            }
            .alert(String(localized: "picker.save.failed", comment: "Custom exercise save failed"), isPresented: $saveFailed) {
                Button(String(localized: "picker.ok", comment: "Dismiss exercise error"), role: .cancel) {}
            }
        }
    }

    static func validName(_ nameEn: String, _ nameZh: String) -> Bool {
        !nameEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !nameZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canDelete(_ exercise: Exercise) -> Bool {
        exercise.isCustom && (exercise.workoutExercises ?? []).isEmpty && (exercise.templateExercises ?? []).isEmpty
    }

    enum SaveError: Error, Equatable { case invalidName, presetReadOnly }

    /// Persist only the editor's fields; restore them on failure without rolling
    /// back unrelated workout changes in the shared ModelContext.
    @MainActor
    @discardableResult
    static func save(exercise: Exercise?, nameEn: String, nameZh: String,
                     muscleGroup: MuscleGroup, equipment: Equipment, context: ModelContext) throws -> Exercise {
        guard validName(nameEn, nameZh) else { throw SaveError.invalidName }
        guard exercise?.isCustom != false else { throw SaveError.presetReadOnly }
        let english = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let chinese = nameZh.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = exercise ?? Exercise(nameEn: "", nameZh: "", muscleGroup: muscleGroup, equipment: equipment, isCustom: true)
        let original = (target.nameEn, target.nameZh, target.muscleGroup, target.equipment)
        target.nameEn = english
        target.nameZh = chinese
        target.muscleGroup = muscleGroup
        target.equipment = equipment
        if exercise == nil { context.insert(target) }
        do { try context.save() } catch {
            if exercise == nil { context.delete(target) }
            else {
                target.nameEn = original.0
                target.nameZh = original.1
                target.muscleGroup = original.2
                target.equipment = original.3
            }
            throw error
        }
        return target
    }
}

#Preview("Picker · Light") {
    ExercisePickerView(onConfirm: { _ in })
        .modelContainer(for: Exercise.self, inMemory: true)
        .designTheme()
}

#Preview("Picker · Dark") {
    ExercisePickerView(onConfirm: { _ in })
        .modelContainer(for: Exercise.self, inMemory: true)
        .preferredColorScheme(.dark)
        .designTheme()
}

#Preview("Picker dock · Light") {
    PickerBottomBar(searchText: .constant(""), selectedCount: 2, isMultiSelect: true, onCreate: {}, onConfirm: {})
        .padding().designTheme()
}

#Preview("Picker dock · Dark") {
    PickerBottomBar(searchText: .constant(""), selectedCount: 0, isMultiSelect: true, onCreate: {}, onConfirm: {})
        .padding().preferredColorScheme(.dark).designTheme()
}

#Preview("Custom exercise · Create") {
    PickerExerciseEditor(exercise: nil, initialGroup: .chest, onSaved: {})
        .modelContainer(for: Exercise.self, inMemory: true).designTheme()
}

#Preview("Custom exercise · Dark") {
    PickerExerciseEditor(exercise: nil, initialGroup: .back, onSaved: {})
        .modelContainer(for: Exercise.self, inMemory: true)
        .preferredColorScheme(.dark).designTheme()
}
