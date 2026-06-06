import Foundation
import Testing

@testable import VitalStride

@Suite("AIPromptBuilder Tests")
struct AIPromptBuilderTests {

    // MARK: - Test Data Helpers

    private func makeWorkoutSnapshot(
        daysAgo: Int = 0,
        durationMinutes: Int = 60,
        exercises: [AIPromptContext.ExerciseSnapshot] = []
    ) -> AIPromptContext.WorkoutSnapshot {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let end = start.addingTimeInterval(Double(durationMinutes * 60))
        return AIPromptContext.WorkoutSnapshot(
            startDate: start,
            endDate: end,
            type: "strength",
            exercises: exercises
        )
    }

    private func makeExerciseSnapshot(
        name: String = "平板卧推",
        muscleGroup: String = "chest",
        sets: [AIPromptContext.SetSnapshot] = []
    ) -> AIPromptContext.ExerciseSnapshot {
        AIPromptContext.ExerciseSnapshot(name: name, muscleGroup: muscleGroup, sets: sets)
    }

    private func makeSetSnapshot(
        weight: Double = 60.0,
        reps: Int = 10,
        setType: String = "working"
    ) -> AIPromptContext.SetSnapshot {
        AIPromptContext.SetSnapshot(weight: weight, reps: reps, setType: setType)
    }

    private func makeHealthSnapshot(
        averageHeartRate: Int? = nil,
        todaySteps: Int? = nil,
        lastNightSleep: TimeInterval? = nil,
        latestWeight: Double? = nil
    ) -> AIPromptContext.HealthSnapshot {
        AIPromptContext.HealthSnapshot(
            averageHeartRate: averageHeartRate,
            todaySteps: todaySteps,
            lastNightSleep: lastNightSleep,
            latestWeight: latestWeight
        )
    }

    // MARK: - Weekly Summary Tests

    @Test("Weekly summary prompt with workouts includes training data")
    func weeklySummaryWithData() {
        let sets = [
            makeSetSnapshot(weight: 80.0, reps: 8),
            makeSetSnapshot(weight: 80.0, reps: 6),
            makeSetSnapshot(weight: 75.0, reps: 8),
        ]
        let exercise = makeExerciseSnapshot(name: "平板卧推", muscleGroup: "chest", sets: sets)
        let workout = makeWorkoutSnapshot(daysAgo: 1, exercises: [exercise])

        let context = AIPromptContext(
            workouts: [workout],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildWeeklySummaryPrompt(context: context)

        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[1].role == "user")

        let userContent = messages[1].content
        #expect(userContent.contains("平板卧推"))
        #expect(userContent.contains("80.0kg×8"))
        #expect(userContent.contains("chest"))
        #expect(userContent.contains("本周训练次数：1"))
    }

    @Test("Weekly summary prompt without workouts shows no-data message")
    func weeklySummaryEmpty() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildWeeklySummaryPrompt(context: context)

        #expect(messages.count == 2)
        let userContent = messages[1].content
        #expect(userContent.contains("本周暂无训练记录"))
    }

    @Test("Weekly summary calculates total volume correctly")
    func weeklySummaryVolume() {
        let sets = [
            makeSetSnapshot(weight: 100.0, reps: 5),
            makeSetSnapshot(weight: 100.0, reps: 5),
        ]
        let exercise = makeExerciseSnapshot(name: "深蹲", muscleGroup: "legs", sets: sets)
        let workout = makeWorkoutSnapshot(daysAgo: 0, exercises: [exercise])

        let context = AIPromptContext(
            workouts: [workout],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildWeeklySummaryPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("1000"))
    }

    @Test("Weekly summary excludes warmup sets from volume")
    func weeklySummaryExcludesWarmup() {
        let sets = [
            makeSetSnapshot(weight: 40.0, reps: 10, setType: "warmup"),
            makeSetSnapshot(weight: 80.0, reps: 5, setType: "working"),
        ]
        let exercise = makeExerciseSnapshot(name: "卧推", muscleGroup: "chest", sets: sets)
        let workout = makeWorkoutSnapshot(daysAgo: 0, exercises: [exercise])

        let context = AIPromptContext(
            workouts: [workout],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildWeeklySummaryPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("400"))
    }

    // MARK: - Recovery Prompt Tests

    @Test("Recovery prompt includes health data")
    func recoveryWithHealthData() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot(
                averageHeartRate: 62,
                todaySteps: 8500,
                lastNightSleep: 7 * 3600 + 30 * 60,
                latestWeight: 75.5
            )
        )

        let messages = AIPromptBuilder.buildRecoveryPrompt(context: context)

        #expect(messages.count == 2)
        let userContent = messages[1].content
        #expect(userContent.contains("62 bpm"))
        #expect(userContent.contains("8500"))
        #expect(userContent.contains("7小时30分钟"))
        #expect(userContent.contains("75.5 kg"))
    }

    @Test("Recovery prompt includes muscle group frequency")
    func recoveryMuscleFrequency() {
        let chestExercise = makeExerciseSnapshot(
            name: "卧推", muscleGroup: "chest",
            sets: [makeSetSnapshot()]
        )
        let legExercise = makeExerciseSnapshot(
            name: "深蹲", muscleGroup: "legs",
            sets: [makeSetSnapshot()]
        )

        let workout1 = makeWorkoutSnapshot(daysAgo: 1, exercises: [chestExercise])
        let workout2 = makeWorkoutSnapshot(daysAgo: 3, exercises: [legExercise])
        let workout3 = makeWorkoutSnapshot(daysAgo: 5, exercises: [chestExercise])

        let context = AIPromptContext(
            workouts: [workout1, workout2, workout3],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildRecoveryPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("chest"))
        #expect(userContent.contains("legs"))
    }

    @Test("Recovery prompt with no health data omits fields gracefully")
    func recoveryNoHealthData() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildRecoveryPrompt(context: context)
        let userContent = messages[1].content
        #expect(!userContent.contains("bpm"))
        #expect(!userContent.contains("步数"))
        #expect(userContent.contains("近期无训练记录"))
    }

    // MARK: - PR Detection Tests

    @Test("PR detection identifies max weight correctly")
    func prDetectionMaxWeight() {
        let sets = [
            makeSetSnapshot(weight: 60.0, reps: 10),
            makeSetSnapshot(weight: 80.0, reps: 5),
            makeSetSnapshot(weight: 100.0, reps: 3),
        ]
        let exercise = makeExerciseSnapshot(name: "硬拉", muscleGroup: "back", sets: sets)
        let workout = makeWorkoutSnapshot(daysAgo: 2, exercises: [exercise])

        let context = AIPromptContext(
            workouts: [workout],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildPRDetectionPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("硬拉"))
        #expect(userContent.contains("100.0"))
    }

    @Test("PR detection with no data shows appropriate message")
    func prDetectionEmpty() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildPRDetectionPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("暂无训练记录"))
    }

    @Test("PR detection aggregates across multiple workouts")
    func prDetectionMultipleWorkouts() {
        let sets1 = [makeSetSnapshot(weight: 60.0, reps: 10)]
        let sets2 = [makeSetSnapshot(weight: 80.0, reps: 8)]

        let exercise1 = makeExerciseSnapshot(name: "卧推", muscleGroup: "chest", sets: sets1)
        let exercise2 = makeExerciseSnapshot(name: "卧推", muscleGroup: "chest", sets: sets2)

        let workout1 = makeWorkoutSnapshot(daysAgo: 7, exercises: [exercise1])
        let workout2 = makeWorkoutSnapshot(daysAgo: 1, exercises: [exercise2])

        let context = AIPromptContext(
            workouts: [workout1, workout2],
            healthData: makeHealthSnapshot()
        )

        let messages = AIPromptBuilder.buildPRDetectionPrompt(context: context)
        let userContent = messages[1].content
        #expect(userContent.contains("80.0"))
        #expect(userContent.contains("2 组"))
    }

    // MARK: - System Context Tests

    @Test("System context includes workout summary")
    func systemContextWorkouts() {
        let exercise = makeExerciseSnapshot(
            name: "卧推", muscleGroup: "chest",
            sets: [makeSetSnapshot()]
        )
        let workout = makeWorkoutSnapshot(daysAgo: 0, exercises: [exercise])

        let context = AIPromptContext(
            workouts: [workout],
            healthData: makeHealthSnapshot(averageHeartRate: 65, latestWeight: 72.0)
        )

        let systemContext = AIPromptBuilder.buildSystemContext(context: context)
        #expect(systemContext.contains("训练 1 次"))
        #expect(systemContext.contains("chest"))
        #expect(systemContext.contains("65 bpm"))
        #expect(systemContext.contains("72.0 kg"))
    }

    @Test("System context with no data shows appropriate placeholder")
    func systemContextEmpty() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot()
        )

        let systemContext = AIPromptBuilder.buildSystemContext(context: context)
        #expect(systemContext.contains("近期无训练记录"))
    }

    // MARK: - ChatMessagePayload Tests

    @Test("All prompt builders return system + user message pair")
    func promptStructure() {
        let context = AIPromptContext(
            workouts: [],
            healthData: makeHealthSnapshot()
        )

        let weekly = AIPromptBuilder.buildWeeklySummaryPrompt(context: context)
        let recovery = AIPromptBuilder.buildRecoveryPrompt(context: context)
        let pr = AIPromptBuilder.buildPRDetectionPrompt(context: context)

        for messages in [weekly, recovery, pr] {
            #expect(messages.count == 2)
            #expect(messages[0].role == "system")
            #expect(messages[1].role == "user")
            #expect(!messages[0].content.isEmpty)
            #expect(!messages[1].content.isEmpty)
        }
    }
}
