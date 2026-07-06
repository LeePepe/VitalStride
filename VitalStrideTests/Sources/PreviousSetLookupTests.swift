import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@MainActor
@Suite("PreviousSetLookup")
struct PreviousSetLookupTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Fixture helpers

    private func makeExercise(nameEn: String = "Squat", nameZh: String = "深蹲") -> Exercise {
        Exercise(
            nameEn: nameEn,
            nameZh: nameZh,
            muscleGroup: .legs,
            equipment: .barbell,
            primaryMuscles: ["Quadriceps"],
            secondaryMuscles: [],
            isCustom: false
        )
    }

    @discardableResult
    private func makeWorkout(
        in context: ModelContext,
        startDate: Date,
        endDate: Date?,
        exercise: Exercise,
        sets: [ExerciseSet]
    ) -> Workout {
        let workout = Workout(type: .strength, startDate: startDate, endDate: endDate)
        context.insert(workout)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)

        for set in sets {
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
        return workout
    }

    // MARK: - Tests

    @Test("Same exercise / same main-set index returns matching prior set")
    func returnsPriorMainSetAtSameIndex() throws {
        let context = ModelContext(container)
        let exercise = makeExercise()
        context.insert(exercise)

        let now = Date()
        let priorStart = now.addingTimeInterval(-86_400) // yesterday
        let priorEnd = priorStart.addingTimeInterval(3_600)

        makeWorkout(
            in: context,
            startDate: priorStart,
            endDate: priorEnd,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 60.0, reps: 10, setType: .working, isCompleted: true),
                ExerciseSet(order: 1, weight: 65.0, reps: 8, setType: .working, isCompleted: true),
                ExerciseSet(order: 2, weight: 70.0, reps: 6, setType: .working, isCompleted: true),
            ]
        )

        let current = makeWorkout(
            in: context,
            startDate: now,
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )

        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 1,
            in: context
        )

        #expect(hit != nil)
        #expect(hit?.weight == 65.0)
        #expect(hit?.reps == 8)
    }

    @Test("First-time exercise (no prior workouts) returns nil")
    func firstTimeExerciseReturnsNil() throws {
        let context = ModelContext(container)
        let exercise = makeExercise(nameEn: "Deadlift", nameZh: "硬拉")
        context.insert(exercise)

        let current = makeWorkout(
            in: context,
            startDate: Date(),
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )
        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 0,
            in: context
        )

        #expect(hit == nil)
    }

    @Test("Prior workout has too few main sets for requested index returns nil")
    func priorWorkoutTooShortReturnsNil() throws {
        let context = ModelContext(container)
        let exercise = makeExercise(nameEn: "Bench Press", nameZh: "卧推")
        context.insert(exercise)

        let now = Date()
        let priorStart = now.addingTimeInterval(-86_400)
        let priorEnd = priorStart.addingTimeInterval(3_600)

        makeWorkout(
            in: context,
            startDate: priorStart,
            endDate: priorEnd,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 60.0, reps: 10, setType: .working, isCompleted: true),
                ExerciseSet(order: 1, weight: 65.0, reps: 8, setType: .working, isCompleted: true),
            ]
        )

        let current = makeWorkout(
            in: context,
            startDate: now,
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )

        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 5,
            in: context
        )

        #expect(hit == nil)
    }

    @Test("Current in-progress workout is excluded from search")
    func currentInProgressWorkoutIsExcluded() throws {
        let context = ModelContext(container)
        let exercise = makeExercise(nameEn: "Row", nameZh: "划船")
        context.insert(exercise)

        // Only the current in-progress workout has the exercise — even though it
        // has completed sets, it must not surface as its own "previous".
        let current = makeWorkout(
            in: context,
            startDate: Date(),
            endDate: nil,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 40.0, reps: 12, setType: .working, isCompleted: true),
                ExerciseSet(order: 1, weight: 45.0, reps: 10, setType: .working),
            ]
        )
        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 0,
            in: context
        )

        #expect(hit == nil)
    }

    @Test("Later completed workouts (after currentWorkout.startDate) are excluded")
    func laterCompletedWorkoutIsExcluded() throws {
        let context = ModelContext(container)
        let exercise = makeExercise(nameEn: "OHP", nameZh: "推举")
        context.insert(exercise)

        let currentStart = Date().addingTimeInterval(-3_600) // 1h ago

        // A "later" completed workout: started AFTER currentStart. Even though
        // it's completed, T003 constrains the search to startDate < currentStart.
        let laterStart = currentStart.addingTimeInterval(1_800)
        let laterEnd = laterStart.addingTimeInterval(1_200)
        makeWorkout(
            in: context,
            startDate: laterStart,
            endDate: laterEnd,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 99.0, reps: 3, setType: .working, isCompleted: true),
            ]
        )

        // A genuine "prior" completed workout: startDate BEFORE currentStart.
        let priorStart = currentStart.addingTimeInterval(-86_400)
        let priorEnd = priorStart.addingTimeInterval(3_600)
        makeWorkout(
            in: context,
            startDate: priorStart,
            endDate: priorEnd,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 30.0, reps: 10, setType: .working, isCompleted: true),
            ]
        )

        let current = makeWorkout(
            in: context,
            startDate: currentStart,
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )

        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 0,
            in: context
        )

        #expect(hit != nil)
        // Must come from the genuinely-prior workout, not the later one.
        #expect(hit?.weight == 30.0)
        #expect(hit?.reps == 10)
    }

    @Test("Sub-sets (drop / pyramid) are skipped when indexing main sets")
    func subSetsAreSkipped() throws {
        let context = ModelContext(container)
        let exercise = makeExercise(nameEn: "Curl", nameZh: "弯举")
        context.insert(exercise)

        let now = Date()
        let priorStart = now.addingTimeInterval(-86_400)
        let priorEnd = priorStart.addingTimeInterval(3_600)

        // order-0 working, order-1 dropSet (sub), order-2 working — mainSetIndex 1
        // must resolve to the order-2 working set (weight 55).
        makeWorkout(
            in: context,
            startDate: priorStart,
            endDate: priorEnd,
            exercise: exercise,
            sets: [
                ExerciseSet(order: 0, weight: 50.0, reps: 10, setType: .working, isCompleted: true),
                ExerciseSet(order: 1, weight: 40.0, reps: 6, setType: .dropSet, isCompleted: true),
                ExerciseSet(order: 2, weight: 55.0, reps: 8, setType: .working, isCompleted: true),
            ]
        )

        let current = makeWorkout(
            in: context,
            startDate: now,
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )

        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: 1,
            in: context
        )

        #expect(hit != nil)
        #expect(hit?.weight == 55.0)
        #expect(hit?.reps == 8)
        #expect(hit?.setType == .working)
    }

    @Test("Nil exercise argument returns nil")
    func nilExerciseReturnsNil() throws {
        let context = ModelContext(container)
        let current = Workout(type: .strength, startDate: Date())
        context.insert(current)
        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: nil,
            mainSetIndex: 0,
            in: context
        )

        #expect(hit == nil)
    }

    @Test("Negative mainSetIndex returns nil")
    func negativeIndexReturnsNil() throws {
        let context = ModelContext(container)
        let exercise = makeExercise()
        context.insert(exercise)

        let current = makeWorkout(
            in: context,
            startDate: Date(),
            endDate: nil,
            exercise: exercise,
            sets: [ExerciseSet(order: 0, weight: 0.0, reps: 0, setType: .working)]
        )
        try context.save()

        let hit = PreviousSetLookup.previousMainSet(
            currentWorkout: current,
            exercise: exercise,
            mainSetIndex: -1,
            in: context
        )

        #expect(hit == nil)
    }
}
