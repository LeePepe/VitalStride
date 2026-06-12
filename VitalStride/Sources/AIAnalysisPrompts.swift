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

            cardType 可选值：metric、insight、trend、summary、list、action
            cardSize 可选值：small、medium、wide、large

            合法的 cardSize×cardType 组合（白名单）：
            small×metric, small×action,
            medium×metric, medium×trend, medium×insight,
            wide×insight, wide×list, wide×summary, wide×action, wide×trend,
            large×trend, large×list, large×summary

            content 格式要求：
            - metric/insight/action: 纯文本字符串
            - trend: JSON 数组，每个元素 {"date":"标签","value":数字}
            - list: JSON 数组，每个元素 {"label":"名称","value":"值"} 或纯字符串数组
            - summary: JSON 对象，key-value 对，如 {"Steps":"8K","Calories":"500"}

            规则：
            - 生成 5-8 个洞察卡片
            - 必须包含至少 3 种不同的 cardType（例如 metric + insight + list）
            - 不允许全部使用 metric 类型
            - 至少包含 1 个 wide 或 large 尺寸的卡片，提供视觉层次
            - cardType 根据内容选择合适的类型
            - cardSize×cardType 必须在上述白名单内
            - 内容简洁，每个 content 控制在 50 字以内（trend/list/summary 的 JSON 不计入）
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

    // MARK: - Category-Specific Data Trend Analysis

    static func buildCategoryTrendMessages(sampleType: String, context: DataContext) -> [ChatMessage] {
        guard let categoryPrompt = categorySystemPrompt(for: sampleType, context: context) else {
            return buildDataTrendMessages(context: context)
        }

        let system = ChatMessage(role: "system", content: categoryPrompt)
        let user = ChatMessage(role: "user", content: buildDataUserMessage(context: context))
        return [system, user]
    }

    // MARK: - Data Trend Analysis (Generic Fallback)

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

    // MARK: - Category Prompt Helpers

    private static let baseResponseFormat = """
        你必须返回一个 JSON 对象，格式如下：
        {"sampleType":"<sampleType>","summary":"数据摘要","trend":"rising|falling|stable|insufficient","suggestion":"建议(可选,可为null)"}

        规则：
        - trend 只能是 rising、falling、stable、insufficient 之一
        - summary 控制在 80 字以内
        - suggestion 给出针对性建议，控制在 50 字以内
        - 只返回 JSON 对象，不要包含其他文字
        - 使用中文
        """

    private static let categorySampleTypes: Set<String> = [
        "stepCount", "heartRate", "sleepAnalysis", "bodyMass", "activeEnergyBurned",
    ]

    static func isCategorySampleType(_ sampleType: String) -> Bool {
        categorySampleTypes.contains(sampleType)
    }

    private static func categorySystemPrompt(for sampleType: String, context: DataContext) -> String? {
        let responseFormat = baseResponseFormat
            .replacingOccurrences(of: "<sampleType>", with: sampleType)

        switch sampleType {
        case "stepCount":
            return """
                你是 VitalStride 的步数分析助手。请从以下维度分析用户的步数数据：
                1. 今日步数 vs 7 天均值——是否达标（参考 8000 步/日标准）
                2. 工作日 vs 周末步数模式差异
                3. 连续达标天数（连续 ≥8000 步的天数）
                4. 步数趋势方向（近期是否在增长或下降）

                \(responseFormat)
                """

        case "heartRate":
            return """
                你是 VitalStride 的心率分析助手。请从以下维度分析用户的心率数据：
                1. 静息心率 7 天趋势——是否保持在健康范围（60-100 bpm）
                2. 运动后恢复能力——运动心率回落速度
                3. HRV（心率变异性）趋势——压力与恢复状态
                4. 跨周均值对比——本周 vs 上周静息心率变化

                \(responseFormat)
                """

        case "sleepAnalysis":
            return """
                你是 VitalStride 的睡眠分析助手。请从以下维度分析用户的睡眠数据：
                1. 平均睡眠时长——是否达到 7-9 小时推荐标准
                2. 睡眠规律性——入睡时间和起床时间的波动幅度
                3. 深睡/REM 占比——睡眠质量评估（如有数据）
                4. 工作日 vs 周末睡眠模式差异

                \(responseFormat)
                """

        case "bodyMass":
            return """
                你是 VitalStride 的体重分析助手。请从以下维度分析用户的体重数据：
                1. 30 天趋势方向——整体上升、下降还是稳定
                2. 周均值变化率——每周平均增减幅度
                3. 距目标进度——结合趋势评估是否朝目标方向前进
                4. 波动幅度——日间波动是否在正常范围（±1kg）

                \(responseFormat)
                """

        case "activeEnergyBurned":
            return """
                你是 VitalStride 的活动能量分析助手。请从以下维度分析用户的活动能量数据：
                1. 日均消耗对比——近期 vs 历史日均消耗量
                2. 训练日 vs 非训练日差异——运动对能量消耗的贡献
                3. 趋势方向——活动能量是否在增长或下降
                4. 消耗稳定性——日间波动是否过大

                \(responseFormat)
                """

        default:
            return nil
        }
    }

    private static func buildDataUserMessage(context: DataContext) -> String {
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
        return "以下是我的健康数据统计：\n\(userData)\n\n请分析数据趋势。"
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
