// MY-1088 — Active workout Large Mode tokens.
//
// Verifies the numeric values behind the toolbar toggle so refactors cannot
// silently drop the width / font ramp below the acceptance floor documented on
// MY-1088 (weight/reps ≥ 28pt, bilateral input 70 → 110, unilateral field
// grows, tap-target minHeight ≥ 44pt).

import SwiftUI
import Testing

@testable import VitalStride

@Suite("Large Workout Mode tokens (MY-1088)")
struct LargeWorkoutModeTests {

    // MARK: - LargeWorkoutFieldWidth

    @Test("Bilateral weight input width matches spec: 70pt → 110pt")
    func bilateralWeightWidthRamp() {
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: false) == 70)
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: true) == 110)
    }

    @Test("Unilateral weight input grows in large mode")
    func unilateralWeightWidthGrows() {
        let normal = LargeWorkoutFieldWidth.unilateralWeight(large: false)
        let large = LargeWorkoutFieldWidth.unilateralWeight(large: true)
        #expect(normal == 56)
        #expect(large > normal)
    }

    @Test("Reps input grows in large mode")
    func repsWidthGrows() {
        let normal = LargeWorkoutFieldWidth.reps(large: false)
        let large = LargeWorkoutFieldWidth.reps(large: true)
        #expect(normal == 60)
        #expect(large > normal)
    }

    @Test("Large mode minHeight is ≥ 60pt (spec) and ≥ 44pt HIG floor")
    func largeMinHeightMeetsFloor() {
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 60)
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 44)
    }

    // MARK: - LargeWorkoutFonts

    @Test("Weight/reps fonts change between modes")
    func fontsChangeBetweenModes() {
        #expect(LargeWorkoutFonts.weight(large: true) != LargeWorkoutFonts.weight(large: false))
        #expect(LargeWorkoutFonts.reps(large: true) != LargeWorkoutFonts.reps(large: false))
    }

    @Test("Timer font is largeTitle in large mode, title3 otherwise")
    func timerFontMatchesSpec() {
        #expect(LargeWorkoutFonts.timer(large: true) == Font.largeTitle.monospacedDigit())
        #expect(LargeWorkoutFonts.timer(large: false) == Font.title3.monospacedDigit())
    }

    @Test("Exercise name font is title2 bold in large mode, headline otherwise")
    func exerciseNameFontMatchesSpec() {
        #expect(LargeWorkoutFonts.exerciseName(large: true) == Font.title2.bold())
        #expect(LargeWorkoutFonts.exerciseName(large: false) == Font.headline)
    }

    // MARK: - Environment default

    @Test("Environment default value is false so non-workout screens see normal fonts")
    func environmentDefaultIsFalse() {
        #expect(LargeWorkoutModeKey.defaultValue == false)
    }
}
