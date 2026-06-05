import Foundation
import SwiftData
import Testing

@testable import VitalStride

@Suite("Workout Deletion Tests")
struct WorkoutDeletionTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Deleting workout cascades to WorkoutExercise and ExerciseSet")
    func cascadeDelete() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let set1 = ExerciseSet(weight: 60.0, reps: 10, setType: .warmup)
        let set2 = ExerciseSet(weight: 80.0, reps: 8, setType: .working)
        context.insert(set1)
        context.insert(set2)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2])
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.exercises?.count == 1)
        #expect(workout.exercises?.first?.sets?.count == 2)

        context.delete(workout)
        try context.save()

        let remainingWorkouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(remainingWorkouts.isEmpty)

        let remainingExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        #expect(remainingExercises.isEmpty)

        let remainingSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(remainingSets.isEmpty)
    }

    @Test("Deleting HealthKit-source workout only removes SwiftData record")
    func deleteHealthKitSourceWorkout() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise)

        let set = ExerciseSet(weight: 100.0, reps: 5, setType: .working)
        context.insert(set)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set])
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .healthkit,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.source == .healthkit)

        context.delete(workout)
        try context.save()

        let remainingWorkouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(remainingWorkouts.isEmpty)

        let remainingExercises = try context.fetch(FetchDescriptor<WorkoutExercise>())
        #expect(remainingExercises.isEmpty)

        let remainingSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(remainingSets.isEmpty)
    }

    @Test("Deleting workout does not affect Exercise catalog entries")
    func deleteWorkoutPreservesExerciseCatalog() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Deadlift",
            nameZh: "硬拉",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise)

        let set = ExerciseSet(weight: 120.0, reps: 5, setType: .working)
        context.insert(set)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set])
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()

        context.delete(workout)
        try context.save()

        let remainingExercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(remainingExercises.contains { $0.nameEn == "Deadlift" })
    }
}
