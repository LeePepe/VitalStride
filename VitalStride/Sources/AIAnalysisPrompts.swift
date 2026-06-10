import AIService
import Foundation

enum AIAnalysisPrompts {

    // MARK: - Overview Insights

    static func buildInsightsMessages(context: OverviewContext) -> [ChatMessage] {
        let languageInstruction = localeLanguageInstruction(context.userLocale)
        let system = ChatMessage(
            role: "system",
            content: """
            你是 VitalStride 的健康数据分析助手。根据用户的健康和运动数据生成洞察卡片。
            你必须返回一个 JSON 数组，每个元素的格式如下：
            {"key":"唯一标识","cardType":"<type>","cardSize":"<size>","title":"标题","content":"正文","suggestion":"建议(可选,可为null)","iconName":"SF Symbol名称(可选,可为null)"}

            cardType 和 cardSize 的合法组合（只能使用以下组合，其他组合无效）：
            - metric: small, medium
            - insight: medium, wide
            - trend: medium, wide, large
            - summary: wide, large

            规则：
            - 生成 2-4 个洞察卡片
            - cardType 根据内容选择：metric(数据指标)、insight(分析洞察)、trend(趋势)、summary(总结)
            - cardSize 必须从上述合法组合中选择
            - 内容简洁，每个 content 控制在 50 字以内
            - 只返回 JSON 数组，不要包含其他文字
            - \(languageInstruction)
            """
        )

        var dataParts: [String] = []
        if let steps = context.todaySteps {
            dataParts.append("今日步数：\(steps)")
        }
        if let energy = context.todayActiveEnergy {
            dataParts.append("今日活动能量：\(String(format: "%.0f", energy)) kcal")
        }
        if let hr = context.restingHeartRate {
            dataParts.append("静息心率：\(hr) bpm")
        }
        if let sleep = context.lastNightSleepHours {
            dataParts.append("昨晚睡眠：\(String(format: "%.1f", sleep)) 小时")
        }
        if let weight = context.latestWeight {
            dataParts.append("最新体重：\(String(format: "%.1f", weight)) kg")
        }
        dataParts.append("近期训练次数：\(context.recentWorkoutCount)")
        if !context.recentMuscleGroups.isEmpty {
            let groups = context.recentMuscleGroups
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)次" }
                .joined(separator: "、")
            dataParts.append("肌群训练分布：\(groups)")
        }

        let userData = dataParts.isEmpty
            ? "暂无健康数据。"
            : dataParts.joined(separator: "\n")

        let user = ChatMessage(
            role: "user",
            content: "以下是我的健康和运动数据：\n\(userData)\n\n请生成洞察卡片。"
        )

        return [system, user]
    }

    // MARK: - Training Advice

    static func buildTrainingAdviceMessages(context: TrainingContext) -> [ChatMessage] {
        let system = ChatMessage(
            role: "system",
            content: """
            你是 VitalStride 的力量训练教练。根据用户的训练历史推荐今日训练计划。
            你必须返回一个 JSON 对象，格式如下：
            {"title":"推荐标题","muscleGroups":["肌群1","肌群2"],"exercises":["动作1","动作2","动作3"],"reasoning":"推荐理由"}

            规则：
            - muscleGroups 使用英文标识：chest, back, shoulders, legs, arms, core, fullBody
            - exercises 使用中文动作名称
            - reasoning 控制在 100 字以内，说明为什么推荐这些动作
            - 考虑肌群恢复时间，避免连续训练同一肌群
            - 只返回 JSON 对象，不要包含其他文字
            """
        )

        var dataParts: [String] = []

        if let days = context.daysSinceLastWorkout {
            dataParts.append("距上次训练：\(days) 天")
        } else {
            dataParts.append("近期无训练记录")
        }

        if !context.muscleGroupFrequency.isEmpty {
            let groups = context.muscleGroupFrequency
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)次" }
                .joined(separator: "、")
            dataParts.append("近期肌群训练频率：\(groups)")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"

        for (index, workout) in context.recentWorkouts.prefix(5).enumerated() {
            let dateStr = formatter.string(from: workout.date)
            let muscles = workout.muscleGroups.joined(separator: "/")
            let exercises = workout.exerciseNames.prefix(3).joined(separator: "、")
            dataParts.append(
                "训练\(index + 1)（\(dateStr)，\(workout.durationMinutes)分钟，\(muscles)）：\(exercises)"
            )
        }

        let userData = dataParts.joined(separator: "\n")

        let user = ChatMessage(
            role: "user",
            content: "以下是我最近的训练情况：\n\(userData)\n\n请推荐今日训练计划。"
        )

        return [system, user]
    }

    // MARK: - Data Trend Analysis

    static func buildDataTrendMessages(context: DataContext) -> [ChatMessage] {
        let system = ChatMessage(
            role: "system",
            content: """
            你是 VitalStride 的健康数据分析助手。分析用户某项健康数据的趋势。
            你必须返回一个 JSON 对象，格式如下：
            {"sampleType":"\(context.sampleType)","summary":"数据摘要","trend":"rising|falling|stable|insufficient","suggestion":"建议(可选,可为null)"}

            规则：
            - sampleType 必须为 "\(context.sampleType)"
            - trend 只能是 rising、falling、stable、insufficient 之一
            - summary 控制在 80 字以内
            - suggestion 给出针对性建议，控制在 50 字以内
            - 只返回 JSON 对象，不要包含其他文字
            - 使用中文
            """
        )

        var dataParts: [String] = []
        dataParts.append("数据类型：\(context.sampleType)")
        dataParts.append("数据点数量：\(context.dataPointCount)")
        dataParts.append("时间范围：\(context.timeRangeDescription)")

        let stats = context.statistics
        if let avg = stats.average {
            dataParts.append("平均值：\(String(format: "%.1f", avg)) \(stats.unit)")
        }
        if let min = stats.minimum {
            dataParts.append("最小值：\(String(format: "%.1f", min)) \(stats.unit)")
        }
        if let max = stats.maximum {
            dataParts.append("最大值：\(String(format: "%.1f", max)) \(stats.unit)")
        }
        if let latest = stats.latestValue {
            dataParts.append("最新值：\(String(format: "%.1f", latest)) \(stats.unit)")
        }

        let userData = dataParts.joined(separator: "\n")

        let user = ChatMessage(
            role: "user",
            content: "以下是我的健康数据统计：\n\(userData)\n\n请分析数据趋势。"
        )

        return [system, user]
    }

    // MARK: - JSON Extraction

    static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let jsonStart = trimmed.range(of: "```json"),
           let contentStart = trimmed[jsonStart.upperBound...].firstIndex(of: "\n"),
           let jsonEnd = trimmed.range(
               of: "```",
               range: trimmed.index(after: contentStart)..<trimmed.endIndex
           )
        {
            return String(trimmed[trimmed.index(after: contentStart)..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let jsonStart = trimmed.range(of: "```"),
           let contentStart = trimmed[jsonStart.upperBound...].firstIndex(of: "\n"),
           let jsonEnd = trimmed.range(
               of: "```",
               range: trimmed.index(after: contentStart)..<trimmed.endIndex
           )
        {
            return String(trimmed[trimmed.index(after: contentStart)..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    // MARK: - Locale Helper

    static func localeLanguageInstruction(_ locale: String) -> String {
        if locale.isEmpty { return "使用中文" }
        let isZh = locale.hasPrefix("zh")
        return isZh ? "使用中文" : "Use English"
    }
}
