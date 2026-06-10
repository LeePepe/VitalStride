import AIService
import Foundation
import SwiftData
import Synchronization
import Testing
import VitalModels

@testable import VitalStride

@Suite("AITrainingAdviceCard Tests")
struct AITrainingAdviceCardTests {

    // MARK: - TrainingContext Building

    @Test("buildTrainingContext returns empty context when no workouts exist")
    @MainActor
    func testBuildContextNoWorkouts() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = buildTrainingContext(modelContext: container.mainContext)

        #expect(context.recentWorkouts.isEmpty)
        #expect(context.muscleGroupFrequency.isEmpty)
        #expect(context.daysSinceLastWorkout == nil)
    }

    @Test("buildTrainingContext extracts workout summaries correctly")
    @MainActor
    func testBuildContextWithWorkouts() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let ctx = container.mainContext

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        ctx.insert(exercise)

        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-86400),
            source: .recorded
        )
        workout.endDate = Date().addingTimeInterval(-86400 + 3600)
        ctx.insert(workout)

        let workoutExercise = WorkoutExercise(order: 0)
        workoutExercise.workout = workout
        workoutExercise.exercise = exercise
        ctx.insert(workoutExercise)

        let set = ExerciseSet(order: 0, weight: 80, reps: 5, setType: .working)
        set.workoutExercise = workoutExercise
        ctx.insert(set)

        try ctx.save()

        let trainingContext = buildTrainingContext(modelContext: ctx)

        #expect(trainingContext.recentWorkouts.count == 1)
        let expectedName = exercise.localizedName
        #expect(trainingContext.recentWorkouts[0].exerciseNames.contains(expectedName))
        #expect(trainingContext.recentWorkouts[0].muscleGroups.contains("chest"))
        #expect(trainingContext.recentWorkouts[0].totalVolume == 400)
        #expect(trainingContext.muscleGroupFrequency["chest"] == 1)
        #expect(trainingContext.daysSinceLastWorkout != nil)
    }

    @Test("buildTrainingContext computes muscle group frequency across multiple workouts")
    @MainActor
    func testBuildContextMuscleGroupFrequency() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let ctx = container.mainContext

        let chestExercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let backExercise = Exercise(
            nameEn: "Barbell Row",
            nameZh: "杠铃划船",
            muscleGroup: .back,
            equipment: .barbell
        )
        ctx.insert(chestExercise)
        ctx.insert(backExercise)

        for dayOffset in [1, 3] {
            let workout = Workout(
                type: .strength,
                startDate: Date().addingTimeInterval(-86400 * Double(dayOffset)),
                source: .recorded
            )
            workout.endDate = workout.startDate.addingTimeInterval(3600)
            ctx.insert(workout)

            let we = WorkoutExercise(order: 0)
            we.workout = workout
            we.exercise = chestExercise
            ctx.insert(we)
        }

        let backWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-86400 * 2),
            source: .recorded
        )
        backWorkout.endDate = backWorkout.startDate.addingTimeInterval(3600)
        ctx.insert(backWorkout)

        let backWE = WorkoutExercise(order: 0)
        backWE.workout = backWorkout
        backWE.exercise = backExercise
        ctx.insert(backWE)

        try ctx.save()

        let trainingContext = buildTrainingContext(modelContext: ctx)

        #expect(trainingContext.recentWorkouts.count == 3)
        #expect(trainingContext.muscleGroupFrequency["chest"] == 2)
        #expect(trainingContext.muscleGroupFrequency["back"] == 1)
    }

    @Test("buildTrainingContext only includes warmup volume excluded from total")
    @MainActor
    func testBuildContextVolumeExcludesWarmup() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let ctx = container.mainContext

        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        ctx.insert(exercise)

        let workout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            source: .recorded
        )
        workout.endDate = Date()
        ctx.insert(workout)

        let we = WorkoutExercise(order: 0)
        we.workout = workout
        we.exercise = exercise
        ctx.insert(we)

        let warmupSet = ExerciseSet(order: 0, weight: 40, reps: 10, setType: .warmup)
        warmupSet.workoutExercise = we
        ctx.insert(warmupSet)

        let workingSet = ExerciseSet(order: 1, weight: 100, reps: 5, setType: .working)
        workingSet.workoutExercise = we
        ctx.insert(workingSet)

        try ctx.save()

        let trainingContext = buildTrainingContext(modelContext: ctx)

        #expect(trainingContext.recentWorkouts.count == 1)
        #expect(trainingContext.recentWorkouts[0].totalVolume == 500)
    }

    // MARK: - TrainingAdviceCache TTL

    @Test("TrainingAdviceCache isExpired returns false before expiry")
    func testCacheNotExpired() {
        let cache = TrainingAdviceCache(
            contentJSON: "{}",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        #expect(!cache.isExpired)
    }

    @Test("TrainingAdviceCache isExpired returns true after expiry")
    func testCacheExpired() {
        let cache = TrainingAdviceCache(
            contentJSON: "{}",
            generatedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        #expect(cache.isExpired)
    }

    // MARK: - Integration: AI Service + Training Advice

    @Test("generateTrainingAdvice returns recommendation and caches it")
    func testServiceGeneratesAndCachesAdvice() async throws {
        let validJSON = """
        {"title":"今日推荐：背部训练","muscleGroups":["back","arms"],"exercises":["引体向上","杠铃划船","坐姿绳索划船"],"reasoning":"距离上次背部训练已2天。"}
        """
        let callCount = Mutex(0)
        let container = try ModelContainerConfiguration.makeTestContainer()
        let provider = MockAIProvider { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validJSON)
        }
        let service = AIAnalysisService(modelContainer: container, provider: provider)

        let context = TrainingContext(
            muscleGroupFrequency: ["chest": 2, "back": 1],
            daysSinceLastWorkout: 2
        )

        let first = try await service.generateTrainingAdvice(context: context)
        #expect(first.title == "今日推荐：背部训练")
        #expect(first.muscleGroups == ["back", "arms"])
        #expect(first.exercises.count == 3)

        let second = try await service.generateTrainingAdvice(context: context)
        #expect(second == first)
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("generateTrainingAdvice with forceRefresh bypasses cache")
    func testServiceForceRefreshAdvice() async throws {
        let validJSON = """
        {"title":"训练建议","muscleGroups":["legs"],"exercises":["深蹲"],"reasoning":"腿部需要训练。"}
        """
        let callCount = Mutex(0)
        let container = try ModelContainerConfiguration.makeTestContainer()
        let provider = MockAIProvider { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validJSON)
        }
        let service = AIAnalysisService(modelContainer: container, provider: provider)
        let context = TrainingContext(daysSinceLastWorkout: 3)

        _ = try await service.generateTrainingAdvice(context: context)
        _ = try await service.generateTrainingAdvice(context: context, forceRefresh: true)

        #expect(callCount.withLock { $0 } == 2)
    }
}
