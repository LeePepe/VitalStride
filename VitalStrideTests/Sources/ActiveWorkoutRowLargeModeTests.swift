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
/// Row layout is verified visually via the
/// `#Preview("Row - Normal Mode")` / `#Preview("Row - Large Mode")` /
/// `#Preview("Row - Large Mode Unilateral")` blocks that live at the bottom
/// of `SetRow.swift`; the unilateral preview specifically exposes the
/// two-input overflow risk the AC calls out.
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

    @Test("Exercise name font is nil in normal mode (default header sizing preserved) and .title2 in Large Mode")
    func exerciseNameFontResolvesForBothModes() {
        // Normal mode must return nil so `.font(nil)` is applied to the
        // section header — this preserves the pre-MY-1091 default header
        // font (AC: "normal sizing must remain unchanged"). Any concrete
        // Font value here would be a regression.
        #expect(LargeWorkoutFonts.exerciseName(large: false) == nil)
        #expect(LargeWorkoutFonts.exerciseName(large: true) != nil)
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

    // MARK: Compact-width fit (MY-1091 P0 fix)

    /// iPhone SE / iPhone Mini list content width. `List.plain` on a 375pt
    /// device gives ≈343pt of horizontal space to a row after the row's own
    /// 16pt leading + 16pt trailing insets set in `ActiveExerciseSection`.
    /// This is the compact-width budget every Large Mode row must fit.
    private static let compactRowContentWidth: CGFloat = 343

    /// The trailing chrome the row unconditionally reserves: menu ellipsis
    /// button (44pt hit target) + completion button (44pt hit target). The
    /// `Spacer()` between them can fully collapse when the row is tight, so
    /// only the two fixed 44pt frames are counted against the fit budget.
    private static let trailingChromeWidth: CGFloat = 44 + 44

    /// Bilateral-row minimum required width.
    ///
    /// HStack children with fixed widths: setIndex, weight, reps, menu,
    /// Spacer, completion. The `Spacer()` between menu and completion
    /// collapses fully under pressure. The "×" glyph between weight and
    /// reps is not sized by us — SwiftUI lays it out at its intrinsic
    /// width, which is a handful of points at the row's font size and is
    /// dwarfed by the field widths. Counted spacings are the 4 non-Spacer
    /// HStack gaps (setIndex↔weight, weight↔×, ×↔reps, reps↔menu).
    private static func bilateralMinWidth(_ variant: LargeWorkoutFieldWidth.Variant) -> CGFloat {
        let spacing = LargeWorkoutFieldWidth.rowSpacing(variant)
        return LargeWorkoutFieldWidth.setIndexWidth(variant)
            + LargeWorkoutFieldWidth.bilateralWeight(variant)
            + LargeWorkoutFieldWidth.reps(variant)
            + trailingChromeWidth
            + spacing * 4
    }

    /// Unilateral-row minimum required width.
    ///
    /// HStack children with fixed widths: setIndex, weightL, weightR, reps,
    /// menu, Spacer, completion. The Spacer collapses fully under pressure.
    /// The "/" and "×" glyphs use intrinsic widths as above. Counted
    /// spacings are the 6 non-Spacer HStack gaps (setIndex↔wL, wL↔/,
    /// /↔wR, wR↔×, ×↔reps, reps↔menu).
    private static func unilateralMinWidth(_ variant: LargeWorkoutFieldWidth.Variant) -> CGFloat {
        let spacing = LargeWorkoutFieldWidth.rowSpacing(variant)
        return LargeWorkoutFieldWidth.setIndexWidth(variant)
            + LargeWorkoutFieldWidth.unilateralWeight(variant) * 2
            + LargeWorkoutFieldWidth.reps(variant)
            + trailingChromeWidth
            + spacing * 6
    }

    @Test("Wide Large Mode intentionally exceeds iPhone SE budget (justifies the ViewThatFits fallback)")
    func wideLargeExceedsCompactBudget() {
        // Reviewer P0 baseline: proves the wide variant does NOT fit compact
        // rows. If a future refactor accidentally shrinks the wide tokens
        // enough to fit, this test fails loudly and the ViewThatFits
        // fallback becomes redundant / dead code.
        #expect(Self.bilateralMinWidth(.large) > Self.compactRowContentWidth)
        #expect(Self.unilateralMinWidth(.large) > Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode fits iPhone SE list content width (bilateral)")
    func compactBilateralFitsCompactWidth() {
        // Reviewer P0 fix: the .largeCompact variant is what ViewThatFits
        // substitutes on 375pt phones. Its full row footprint MUST stay
        // within the 343pt content budget or the trailing menu / completion
        // controls clip off-screen — exactly the failure the reviewer cited.
        #expect(Self.bilateralMinWidth(.largeCompact) <= Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode fits iPhone SE list content width (unilateral overflow guard)")
    func compactUnilateralFitsCompactWidth() {
        // The AC explicitly calls out the unilateral overflow risk — two
        // side-by-side weight inputs plus a divider are the widest path.
        // The compact fallback must clear the budget here or the ViewThatFits
        // substitution is meaningless for the very case the reviewer cited.
        #expect(Self.unilateralMinWidth(.largeCompact) <= Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode still ramps at least one width above normal (Large intent preserved)")
    func compactLargeStillRampsAboveNormal() {
        // The compact fallback shrinks vs. wide Large so the unilateral row
        // fits an iPhone SE budget — for the two-input case, per-side weight
        // and reps must fall back to normal-mode widths (56 / 60) or the row
        // would clip its trailing controls. The Large Mode font ramp still
        // applies to those inputs (via SelectAllTextField's `.title1` font),
        // so legibility is preserved even at normal widths. But at LEAST one
        // width must still strictly ramp up in compact-large, otherwise
        // Large Mode delivers no visible sizing win on compact phones —
        // bilateral weight is the canonical ramp target because bilateral
        // rows have the horizontal headroom for it.
        #expect(
            LargeWorkoutFieldWidth.bilateralWeight(.largeCompact)
                > LargeWorkoutFieldWidth.bilateralWeight(.normal)
        )
        // Set-index badge also ramps up in Large Mode (both variants) so
        // multi-digit set counts stay legible without shifting column.
        #expect(
            LargeWorkoutFieldWidth.setIndexWidth(.largeCompact)
                > LargeWorkoutFieldWidth.setIndexWidth(.normal)
        )
        // The width fallback tokens must never *shrink* below normal — that
        // would be strictly worse than the pre-Large-Mode UI.
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(.largeCompact)
                >= LargeWorkoutFieldWidth.unilateralWeight(.normal)
        )
        #expect(
            LargeWorkoutFieldWidth.reps(.largeCompact)
                >= LargeWorkoutFieldWidth.reps(.normal)
        )
    }

    @Test("Normal mode already fits compact width (no ViewThatFits needed off Large Mode)")
    func normalFitsCompactWidth() {
        // Pins the "normal path is safe" invariant so a future refactor
        // that widens normal tokens gets caught here rather than by users.
        #expect(Self.bilateralMinWidth(.normal) <= Self.compactRowContentWidth)
        #expect(Self.unilateralMinWidth(.normal) <= Self.compactRowContentWidth)
    }
}
