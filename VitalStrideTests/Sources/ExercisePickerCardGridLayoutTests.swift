import Foundation
import Testing

@testable import VitalStride

/// Regression coverage for MY-1251 / MY-1258 — the card-grid horizontal
/// padding must be stable across multi-section ↔ single-section muscle-group
/// switches (i.e. across index-bar-visible vs index-bar-hidden states). In
/// the prior implementation the trailing padding toggled 48pt / 0pt with
/// index-bar visibility, reflowing the LazyVGrid columns and shifting the
/// visible leading margin. These tests behaviorally evaluate the inset
/// functions in both states and assert that the values — and the width
/// available to `LazyVGrid` — do not change between them.
@Suite("ExercisePicker card grid layout invariants (MY-1251 / MY-1258)")
struct ExercisePickerCardGridLayoutTests {

    // MARK: Behavioral checkpoint — invariant across index-bar visibility

    @Test("Leading inset is invariant across index-bar-visible and index-bar-hidden states")
    func leadingInsetInvariantAcrossVisibilityStates() {
        let visible = ExercisePickerView.cardGridLeadingInset(showsIndexBar: true)
        let hidden = ExercisePickerView.cardGridLeadingInset(showsIndexBar: false)

        // The core behavioral invariant: switching muscle groups between
        // multi-section (bar visible) and single-section (bar hidden) MUST
        // NOT change the leading inset. If a future change conditionally
        // varies leading on `showsIndexBar`, this fails.
        #expect(visible == hidden)

        // The reserved leading value must be positive (grid should not touch
        // the container edge).
        #expect(visible > 0)
    }

    @Test("Trailing inset is invariant across index-bar-visible and index-bar-hidden states")
    func trailingInsetInvariantAcrossVisibilityStates() {
        let visible = ExercisePickerView.cardGridTrailingInset(showsIndexBar: true)
        let hidden = ExercisePickerView.cardGridTrailingInset(showsIndexBar: false)

        // Core behavioral invariant of the MY-1251 fix. If a future change
        // makes the trailing padding toggle with index-bar visibility (the
        // exact regression we are guarding), this fails.
        #expect(visible == hidden)

        // Trailing inset must reserve at least the physical width of the
        // index-bar hit target so the grid never overlaps the bar area,
        // even when the bar is currently hidden.
        #expect(visible >= 44)
    }

    @Test("Available card-grid width is invariant across index-bar visibility")
    func availableGridWidthInvariantAcrossVisibilityStates() {
        // Exercise the invariant at multiple realistic container widths
        // (iPhone SE, iPhone 16, iPad column).
        for containerWidth in [320.0, 393.0, 430.0, 744.0, 1024.0] as [CGFloat] {
            let widthWhenVisible = ExercisePickerView.cardGridAvailableWidth(
                containerWidth: containerWidth,
                showsIndexBar: true
            )
            let widthWhenHidden = ExercisePickerView.cardGridAvailableWidth(
                containerWidth: containerWidth,
                showsIndexBar: false
            )

            // The regression MY-1251 fixed manifested as the LazyVGrid
            // available width changing when the index bar hid; this
            // asserts that behavior does not return.
            #expect(widthWhenVisible == widthWhenHidden,
                    "available grid width differed at container=\(containerWidth): visible=\(widthWhenVisible), hidden=\(widthWhenHidden)")

            // And the available width must consume both leading and
            // trailing insets from the container.
            let expected = containerWidth
                - ExercisePickerView.cardGridLeadingInset(showsIndexBar: true)
                - ExercisePickerView.cardGridTrailingInset(showsIndexBar: true)
            #expect(widthWhenVisible == max(0, expected))
        }
    }

    // MARK: Constants preserved (guards the merged visual fix)

    @Test("Reserved trailing space covers the full index-bar hit target")
    func trailingInsetCoversIndexBarHitTarget() {
        // The trailing reserve must be strictly greater than horizontal
        // inset alone — proving space is actually reserved for the index
        // bar even when it is not rendered.
        let trailing = ExercisePickerView.cardGridTrailingInset(showsIndexBar: false)
        #expect(trailing > ExercisePickerView.cardGridHorizontalInset)
    }

    @Test("Vertical inset stays constant across section-count changes")
    func verticalInsetIsConstant() {
        #expect(ExercisePickerView.cardGridVerticalInset == 16)
    }
}
