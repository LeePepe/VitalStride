import Foundation
import SwiftData
import Testing

@testable import VitalStride

@Suite("Relationship Tests")
struct RelationshipTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Workout → WorkoutExercise → ExerciseSet relationship chain")
    func workoutRelationshipChain() throws {
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
        let set3 = ExerciseSet(weight: 80.0, reps: 7, setType: .working, restDuration: 120)
        context.insert(set1)
        context.insert(set2)
        context.insert(set3)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2, set3])
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.exercises?.count == 1)
        #expect(workout.exercises?.first?.exercise?.nameEn == "Bench Press")
        #expect(workout.exercises?.first?.sets?.count == 3)
        #expect(workout.exercises?.first?.order == 0)
    }

    @Test("WorkoutExercise inverse relationship to Workout")
    func workoutExerciseInverseRelationship() throws {
        let context = ModelContext(container)

        let workoutExercise = WorkoutExercise(order: 0)
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()

        #expect(workoutExercise.workout === workout)
    }

    @Test("ExerciseSet inverse relationship to WorkoutExercise")
    func exerciseSetInverseRelationship() throws {
        let context = ModelContext(container)

        let set = ExerciseSet(weight: 100.0, reps: 5, setType: .working)
        context.insert(set)

        let workoutExercise = WorkoutExercise(order: 0, sets: [set])
        context.insert(workoutExercise)
        try context.save()

        #expect(set.workoutExercise === workoutExercise)
    }

    @Test("WorkoutTemplate → TemplateExercise relationship")
    func templateRelationship() throws {
        let context = ModelContext(container)

        let exercise1 = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        let exercise2 = Exercise(
            nameEn: "Leg Press",
            nameZh: "腿举",
            muscleGroup: .legs,
            equipment: .machine
        )
        context.insert(exercise1)
        context.insert(exercise2)

        let te1 = TemplateExercise(exercise: exercise1, targetSets: 4, targetWeight: 100.0, order: 0)
        let te2 = TemplateExercise(exercise: exercise2, targetSets: 3, targetWeight: 200.0, order: 1)
        context.insert(te1)
        context.insert(te2)

        let template = WorkoutTemplate(name: "Leg Day", exercises: [te1, te2])
        context.insert(template)
        try context.save()

        #expect(template.exercises?.count == 2)
        #expect(te1.template === template)
        #expect(te2.template === template)
    }

    @Test("Multiple exercises in a single workout")
    func multipleExercisesInWorkout() throws {
        let context = ModelContext(container)

        let benchPress = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let shoulderPress = Exercise(
            nameEn: "Shoulder Press",
            nameZh: "肩推",
            muscleGroup: .shoulders,
            equipment: .dumbbell
        )
        context.insert(benchPress)
        context.insert(shoulderPress)

        let we1 = WorkoutExercise(order: 0, exercise: benchPress)
        let we2 = WorkoutExercise(order: 1, exercise: shoulderPress)
        context.insert(we1)
        context.insert(we2)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [we1, we2]
        )
        context.insert(workout)
        try context.save()

        #expect(workout.exercises?.count == 2)
    }
}
