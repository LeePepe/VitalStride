import Foundation
import HealthKitService
import SwiftData
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIPromptBuilder")

struct AIPromptContext: Sendable {
    let workouts: [WorkoutSnapshot]
    let healthData: HealthSnapshot

    struct WorkoutSnapshot: Sendable {
        let startDate: Date
        let endDate: Date?
        let type: String
        let exercises: [ExerciseSnapshot]
    }

    struct ExerciseSnapshot: Sendable {
        let name: String
        let muscleGroup: String
        let sets: [SetSnapshot]
    }

    struct SetSnapshot: Sendable {
        let weight: Double
        let reps: Int
        let setType: String
    }

    struct HealthSnapshot: Sendable {
        let averageHeartRate: Int?
        let todaySteps: Int?
        let lastNightSleep: TimeInterval?
        let latestWeight: Double?
    }
}

enum AIPromptBuilder {

    // MARK: - Context Building

    @MainActor
    static func buildContext(
        modelContext: ModelContext,
        healthKitService: HealthKitService,
        dateRange: DateInterval
    ) async -> AIPromptContext {
        let start = ContinuousClock.now

        let workoutSnapshots = fetchWorkoutSnapshots(modelContext: modelContext, dateRange: dateRange)
        let healthSnapshot = await fetchHealthSnapshot(healthKitService: healthKitService)

        let context = AIPromptContext(
            workouts: workoutSnapshots,
            healthData: healthSnapshot
        )

        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        logger.info("context built in \(ms)ms workouts=\(context.workouts.count)")

        return context
    }

    // MARK: - Prompt Builders

    static func buildWeeklySummaryPrompt(context: AIPromptContext) -> [ChatMessagePayload] {
        var dataSummary = "以下是用户本周的力量训练数据：\n\n"

        if context.workouts.isEmpty {
            dataSummary += "本周暂无训练记录。\n"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 HH:mm"

            for (index, workout) in context.workouts.enumerated() {
                let dateStr = formatter.string(from: workout.startDate)
                var duration = ""
                if let end = workout.endDate {
                    let minutes = Int(end.timeIntervalSince(workout.startDate) / 60)
                    duration = "，时长 \(minutes) 分钟"
                }
                dataSummary += "训练 \(index + 1)（\(dateStr)\(duration)）：\n"

                let totalVolume = workout.exercises.reduce(0.0) { exerciseTotal, exercise in
                    exerciseTotal + exercise.sets.filter { $0.setType == "working" }
                        .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                }

                for exercise in workout.exercises {
                    let workingSets = exercise.sets.filter { $0.setType == "working" }
                    guard !workingSets.isEmpty else { continue }
                    let setDescriptions = workingSets.map { "\($0.weight)kg×\($0.reps)" }
                    dataSummary += "  - \(exercise.name)（\(exercise.muscleGroup)）：\(setDescriptions.joined(separator: ", "))\n"
                }

                dataSummary += "  总训练量：\(String(format: "%.0f", totalVolume)) kg\n\n"
            }

            dataSummary += "本周训练次数：\(context.workouts.count)\n"
        }

        let systemMessage = ChatMessagePayload(
            role: "system",
            content: "你是一个专业的力量训练教练和运动科学顾问。请基于用户的训练数据，给出简洁、有针对性的训练总结和建议。使用中文回复，控制在 300 字以内。"
        )

        let userMessage = ChatMessagePayload(
            role: "user",
            content: "\(dataSummary)\n请总结我本周的训练情况，包括训练频率、肌群覆盖、训练量趋势，并给出简短建议。"
        )

        return [systemMessage, userMessage]
    }

    static func buildRecoveryPrompt(context: AIPromptContext) -> [ChatMessagePayload] {
        var dataSummary = "以下是用户最近的训练和健康数据：\n\n"

        dataSummary += "【训练频率】\n"
        if context.workouts.isEmpty {
            dataSummary += "近期无训练记录。\n"
        } else {
            let muscleGroupFrequency = buildMuscleGroupFrequency(workouts: context.workouts)
            for (group, count) in muscleGroupFrequency.sorted(by: { $0.value > $1.value }) {
                dataSummary += "  - \(group)：\(count) 次\n"
            }

            if let lastWorkout = context.workouts.sorted(by: { $0.startDate > $1.startDate }).first {
                let formatter = DateFormatter()
                formatter.dateFormat = "M月d日"
                dataSummary += "最近一次训练：\(formatter.string(from: lastWorkout.startDate))\n"
            }
        }

        dataSummary += "\n【健康数据】\n"
        if let hr = context.healthData.averageHeartRate {
            dataSummary += "  - 平均心率：\(hr) bpm\n"
        }
        if let sleep = context.healthData.lastNightSleep {
            let hours = Int(sleep / 3600)
            let minutes = Int((sleep.truncatingRemainder(dividingBy: 3600)) / 60)
            dataSummary += "  - 昨晚睡眠：\(hours)小时\(minutes)分钟\n"
        }
        if let steps = context.healthData.todaySteps {
            dataSummary += "  - 今日步数：\(steps)\n"
        }
        if let weight = context.healthData.latestWeight {
            dataSummary += "  - 体重：\(String(format: "%.1f", weight)) kg\n"
        }

        let systemMessage = ChatMessagePayload(
            role: "system",
            content: "你是一个专业的运动恢复顾问。请基于用户的训练频率和健康数据，评估恢复状态并给出具体建议。使用中文回复，控制在 300 字以内。"
        )

        let userMessage = ChatMessagePayload(
            role: "user",
            content: "\(dataSummary)\n请评估我的恢复状态，判断是否存在过度训练风险，并给出恢复建议（包括休息、营养、睡眠等方面）。"
        )

        return [systemMessage, userMessage]
    }

    static func buildPRDetectionPrompt(context: AIPromptContext) -> [ChatMessagePayload] {
        var dataSummary = "以下是用户的历史训练记录，请帮我检测个人记录（PR）：\n\n"

        if context.workouts.isEmpty {
            dataSummary += "暂无训练记录。\n"
        } else {
            let prData = detectPotentialPRs(workouts: context.workouts)

            if prData.isEmpty {
                dataSummary += "暂无足够数据检测 PR。\n"
            } else {
                for pr in prData {
                    dataSummary += "【\(pr.exerciseName)】\n"
                    dataSummary += "  最大重量：\(String(format: "%.1f", pr.maxWeight)) kg × \(pr.repsAtMaxWeight)\n"
                    dataSummary += "  最大单组容量：\(String(format: "%.0f", pr.maxVolumeSet)) kg\n"
                    dataSummary += "  记录数据条数：\(pr.totalSets) 组\n\n"
                }
            }
        }

        let systemMessage = ChatMessagePayload(
            role: "system",
            content: "你是一个专业的力量训练教练。请基于用户的历史训练数据，识别个人记录（PR），并给予鼓励和建议。使用中文回复，控制在 300 字以内。"
        )

        let userMessage = ChatMessagePayload(
            role: "user",
            content: "\(dataSummary)\n请分析我的个人记录情况，指出哪些动作有突破，并给出进一步提升的建议。"
        )

        return [systemMessage, userMessage]
    }

    static func buildSystemContext(context: AIPromptContext) -> String {
        var systemPrompt = "你是 VitalStride 的 AI 训练助手，帮助用户分析训练数据和健康状况。\n\n"
        systemPrompt += "【用户近期数据摘要】\n"

        if !context.workouts.isEmpty {
            systemPrompt += "近期训练 \(context.workouts.count) 次。\n"
            let muscleGroups = buildMuscleGroupFrequency(workouts: context.workouts)
            if !muscleGroups.isEmpty {
                let groupSummary = muscleGroups.sorted { $0.value > $1.value }
                    .map { "\($0.key) \($0.value)次" }
                    .joined(separator: "、")
                systemPrompt += "肌群分布：\(groupSummary)。\n"
            }
        } else {
            systemPrompt += "近期无训练记录。\n"
        }

        if let hr = context.healthData.averageHeartRate {
            systemPrompt += "平均心率：\(hr) bpm。\n"
        }
        if let sleep = context.healthData.lastNightSleep {
            let hours = String(format: "%.1f", sleep / 3600)
            systemPrompt += "昨晚睡眠：\(hours) 小时。\n"
        }
        if let weight = context.healthData.latestWeight {
            systemPrompt += "体重：\(String(format: "%.1f", weight)) kg。\n"
        }

        systemPrompt += "\n请使用中文回复，结合上述数据给出个性化建议。"
        return systemPrompt
    }

    // MARK: - Data Fetching

    @MainActor
    private static func fetchWorkoutSnapshots(
        modelContext: ModelContext,
        dateRange: DateInterval
    ) -> [AIPromptContext.WorkoutSnapshot] {
        let rangeStart = dateRange.start
        let rangeEnd = dateRange.end

        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.startDate >= rangeStart && workout.startDate <= rangeEnd && workout.endDate != nil
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = 50

        do {
            let workouts = try modelContext.fetch(descriptor)
            return workouts.map { workout in
                let exercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
                return AIPromptContext.WorkoutSnapshot(
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    type: workout.type.rawValue,
                    exercises: exercises.map { workoutExercise in
                        let sets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
                        let name = workoutExercise.exercise?.localizedName ?? "Unknown"
                        return AIPromptContext.ExerciseSnapshot(
                            name: name,
                            muscleGroup: workoutExercise.exercise?.muscleGroup.rawValue ?? "unknown",
                            sets: sets.map { set in
                                AIPromptContext.SetSnapshot(
                                    weight: set.weight,
                                    reps: set.reps,
                                    setType: set.setType.rawValue
                                )
                            }
                        )
                    }
                )
            }
        } catch {
            logger.error("Failed to fetch workouts: \(error.localizedDescription)")
            return []
        }
    }

    private static func fetchHealthSnapshot(
        healthKitService: HealthKitService
    ) async -> AIPromptContext.HealthSnapshot {
        async let heartRate = fetchLatestHeartRate(service: healthKitService)
        async let steps = fetchTodaySteps(service: healthKitService)
        async let sleep = fetchLastNightSleep(service: healthKitService)
        async let weight = fetchLatestWeight(service: healthKitService)

        return await AIPromptContext.HealthSnapshot(
            averageHeartRate: heartRate,
            todaySteps: steps,
            lastNightSleep: sleep,
            latestWeight: weight
        )
    }

    private static func fetchLatestHeartRate(service: HealthKitService) async -> Int? {
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: Date()),
            end: Date()
        )
        do {
            let result = try await service.fetchData(for: .heartRate, dateRange: interval)
            guard !result.dataPoints.isEmpty else { return nil }
            let avg = result.dataPoints.reduce(0.0) { $0 + $1.value } / Double(result.dataPoints.count)
            return Int(avg.rounded())
        } catch {
            return nil
        }
    }

    private static func fetchTodaySteps(service: HealthKitService) async -> Int? {
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: Date()),
            end: Date()
        )
        do {
            let result = try await service.fetchData(for: .stepCount, dateRange: interval)
            guard !result.dataPoints.isEmpty else { return nil }
            return Int(result.dataPoints.reduce(0.0) { $0 + $1.value })
        } catch {
            return nil
        }
    }

    private static func fetchLastNightSleep(service: HealthKitService) async -> TimeInterval? {
        let calendar = Calendar.current
        let now = Date()
        let interval = DateInterval(
            start: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!,
            end: now
        )
        do {
            let result = try await service.fetchData(for: .sleepAnalysis, dateRange: interval)
            let sleepSamples = result.dataPoints.filter { point in
                if let stage = point.sleepStage {
                    return stage != .inBed && stage != .awake
                }
                return false
            }
            guard !sleepSamples.isEmpty else { return nil }
            return sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        } catch {
            return nil
        }
    }

    private static func fetchLatestWeight(service: HealthKitService) async -> Double? {
        let interval = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
            end: Date()
        )
        do {
            let result = try await service.fetchData(for: .bodyMass, dateRange: interval)
            return result.dataPoints.sorted(by: { $0.startDate > $1.startDate }).first?.value
        } catch {
            return nil
        }
    }

    // MARK: - Analysis Helpers

    private static func buildMuscleGroupFrequency(
        workouts: [AIPromptContext.WorkoutSnapshot]
    ) -> [String: Int] {
        var frequency: [String: Int] = [:]
        for workout in workouts {
            var seen: Set<String> = []
            for exercise in workout.exercises {
                if seen.insert(exercise.muscleGroup).inserted {
                    frequency[exercise.muscleGroup, default: 0] += 1
                }
            }
        }
        return frequency
    }

    private static func detectPotentialPRs(
        workouts: [AIPromptContext.WorkoutSnapshot]
    ) -> [PRRecord] {
        var exerciseRecords: [String: PRRecord] = [:]

        for workout in workouts {
            for exercise in workout.exercises {
                let workingSets = exercise.sets.filter { $0.setType == "working" }
                guard !workingSets.isEmpty else { continue }

                var record = exerciseRecords[exercise.name] ?? PRRecord(
                    exerciseName: exercise.name,
                    maxWeight: 0,
                    repsAtMaxWeight: 0,
                    maxVolumeSet: 0,
                    totalSets: 0
                )

                for set in workingSets {
                    record = PRRecord(
                        exerciseName: record.exerciseName,
                        maxWeight: set.weight > record.maxWeight ? set.weight : record.maxWeight,
                        repsAtMaxWeight: set.weight > record.maxWeight ? set.reps : record.repsAtMaxWeight,
                        maxVolumeSet: max(record.maxVolumeSet, set.weight * Double(set.reps)),
                        totalSets: record.totalSets + 1
                    )
                }

                exerciseRecords[exercise.name] = record
            }
        }

        return exerciseRecords.values.sorted { $0.maxWeight > $1.maxWeight }
    }
}

struct PRRecord: Sendable {
    let exerciseName: String
    let maxWeight: Double
    let repsAtMaxWeight: Int
    let maxVolumeSet: Double
    let totalSets: Int
}

struct ChatMessagePayload: Sendable {
    let role: String
    let content: String
}
