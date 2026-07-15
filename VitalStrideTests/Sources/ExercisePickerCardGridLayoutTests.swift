import Foundation
import Testing

@testable import VitalStride

/// Regression coverage for MY-1251 — the card-grid horizontal padding must be
/// stable across multi-section ↔ single-section muscle-group switches. In the
/// prior implementation the trailing padding toggled 48pt / 0pt with index-bar
/// visibility, reflowing the LazyVGrid columns and shifting the visible
/// leading margin. The fix pins the horizontal insets to constants that do
/// not depend on `showsIndexBar`; this test pins those constants so a future
/// change cannot silently re-introduce the toggle.
@Suite("ExercisePicker card grid layout invariants (MY-1251)")
struct ExercisePickerCardGridLayoutTests {

    @Test("Horizontal card-grid insets are constants, independent of index-bar visibility")
    func horizontalInsetsAreConstant() {
        // Leading inset is a fixed constant — never conditional.
        #expect(ExercisePickerView.cardGridHorizontalInset == 16)

        // Trailing reserve is a fixed constant — the space the index bar
        // physically occupies is always reserved, whether or not the bar is
        // rendered, so switching between multi-section and single-section
        // groups cannot change the available width for `LazyVGrid` columns.
        #expect(ExercisePickerView.cardGridIndexBarReserve > 0)

        // The reserve must cover the full index-bar hit target so the visible
        // card content never overlaps or shifts under the bar.
        #expect(ExercisePickerView.cardGridIndexBarReserve >= 44)
    }

    @Test("Vertical inset stays constant across section-count changes")
    func verticalInsetIsConstant() {
        #expect(ExercisePickerView.cardGridVerticalInset == 16)
    }
}
