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
    /// MY-1338: number of distinct equipment sections the current drag
    /// gesture has visited. Reset on drag start, reported via
    /// `exercisePickerIndexScrubbed(count:)` on drag end, so we can watch
    /// for high-count bursts that indicate the highlight is racing through
    /// neighbours instead of settling on the finger's target.
    @State private var dragScrubCount: Int = 0
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
    // MY-1272: scroll target for the next `scrollResetToken` bump. Search
    // resets always anchor to the first section; muscle-group changes
    // prefer the current `visibleEquipment` when it survives (see
    // `resolveMuscleGroupScrollAnchor`). Captured at the moment the token
    // bumps so the `.onChange(scrollResetToken)` handler picks the correct
    // section without re-deriving intent.
    @State private var pendingScrollAnchor: Equipment?
    // MY-1272: floating-search collapsed/expanded state. Collapsed = a
    // circular magnifier button; expanded = the full search field. Forced
    // open whenever `searchText` is non-empty so we never orphan an
    // in-flight query behind a collapsed button.
    @State private var isSearchExpanded: Bool = false

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
                        .modifier(
                            FloatingPanelAttachment(
                                panelHeight: $panelHeight,
                                panel: floatingSearchAndFilterPanel
                            )
                        )
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
            // MY-1272: keep the collapsed/expanded state consistent with
            // focus + query state. Any focus change while `searchText` is
            // empty collapses the pill; any non-empty query forces expand
            // so the user can always see and edit what they typed.
            .onChange(of: isSearchFocused) { _, focused in
                if !focused && searchText.isEmpty {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isSearchExpanded = false
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                if !newValue.isEmpty && !isSearchExpanded {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isSearchExpanded = true
                    }
                } else if newValue.isEmpty && !isSearchFocused && isSearchExpanded {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isSearchExpanded = false
                    }
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

    // MARK: - Floating Search + Muscle Filter Panel (MY-1272, order reversed MY-1277)
    //
    // Two independent floating glass surfaces stacked above the safe-area:
    //   • Search control (collapsible — circular magnifier button by
    //     default; expands into a full-width search field once tapped).
    //     Sits on top per MY-1277 (user preference).
    //   • Muscle-group chips row (always full-width glass panel). Sits on
    //     the bottom per MY-1277.
    //
    // Replaces the prior MY-1260 single combined panel that hosted both
    // rows inside one glass surface separated by a 1pt hairline. The two
    // controls now read as two distinct floating widgets so the search
    // can shrink to a compact pill without dragging the chip strip with
    // it.
    //
    // Debounce + `debouncedSearchText` (`.task(id: searchText)`) is
    // preserved verbatim — only the outer chrome changes.

    static let panelHorizontalInset: CGFloat = 12
    private static let panelBottomInset: CGFloat = 8
    private static let panelInnerHPadding: CGFloat = 14
    private static let panelInnerVPadding: CGFloat = 10
    private static let panelSurfaceSpacing: CGFloat = 8
    /// Diameter of the collapsed search pill. Satisfies Constitution §H
    /// (≥44pt) directly — the visual pill itself is the hit target.
    static let collapsedSearchDiameter: CGFloat = 44

    /// MY-1445: max width of the search surface ZStack in collapsed state.
    /// Equals `collapsedSearchDiameter` so the hidden expanded surface does
    /// not force a full-width ZStack layout contribution.
    static let collapsedSearchMaxWidth: CGFloat = collapsedSearchDiameter

    /// MY-1445: alignment applied to the searchSurface frame. When the ZStack
    /// is narrower than the parent's proposal (collapsed state), the parent
    /// VStack's `.trailing` alignment positions the 44pt frame flush to the
    /// trailing edge. This frame alignment governs content placement WITHIN
    /// the ZStack (the collapsed pill centers vertically within its fixed
    /// frame). Both work together: parent positions the frame, frame aligns
    /// its children.
    static let searchSurfaceCollapsedAlignment: HorizontalAlignment = .trailing

    private var floatingSearchAndFilterPanel: some View {
        // MY-1277: search on TOP, chips on BOTTOM (user preference — reversed
        // from the MY-1272 layout where chips were on top). Both surfaces
        // remain independent glass panels; the search surface still collapses
        // to a compact pill and the chip strip still horizontally scrolls.
        VStack(alignment: .trailing, spacing: Self.panelSurfaceSpacing) {
            // Row 1: search control glass surface — right-aligned in
            // collapsed state (compact pill) so the chip strip below it
            // keeps its full breathing room; expands to full width when
            // active. Trailing-alignment of the outer VStack keeps the
            // collapsed pill snapped to the trailing edge without
            // stretching the surface itself.
            searchSurface
            // Row 2: chips strip on its own glass surface (full width).
            muscleGroupChipsSurface
        }
        .padding(.horizontal, Self.panelHorizontalInset)
        .padding(.bottom, Self.panelBottomInset)
        .animation(.easeOut(duration: 0.22), value: isSearchExpanded)
    }

    // MARK: Muscle-group chips surface (independent glass)

    private var muscleGroupChipsSurface: some View {
        // MY-1277: horizontal insets moved from the outer padding onto the
        // ScrollView's content margins so chips can scroll under the glass
        // panel's rounded edge without being clipped mid-pill. The previous
        // outer `.padding(.horizontal, panelInnerHPadding)` placed the
        // scroll content inside a rectangular cutout the ScrollView clipped
        // to; edges of the scrolling row therefore hit the panel's rounded
        // clipShape and got sliced. `.contentMargins(.horizontal, ...)`
        // insets the row's *content* while keeping the ScrollView itself
        // full-width, so the row now visually flush-fills the glass and
        // chips near the edges scroll cleanly to the inner rounded corner.
        muscleGroupChipsRow
            .padding(.vertical, Self.panelInnerVPadding)
            .frame(maxWidth: .infinity)
            .modifier(PanelSurfaceModifier(theme: theme, opaque: reduceTransparency))
    }

    // MARK: Search surface (collapsible — circular button ↔ full field)

    /// Renders **both** collapsed and expanded search surfaces in the same
    /// SwiftUI subtree simultaneously, toggling visibility with
    /// `.opacity` + `.allowsHitTesting` per `isSearchExpanded`. This
    /// preserves the `TextField` view identity across every state
    /// transition — critical because the `@FocusState var
    /// isSearchFocused` binding is tied to that specific TextField
    /// instance. A prior `if isSearchExpanded { ... } else { ... }` diff
    /// tore down and re-mounted the TextField whenever the underlying
    /// `@Query` re-emitted (e.g. new Exercise inserted mid-typing) or
    /// whenever any observable that touches this view churned during the
    /// 200ms debounce, causing SwiftUI to invalidate the FocusState
    /// binding and drop the keyboard (MY-1368).
    ///
    /// Both surfaces are always in the layout; the invisible one has
    /// `.opacity(0)` and disables hit-testing so it can't accidentally
    /// steal a tap. MY-1445: the ZStack is constrained via
    /// `SearchSurfaceContainer` to `collapsedSearchMaxWidth` (44pt) in
    /// collapsed state, preventing the hidden expanded surface from
    /// forcing a full-width layout contribution. The parent VStack's
    /// `.trailing` alignment positions this narrower ZStack flush to
    /// the panel trailing edge.
    private var searchSurface: some View {
        SearchSurfaceContainer(
            isExpanded: isSearchExpanded,
            expanded: expandedSearchSurface,
            collapsed: collapsedSearchSurface
        )
    }

    private var expandedSearchSurface: some View {
        searchRow
            .padding(.horizontal, Self.panelInnerHPadding)
            .padding(.vertical, Self.panelInnerVPadding)
            .frame(maxWidth: .infinity)
            .modifier(PanelSurfaceModifier(theme: theme, opaque: reduceTransparency))
    }

    /// Collapsed = a circular magnifier button. Tapping expands the
    /// surface into `expandedSearchSurface` and focuses the field. The
    /// diameter equals `collapsedSearchDiameter` (≥44pt) so the visible
    /// pill is the full hit target — no invisible padding trickery.
    private var collapsedSearchSurface: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) {
                isSearchExpanded = true
            }
            // Defer focus to the next runloop tick so the TextField exists
            // before we try to focus it. Without this, the first tap
            // sometimes expands the pill without pulling up the keyboard.
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, design: .default, weight: .semibold))
                .foregroundStyle(theme.neutrals.text2)
                .frame(
                    width: Self.collapsedSearchDiameter,
                    height: Self.collapsedSearchDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise_picker_search_expand")
        .background(
            CollapsedSearchPillSurface(theme: theme, opaque: reduceTransparency)
        )
        .accessibilityLabel(String(localized: "搜索动作", comment: "Exercise search prompt"))
        .accessibilityHint(String(localized: "展开搜索", comment: "Expand search a11y hint"))
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
            .accessibilityIdentifier("exercise_picker_search_field")
            // Bind semantic visibility to the actual control. Applying
            // accessibilityHidden to its always-mounted ancestor leaves the
            // descendant TextField cached as hidden in the XCUI tree after
            // expansion on iOS 26, so it exists but is never hittable.
            .accessibilityHidden(!isSearchExpanded)
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
                    // MY-1272: clearing an empty query while unfocused
                    // collapses the pill (search focus onChange handles
                    // the empty-and-blur case). Explicit blur so tapping
                    // the clear button collapses without an extra tap.
                    isSearchFocused = false
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
        // MY-1277: use `.contentMargins` (iOS 17+) so the ScrollView itself
        // extends edge-to-edge inside the glass panel while its scrollable
        // *content* is inset by `panelInnerHPadding`. This lets chips near
        // the leading/trailing edge scroll past the visual inset without
        // being sliced by the panel's rounded clipShape (previously the
        // outer `.padding(.horizontal)` produced a rectangular cutout that
        // clipped chips mid-pill when scrolled to either end).
        .contentMargins(.horizontal, Self.panelInnerHPadding, for: .scrollContent)
    }

    private func muscleChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(TypeScale.meta)
                // MY-1277 repair: differentiate the two states via weight
                // per the approved design-reviewer scheme — unselected
                // `.medium`, selected `.semibold`. Weight (in addition to
                // colour) reinforces the selected pill without shouting.
                .fontWeight(isSelected ? .semibold : .medium)
                // MY-1277: unselected text uses `text1` (primary body color)
                // for stronger legibility on the glass surface — the prior
                // `text2` reduction made unselected chips look disabled.
                // Selected retains `onPrimary` for AA contrast on the
                // primary fill (see DesignKit `contrastChoose`).
                .foregroundStyle(isSelected ? theme.primary.onPrimary : theme.neutrals.text1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(
                    // MY-1277: refined chip visual language.
                    //
                    // * Selected: filled `primary` capsule — unchanged
                    //   colour token, but no stroke overlay, so it reads
                    //   as one confident solid pill (matches iOS
                    //   segmented-control selected segment).
                    // * Unselected: subtle `neutrals.inner` fill (the
                    //   luminance-tier one step *up* from `card`, per
                    //   Components.swift elevation model), no stroke. This
                    //   replaces the prior transparent + hairline-border
                    //   look — on glass, a soft filled pill reads more
                    //   like a modern filter chip and less like a wire
                    //   outline. All tokens sourced from DesignKit; no
                    //   hardcoded colours.
                    Group {
                        if isSelected {
                            Capsule().fill(theme.primary.primary)
                        } else {
                            Capsule().fill(theme.neutrals.inner)
                        }
                    }
                )
                // MY-1277 repair: selected-state micro-lift via a
                // token-derived shadow (primary @ 25% opacity). Matches the
                // design-reviewer spec exactly (radius 4, y-offset 1) and
                // pulls the selected pill fractionally out of the row
                // without adding a stroke. Unselected chips remain flat so
                // the row reads as a family of pills with one raised
                // member. Shadow is attached to the capsule background,
                // not the outer hit rect, so it hugs the pill silhouette.
                .shadow(
                    color: isSelected ? theme.primary.primary.opacity(0.25) : .clear,
                    radius: isSelected ? 4 : 0,
                    y: isSelected ? 1 : 0
                )
                // Extend the tap area vertically beyond the ~32pt visual
                // capsule so the *hit* target satisfies Constitution §H
                // (≥44pt). `contentShape` picks up the padded frame so a
                // finger landing on the invisible top/bottom band above/below
                // the capsule still hits this chip.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                // MY-1277 repair: enforce ≥44pt on BOTH axes so
                // single-character CJK labels ("胸/背/肩/腿/臂") whose visual
                // capsule renders ~40pt wide still meet Constitution §H
                // (Cross-Cutting hit target). `.frame(minWidth: 44)`
                // widens only the invisible tap rectangle picked up by
                // `contentShape(Rectangle())`; the visible Capsule
                // background sits inside and keeps its content-hugging
                // width, so the chip strip's visual density is unchanged.
                .frame(minWidth: 44, minHeight: 44)
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
    @ViewBuilder
    private var exerciseCardGrid: some View {
        let groups = equipmentGroups
        let equipments = groups.map { $0.0 }
        let showsIndexBar = equipments.count >= 2
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
                // The empty state is exactly as tall as the container, so
                // without an explicit always-bounce it would refuse the
                // drag and `.scrollDismissesKeyboard` could never fire
                // there. The populated path keeps the default
                // (`.automatic`) physics untouched.
                .scrollBounceBehavior(groups.isEmpty ? .always : .automatic, axes: .vertical)
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
                // subsequent `isSearchFocused == false` transition
                // collapses the search control back to its magnifier
                // pill when `searchText` is empty (see
                // `.onChange(of: isSearchFocused)` below).
                .scrollDismissesKeyboard(.immediately)
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
                        current: visibleEquipment,
                        isDragging: draggedEquipment != nil,
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
    private func applyVisibleEquipment(_ equipment: Equipment?) {
        guard visibleEquipment != equipment else { return }
        emitSectionJumpTelemetry(
            from: visibleEquipment,
            to: equipment,
            source: Self.sectionJumpSourceScroll
        )
        visibleEquipment = equipment
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
    /// values — `Equipment.rawValue` is already ASCII lowercase (see
    /// `VitalModels/Equipment.swift`) so it satisfies the identifier
    /// character set by construction. Falls back to `sectionJumpNone`
    /// when either endpoint is `nil`, which happens on the initial mount
    /// and when the grid empties mid-scroll.
    @MainActor
    private func emitSectionJumpTelemetry(
        from: Equipment?,
        to: Equipment?,
        source: TelemetryIdentifier
    ) {
        let fromID = Self.telemetryIdentifier(for: from)
        let toID = Self.telemetryIdentifier(for: to)
        TelemetryService.shared.trackNonisolated(
            .exercisePickerSectionJump(from: fromID, to: toID, source: source)
        )
    }

    /// Maps an optional `Equipment` to a canonical `TelemetryIdentifier`.
    /// Non-nil equipments serialize via their raw case name (guaranteed
    /// ASCII lowercase); nil serializes to `sectionJumpNone`. If a future
    /// case somehow fails `TelemetryIdentifier.init(validating:)` (should
    /// never happen for `Equipment` cases), we fall back to
    /// `sectionJumpNone` rather than silently dropping the event.
    static func telemetryIdentifier(for equipment: Equipment?) -> TelemetryIdentifier {
        guard let raw = equipment?.rawValue,
              let identifier = TelemetryIdentifier(validating: raw)
        else {
            return sectionJumpNone
        }
        return identifier
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

    /// Dedup-aware variant of `applyVisibleIds`. Resolves the top-visible
    /// section from the callback payload and invokes `setter` **only when
    /// it differs from `current`**, returning the resolved value so callers
    /// can thread it forward. This is the pure mirror of the production
    /// `applyVisibleEquipment` dedup guard: during a finger scroll the
    /// SwiftUI callback fires on nearly every frame with an unchanged
    /// top-visible section, and suppressing those no-op `@State` writes is
    /// what keeps the main thread free of redundant grid re-evaluation.
    /// Extracted as a `static` pure function so the dedup contract is
    /// directly testable without a rendered view (see
    /// `ExercisePickerIndexSyncTests`).
    @discardableResult
    static func applyVisibleIds(
        _ visibleIds: [Equipment],
        in order: [Equipment],
        current: Equipment?,
        using setter: (Equipment?) -> Void
    ) -> Equipment? {
        applyVisibleIds(
            visibleIds,
            in: order,
            current: current,
            isDragging: false,
            using: setter
        )
    }

    /// MY-1338: drag-aware variant of the scroll-callback bridge. When the
    /// side index bar is being scrubbed (`isDragging == true`), the drag
    /// gesture owns the authoritative highlight — `scrollTo(_:anchor:.top)`
    /// requests trigger their own `onScrollTargetVisibilityChange` bursts
    /// with stale/out-of-order top-visible payloads that would overwrite
    /// the finger's actual target with a neighbouring section mid-drag.
    /// Ignoring those payloads while the drag is live eliminates the
    /// "highlight jumps to neighbour then settles" glitch; the reducer
    /// returns `current` unchanged so the caller's `visibleEquipment`
    /// state stays pinned to the drag target. When the drag ends
    /// (`isDragging == false`), the next callback reconciles the highlight
    /// to whatever section is actually top-visible after all queued scroll
    /// animations settle, matching the pre-fix contract.
    ///
    /// The dedup guard (skip write when resolved == current) is still
    /// applied on non-drag frames — that behaviour is what the MY-1249
    /// `dedupCollapsesHighFrequencyFrames` test locks in.
    @discardableResult
    static func applyVisibleIds(
        _ visibleIds: [Equipment],
        in order: [Equipment],
        current: Equipment?,
        isDragging: Bool,
        using setter: (Equipment?) -> Void
    ) -> Equipment? {
        // Drag owns the highlight — ignore scroll-derived visibility during
        // scrub. Return `current` so the caller keeps its pinned drag
        // target rather than adopting the racing top-visible payload.
        if isDragging {
            return current
        }
        let resolved = firstVisibleEquipment(from: visibleIds, in: order)
        if resolved != current {
            setter(resolved)
        }
        return resolved
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

    /// MY-1272: pick the equipment section to scroll to when the muscle
    /// group filter changes. Prefer the user's currently-visible
    /// equipment when it survives the filter — that anchors the reset to
    /// "the section you were already reading" (per parent MY-1271 UX).
    /// When the previously visible equipment is missing from the new
    /// list (e.g. the current group has no barbell exercises), fall back
    /// to the first section of the new list (preserving MY-1250).
    /// Returns `nil` when the new list is empty.
    static func resolveMuscleGroupScrollAnchor(
        previouslyVisible: Equipment?,
        in newOrder: [Equipment]
    ) -> Equipment? {
        if let previous = previouslyVisible, newOrder.contains(previous) {
            return previous
        }
        return newOrder.first
    }

    /// MY-1259: pick the equipment section to scroll to when the search
    /// text changes. Search always resets scroll intent (the user changed
    /// query), so the anchor is unconditionally the first section of the
    /// filtered list — or `nil` when the search yields no matches so the
    /// caller does not attempt to scroll to a missing target. Mirrors
    /// `resolveMuscleGroupScrollAnchor`'s empty-list contract.
    static func resolveSearchScrollAnchor(
        in newOrder: [Equipment]
    ) -> Equipment? {
        newOrder.first
    }

    /// MY-1338: fixed section-preview popup dimensions. The popup used to
    /// grow horizontally with long equipment names (`minWidth: 140`), which
    /// made the surface visibly resize per scrub target and drift off
    /// centre. Locking a hard `width × height` means the layout is a
    /// no-op on every drag frame — long names truncate/scale inside the
    /// fixed frame instead of pushing the frame out.
    static let sectionPreviewPopupWidth: CGFloat = 160
    static let sectionPreviewPopupHeight: CGFloat = 160

    private func sectionPreviewPopup(equipment: Equipment) -> some View {
        VStack(spacing: 8) {
            Image(systemName: equipment.sfSymbol)
                .font(.system(size: 48, weight: .light))
            Text(equipment.localizedName)
                .font(.title3)
                .fontWeight(.medium)
                // MY-1338: single-line + shrink-to-fit so long localized
                // names (e.g. Chinese 3-4 chars, or long English words)
                // stay inside the fixed popup frame instead of stretching
                // it. `minimumScaleFactor(0.6)` keeps the text legible
                // down to ~60% of the base title3 point size, then the
                // trailing truncation kicks in if the string is still
                // too long — the frame itself never resizes.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(
            width: Self.sectionPreviewPopupWidth,
            height: Self.sectionPreviewPopupHeight
        )
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

// MARK: - Search Surface Container (MY-1445)

/// MY-1445: Shared container that applies the collapsed/expanded frame
/// constraint to the search surface ZStack. Used by both production
/// `ExercisePickerView.searchSurface` and layout regression tests so
/// the tested code path is identical to the production path.
///
/// In collapsed state, constrains the ZStack to `collapsedSearchMaxWidth`
/// (44pt) so the hidden expanded surface does not force a full-width
/// layout contribution. In expanded state, `.infinity` lets the search
/// field fill the available width.
///
/// The `.animation` modifier is placed BEFORE `.frame` so that opacity
/// transitions inside the ZStack are animated, but the frame width change
/// (44pt ↔ .infinity) bypasses animation — preventing intermediate widths
/// where the accessibility hit target is too narrow for XCUITest taps.
internal struct SearchSurfaceContainer<Expanded: View, Collapsed: View>: View {
    let isExpanded: Bool
    let expanded: Expanded
    let collapsed: Collapsed

    var body: some View {
        ZStack {
            expanded
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                // Both branches stay mounted to preserve the TextField's
                // FocusState identity. Keep the active branch physically on
                // top as well: XCUITest otherwise treats the transparent
                // collapsed Button as occluding the expanded TextField and
                // reports the field as non-hittable.
                .zIndex(isExpanded ? 1 : 0)
            collapsed
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)
                .zIndex(isExpanded ? 0 : 1)
        }
        .animation(.easeOut(duration: 0.22), value: isExpanded)
        .frame(
            maxWidth: isExpanded ? .infinity : ExercisePickerView.collapsedSearchMaxWidth,
            alignment: Alignment(
                horizontal: ExercisePickerView.searchSurfaceCollapsedAlignment,
                vertical: .center
            )
        )
    }
}

#if DEBUG
// MARK: - SearchSurfaceContainer Previews

#Preview("SearchSurface — Collapsed") {
    VStack(alignment: .trailing) {
        SearchSurfaceContainer(
            isExpanded: false,
            expanded: RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.15))
                .frame(maxWidth: .infinity)
                .frame(height: 44),
            collapsed: Circle()
                .fill(Color.blue)
                .frame(width: 44, height: 44)
        )
    }
    .frame(width: 369, height: 60, alignment: .trailing)
    .background(Color(.systemGroupedBackground))
}

#Preview("SearchSurface — Expanded") {
    VStack(alignment: .trailing) {
        SearchSurfaceContainer(
            isExpanded: true,
            expanded: RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.15))
                .overlay(
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("bench press")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 44),
            collapsed: Circle()
                .fill(Color.blue)
                .frame(width: 44, height: 44)
        )
    }
    .frame(width: 369, height: 60, alignment: .trailing)
    .background(Color(.systemGroupedBackground))
}
#endif

// MARK: - Floating Panel Attachment

/// Attaches the floating search + filter panel to the card grid without letting
/// it drive a layout-feedback loop.
///
/// The picker previously used `.safeAreaInset(edge: .bottom)`, whose resolved
/// inset is recomputed *inside* the grid's `LazySubviewPlacements.placeSubviews`
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

// MARK: - Collapsed Search Pill Surface (MY-1272)

/// Circular Liquid-Glass background for the collapsed search pill. Uses
/// the same gated material as `PanelSurfaceModifier` but clipped to a
/// `Circle()` so it reads as a compact pill instead of a slab. Falls back
/// to an opaque DesignKit card fill when Reduce Transparency is on.
private struct CollapsedSearchPillSurface: View {
    let theme: Theme
    let opaque: Bool

    @ViewBuilder
    var body: some View {
        if opaque {
            Circle()
                .fill(theme.neutrals.card)
                .overlay(Circle().strokeBorder(theme.neutrals.border, lineWidth: 1))
        } else {
            Color.clear
                .liquidGlassCapsule(theme: theme)
                .overlay(Circle().strokeBorder(theme.neutrals.border, lineWidth: 1))
                .clipShape(Circle())
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
    /// `animated == false` during a finger drag: the drag scrubs across many
    /// equipments and each triggers a `scrollTo`, so stacking a 0.2s animated
    /// scroll per frame to a tall section (e.g. 201-item machine) makes the
    /// animations fight and spikes the main thread. A tap sets `animated ==
    /// true` for a single smooth jump.
    let onSelect: (_ equipment: Equipment, _ animated: Bool) -> Void
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
                        onSelect(equipment, false)
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
