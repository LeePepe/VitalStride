// MY-1091: row-level Large Mode tokens for Active Workout.
//
// Split out of MY-1088 (which shipped the toolbar toggle + header font ramp)
// after Fullstack's re-scope signal. This file introduces the environment key
// consumed by descendant rows (SetRow / ActiveExerciseSection) plus the pure
// value tokens for font/width used by the row-level Large Mode.
//
// Dynamic Type contract (MY-1088 P0 lesson): Large Mode raises the base
// text style; it never replaces the user's system Dynamic Type setting.
// - SwiftUI fonts use `Font.system(_ TextStyle, ...)` so they scale with the
//   user's Content Size Category.
// - UIKit inputs (SelectAllTextField) use `UIFont.preferredFont(forTextStyle:)`
//   whose text-field host already sets `adjustsFontForContentSizeCategory = true`,
//   so those also scale with Dynamic Type.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Environment flag propagated from `ActiveWorkoutView` to descendant rows so
/// they can pick the larger font/width variants when Large Mode is on. Rows do
/// not re-read `UserDefaults` per render — the toggle lives on the workout
/// view; the value flows down through the environment.
struct LargeWorkoutModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` when Active Workout Large Mode is on. Read by `SetRow` and
    /// `ActiveExerciseSection` to select the row-level font/width variants.
    var isLargeWorkoutMode: Bool {
        get { self[LargeWorkoutModeKey.self] }
        set { self[LargeWorkoutModeKey.self] = newValue }
    }
}

/// SwiftUI `Font` tokens for the Active Workout row-level Large Mode.
///
/// All fonts are built from `Font.system(_ TextStyle, ...)` so they stack with
/// the user's Dynamic Type setting instead of pinning to a fixed point size
/// (MY-1088 review lesson: `.system(size: N)` blocks Dynamic Type).
enum LargeWorkoutFonts {
    /// Exercise name shown in the section header. `.title2` in Large Mode so
    /// the currently-worked movement stays legible from a rack step away;
    /// `.headline` in normal mode preserves current density.
    static func exerciseName(large: Bool) -> Font {
        Font.system(large ? .title2 : .headline, design: .default).weight(.semibold)
    }

    /// Set-index badge ("1", "2", …) leading the row. `.title3` in Large Mode,
    /// `.subheadline` in normal mode. Monospaced digits so multi-digit indices
    /// do not shift the column.
    static func setIndex(large: Bool) -> Font {
        Font.system(large ? .title3 : .subheadline, design: .default).monospacedDigit()
    }
}

/// UIKit `UIFont` tokens for the Active Workout row-level Large Mode.
///
/// SelectAllTextField's host `UITextField` sets
/// `adjustsFontForContentSizeCategory = true`, so `preferredFont(forTextStyle:)`
/// naturally scales with the user's Dynamic Type setting. Large Mode picks
/// `.title1` (≈ 28pt at the default Dynamic Type size, which satisfies the
/// ≥ 28pt Large Mode acceptance criterion while still scaling up further when
/// the user enlarges system text).
enum LargeWorkoutInputFont {
    #if canImport(UIKit)
    /// Bold monospaced-digit weight/reps input font. Uses text-style-driven
    /// sizing so Dynamic Type stacks on top of Large Mode.
    static func weightReps(large: Bool) -> UIFont {
        let baseStyle: UIFont.TextStyle = large ? .title1 : .body
        let base = UIFont.preferredFont(forTextStyle: baseStyle)
        let descriptor = base.fontDescriptor
            .addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
            .withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }
    #endif
}

/// Width / height tokens for the row-level Large Mode.
///
/// Normal-mode values mirror the pre-MY-1088 shape (bilateral 70 / unilateral
/// 56 / reps 60) so the existing UI does not shift. Large-mode values expand
/// the inputs to keep multi-digit weights/reps readable at glance distance.
enum LargeWorkoutFieldWidth {
    /// Bilateral weight input width. Normal 70pt → Large 110pt so a three-digit
    /// kg/lb value stays on one line without truncation (per issue AC).
    static func bilateralWeight(large: Bool) -> CGFloat { large ? 110 : 70 }

    /// Per-side (unilateral) weight input width. Normal 56pt → Large 88pt.
    /// A single unilateral row shows two side-by-side weight inputs plus a
    /// "/" divider plus "×" plus reps; 88pt per side keeps three digits + a
    /// decimal on one line without overflowing the row on 375pt-wide phones.
    static func unilateralWeight(large: Bool) -> CGFloat { large ? 88 : 56 }

    /// Reps input width. Normal 60pt → Large 88pt so a two-digit reps value
    /// plus the larger-mode font still fits without clipping.
    static func reps(large: Bool) -> CGFloat { large ? 88 : 60 }

    /// Row min-height applied to every editable input in Large Mode. 60pt is
    /// the AC target; the HIG 44pt floor is preserved implicitly (60 > 44).
    static let largeMinHeight: CGFloat = 60
}
