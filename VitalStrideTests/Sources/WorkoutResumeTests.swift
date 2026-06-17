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

        let set1 = ExerciseSet(order: 0, weight: 100.0, reps: 5, setType: .working, isCompleted: true)
        let set2 = ExerciseSet(order: 1, weight: 100.0, reps: 5, setType: .working)
        context.insert(set1)
        context.insert(set2)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2])
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

    private func resolveResumeSource(_ source: WorkoutStartSource) -> Workout? {
        switch source {
        case .resume(let existingWorkout):
            return existingWorkout
        default:
            return nil
        }
    }

    @Test("Resume source carries the existing workout identity")
    func resumeSourceCarriesWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)

        #expect(resolved?.persistentModelID == workout.persistentModelID)
    }

    @Test("Resume does not create a new Workout — only the original exists")
    func resumeDoesNotCreateNewWorkout() throws {
        let context = ModelContext(container)
        _ = try makeInProgressWorkout(in: context)

        let descriptor = FetchDescriptor<Workout>()
        let allWorkouts = try context.fetch(descriptor)
        #expect(allWorkouts.count == 1)
    }

    @Test("Resumed workout preserves original startDate")
    func resumePreservesStartDate() throws {
        let context = ModelContext(container)
        let originalStart = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = try makeInProgressWorkout(in: context, startDate: originalStart)

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)!

        #expect(resolved.startDate == originalStart)
        #expect(resolved.isInProgress == true)
    }

    @Test("Resumed workout exposes existing exercises and sets")
    func resumeExposesExistingData() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)!

        let exercises = (resolved.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        #expect(exercises[0].exercise?.nameEn == "Squat")

        let sets = (exercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(sets.count == 2)
        #expect(sets[0].weight == 100.0)
        #expect(sets[0].reps == 5)
        #expect(sets[0].isCompleted == true)
        #expect(sets[1].isCompleted == false)
    }

    @Test("Finish on resumed workout sets endDate and marks incomplete sets completed")
    func finishResumedWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)!
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

    @Test("Discard (delete) on resumed workout removes it from the store")
    func discardResumedWorkout() throws {
        let context = ModelContext(container)
        let workout = try makeInProgressWorkout(in: context)

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)!
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

        let source = WorkoutStartSource.resume(workout)
        let resolved = resolveResumeSource(source)!
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
}
