import Foundation
import Testing
@testable import VitalModels

@Suite("WorkoutExercise workingVolume Tests")
struct WorkoutExerciseTests {

    // MARK: - Bilateral Volume

    @Test("bilateral volume sums weight × reps for completed working sets")
    func bilateralVolumeCompleted() {
        let s1 = ExerciseSet(order: 0, weight: 60.0, reps: 10, isCompleted: true)
        let s2 = ExerciseSet(order: 1, weight: 80.0, reps: 8, isCompleted: true)
        let we = WorkoutExercise(order: 0, sets: [s1, s2])
        #expect(we.workingVolume == 60.0 * 10 + 80.0 * 8)
    }

    @Test("bilateral volume ignores non-completed sets when workout is in progress")
    func bilateralVolumeIgnoresIncomplete() {
        let completed = ExerciseSet(order: 0, weight: 60.0, reps: 10, isCompleted: true)
        let incomplete = ExerciseSet(order: 1, weight: 80.0, reps: 8, isCompleted: false)
        let we = WorkoutExercise(order: 0, sets: [completed, incomplete])
        #expect(we.workingVolume == 60.0 * 10)
    }

    @Test("bilateral volume is zero when no sets are completed")
    func bilateralVolumeZeroWhenNoneCompleted() {
        let s1 = ExerciseSet(order: 0, weight: 60.0, reps: 10, isCompleted: false)
        let we = WorkoutExercise(order: 0, sets: [s1])
        #expect(we.workingVolume == 0.0)
    }

    // MARK: - Warmup Exclusion

    @Test("warmup sets are excluded from working volume")
    func warmupExcluded() {
        let warmup = ExerciseSet(order: 0, weight: 40.0, reps: 10, setType: .warmup, isCompleted: true)
        let working = ExerciseSet(order: 1, weight: 80.0, reps: 8, isCompleted: true)
        let we = WorkoutExercise(order: 0, sets: [warmup, working])
        #expect(we.workingVolume == 80.0 * 8)
    }

    @Test("volume is zero when all sets are warmups")
    func allWarmupsVolume() {
        let w1 = ExerciseSet(order: 0, weight: 30.0, reps: 10, setType: .warmup, isCompleted: true)
        let w2 = ExerciseSet(order: 1, weight: 40.0, reps: 8, setType: .warmup, isCompleted: true)
        let we = WorkoutExercise(order: 0, sets: [w1, w2])
        #expect(we.workingVolume == 0.0)
    }

    // MARK: - Unilateral Volume

    @Test("unilateral volume uses left + right independently")
    func unilateralBothWeights() {
        let s = ExerciseSet(
            order: 0, weight: 25.0, reps: 10,
            isCompleted: true, isUnilateral: true, weightRight: 22.5
        )
        let we = WorkoutExercise(order: 0, sets: [s])
        let expected = 25.0 * 10 + 22.5 * 10
        #expect(we.workingVolume == expected)
    }

    @Test("unilateral volume falls back to left weight when weightRight is nil")
    func unilateralNilRightFallback() {
        let s = ExerciseSet(
            order: 0, weight: 30.0, reps: 8,
            isCompleted: true, isUnilateral: true, weightRight: nil
        )
        let we = WorkoutExercise(order: 0, sets: [s])
        let expected = 30.0 * 8 + 30.0 * 8
        #expect(we.workingVolume == expected)
    }

    @Test("unilateral warmup excluded from volume")
    func unilateralWarmupExcluded() {
        let warmup = ExerciseSet(
            order: 0, weight: 15.0, reps: 10, setType: .warmup,
            isCompleted: true, isUnilateral: true, weightRight: 15.0
        )
        let working = ExerciseSet(
            order: 1, weight: 25.0, reps: 8,
            isCompleted: true, isUnilateral: true, weightRight: 22.5
        )
        let we = WorkoutExercise(order: 0, sets: [warmup, working])
        let expected = 25.0 * 8 + 22.5 * 8
        #expect(we.workingVolume == expected)
    }

    // MARK: - Finished Workout (all sets count)

    @Test("finished workout counts all working sets regardless of isCompleted")
    func finishedWorkoutCountsAll() {
        let completed = ExerciseSet(order: 0, weight: 60.0, reps: 10, isCompleted: true)
        let incomplete = ExerciseSet(order: 1, weight: 80.0, reps: 8, isCompleted: false)
        let we = WorkoutExercise(order: 0, sets: [completed, incomplete])
        let workout = Workout(type: .strength, startDate: Date(), endDate: Date())
        we.workout = workout
        #expect(we.workingVolume == 60.0 * 10 + 80.0 * 8)
    }

    @Test("finished workout still excludes warmup sets")
    func finishedWorkoutExcludesWarmup() {
        let warmup = ExerciseSet(order: 0, weight: 40.0, reps: 10, setType: .warmup, isCompleted: false)
        let working = ExerciseSet(order: 1, weight: 80.0, reps: 8, isCompleted: false)
        let we = WorkoutExercise(order: 0, sets: [warmup, working])
        let workout = Workout(type: .strength, startDate: Date(), endDate: Date())
        we.workout = workout
        #expect(we.workingVolume == 80.0 * 8)
    }

    // MARK: - Mixed Bilateral + Unilateral

    @Test("mixed bilateral and unilateral sets compute correctly")
    func mixedBilateralUnilateral() {
        let bilateral = ExerciseSet(order: 0, weight: 100.0, reps: 5, isCompleted: true)
        let unilateral = ExerciseSet(
            order: 1, weight: 25.0, reps: 10,
            isCompleted: true, isUnilateral: true, weightRight: 20.0
        )
        let we = WorkoutExercise(order: 0, sets: [bilateral, unilateral])
        let expected = 100.0 * 5 + (25.0 * 10 + 20.0 * 10)
        #expect(we.workingVolume == expected)
    }

    // MARK: - Sub-set Types (dropSet, pyramid)

    @Test("dropSet and pyramid sets contribute to volume")
    func subSetTypesContribute() {
        let drop = ExerciseSet(order: 0, weight: 60.0, reps: 10, setType: .dropSet, isCompleted: true)
        let pyramid = ExerciseSet(order: 1, weight: 80.0, reps: 6, setType: .pyramid, isCompleted: true)
        let we = WorkoutExercise(order: 0, sets: [drop, pyramid])
        #expect(we.workingVolume == 60.0 * 10 + 80.0 * 6)
    }

    // MARK: - Empty / Nil Sets

    @Test("empty sets array yields zero volume")
    func emptySetsVolume() {
        let we = WorkoutExercise(order: 0, sets: [])
        #expect(we.workingVolume == 0.0)
    }
}
