import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Exercise Management Tests")
struct ExerciseManagementTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    private func makeExercise(
        _ context: ModelContext,
        nameEn: String,
        nameZh: String,
        muscleGroup: MuscleGroup = .chest,
        equipment: Equipment = .barbell
    ) -> Exercise {
        let exercise = Exercise(
            nameEn: nameEn,
            nameZh: nameZh,
            muscleGroup: muscleGroup,
            equipment: equipment
        )
        context.insert(exercise)
        return exercise
    }

    private func makeWorkoutWithExercises(
        _ context: ModelContext,
        exerciseNames: [(en: String, zh: String)]
    ) -> (Workout, [WorkoutExercise]) {
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        var workoutExercises: [WorkoutExercise] = []
        for (index, name) in exerciseNames.enumerated() {
            let exercise = makeExercise(context, nameEn: name.en, nameZh: name.zh)
            let we = WorkoutExercise(order: index, exercise: exercise)
            we.workout = workout
            context.insert(we)
            workoutExercises.append(we)
        }
        return (workout, workoutExercises)
    }

    // MARK: - Reorder Tests

    @Test("Reorder exercises updates order fields correctly and persists across fresh context refetch")
    @MainActor
    func reorderExercises() throws {
        let context = ModelContext(container)
        let emptyWorkout = Workout(type: .strength, startDate: Date())
        context.insert(emptyWorkout)
        #expect(!ActiveWorkoutView.reorderExercises(
            in: emptyWorkout,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 0
        ))

        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
            (en: "Squat", zh: "深蹲"),
            (en: "Deadlift", zh: "硬拉"),
        ])
        try context.save()

        // Move Deadlift (originally index 2) before Bench Press (index 0) using production seam
        let didReorder = ActiveWorkoutView.reorderExercises(
            in: workout,
            fromOffsets: IndexSet(integer: 2),
            toOffset: 0
        )
        #expect(didReorder)
        try context.save()

        let reordered = exercises.sorted { $0.order < $1.order }
        #expect(reordered[0].exercise?.nameEn == "Deadlift")
        #expect(reordered[1].exercise?.nameEn == "Bench Press")
        #expect(reordered[2].exercise?.nameEn == "Squat")
        #expect(reordered[0].order == 0)
        #expect(reordered[1].order == 1)
        #expect(reordered[2].order == 2)

        // Refetch from a fresh ModelContext to prove true persistence
        let freshContext = ModelContext(container)
        let workoutID = workout.persistentModelID
        guard let refetchedWorkout = freshContext.model(for: workoutID) as? Workout else {
            Issue.record("Failed to refetch workout from fresh context")
            return
        }

        let refetchedExercises = (refetchedWorkout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(refetchedExercises.count == 3)
        #expect(refetchedExercises[0].exercise?.nameEn == "Deadlift")
        #expect(refetchedExercises[1].exercise?.nameEn == "Bench Press")
        #expect(refetchedExercises[2].exercise?.nameEn == "Squat")
        #expect(refetchedExercises[0].order == 0)
        #expect(refetchedExercises[1].order == 1)
        #expect(refetchedExercises[2].order == 2)
    }

    @Test("Reorder preserves sets data across production seam move and save")
    @MainActor
    func reorderPreservesSets() throws {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
            (en: "Squat", zh: "深蹲"),
        ])

        let set1 = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        set1.workoutExercise = exercises[0]
        context.insert(set1)
        let set2 = ExerciseSet(order: 0, weight: 100.0, reps: 5, setType: .working)
        set2.workoutExercise = exercises[1]
        context.insert(set2)
        try context.save()

        // Move Squat (index 1) to index 0 via production seam helper
        let didReorder = ActiveWorkoutView.reorderExercise(
            exercises[1],
            toIndex: 0,
            in: workout
        )
        #expect(didReorder)
        try context.save()

        let reordered = exercises.sorted { $0.order < $1.order }
        #expect(reordered[0].exercise?.nameEn == "Squat")
        #expect(reordered[0].sets?.first?.weight == 100.0)
        #expect(reordered[1].exercise?.nameEn == "Bench Press")
        #expect(reordered[1].sets?.first?.weight == 80.0)
        #expect(reordered[0].order == 0)
        #expect(reordered[1].order == 1)
    }

    @Test("Dropping an earlier exercise onto a later exercise inserts before the target")
    @MainActor
    func downwardDropInsertsBeforeTarget() {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "A", zh: "A"),
            (en: "B", zh: "B"),
            (en: "C", zh: "C"),
        ])

        let didReorder = ActiveWorkoutView.reorderExercise(
            exercises[0],
            before: exercises[2],
            in: workout
        )

        #expect(didReorder)
        let reordered = exercises.sorted { $0.order < $1.order }
        #expect(reordered.map { $0.exercise?.nameEn } == ["B", "A", "C"])
        #expect(reordered.map(\.order) == [0, 1, 2])
    }

    @Test("Moving the first exercise to the terminal destination preserves every exercise once")
    @MainActor
    func firstExerciseMovesToEnd() {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "A", zh: "A"),
            (en: "B", zh: "B"),
            (en: "C", zh: "C"),
        ])
        exercises[0].order = 2
        exercises[1].order = 4
        exercises[2].order = 8

        let didReorder = ActiveWorkoutView.reorderExercises(
            in: workout,
            fromOffsets: IndexSet(integer: 0),
            toOffset: exercises.count
        )

        #expect(didReorder)
        let reordered = exercises.sorted { $0.order < $1.order }
        #expect(reordered.map { $0.exercise?.nameEn } == ["B", "C", "A"])
        #expect(Set(reordered.map(\.persistentModelID)).count == exercises.count)
        #expect(reordered.map(\.order) == [0, 1, 2])
    }

    @Test("Invalid, no-op, empty, and single-exercise moves stay unchanged")
    @MainActor
    func invalidAndNoOpReordersStayUnchanged() {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
            (en: "Squat", zh: "深蹲"),
            (en: "Deadlift", zh: "硬拉"),
        ])
        exercises[0].order = 2
        exercises[1].order = 4
        exercises[2].order = 8
        let originalOrders = exercises.map(\.order)

        #expect(!ActiveWorkoutView.reorderExercises(
            in: workout,
            fromOffsets: IndexSet(integer: 4),
            toOffset: 0
        ))
        #expect(exercises.map(\.order) == originalOrders)

        #expect(!ActiveWorkoutView.reorderExercises(
            in: workout,
            fromOffsets: [],
            toOffset: 0
        ))
        #expect(exercises.map(\.order) == originalOrders)

        #expect(!ActiveWorkoutView.reorderExercises(
            in: workout,
            fromOffsets: IndexSet(integer: 1),
            toOffset: 2
        ))
        #expect(exercises.map(\.order) == originalOrders)

        let (singleWorkout, singleExercises) = makeWorkoutWithExercises(
            context,
            exerciseNames: [(en: "Row", zh: "划船")]
        )
        singleExercises[0].order = 7
        #expect(!ActiveWorkoutView.reorderExercises(
            in: singleWorkout,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 1
        ))
        #expect(singleExercises[0].order == 7)
    }

    // MARK: - Replace Tests

    @Test("Replace exercise changes exercise reference only")
    func replaceExercise() throws {
        let context = ModelContext(container)
        let (_, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
        ])

        let set1 = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        let set2 = ExerciseSet(order: 1, weight: 80.0, reps: 6, setType: .working)
        set1.workoutExercise = exercises[0]
        set2.workoutExercise = exercises[0]
        context.insert(set1)
        context.insert(set2)
        try context.save()

        let newExercise = makeExercise(
            context, nameEn: "Incline Press", nameZh: "上斜卧推"
        )
        exercises[0].exercise = newExercise
        try context.save()

        #expect(exercises[0].exercise?.nameEn == "Incline Press")
        #expect(exercises[0].sets?.count == 2)
        let sets = (exercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(sets[0].weight == 80.0)
        #expect(sets[0].reps == 8)
        #expect(sets[1].weight == 80.0)
        #expect(sets[1].reps == 6)
    }

    @Test("Replace exercise preserves order")
    func replaceExercisePreservesOrder() throws {
        let context = ModelContext(container)
        let (_, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
            (en: "Squat", zh: "深蹲"),
            (en: "Deadlift", zh: "硬拉"),
        ])
        try context.save()

        let newExercise = makeExercise(
            context, nameEn: "Overhead Press", nameZh: "肩推",
            muscleGroup: .shoulders
        )
        exercises[1].exercise = newExercise
        try context.save()

        #expect(exercises[1].exercise?.nameEn == "Overhead Press")
        #expect(exercises[1].order == 1)
        #expect(exercises[0].order == 0)
        #expect(exercises[2].order == 2)
    }

    // MARK: - Delete Tests

    @Test("Delete exercise removes it and recalculates order")
    func deleteExercise() throws {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
            (en: "Squat", zh: "深蹲"),
            (en: "Deadlift", zh: "硬拉"),
        ])
        try context.save()

        let toDelete = exercises[1]
        let deletedID = toDelete.persistentModelID
        context.delete(toDelete)

        let remaining = (workout.exercises ?? [])
            .filter { $0.persistentModelID != deletedID }
            .sorted { $0.order < $1.order }
        for (index, exercise) in remaining.enumerated() {
            exercise.order = index
        }
        try context.save()

        #expect(remaining.count == 2)
        #expect(remaining[0].exercise?.nameEn == "Bench Press")
        #expect(remaining[0].order == 0)
        #expect(remaining[1].exercise?.nameEn == "Deadlift")
        #expect(remaining[1].order == 1)
    }

    @Test("Delete exercise cascades to sets")
    func deleteExerciseCascadesToSets() throws {
        let context = ModelContext(container)
        let (_, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
        ])

        let set1 = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        let set2 = ExerciseSet(order: 1, weight: 80.0, reps: 6, setType: .working)
        set1.workoutExercise = exercises[0]
        set2.workoutExercise = exercises[0]
        context.insert(set1)
        context.insert(set2)
        try context.save()

        context.delete(exercises[0])
        try context.save()

        let descriptor = FetchDescriptor<ExerciseSet>()
        let allSets = try context.fetch(descriptor)
        #expect(allSets.isEmpty)
    }

    @Test("Delete last exercise leaves workout with no exercises")
    func deleteLastExercise() throws {
        let context = ModelContext(container)
        let (workout, exercises) = makeWorkoutWithExercises(context, exerciseNames: [
            (en: "Bench Press", zh: "卧推"),
        ])
        try context.save()

        context.delete(exercises[0])
        try context.save()

        #expect(workout.exercises?.isEmpty != false)
    }
}
