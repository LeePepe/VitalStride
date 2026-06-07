import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Model Tests")
struct ModelTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Workout creation and property assignment")
    func workoutCreation() throws {
        let context = ModelContext(container)
        let now = Date()
        let workout = Workout(type: .strength, startDate: now, source: .recorded)
        context.insert(workout)
        try context.save()

        #expect(workout.type == .strength)
        #expect(workout.startDate == now)
        #expect(workout.endDate == nil)
        #expect(workout.source == .recorded)
        #expect(workout.exercises?.isEmpty == true)
    }

    @Test("Workout with endDate")
    func workoutWithEndDate() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let workout = Workout(type: .strength, startDate: start, endDate: end, totalCalories: 250.0, source: .imported)
        context.insert(workout)
        try context.save()

        #expect(workout.endDate == end)
        #expect(workout.totalCalories == 250.0)
        #expect(workout.source == .imported)
    }

    @Test("Exercise creation and property assignment")
    func exerciseCreation() throws {
        let context = ModelContext(container)
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["Pectoralis Major"],
            secondaryMuscles: ["Triceps", "Anterior Deltoid"],
            isCustom: false
        )
        context.insert(exercise)
        try context.save()

        #expect(exercise.nameEn == "Bench Press")
        #expect(exercise.nameZh == "平板卧推")
        #expect(exercise.muscleGroup == .chest)
        #expect(exercise.equipment == .barbell)
        #expect(exercise.primaryMuscles == ["Pectoralis Major"])
        #expect(exercise.secondaryMuscles == ["Triceps", "Anterior Deltoid"])
        #expect(exercise.isCustom == false)
    }

    @Test("ExerciseSet creation and property assignment")
    func exerciseSetCreation() throws {
        let context = ModelContext(container)
        let set = ExerciseSet(weight: 80.0, reps: 8, setType: .working, restDuration: 90)
        context.insert(set)
        try context.save()

        #expect(set.weight == 80.0)
        #expect(set.reps == 8)
        #expect(set.setType == .working)
        #expect(set.restDuration == 90)
        #expect(set.completedAt == nil)
        #expect(set.isCompleted == false)
    }

    @Test("ExerciseSet warmup type")
    func exerciseSetWarmup() throws {
        let context = ModelContext(container)
        let set = ExerciseSet(weight: 40.0, reps: 12, setType: .warmup)
        context.insert(set)
        try context.save()

        #expect(set.setType == .warmup)
        #expect(set.restDuration == nil)
        #expect(set.completedAt == nil)
    }

    @Test("ExerciseSet with completedAt persists")
    func exerciseSetCompletedAtPersists() throws {
        let context = ModelContext(container)
        let now = Date()
        let set = ExerciseSet(weight: 60.0, reps: 10, completedAt: now)
        context.insert(set)
        try context.save()

        #expect(set.completedAt == now)
        #expect(set.isCompleted == true)
    }

    @Test("WorkoutTemplate creation")
    func workoutTemplateCreation() throws {
        let context = ModelContext(container)
        let template = WorkoutTemplate(name: "Push Day")
        context.insert(template)
        try context.save()

        #expect(template.name == "Push Day")
        #expect(template.exercises?.isEmpty == true)
    }

    @Test("TemplateExercise creation")
    func templateExerciseCreation() throws {
        let context = ModelContext(container)
        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise)

        let templateExercise = TemplateExercise(
            exercise: exercise,
            targetSets: 4,
            targetWeight: 100.0,
            order: 0
        )
        context.insert(templateExercise)
        try context.save()

        #expect(templateExercise.targetSets == 4)
        #expect(templateExercise.targetWeight == 100.0)
        #expect(templateExercise.order == 0)
        #expect(templateExercise.exercise?.nameEn == "Squat")
    }
}
