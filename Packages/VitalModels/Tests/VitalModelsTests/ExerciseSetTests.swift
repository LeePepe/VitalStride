import Foundation
import Testing
@testable import VitalModels

@Suite("ExerciseSet Tests")
struct ExerciseSetTests {
    @Test("isCompleted defaults to false")
    func isCompletedDefaultValue() {
        let set = ExerciseSet(weight: 60.0, reps: 10)
        #expect(set.isCompleted == false)
    }

    @Test("isCompleted can be set to true via init")
    func isCompletedViaInit() {
        let set = ExerciseSet(weight: 80.0, reps: 5, isCompleted: true)
        #expect(set.isCompleted == true)
    }

    @Test("isCompleted can be toggled")
    func isCompletedToggle() {
        let set = ExerciseSet(weight: 100.0, reps: 3)
        #expect(set.isCompleted == false)
        set.isCompleted = true
        #expect(set.isCompleted == true)
        set.isCompleted = false
        #expect(set.isCompleted == false)
    }

    @Test("SetType displayName returns correct Chinese names")
    func setTypeDisplayName() {
        #expect(SetType.working.displayName == "正式")
        #expect(SetType.warmup.displayName == "热身")
    }

    @Test("init preserves all fields")
    func initPreservesFields() {
        let set = ExerciseSet(
            order: 2,
            weight: 50.5,
            reps: 12,
            setType: .warmup,
            restDuration: 90,
            isCompleted: true
        )
        #expect(set.order == 2)
        #expect(set.weight == 50.5)
        #expect(set.reps == 12)
        #expect(set.setType == .warmup)
        #expect(set.restDuration == 90)
        #expect(set.isCompleted == true)
    }

    @Test("default values for optional and defaulted fields")
    func defaultValues() {
        let set = ExerciseSet(weight: 0, reps: 0)
        #expect(set.order == 0)
        #expect(set.weight == 0)
        #expect(set.reps == 0)
        #expect(set.setType == .working)
        #expect(set.restDuration == nil)
        #expect(set.isCompleted == false)
        #expect(set.workoutExercise == nil)
    }
}
