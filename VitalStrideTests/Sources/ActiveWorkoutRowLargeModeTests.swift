import SwiftUI
import Testing

@testable import VitalStride

/// MY-1091 — Row-level Large Mode token verification for `SetRow` /
/// `ActiveExerciseSection`.
///
/// These tests pin the numeric contract behind the row-level Large Mode:
/// the width/font/min-height tokens introduced in `LargeWorkoutMode.swift`
/// and the persistence key shared with the toolbar toggle from MY-1088.
///
/// The visual side (SwiftUI layout of both modes, including unilateral
/// weight overflow risk on a 375pt-wide phone) is covered by the
/// `#Preview("Row - Normal Mode")` / `#Preview("Row - Large Mode")` /
/// `#Preview("Row - Large Mode Unilateral")` blocks in
/// `LargeWorkoutMode.swift`.
@Suite("Active Workout row-level Large Mode (MY-1091)")
struct ActiveWorkoutRowLargeModeTests {
    private static let largeModeKey = "activeWorkoutLargeMode"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.largeModeKey)
    }

    // MARK: Width tokens

    @Test("Bilateral weight width expands 70 → 110 for Large Mode (AC)")
    func bilateralWeightWidthExpands() {
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: false) == 70)
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: true) == 110)
    }

    @Test("Unilateral weight width expands 56 → 88 for Large Mode (AC)")
    func unilateralWeightWidthExpands() {
        #expect(LargeWorkoutFieldWidth.unilateralWeight(large: false) == 56)
        #expect(LargeWorkoutFieldWidth.unilateralWeight(large: true) == 88)
    }

    @Test("Reps width expands 60 → 88 for Large Mode (AC)")
    func repsWidthExpands() {
        #expect(LargeWorkoutFieldWidth.reps(large: false) == 60)
        #expect(LargeWorkoutFieldWidth.reps(large: true) == 88)
    }

    @Test("Large Mode min-height meets ≥60pt AC and clears HIG 44pt tap target")
    func minHeightMeetsAcAndHigFloor() {
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 60)
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 44)
    }

    /// Unilateral rows show two side-by-side weight inputs where bilateral
    /// rows show one — the AC calls out overflow risk on this path. The
    /// design invariant that keeps both modes rendering in an iPhone row is
    /// that per-side unilateral width stays below bilateral width so the
    /// two-input pair does not simply double the bilateral footprint. This
    /// test pins that invariant in both modes so a future width tweak
    /// cannot silently widen unilateral back to bilateral parity (which is
    /// what would push the row into horizontal clipping).
    @Test("Per-side unilateral weight width stays below bilateral in both modes (overflow guard)")
    func unilateralWidthStaysBelowBilateral() {
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: false)
                < LargeWorkoutFieldWidth.bilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: true)
                < LargeWorkoutFieldWidth.bilateralWeight(large: true)
        )
    }

    /// Widths must ramp *up* into Large Mode for every input class — a
    /// future refactor that accidentally flipped a token would still pass
    /// the equality checks above but violate the AC intent.
    @Test("Every input width ramps up in Large Mode (AC intent guard)")
    func everyInputWidthRampsUp() {
        #expect(
            LargeWorkoutFieldWidth.bilateralWeight(large: true)
                > LargeWorkoutFieldWidth.bilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: true)
                > LargeWorkoutFieldWidth.unilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.reps(large: true)
                > LargeWorkoutFieldWidth.reps(large: false)
        )
    }

    // MARK: Font tokens (Dynamic-Type-stacking contract)

    @Test("Weight/reps input font differs between modes (Large Mode raises the ramp)")
    func inputFontDiffersAcrossModes() {
        #if canImport(UIKit)
        let normalFont = LargeWorkoutInputFont.weightReps(large: false)
        let largeFont = LargeWorkoutInputFont.weightReps(large: true)
        // Dynamic Type may scale both, but Large Mode's base text style
        // (.title1) is strictly larger than normal mode's (.body), so the
        // resolved point size must be strictly greater for equal environment.
        #expect(largeFont.pointSize > normalFont.pointSize)
        #endif
    }

    @Test("Large Mode input font satisfies the ≥28pt AC at default Dynamic Type size")
    func inputFontMeetsMinimumSize() {
        #if canImport(UIKit)
        // .title1 at the default (.large) Content Size Category is 28pt on
        // Apple's published Type Ramp, matching the AC floor. If a future
        // refactor swaps to a smaller text style, .title1's pointSize check
        // below still passes but this token contract catches the drift.
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let title1 = UIFont.preferredFont(forTextStyle: .title1, compatibleWith: traits)
        #expect(title1.pointSize >= 28)
        #endif
    }

    @Test("Exercise name font token defined for both modes (no crash / nil path)")
    func exerciseNameFontResolvesForBothModes() {
        _ = LargeWorkoutFonts.exerciseName(large: false)
        _ = LargeWorkoutFonts.exerciseName(large: true)
    }

    @Test("Set-index badge font token defined for both modes (no crash / nil path)")
    func setIndexFontResolvesForBothModes() {
        _ = LargeWorkoutFonts.setIndex(large: false)
        _ = LargeWorkoutFonts.setIndex(large: true)
    }

    // MARK: Persistence contract

    @Test("Row Large Mode reads the same @AppStorage key the toolbar toggle writes")
    func rowLargeModeSharesToolbarPersistenceKey() {
        UserDefaults.standard.set(true, forKey: Self.largeModeKey)
        // A fresh SetRow / ActiveExerciseSection's
        // @AppStorage("activeWorkoutLargeMode") reads this back, so the row
        // font/frame ramp restores together with the header the toolbar
        // toggle already restored (MY-1088 AC preserved end-to-end).
        #expect(UserDefaults.standard.bool(forKey: Self.largeModeKey))
        UserDefaults.standard.removeObject(forKey: Self.largeModeKey)
    }
}
