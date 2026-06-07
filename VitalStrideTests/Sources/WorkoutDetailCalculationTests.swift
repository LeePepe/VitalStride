import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Workout Detail Calculation Tests")
struct WorkoutDetailCalculationTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - ExerciseSet completedAt

    @Test("ExerciseSet defaults to pending (completedAt nil)")
    func exerciseSetDefaultsPending() throws {
        let set = ExerciseSet(weight: 80, reps: 8)
        #expect(set.completedAt == nil)
        #expect(set.isCompleted == false)
    }

    @Test("ExerciseSet with completedAt is completed")
    func exerciseSetCompleted() throws {
        let now = Date()
        let set = ExerciseSet(weight: 80, reps: 8, completedAt: now)
        #expect(set.completedAt == now)
        #expect(set.isCompleted == true)
    }

    // MARK: - Per-Exercise Calculations

    @Test("totalSetsCount includes all set types regardless of completion")
    func totalSetsCountIncludesAllTypes() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 60, reps: 10, setType: .warmup, completedAt: Date()),
            ExerciseSet(weight: 80, reps: 8, setType: .working, completedAt: Date()),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.totalSetsCount == 3)
    }

    @Test("totalRepsCount only counts completed sets")
    func totalRepsCountOnlyCompleted() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup, completedAt: Date()),
            ExerciseSet(weight: 60, reps: 10, setType: .working, completedAt: Date()),
            ExerciseSet(weight: 60, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.totalRepsCount == 22)
    }

    @Test("workingVolume excludes warmup and pending sets")
    func workingVolumeExcludesWarmupAndPending() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup, completedAt: Date()),
            ExerciseSet(weight: 80, reps: 10, setType: .working, completedAt: Date()),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        let expected = 80.0 * 10.0
        #expect(exercise.workingVolume == expected)
    }

    @Test("workingVolume is zero when only warmup sets are completed")
    func workingVolumeZeroForWarmupOnly() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup, completedAt: Date()),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.workingVolume == 0.0)
    }

    @Test("workingVolume is zero when all sets are pending")
    func workingVolumeZeroWhenAllPending() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 80, reps: 10, setType: .working),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.workingVolume == 0.0)
    }

    @Test("per-exercise calculations with empty sets")
    func perExerciseEmptySets() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [])
        context.insert(exercise)
        try context.save()

        #expect(exercise.totalSetsCount == 0)
        #expect(exercise.totalRepsCount == 0)
        #expect(exercise.workingVolume == 0.0)
    }

    // MARK: - Overall Workout Calculations

    @Test("overallWorkingVolume sums across exercises excluding warmup and pending")
    func overallWorkingVolumeSumsExercises() throws {
        let context = ModelContext(container)
        let exercise1 = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 20, reps: 10, setType: .warmup, completedAt: Date()),
            ExerciseSet(weight: 60, reps: 10, setType: .working, completedAt: Date()),
        ])
        let exercise2 = WorkoutExercise(order: 1, sets: [
            ExerciseSet(weight: 40, reps: 8, setType: .working, completedAt: Date()),
        ])
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [exercise1, exercise2]
        )
        context.insert(workout)
        try context.save()

        let expected = 60.0 * 10.0 + 40.0 * 8.0
        #expect(workout.overallWorkingVolume == expected)
    }

    @Test("hasWorkingSets returns true when working sets exist")
    func hasWorkingSetsTrue() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 60, reps: 10, setType: .working),
        ])
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [exercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.hasWorkingSets == true)
    }

    @Test("hasWorkingSets returns false for warmup-only workout")
    func hasWorkingSetsFalseForWarmupOnly() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 20, reps: 10, setType: .warmup),
        ])
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [exercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.hasWorkingSets == false)
    }

    @Test("hasWorkingSets returns false for empty workout")
    func hasWorkingSetsFalseForEmpty() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        #expect(workout.hasWorkingSets == false)
        #expect(workout.overallWorkingVolume == 0.0)
    }

    // MARK: - finishWorkout Auto-Complete

    @Test("finishing workout completes all pending sets")
    func finishWorkoutCompletesPendingSets() throws {
        let context = ModelContext(container)
        let set1 = ExerciseSet(weight: 80, reps: 10, setType: .working, completedAt: Date().addingTimeInterval(-60))
        let set2 = ExerciseSet(weight: 80, reps: 8, setType: .working)
        let set3 = ExerciseSet(weight: 40, reps: 12, setType: .warmup)
        let exercise = WorkoutExercise(order: 0, sets: [set1, set2, set3])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [exercise])
        context.insert(workout)
        try context.save()

        #expect(set2.completedAt == nil)
        #expect(set3.completedAt == nil)

        workout.finish()
        try context.save()

        #expect(set1.isCompleted == true)
        #expect(set2.isCompleted == true)
        #expect(set3.isCompleted == true)
        #expect(workout.endDate != nil)

        let expectedVolume = 80.0 * 10.0 + 80.0 * 8.0
        #expect(exercise.workingVolume == expectedVolume)
    }

    @Test("historical workout with nil completedAt still counts all sets in stats")
    func historicalWorkoutCountsAllSets() throws {
        let context = ModelContext(container)
        let set1 = ExerciseSet(weight: 80, reps: 10, setType: .working)
        let set2 = ExerciseSet(weight: 80, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, sets: [set1, set2])
        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [exercise]
        )
        context.insert(workout)
        try context.save()

        #expect(set1.completedAt == nil)
        #expect(set2.completedAt == nil)
        #expect(exercise.totalRepsCount == 18)
        #expect(exercise.workingVolume == 80.0 * 10.0 + 80.0 * 8.0)
    }

    // MARK: - Unit Conversion

    @Test("displayWeight conversion factor for lb")
    func displayWeightConversion() {
        let kgValue = 100.0
        let lbValue = kgValue * 2.20462
        #expect(abs(lbValue - 220.462) < 0.001)
    }
}
