import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Workout resume acceptance criteria")
struct WorkoutResumeTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    private func makeInProgressWorkout(
        in context: ModelContext,
        startDate: Date = Date().addingTimeInterval(-1800)
    ) throws -> Workout {
        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise)

        let set1 = ExerciseSet(
            order: 0, weight: 100.0, reps: 5,
            setType: .working, isCompleted: true
        )
        let set2 = ExerciseSet(
            order: 1, weight: 100.0, reps: 5,
            setType: .working
        )
        context.insert(set1)
        context.insert(set2)

        let workoutExercise = WorkoutExercise(
            order: 0, exercise: exercise, sets: [set1, set2]
        )
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: startDate,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try context.save()
        return workout
    }

    // MARK: - Resume path via WorkoutResolver

    @Test("Resume resolver returns the existing workout identity")
    func resumeResolverReturnsExistingWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )

        #expect(
            result.workout.persistentModelID == workout.persistentModelID
        )
    }

    @Test("Resume resolver does not insert a new Workout — count stays 1 after resolve")
    func resumeDoesNotCreateNewWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let beforeCount = try context.fetchCount(FetchDescriptor<Workout>())
        #expect(beforeCount == 1)

        _ = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )
        try context.save()

        let afterCount = try context.fetchCount(FetchDescriptor<Workout>())
        #expect(afterCount == 1, "Resume must not insert a duplicate Workout")
    }

    @Test("Resume resolver preserves the original startDate")
    func resumePreservesStartDate() throws {
        let context = ModelContext(container)
        let originalStart = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = try makeInProgressWorkout(
            in: context, startDate: originalStart
        )

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(), // caller's "now" — should be overridden
            using: context
        )

        #expect(result.startTime == originalStart)
        #expect(result.workout.startDate == originalStart)
        #expect(result.workout.isInProgress == true)
    }

    @Test("Resume resolver exposes existing exercises and sets")
    func resumeExposesExistingData() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )

        let exercises = (result.workout.exercises ?? [])
            .sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        #expect(exercises[0].exercise?.nameEn == "Squat")

        let sets = (exercises[0].sets ?? [])
            .sorted { $0.order < $1.order }
        #expect(sets.count == 2)
        #expect(sets[0].weight == 100.0)
        #expect(sets[0].reps == 5)
        #expect(sets[0].isCompleted == true)
        #expect(sets[1].isCompleted == false)
    }

    @Test("Finish on resolved-resume workout sets endDate and marks incomplete sets completed")
    func finishResumedWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )
        let resolved = result.workout
        let originalStart = resolved.startDate

        #expect(resolved.endDate == nil)
        resolved.finish()
        try context.save()

        #expect(resolved.endDate != nil)
        #expect(resolved.startDate == originalStart)
        #expect(resolved.isInProgress == false)

        let sets = (resolved.exercises ?? [])
            .flatMap { $0.sets ?? [] }
        for set in sets {
            #expect(set.isCompleted == true)
        }
    }

    @Test("Discard (delete) on resolved-resume workout removes it from the store")
    func discardResumedWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )
        let resolved = result.workout
        #expect(resolved.isInProgress == true)

        context.delete(resolved)
        try context.save()

        let readContext = ModelContext(container)
        let descriptor = FetchDescriptor<Workout>()
        let remaining = try readContext.fetch(descriptor)
        #expect(remaining.isEmpty)
    }

    @Test("Discard cascades to exercises and sets")
    func discardCascadesToChildren() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let result = WorkoutResolver.resolve(
            source: .resume(workout),
            startTime: Date(),
            using: context
        )
        let resolved = result.workout
        #expect(resolved.exercises?.isEmpty == false)

        context.delete(resolved)
        try context.save()

        let readContext = ModelContext(container)
        let exerciseDescriptor = FetchDescriptor<WorkoutExercise>()
        let remainingExercises = try readContext.fetch(exerciseDescriptor)
        #expect(remainingExercises.isEmpty)

        let setDescriptor = FetchDescriptor<ExerciseSet>()
        let remainingSets = try readContext.fetch(setDescriptor)
        #expect(remainingSets.isEmpty)
    }

    // MARK: - Contrast: blank source DOES create a new Workout

    @Test("Blank source inserts a new Workout into the context")
    func blankSourceCreatesNewWorkout() throws {
        let context = ModelContext(container)

        let beforeCount = try context.fetchCount(FetchDescriptor<Workout>())
        #expect(beforeCount == 0)

        _ = WorkoutResolver.resolve(
            source: .blank,
            startTime: Date(),
            using: context
        )
        try context.save()

        let afterCount = try context.fetchCount(FetchDescriptor<Workout>())
        #expect(afterCount == 1, "Blank source must insert a new Workout")
    }
}
