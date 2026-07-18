import AIService
import Foundation
import SwiftData
import Synchronization
import Testing
import VitalModels

@testable import VitalStride

// MARK: - Mock Provider

struct MockAIProvider: AIProvider, Sendable {
    let chatHandler: @Sendable ([ChatMessage], String?) async throws -> ChatResponse

    init(chatHandler: @escaping @Sendable ([ChatMessage], String?) async throws -> ChatResponse) {
        self.chatHandler = chatHandler
    }

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try await chatHandler(messages, model)
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIServiceError.noProviderAvailable) }
    }
}

// MARK: - Test Fixtures

private let validInsightsJSON = """
{"headline":"今日步数达标，睡眠质量良好","insights":[{"key":"steps","cardType":"metric","cardSize":"small","title":"步数","content":"今日已走8000步","suggestion":"再走2000步达标","iconName":"figure.walk"},{"key":"sleep","cardType":"insight","cardSize":"medium","title":"睡眠","content":"昨晚睡了7.5小时","suggestion":null,"iconName":"moon.zzz"}]}
"""

private let legacyInsightsJSON = """
[{"key":"steps","cardType":"metric","cardSize":"small","title":"步数","content":"今日已走8000步","suggestion":"再走2000步达标","iconName":"figure.walk"},{"key":"sleep","cardType":"insight","cardSize":"medium","title":"睡眠","content":"昨晚睡了7.5小时","suggestion":null,"iconName":"moon.zzz"}]
"""

private let validTrainingJSON = """
{"title":"今日推荐：胸部训练","muscleGroups":["chest","arms"],"exercises":["平板卧推","上斜哑铃飞鸟","绳索夹胸"],"reasoning":"距离上次胸部训练已3天，肌肉已充分恢复。"}
"""

private let validDataAnalysisJSON = """
{"sampleType":"bodyMass","summary":"近一周体重稳定在72kg左右","trend":"stable","suggestion":"保持当前饮食和训练计划"}
"""

// MARK: - Tests

@Suite("AIAnalysisService Tests")
struct AIAnalysisServiceTests {

    private func makeService(
        chatHandler: @escaping @Sendable ([ChatMessage], String?) async throws -> ChatResponse,
        cacheTTL: TimeInterval = 3600
    ) throws -> AIAnalysisService {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let provider = MockAIProvider(chatHandler: chatHandler)
        return AIAnalysisService(modelContainer: container, provider: provider, cacheTTL: cacheTTL)
    }

    private func makeOverviewContext() -> OverviewContext {
        OverviewContext(
            todaySteps: 8000,
            restingHeartRate: 65,
            lastNightSleepHours: 7.5,
            latestWeight: 72.0,
            recentWorkoutCount: 3,
            recentMuscleGroups: ["chest": 2, "back": 1]
        )
    }

    private func makeTrainingContext() -> TrainingContext {
        TrainingContext(
            recentWorkouts: [
                TrainingContext.WorkoutSummary(
                    date: Date().addingTimeInterval(-86400 * 2),
                    durationMinutes: 60,
                    exerciseNames: ["平板卧推", "上斜哑铃飞鸟"],
                    muscleGroups: ["chest"],
                    totalVolume: 5000
                ),
            ],
            muscleGroupFrequency: ["chest": 2, "back": 1],
            daysSinceLastWorkout: 2
        )
    }

    private func makeDataContext(sampleType: String = "bodyMass") -> DataContext {
        DataContext(
            sampleType: sampleType,
            dataPointCount: 14,
            timeRangeDescription: "最近两周",
            statistics: DataContext.DataStatistics(
                average: 72.0,
                minimum: 71.5,
                maximum: 72.8,
                latestValue: 72.1,
                unit: "kg"
            )
        )
    }

    // MARK: - generateInsights

    @Test("generateInsights returns parsed AIAnalysisResponse on valid JSON response")
    func testGenerateInsightsSuccess() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: validInsightsJSON)
        }
        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.headline == "今日步数达标，睡眠质量良好")
        #expect(result.insights.count == 2)
        #expect(result.insights[0].key == "steps")
        #expect(result.insights[0].cardType == "metric")
        #expect(result.insights[1].key == "sleep")
    }

    @Test("generateInsights returns cached data on cache hit")
    func testGenerateInsightsCacheHit() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        let cached = try await service.generateInsights(context: context)

        #expect(cached.insights.count == 2)
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("generateInsights with forceRefresh bypasses cache")
    func testGenerateInsightsForceRefresh() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        _ = try await service.generateInsights(context: context, forceRefresh: true)

        #expect(callCount.withLock { $0 } == 2)
    }

    @Test("generateInsights returns stale data on expired cache")
    func testGenerateInsightsStaleServe() async throws {
        let callCount = Mutex(0)
        let service = try makeService(chatHandler: { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validInsightsJSON)
        }, cacheTTL: 0.001)
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        try await Task.sleep(for: .milliseconds(10))
        let stale = try await service.generateInsights(context: context)

        #expect(stale.insights.count == 2)
    }

    @Test("generateInsights throws responseParsingFailed on JSON parse failure after retry")
    func testGenerateInsightsParseFallback() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: "This is not valid JSON at all")
        }
        await #expect(throws: AIServiceError.self) {
            try await service.generateInsights(context: makeOverviewContext())
        }
    }

    @Test("generateInsights retries once and succeeds on second parse")
    func testGenerateInsightsRetrySuccess() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 1 {
                return ChatResponse(content: "invalid json")
            }
            return ChatResponse(content: validInsightsJSON)
        }

        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.insights.count == 2)
        #expect(callCount.withLock { $0 } == 2)
    }

    @Test("generateInsights throws on noProviderAvailable with no cache")
    func testGenerateInsightsNoProviderNoCacheThrows() async throws {
        let service = try makeService { _, _ in
            throw AIServiceError.noProviderAvailable
        }

        await #expect(throws: AIServiceError.self) {
            try await service.generateInsights(context: makeOverviewContext())
        }
    }

    @Test("generateInsights returns cache on noProviderAvailable with existing cache")
    func testGenerateInsightsNoProviderWithCache() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 1 {
                return ChatResponse(content: validInsightsJSON)
            }
            throw AIServiceError.noProviderAvailable
        }
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        let result = try await service.generateInsights(context: context, forceRefresh: true)

        #expect(result.insights.count == 2)
    }

    @Test("generateInsights handles markdown code block wrapped JSON")
    func testGenerateInsightsMarkdownJSON() async throws {
        let wrappedJSON = "```json\n\(validInsightsJSON)\n```"
        let service = try makeService { _, _ in
            ChatResponse(content: wrappedJSON)
        }
        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.insights.count == 2)
    }

    // MARK: - generateTrainingAdvice

    @Test("generateTrainingAdvice returns parsed recommendation")
    func testGenerateTrainingAdviceSuccess() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: validTrainingJSON)
        }
        let advice = try await service.generateTrainingAdvice(context: makeTrainingContext())
        #expect(advice.title == "今日推荐：胸部训练")
        #expect(advice.muscleGroups == ["chest", "arms"])
        #expect(advice.exercises.count == 3)
    }

    @Test("generateTrainingAdvice returns cached data on hit")
    func testGenerateTrainingAdviceCacheHit() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validTrainingJSON)
        }
        let context = makeTrainingContext()

        _ = try await service.generateTrainingAdvice(context: context)
        let cached = try await service.generateTrainingAdvice(context: context)

        #expect(cached.muscleGroups == ["chest", "arms"])
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("generateTrainingAdvice falls back on parse failure")
    func testGenerateTrainingAdviceFallback() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: "not json")
        }
        let result = try await service.generateTrainingAdvice(context: makeTrainingContext())
        #expect(result.title == String(localized: "训练建议", comment: "Fallback training advice title"))
        #expect(result.muscleGroups.isEmpty)
        #expect(result.reasoning == String(localized: "暂时无法生成训练建议，请稍后重试。", comment: "Fallback training advice reasoning"))
    }

    @Test("generateTrainingAdvice with forceRefresh bypasses cache")
    func testGenerateTrainingAdviceForceRefresh() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validTrainingJSON)
        }
        let context = makeTrainingContext()

        _ = try await service.generateTrainingAdvice(context: context)
        _ = try await service.generateTrainingAdvice(context: context, forceRefresh: true)

        #expect(callCount.withLock { $0 } == 2)
    }

    // MARK: - analyzeDataTrend

    @Test("analyzeDataTrend returns parsed analysis")
    func testAnalyzeDataTrendSuccess() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: validDataAnalysisJSON)
        }
        let analysis = try await service.analyzeDataTrend(context: makeDataContext())
        #expect(analysis.sampleType == "bodyMass")
        #expect(analysis.trend == "stable")
    }

    @Test("analyzeDataTrend caches by sampleType")
    func testAnalyzeDataTrendCacheBySampleType() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validDataAnalysisJSON)
        }

        _ = try await service.analyzeDataTrend(context: makeDataContext(sampleType: "bodyMass"))
        _ = try await service.analyzeDataTrend(context: makeDataContext(sampleType: "bodyMass"))

        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("analyzeDataTrend falls back on parse failure")
    func testAnalyzeDataTrendFallback() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: "not json")
        }
        let result = try await service.analyzeDataTrend(context: makeDataContext())
        #expect(result.sampleType == "bodyMass")
        #expect(result.trend == "insufficient")
        #expect(result.summary == "暂时无法分析数据趋势，请稍后重试。")
    }

    @Test("analyzeDataTrend with forceRefresh bypasses cache")
    func testAnalyzeDataTrendForceRefresh() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validDataAnalysisJSON)
        }
        let context = makeDataContext()

        _ = try await service.analyzeDataTrend(context: context)
        _ = try await service.analyzeDataTrend(context: context, forceRefresh: true)

        #expect(callCount.withLock { $0 } == 2)
    }

    @Test("analyzeDataTrend returns stale data on expired cache")
    func testAnalyzeDataTrendStaleServe() async throws {
        let callCount = Mutex(0)
        let service = try makeService(chatHandler: { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validDataAnalysisJSON)
        }, cacheTTL: 0.001)
        let context = makeDataContext()

        _ = try await service.analyzeDataTrend(context: context)
        try await Task.sleep(for: .milliseconds(10))
        let stale = try await service.analyzeDataTrend(context: context)

        #expect(stale.sampleType == "bodyMass")
        #expect(stale.trend == "stable")
    }

    // MARK: - Prompt Building

    @Test("prompt builder includes context data in insights messages")
    func testInsightsPromptContainsData() {
        let context = OverviewContext(
            todaySteps: 5000,
            restingHeartRate: 70,
            recentWorkoutCount: 2
        )
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context)

        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[1].role == "user")
        #expect(messages[1].content.contains("5000"))
        #expect(messages[1].content.contains("70"))
    }

    @Test("insights prompt with previousInsights includes summary in user message")
    func testInsightsPromptWithPreviousInsights() {
        let context = OverviewContext(
            todaySteps: 8000,
            recentWorkoutCount: 3
        )
        let previous = [
            OverviewInsight(key: "steps", cardType: "metric", cardSize: "small", title: "步数", content: "今日已走6000步"),
            OverviewInsight(key: "sleep", cardType: "insight", cardSize: "medium", title: "睡眠", content: "昨晚睡了7小时"),
        ]
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context, previousInsights: previous)

        #expect(messages.count == 2)
        #expect(messages[1].content.contains("上次分析结果"))
        #expect(messages[1].content.contains("[步数] 今日已走6000步"))
        #expect(messages[1].content.contains("[睡眠] 昨晚睡了7小时"))
        #expect(messages[1].content.contains("---"))
    }

    @Test("insights prompt without previousInsights does not include summary")
    func testInsightsPromptWithoutPreviousInsights() {
        let context = OverviewContext(
            todaySteps: 5000,
            recentWorkoutCount: 2
        )
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context)

        #expect(!messages[1].content.contains("上次分析结果"))
    }

    @Test("insights prompt with empty previousInsights does not include summary")
    func testInsightsPromptWithEmptyPreviousInsights() {
        let context = OverviewContext(
            todaySteps: 5000,
            recentWorkoutCount: 2
        )
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context, previousInsights: [])

        #expect(!messages[1].content.contains("上次分析结果"))
    }

    @Test("insights system prompt requires headline JSON object format")
    func testInsightsPromptHeadlineFormat() {
        let context = OverviewContext(recentWorkoutCount: 0)
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context)

        #expect(messages[0].content.contains("\"headline\""))
        #expect(messages[0].content.contains("\"insights\""))
        #expect(messages[0].content.contains("JSON 对象"))
    }

    @Test("insights headline instruction uses Chinese for zh locale")
    func testInsightsHeadlineChineseLocale() {
        let context = OverviewContext(recentWorkoutCount: 0, userLocale: "zh-Hans")
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context)

        #expect(messages[0].content.contains("用一句话概括最显著的变化"))
    }

    @Test("insights headline instruction uses English for non-zh locale")
    func testInsightsHeadlineEnglishLocale() {
        let context = OverviewContext(recentWorkoutCount: 0, userLocale: "en")
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context)

        #expect(messages[0].content.contains("Summarize the most notable change in one sentence"))
    }

    @Test("insights prompt truncates long previousInsights title and content")
    func testInsightsPromptTruncatesPreviousInsights() {
        let context = OverviewContext(todaySteps: 5000, recentWorkoutCount: 1)
        let longTitle = String(repeating: "标", count: 60)
        let longContent = String(repeating: "内", count: 250)
        let previous = [
            OverviewInsight(key: "long", cardType: "metric", cardSize: "small", title: longTitle, content: longContent),
        ]
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context, previousInsights: previous)

        let userContent = messages[1].content
        #expect(!userContent.contains(longTitle))
        #expect(!userContent.contains(longContent))
        #expect(userContent.contains(String(repeating: "标", count: 50)))
        #expect(userContent.contains(String(repeating: "内", count: 200)))
    }

    @Test("prompt builder includes training data")
    func testTrainingPromptContainsData() {
        let context = TrainingContext(
            muscleGroupFrequency: ["chest": 3],
            daysSinceLastWorkout: 1
        )
        let messages = AIAnalysisPrompts.buildTrainingAdviceMessages(context: context)

        #expect(messages.count == 2)
        #expect(messages[1].content.contains("1 天"))
        #expect(messages[1].content.contains("chest"))
    }

    @Test("prompt builder includes data trend statistics")
    func testDataTrendPromptContainsStats() {
        let context = DataContext(
            sampleType: "heartRate",
            dataPointCount: 100,
            timeRangeDescription: "最近一周",
            statistics: DataContext.DataStatistics(
                average: 72.0,
                unit: "bpm"
            )
        )
        let messages = AIAnalysisPrompts.buildDataTrendMessages(context: context)

        #expect(messages.count == 2)
        #expect(messages[0].content.contains("heartRate"))
        #expect(messages[1].content.contains("72.0"))
        #expect(messages[1].content.contains("bpm"))
    }

    // MARK: - JSON Extraction

    @Test("extractJSON handles markdown code blocks")
    func testExtractJSONFromMarkdown() {
        let wrapped = "```json\n[{\"key\":\"test\"}]\n```"
        let result = AIAnalysisPrompts.extractJSON(from: wrapped)
        #expect(result == "[{\"key\":\"test\"}]")
    }

    @Test("extractJSON handles plain code blocks")
    func testExtractJSONFromPlainBlock() {
        let wrapped = "```\n{\"title\":\"test\"}\n```"
        let result = AIAnalysisPrompts.extractJSON(from: wrapped)
        #expect(result == "{\"title\":\"test\"}")
    }

    @Test("extractJSON returns raw text when no blocks found")
    func testExtractJSONRawText() {
        let raw = "[{\"key\":\"test\"}]"
        let result = AIAnalysisPrompts.extractJSON(from: raw)
        #expect(result == raw)
    }

    // MARK: - Cache Integration with SwiftData

    @Test("cache persists across method calls within same service")
    func testCacheIntegration() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        let first = try await service.generateInsights(context: context)
        let second = try await service.generateInsights(context: context)

        #expect(first == second)
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("network error propagates to caller")
    func testNetworkErrorPropagates() async throws {
        let service = try makeService { _, _ in
            throw AIServiceError.networkError(underlying: URLError(.notConnectedToInternet))
        }
        await #expect(throws: AIServiceError.self) {
            try await service.generateInsights(context: makeOverviewContext())
        }
    }

    // MARK: - clearAllCaches

    @Test("clearAllCaches removes all cached data")
    func testClearAllCaches() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        await service.clearAllCaches()

        let callCount = Mutex(0)
        let service2 = try makeService { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(content: validInsightsJSON)
        }
        _ = try await service2.generateInsights(context: context)
        #expect(callCount.withLock { $0 } == 1)
    }

    // MARK: - noProviderAvailable with analyzeDataTrend

    @Test("analyzeDataTrend returns cache on noProviderAvailable with existing cache")
    func testAnalyzeDataTrendNoProviderWithCache() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 1 {
                return ChatResponse(content: validDataAnalysisJSON)
            }
            throw AIServiceError.noProviderAvailable
        }
        let context = makeDataContext()

        _ = try await service.analyzeDataTrend(context: context)
        let result = try await service.analyzeDataTrend(context: context, forceRefresh: true)

        #expect(result.sampleType == "bodyMass")
        #expect(result.trend == "stable")
    }

    @Test("analyzeDataTrend throws on noProviderAvailable with no cache")
    func testAnalyzeDataTrendNoProviderNoCacheThrows() async throws {
        let service = try makeService { _, _ in
            throw AIServiceError.noProviderAvailable
        }
        await #expect(throws: AIServiceError.self) {
            try await service.analyzeDataTrend(context: makeDataContext())
        }
    }

    // MARK: - buildCategoryTrendMessages

    @Test(
        "buildCategoryTrendMessages returns category-specific prompt for each core type",
        arguments: ["stepCount", "heartRate", "sleepAnalysis", "bodyMass", "activeEnergyBurned"]
    )
    func testCategoryPromptForCoreTypes(sampleType: String) {
        let context = makeDataContext(sampleType: sampleType)
        let messages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: sampleType, context: context)

        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[1].role == "user")
        #expect(messages[0].content != AIAnalysisPrompts.buildDataTrendMessages(context: context)[0].content)
    }

    @Test("buildCategoryTrendMessages returns distinct prompts per core type")
    func testCategoryPromptsAreDistinct() {
        let coreTypes = ["stepCount", "heartRate", "sleepAnalysis", "bodyMass", "activeEnergyBurned"]
        var systemContents: [String: String] = [:]

        for sampleType in coreTypes {
            let context = makeDataContext(sampleType: sampleType)
            let messages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: sampleType, context: context)
            systemContents[sampleType] = messages[0].content
        }

        let uniqueContents = Set(systemContents.values)
        #expect(uniqueContents.count == coreTypes.count)
    }

    @Test(
        "buildCategoryTrendMessages falls back to generic prompt for non-core types",
        arguments: ["restingHeartRate", "vo2Max", "flightsClimbed", "unknownType"]
    )
    func testCategoryPromptFallbackForNonCoreTypes(sampleType: String) {
        let context = makeDataContext(sampleType: sampleType)
        let categoryMessages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: sampleType, context: context)
        let genericMessages = AIAnalysisPrompts.buildDataTrendMessages(context: context)

        #expect(categoryMessages[0].content == genericMessages[0].content)
    }

    @Test("buildCategoryTrendMessages user message contains statistics")
    func testCategoryPromptUserMessageContainsStats() {
        let context = DataContext(
            sampleType: "stepCount",
            dataPointCount: 50,
            timeRangeDescription: "最近一周",
            statistics: DataContext.DataStatistics(
                average: 8500,
                minimum: 3200,
                maximum: 15000,
                latestValue: 9000,
                unit: "步"
            )
        )
        let messages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: "stepCount", context: context)

        #expect(messages[1].content.contains("8500.0"))
        #expect(messages[1].content.contains("3200.0"))
        #expect(messages[1].content.contains("15000.0"))
        #expect(messages[1].content.contains("9000.0"))
        #expect(messages[1].content.contains("步"))
    }

    @Test("buildCategoryTrendMessages includes JSON response format in system prompt")
    func testCategoryPromptIncludesResponseFormat() {
        let context = makeDataContext(sampleType: "heartRate")
        let messages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: "heartRate", context: context)
        let systemContent = messages[0].content

        #expect(systemContent.contains("sampleType"))
        #expect(systemContent.contains("summary"))
        #expect(systemContent.contains("trend"))
        #expect(systemContent.contains("rising"))
        #expect(systemContent.contains("falling"))
        #expect(systemContent.contains("stable"))
        #expect(systemContent.contains("insufficient"))
    }

    @Test(
        "isCategorySampleType returns true for core types",
        arguments: ["stepCount", "heartRate", "sleepAnalysis", "bodyMass", "activeEnergyBurned"]
    )
    func testIsCategorySampleTypeTrue(sampleType: String) {
        #expect(AIAnalysisPrompts.isCategorySampleType(sampleType))
    }

    @Test(
        "isCategorySampleType returns false for non-core types",
        arguments: ["restingHeartRate", "vo2Max", "flightsClimbed", "unknown"]
    )
    func testIsCategorySampleTypeFalse(sampleType: String) {
        #expect(!AIAnalysisPrompts.isCategorySampleType(sampleType))
    }

    @Test("analyzeDataTrend uses category prompt and still parses correctly")
    func testAnalyzeDataTrendWithCategoryPrompt() async throws {
        let service = try makeService { messages, _ in
            #expect(messages[0].content.contains("步数分析"))
            return ChatResponse(content: """
                {"sampleType":"stepCount","summary":"今日步数达标","trend":"stable","suggestion":"保持习惯"}
                """)
        }
        let context = makeDataContext(sampleType: "stepCount")
        let analysis = try await service.analyzeDataTrend(context: context)
        #expect(analysis.sampleType == "stepCount")
        #expect(analysis.trend == "stable")
    }

    // MARK: - noProviderAvailable does not refresh timestamps

    @Test("noProviderAvailable returns cached data without refreshing cache timestamps")
    func testNoProviderDoesNotRefreshTimestamps() async throws {
        let callCount = Mutex(0)
        let service = try makeService(chatHandler: { _, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 1 {
                return ChatResponse(content: validInsightsJSON)
            }
            throw AIServiceError.noProviderAvailable
        }, cacheTTL: 0.001)
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        try await Task.sleep(for: .milliseconds(10))

        let result = try await service.generateInsights(context: context, forceRefresh: true)
        #expect(result.insights.count == 2)
    }

    // MARK: - AIAnalysisResponse Backward Compatibility

    @Test("generateInsights decodes legacy array JSON via backward compat")
    func testGenerateInsightsLegacyArrayFormat() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: legacyInsightsJSON)
        }
        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.headline == nil)
        #expect(result.insights.count == 2)
        #expect(result.insights[0].key == "steps")
    }

    @Test("generateInsights returns headline as nil when AI omits it")
    func testGenerateInsightsNullHeadline() async throws {
        let noHeadlineJSON = """
        {"headline":null,"insights":[{"key":"test","cardType":"metric","cardSize":"small","title":"Test","content":"Content"}]}
        """
        let service = try makeService { _, _ in
            ChatResponse(content: noHeadlineJSON)
        }
        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.headline == nil)
        #expect(result.insights.count == 1)
    }

    @Test("cached legacy array JSON is read back as AIAnalysisResponse")
    func testCacheLegacyFormatBackwardCompat() async throws {
        let callCount = Mutex(0)
        let service = try makeService { _, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 1 {
                return ChatResponse(content: legacyInsightsJSON)
            }
            return ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        let first = try await service.generateInsights(context: context)
        #expect(first.headline == nil)
        #expect(first.insights.count == 2)

        let cached = try await service.generateInsights(context: context)
        #expect(cached.headline == nil)
        #expect(cached.insights.count == 2)
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("generateInsights passes previousInsights to prompt builder")
    func testGenerateInsightsPassesPreviousInsights() async throws {
        let capturedMessages = Mutex<[ChatMessage]>([])
        let callCount = Mutex(0)
        let service = try makeService { messages, _ in
            let current = callCount.withLock { value -> Int in
                value += 1
                return value
            }
            if current == 2 {
                capturedMessages.withLock { $0 = messages }
            }
            return ChatResponse(content: validInsightsJSON)
        }
        let context = makeOverviewContext()

        _ = try await service.generateInsights(context: context)
        _ = try await service.generateInsights(context: context, forceRefresh: true)

        let messages = capturedMessages.withLock { $0 }
        #expect(!messages.isEmpty)
        let userMessage = messages.first { $0.role == "user" }
        #expect(userMessage?.content.contains("上次分析结果") == true)
    }
}
