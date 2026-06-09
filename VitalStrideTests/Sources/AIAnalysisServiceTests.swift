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

    @Test("generateInsights returns parsed insights on valid JSON response")
    func testGenerateInsightsSuccess() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: validInsightsJSON)
        }
        let insights = try await service.generateInsights(context: makeOverviewContext())
        #expect(insights.count == 2)
        #expect(insights[0].key == "steps")
        #expect(insights[0].cardType == "metric")
        #expect(insights[1].key == "sleep")
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

        #expect(cached.count == 2)
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

        #expect(stale.count == 2)
    }

    @Test("generateInsights falls back on JSON parse failure after retry")
    func testGenerateInsightsParseFallback() async throws {
        let service = try makeService { _, _ in
            ChatResponse(content: "This is not valid JSON at all")
        }
        let result = try await service.generateInsights(context: makeOverviewContext())

        #expect(result.count == 1)
        #expect(result[0].key == "ai_summary")
        #expect(result[0].cardType == "summary")
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
        #expect(result.count == 2)
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

        #expect(result.count == 2)
    }

    @Test("generateInsights handles markdown code block wrapped JSON")
    func testGenerateInsightsMarkdownJSON() async throws {
        let wrappedJSON = "```json\n\(validInsightsJSON)\n```"
        let service = try makeService { _, _ in
            ChatResponse(content: wrappedJSON)
        }
        let result = try await service.generateInsights(context: makeOverviewContext())
        #expect(result.count == 2)
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
        #expect(result.title == "训练建议")
        #expect(result.muscleGroups.isEmpty)
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
}
