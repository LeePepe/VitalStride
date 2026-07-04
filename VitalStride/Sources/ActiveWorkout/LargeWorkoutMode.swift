// MY-1088: workout-specific Large Mode font/frame helpers, keyed off the
// `activeWorkoutLargeMode` @AppStorage flag on ActiveWorkoutView. The flag is
// propagated to descendant rows through an environment key so SetRow /
// ActiveExerciseSection do not need to re-read UserDefaults per row.
//
// Rationale: this is a *workout-specific* large mode (Hevy "Now Lifting"
// parity), not a substitute for the system Dynamic Type setting. It applies
// only inside `ActiveWorkoutView` and stacks with the user's system text size
// rather than replacing it.

import SwiftUI

/// Toggle propagated to `ActiveWorkoutView`'s subviews so they can pick the
/// larger font/frame variants when Large Mode is on.
struct LargeWorkoutModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `true` when the Large Mode toggle is active for the current
    /// `ActiveWorkoutView`. Read by `SetRow`, `ActiveExerciseSection`, etc.
    var isLargeWorkoutMode: Bool {
        get { self[LargeWorkoutModeKey.self] }
        set { self[LargeWorkoutModeKey.self] = newValue }
    }
}

/// Font/frame tokens for the Active Workout Large Mode.
///
/// Kept as a pure value type so the previews / snapshot tests can render both
/// modes without touching `@AppStorage` or the SwiftUI environment.
enum LargeWorkoutFonts {
    /// Weight / reps input font. Large Mode uses ≥ 28pt bold monospaced digits
    /// so the current set is legible from across a gym rack (issue AC).
    static func weight(large: Bool) -> Font {
        large ? .system(size: 32, weight: .bold).monospacedDigit() : .body
    }

    /// Reps input font — same size profile as `weight` in both modes.
    static func reps(large: Bool) -> Font {
        weight(large: large)
    }

    /// Workout-elapsed timer font. `.largeTitle` in Large Mode per issue AC.
    static func timer(large: Bool) -> Font {
        large ? .largeTitle.monospacedDigit() : .title3.monospacedDigit()
    }

    /// Exercise name header font. `.title2` in Large Mode per issue AC.
    static func exerciseName(large: Bool) -> Font {
        large ? .title2.bold() : .headline
    }

    /// Summary line ("N 动作 · M 组 · V kg") and set-index badge font.
    static func summary(large: Bool) -> Font {
        large ? .title3 : .subheadline
    }
}

/// Width of the bilateral weight / reps input in points.
enum LargeWorkoutFieldWidth {
    static func bilateralWeight(large: Bool) -> CGFloat { large ? 110 : 70 }
    static func unilateralWeight(large: Bool) -> CGFloat { large ? 88 : 56 }
    static func reps(large: Bool) -> CGFloat { large ? 88 : 60 }

    /// Minimum tap-target height in Large Mode. 60pt exceeds the HIG 44pt
    /// floor while giving fingers room in a gym context (issue AC).
    static let largeMinHeight: CGFloat = 60
}
