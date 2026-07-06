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
    /// the currently-worked movement stays legible from a rack step away.
    /// Returns `nil` in normal mode so the caller applies no explicit font —
    /// the pre-MY-1091 header rendered with SwiftUI's default `Section` header
    /// style (inherited via `Text` in a `List` `Section` `header`), and the
    /// AC pins that normal sizing must remain unchanged (MY-1091 P0).
    static func exerciseName(large: Bool) -> Font? {
        large ? Font.system(.title2, design: .default).weight(.semibold) : nil
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
///
/// Large Mode ships two width variants — `.large` (wide preference) and
/// `.largeCompact` (compact fallback). `SetRow` picks between them with
/// `ViewThatFits(in: .horizontal)`: on wide phones (Pro Max, landscape) the
/// wide variant renders; on compact phones (iPhone SE / iPhone Mini, 375pt
/// content width) SwiftUI substitutes the compact variant so the row does not
/// clip its trailing menu / completion controls off-screen.
enum LargeWorkoutFieldWidth {
    /// Sizing variant a row can request. `.normal` matches the pre-MY-1091
    /// density; `.large` is the wide Large Mode preference; `.largeCompact`
    /// is the Large Mode fallback that fits an iPhone SE list content width.
    enum Variant {
        case normal
        case large
        case largeCompact
    }

    /// Bilateral weight input width per variant.
    ///
    /// Wide-large 110 keeps a three-digit kg/lb value on one line at a glance;
    /// compact-large 88 preserves the ≥28pt input font (via `.title1`) and
    /// still fits an iPhone SE (375pt) list content width once the compact
    /// spacing / set-index tokens below are also applied. Values wider than
    /// 88 would push the bilateral row past the 343pt budget after row insets.
    static func bilateralWeight(_ variant: Variant) -> CGFloat {
        switch variant {
        case .normal: return 70
        case .large: return 110
        case .largeCompact: return 88
        }
    }

    /// Per-side (unilateral) weight input width per variant.
    ///
    /// Unilateral rows show two side-by-side weight inputs plus a "/" divider
    /// plus "×" plus reps — the widest path the AC calls out. Wide-large 88
    /// keeps three digits + a decimal on one line at Pro Max width;
    /// compact-large 56 matches the current normal-mode width so the row
    /// still fits an iPhone SE budget after the two-input footprint. The
    /// Large Mode `.title1` font is still applied by `SetRow` in both
    /// variants — legibility comes from the font ramp; only the width falls
    /// back to normal here.
    static func unilateralWeight(_ variant: Variant) -> CGFloat {
        switch variant {
        case .normal: return 56
        case .large: return 88
        case .largeCompact: return 56
        }
    }

    /// Reps input width per variant. Wide-large 88 keeps a two-digit reps
    /// value + Large Mode font comfortable; compact-large 60 matches
    /// normal-mode width — the Large Mode font ramp preserves legibility
    /// while freeing horizontal budget for the two-input unilateral case.
    static func reps(_ variant: Variant) -> CGFloat {
        switch variant {
        case .normal: return 60
        case .large: return 88
        case .largeCompact: return 60
        }
    }

    /// Set-index badge width per variant. The wide-large badge is 32pt (fits
    /// a `.title3` two-digit number); compact-large drops back to 28pt to
    /// reclaim 4pt of horizontal budget without going below the normal 24pt.
    static func setIndexWidth(_ variant: Variant) -> CGFloat {
        switch variant {
        case .normal: return 24
        case .large: return 32
        case .largeCompact: return 28
        }
    }

    /// Row `HStack` spacing per variant. Compact-large drops from 8 to 4 to
    /// reclaim ~16-32pt across the row's spacer count without visibly
    /// crowding — the Large Mode font ramp keeps individual inputs distinct
    /// even at tighter gaps.
    static func rowSpacing(_ variant: Variant) -> CGFloat {
        switch variant {
        case .normal, .large: return 8
        case .largeCompact: return 4
        }
    }

    /// Row min-height applied to every editable input in Large Mode. 60pt is
    /// the AC target; the HIG 44pt floor is preserved implicitly (60 > 44).
    /// Applied to both `.large` and `.largeCompact` — the compact variant
    /// still targets a rack-step-away reading distance.
    static let largeMinHeight: CGFloat = 60

    // MARK: - Bool convenience overloads (retained for the token contract)
    //
    // The `Bool` variants below preserve the pre-adaptive contract so the
    // existing token-level tests keep passing and any callers that only know
    // "large mode on/off" (e.g. non-row surfaces, tests) keep resolving to
    // the current wide-Large values.

    static func bilateralWeight(large: Bool) -> CGFloat {
        bilateralWeight(large ? .large : .normal)
    }

    static func unilateralWeight(large: Bool) -> CGFloat {
        unilateralWeight(large ? .large : .normal)
    }

    static func reps(large: Bool) -> CGFloat {
        reps(large ? .large : .normal)
    }
}
