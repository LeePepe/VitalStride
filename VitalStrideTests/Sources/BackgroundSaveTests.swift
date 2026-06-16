import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Background save persistence")
struct BackgroundSaveTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Explicit save persists in-flight workout data")
    func explicitSavePersistsWorkout() throws {
        let context = ModelContext(container)

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell,
            primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [],
            isCustom: false
        )
        context.insert(exercise)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)

        let set = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        set.workoutExercise = workoutExercise
        context.insert(set)

        try context.save()

        let readContext = ModelContext(container)
        let descriptor = FetchDescriptor<Workout>()
        let workouts = try readContext.fetch(descriptor)
        #expect(workouts.count == 1)
        #expect(workouts[0].exercises?.count == 1)
        let savedSets = workouts[0].exercises?.first?.sets ?? []
        #expect(savedSets.count == 1)
        #expect(savedSets[0].weight == 80.0)
        #expect(savedSets[0].reps == 8)
    }

    @Test("Explicit save captures mid-workout set modifications")
    func explicitSaveCapturesModifications() throws {
        let context = ModelContext(container)

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["Pectoralis Major"],
            secondaryMuscles: [],
            isCustom: false
        )
        context.insert(exercise)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)

        let set = ExerciseSet(order: 0, weight: 60.0, reps: 10, setType: .working)
        set.workoutExercise = workoutExercise
        context.insert(set)
        try context.save()

        set.weight = 65.0
        set.reps = 8
        set.isCompleted = true
        try context.save()

        let readContext = ModelContext(container)
        let descriptor = FetchDescriptor<Workout>()
        let workouts = try readContext.fetch(descriptor)
        let savedSet = workouts[0].exercises?.first?.sets?.first
        #expect(savedSet?.weight == 65.0)
        #expect(savedSet?.reps == 8)
        #expect(savedSet?.isCompleted == true)
    }
}
