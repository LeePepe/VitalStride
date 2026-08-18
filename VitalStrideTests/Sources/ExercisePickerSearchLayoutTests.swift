import Foundation
import Testing

@testable import VitalStride

/// Regression coverage for MY-1445 — the collapsed search surface must NOT
/// force a full-width ZStack. In collapsed state the search pill should be
/// exactly `collapsedSearchDiameter` (44pt) wide and trailing-aligned with
/// the panel content edge. The expanded surface must not contribute to layout
/// width when hidden.
///
/// Tests mirror the static-invariant style of `ExercisePickerCardGridLayoutTests`
/// — asserting on the publicly accessible constants and computed functions that
/// drive the layout constraint.
@Suite("ExercisePicker collapsed search layout (MY-1445)")
struct ExercisePickerSearchLayoutTests {

    // MARK: - Collapsed width invariant

    @Test("Collapsed search surface max width equals collapsedSearchDiameter (44pt)")
    func collapsedSearchWidthEqualsCollapsedDiameter() {
        let maxWidth = ExercisePickerView.collapsedSearchMaxWidth
        #expect(maxWidth == ExercisePickerView.collapsedSearchDiameter)
        #expect(maxWidth == 44, "Constitution §H: ≥44pt hit target")
    }

    @Test("Collapsed search surface is significantly narrower than any realistic panel width")
    func collapsedWidthIsNarrowerThanPanel() {
        // The collapsed pill must be compact; it should never approach panel
        // width. We test against the minimum realistic container width (iPhone
        // SE minus horizontal panel insets) to prove the pill is visually
        // "significantly narrower than panel width" per acceptance criteria.
        let panelInset = ExercisePickerView.panelHorizontalInset
        let minPanelContentWidth: CGFloat = 320 - panelInset * 2 // iPhone SE portrait
        let collapsedWidth = ExercisePickerView.collapsedSearchMaxWidth

        // The pill should be less than 25% of the narrowest realistic panel
        #expect(collapsedWidth < minPanelContentWidth * 0.25,
                "Collapsed pill (\(collapsedWidth)pt) should be significantly narrower than panel content (\(minPanelContentWidth)pt)")
    }

    // MARK: - Expanded width invariant

    @Test("Expanded search surface fills available width (maxWidth is infinity-equivalent)")
    func expandedSearchFillsAvailableWidth() {
        // `expandedSearchMaxWidth` returns nil to represent .infinity
        // (the expanded surface should fill the parent with `maxWidth: .infinity`).
        #expect(ExercisePickerView.expandedSearchMaxWidth == nil,
                "Expanded state should use unconstrained width (nil == .infinity)")
    }

    // MARK: - Alignment invariant

    @Test("Search surface alignment in collapsed state is trailing")
    func collapsedAlignmentIsTrailing() {
        // The floatingSearchAndFilterPanel VStack uses .trailing alignment,
        // and the searchSurface frame uses .trailing alignment — so the
        // collapsed 44pt pill should be flush to the panel's trailing edge.
        // We verify this via the static alignment constant.
        #expect(ExercisePickerView.searchSurfaceCollapsedAlignment == .trailing)
    }
}
