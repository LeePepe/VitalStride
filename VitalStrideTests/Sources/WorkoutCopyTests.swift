import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Workout Copy Tests")
struct WorkoutCopyTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("FetchDescriptor loads exercises from source workout")
    func fetchDescriptorLoadsExercises() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let set1 = ExerciseSet(weight: 80.0, reps: 8, setType: .working)
        let set2 = ExerciseSet(order: 1, weight: 60.0, reps: 12, setType: .warmup)
        context.insert(set1)
        context.insert(set2)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2])
        context.insert(workoutExercise)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [workoutExercise]
        )
        context.insert(sourceWorkout)
        try context.save()

        let sourceID = sourceWorkout.persistentModelID
        var descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate<WorkoutExercise> { $0.workout?.persistentModelID == sourceID },
            sortBy: [SortDescriptor(\.order)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.sets, \.exercise]
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched[0].exercise?.nameEn == "Bench Press")
        #expect(fetched[0].sets?.count == 2)
    }

    @Test("Copy workout preserves exercises and sets")
    func copyWorkoutPreservesData() throws {
        let context = ModelContext(container)

        let exercise1 = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        let exercise2 = Exercise(
            nameEn: "Deadlift",
            nameZh: "硬拉",
            muscleGroup: .back,
            equipment: .barbell
        )
        context.insert(exercise1)
        context.insert(exercise2)

        let sets1 = [
            ExerciseSet(order: 0, weight: 100.0, reps: 5, setType: .working),
            ExerciseSet(order: 1, weight: 100.0, reps: 5, setType: .working),
            ExerciseSet(order: 2, weight: 80.0, reps: 8, setType: .dropSet),
        ]
        let sets2 = [
            ExerciseSet(order: 0, weight: 120.0, reps: 3, setType: .working, isUnilateral: true),
        ]
        for s in sets1 + sets2 { context.insert(s) }

        let we1 = WorkoutExercise(order: 0, exercise: exercise1, sets: sets1)
        let we2 = WorkoutExercise(order: 1, exercise: exercise2, sets: sets2)
        context.insert(we1)
        context.insert(we2)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [we1, we2]
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        let copiedExercises = (newWorkout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(copiedExercises.count == 2)
        #expect(copiedExercises[0].exercise?.nameEn == "Squat")
        #expect(copiedExercises[1].exercise?.nameEn == "Deadlift")

        let copiedSets1 = (copiedExercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(copiedSets1.count == 3)
        #expect(copiedSets1[0].weight == 100.0)
        #expect(copiedSets1[0].reps == 5)
        #expect(copiedSets1[0].setType == .working)
        #expect(copiedSets1[2].setType == .dropSet)

        let copiedSets2 = (copiedExercises[1].sets ?? []).sorted { $0.order < $1.order }
        #expect(copiedSets2.count == 1)
        #expect(copiedSets2[0].weight == 120.0)
        #expect(copiedSets2[0].reps == 3)
        #expect(copiedSets2[0].isUnilateral == true)
    }

    @Test("Copy workout with no exercises produces empty workout")
    func copyEmptyWorkout() throws {
        let context = ModelContext(container)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date()
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        let copiedExercises = newWorkout.exercises ?? []
        #expect(copiedExercises.isEmpty)
    }

    @Test("Copy exercise with no sets creates fallback default set")
    func copyExerciseWithNoSets() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Pull Up",
            nameZh: "引体向上",
            muscleGroup: .back,
            equipment: .bodyweight
        )
        context.insert(exercise)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [we]
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        let copiedExercises = (newWorkout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(copiedExercises.count == 1)
        #expect(copiedExercises[0].exercise?.nameEn == "Pull Up")
        let copiedSets = (copiedExercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(copiedSets.count == 1)
        #expect(copiedSets[0].weight == 0)
        #expect(copiedSets[0].reps == 0)
        #expect(copiedSets[0].setType == .working)
    }

    @Test("Copied sets do not affect source workout data")
    func copiedSetsDoNotAffectSource() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Curl",
            nameZh: "弯举",
            muscleGroup: .arms,
            equipment: .dumbbell
        )
        context.insert(exercise)

        let srcSet = ExerciseSet(order: 0, weight: 15.0, reps: 12, setType: .working)
        context.insert(srcSet)

        let we = WorkoutExercise(order: 0, exercise: exercise, sets: [srcSet])
        context.insert(we)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [we]
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        #expect(sourceWorkout.exercises?.count == 1)
        let originalSets = (sourceWorkout.exercises?.first?.sets ?? [])
        #expect(originalSets.count == 1)
        #expect(originalSets.first?.weight == 15.0)
        #expect(originalSets.first?.reps == 12)
    }
}
