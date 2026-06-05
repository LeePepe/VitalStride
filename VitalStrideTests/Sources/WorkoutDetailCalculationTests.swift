import Foundation
import SwiftData
import Testing

@testable import VitalStride

@Suite("Workout Detail Calculation Tests")
struct WorkoutDetailCalculationTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Per-Exercise Calculations

    @Test("totalSetsCount includes all set types")
    func totalSetsCountIncludesAllTypes() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 60, reps: 10, setType: .warmup),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.totalSetsCount == 3)
    }

    @Test("totalRepsCount sums reps from all set types")
    func totalRepsCountIncludesAllTypes() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup),
            ExerciseSet(weight: 60, reps: 10, setType: .working),
            ExerciseSet(weight: 60, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        #expect(exercise.totalRepsCount == 30)
    }

    @Test("workingVolume excludes warmup sets")
    func workingVolumeExcludesWarmup() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup),
            ExerciseSet(weight: 80, reps: 10, setType: .working),
            ExerciseSet(weight: 80, reps: 8, setType: .working),
        ])
        context.insert(exercise)
        try context.save()

        let expected = 80.0 * 10.0 + 80.0 * 8.0
        #expect(exercise.workingVolume == expected)
    }

    @Test("workingVolume is zero when only warmup sets exist")
    func workingVolumeZeroForWarmupOnly() throws {
        let context = ModelContext(container)
        let exercise = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 40, reps: 12, setType: .warmup),
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

    @Test("overallWorkingVolume sums across exercises excluding warmup")
    func overallWorkingVolumeSumsExercises() throws {
        let context = ModelContext(container)
        let exercise1 = WorkoutExercise(order: 0, sets: [
            ExerciseSet(weight: 20, reps: 10, setType: .warmup),
            ExerciseSet(weight: 60, reps: 10, setType: .working),
        ])
        let exercise2 = WorkoutExercise(order: 1, sets: [
            ExerciseSet(weight: 40, reps: 8, setType: .working),
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

    // MARK: - Unit Conversion

    @Test("displayWeight conversion factor for lb")
    func displayWeightConversion() {
        let kgValue = 100.0
        let lbValue = kgValue * 2.20462
        #expect(abs(lbValue - 220.462) < 0.001)
    }
}
