import AIService
import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("OverviewLayoutState Tests")
struct OverviewLayoutStateTests {

    // MARK: - OverviewLayoutState

    @Test("loading state is the initial state")
    func initialState() {
        let state: OverviewLayoutState = .loading
        if case .loading = state {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected loading state")
        }
    }

    @Test("dynamic state holds insights and lastUpdated")
    func dynamicState() {
        let insight = OverviewInsight(
            key: "steps",
            cardType: "metric",
            cardSize: "small",
            title: "步数",
            content: "8000步"
        )
        let date = Date()
        let state: OverviewLayoutState = .dynamic([insight], lastUpdated: date)

        if case .dynamic(let insights, let lastUpdated) = state {
            #expect(insights.count == 1)
            #expect(insights[0].key == "steps")
            #expect(lastUpdated == date)
        } else {
            #expect(Bool(false), "Expected dynamic state")
        }
    }

    @Test("dynamic state with nil lastUpdated")
    func dynamicStateNilDate() {
        let state: OverviewLayoutState = .dynamic([], lastUpdated: nil)

        if case .dynamic(let insights, let lastUpdated) = state {
            #expect(insights.isEmpty)
            #expect(lastUpdated == nil)
        } else {
            #expect(Bool(false), "Expected dynamic state")
        }
    }

    @Test("fallback state")
    func fallbackState() {
        let state: OverviewLayoutState = .fallback
        if case .fallback = state {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected fallback state")
        }
    }

    // MARK: - OverviewInsight+CardParsing

    @Test("valid variant is correctly identified")
    func validVariant() {
        let insight = OverviewInsight(
            key: "steps",
            cardType: "metric",
            cardSize: "small",
            title: "Steps",
            content: "8000"
        )
        #expect(insight.parsedCardSize == .small)
        #expect(insight.parsedCardType == .metric)
        #expect(insight.isValidVariant == true)
    }

    @Test("invalid cardType returns nil parsed type")
    func invalidCardType() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "invalid",
            cardSize: "small",
            title: "X",
            content: "X"
        )
        #expect(insight.parsedCardType == nil)
        #expect(insight.isValidVariant == false)
    }

    @Test("invalid cardSize returns nil parsed size")
    func invalidCardSize() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "metric",
            cardSize: "huge",
            title: "X",
            content: "X"
        )
        #expect(insight.parsedCardSize == nil)
        #expect(insight.isValidVariant == false)
    }

    @Test("invalid combination (small + trend) returns false")
    func invalidCombination() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "trend",
            cardSize: "small",
            title: "X",
            content: "X"
        )
        #expect(insight.parsedCardSize == .small)
        #expect(insight.parsedCardType == .trend)
        #expect(insight.isValidVariant == false)
    }

    // MARK: - CardVariant

    @Test("CardVariant.isValid checks whitelist")
    func cardVariantWhitelist() {
        #expect(CardVariant.isValid(size: .small, type: .metric) == true)
        #expect(CardVariant.isValid(size: .small, type: .action) == true)
        #expect(CardVariant.isValid(size: .medium, type: .insight) == true)
        #expect(CardVariant.isValid(size: .wide, type: .summary) == true)
        #expect(CardVariant.isValid(size: .large, type: .trend) == true)

        #expect(CardVariant.isValid(size: .small, type: .trend) == false)
        #expect(CardVariant.isValid(size: .small, type: .list) == false)
        #expect(CardVariant.isValid(size: .small, type: .summary) == false)
    }

    // MARK: - effectiveCardSize fallback

    @Test("effectiveCardSize returns correct size for valid variant")
    func effectiveCardSizeValid() {
        let insight = OverviewInsight(
            key: "steps",
            cardType: "metric",
            cardSize: "small",
            title: "Steps",
            content: "8000"
        )
        #expect(insight.effectiveCardSize == .small)
    }

    @Test("effectiveCardSize falls back to default for invalid combo")
    func effectiveCardSizeFallback() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "summary",
            cardSize: "small",
            title: "X",
            content: "X"
        )
        #expect(insight.isValidVariant == false)
        #expect(insight.effectiveCardSize == .wide)
    }

    @Test("effectiveCardSize returns medium for unparseable inputs")
    func effectiveCardSizeUnparseable() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "invalid",
            cardSize: "huge",
            title: "X",
            content: "X"
        )
        #expect(insight.effectiveCardSize == .medium)
    }

    @Test("effectiveCardType returns parsed type")
    func effectiveCardTypeValid() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "trend",
            cardSize: "medium",
            title: "X",
            content: "X"
        )
        #expect(insight.effectiveCardType == .trend)
    }

    @Test("effectiveCardType falls back to insight for invalid type")
    func effectiveCardTypeFallback() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "invalid",
            cardSize: "medium",
            title: "X",
            content: "X"
        )
        #expect(insight.effectiveCardType == .insight)
    }

    @Test("hasValidOrFallbackVariant is true when cardType is parseable")
    func hasValidOrFallbackTrue() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "summary",
            cardSize: "small",
            title: "X",
            content: "X"
        )
        #expect(insight.hasValidOrFallbackVariant == true)
    }

    @Test("hasValidOrFallbackVariant is false when cardType is unparseable")
    func hasValidOrFallbackFalse() {
        let insight = OverviewInsight(
            key: "x",
            cardType: "invalid",
            cardSize: "medium",
            title: "X",
            content: "X"
        )
        #expect(insight.hasValidOrFallbackVariant == false)
    }

    @Test("CardVariant.defaultSize returns correct defaults")
    func defaultSizeMapping() {
        #expect(CardVariant.defaultSize(for: .metric) == .medium)
        #expect(CardVariant.defaultSize(for: .insight) == .medium)
        #expect(CardVariant.defaultSize(for: .trend) == .medium)
        #expect(CardVariant.defaultSize(for: .summary) == .wide)
        #expect(CardVariant.defaultSize(for: .list) == .wide)
        #expect(CardVariant.defaultSize(for: .action) == .small)
    }

    // MARK: - OverviewContext with locale

    @Test("OverviewContext includes userLocale")
    func contextLocale() {
        let context = OverviewContext(
            todaySteps: 8000,
            userLocale: "zh-Hans"
        )
        #expect(context.userLocale == "zh-Hans")
        #expect(context.todaySteps == 8000)
    }

    @Test("OverviewContext defaults userLocale to empty")
    func contextLocaleDefault() {
        let context = OverviewContext()
        #expect(context.userLocale == "")
    }

    // MARK: - Locale Language Instruction

    @Test("localeLanguageInstruction for Chinese locale")
    func localeInstructionChinese() {
        #expect(AIAnalysisPrompts.localeLanguageInstruction("zh-Hans") == "使用中文")
        #expect(AIAnalysisPrompts.localeLanguageInstruction("zh_CN") == "使用中文")
        #expect(AIAnalysisPrompts.localeLanguageInstruction("zh") == "使用中文")
    }

    @Test("localeLanguageInstruction for English locale")
    func localeInstructionEnglish() {
        #expect(AIAnalysisPrompts.localeLanguageInstruction("en-US") == "Use English")
        #expect(AIAnalysisPrompts.localeLanguageInstruction("en_GB") == "Use English")
    }

    @Test("localeLanguageInstruction for empty locale defaults to Chinese")
    func localeInstructionEmpty() {
        #expect(AIAnalysisPrompts.localeLanguageInstruction("") == "使用中文")
    }

    // MARK: - Cache Integration

    @Test("OverviewInsightCache stores and retrieves insights")
    func cacheRoundTrip() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let insights = [
            OverviewInsight(
                key: "steps",
                cardType: "metric",
                cardSize: "small",
                title: "步数",
                content: "8000步"
            ),
        ]
        let json = String(data: try JSONEncoder().encode(insights), encoding: .utf8)!
        let cache = OverviewInsightCache(
            contentJSON: json,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(cache)
        try context.save()

        let descriptor = FetchDescriptor<OverviewInsightCache>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].isExpired == false)

        let decoded = try JSONDecoder().decode([OverviewInsight].self, from: fetched[0].contentJSON.data(using: .utf8)!)
        #expect(decoded.count == 1)
        #expect(decoded[0].key == "steps")
    }

    @Test("OverviewInsightCache isExpired returns true when past expiresAt")
    func cacheExpired() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = OverviewInsightCache(
            contentJSON: "[]",
            generatedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        context.insert(cache)
        try context.save()

        let descriptor = FetchDescriptor<OverviewInsightCache>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched[0].isExpired == true)
    }

    // MARK: - Fallback Trigger Conditions

    @Test("OverviewDynamicState falls back when AI fails and no cache")
    @MainActor
    func fallbackOnAIFailureNoCache() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let snapshot = HealthSnapshotData(
            todaySteps: nil,
            averageBPM: nil,
            lastNightSleep: nil,
            latestWeight: nil
        )

        await state.loadInitial(container: container, snapshot: snapshot, workouts: [])

        if case .fallback = state.layoutState {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected fallback when no API key and no cache")
        }
    }

    @Test("OverviewDynamicState loads from cache when >= 3 insights cached")
    @MainActor
    func loadsFromCacheWithEnoughInsights() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let insights = (1...3).map { i in
            OverviewInsight(
                key: "card\(i)",
                cardType: "metric",
                cardSize: "small",
                title: "Card \(i)",
                content: "Content \(i)"
            )
        }
        let json = String(data: try JSONEncoder().encode(insights), encoding: .utf8)!
        let cache = OverviewInsightCache(
            contentJSON: json,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(cache)
        try context.save()

        let state = OverviewDynamicState()
        let snapshot = HealthSnapshotData(
            todaySteps: nil,
            averageBPM: nil,
            lastNightSleep: nil,
            latestWeight: nil
        )

        await state.loadInitial(container: container, snapshot: snapshot, workouts: [])

        if case .dynamic(let loadedInsights, let lastUpdated) = state.layoutState {
            #expect(loadedInsights.count == 3)
            #expect(loadedInsights[0].key == "card1")
            #expect(lastUpdated != nil)
        } else {
            #expect(Bool(false), "Expected dynamic state from cache with 3 insights")
        }
    }

    @Test("OverviewDynamicState treats cache with < 3 insights as miss and shows fallback")
    @MainActor
    func fallbackWhenCacheHasTooFewInsights() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let insights = [
            OverviewInsight(
                key: "only_one",
                cardType: "metric",
                cardSize: "small",
                title: "Solo",
                content: "Solo content"
            ),
        ]
        let json = String(data: try JSONEncoder().encode(insights), encoding: .utf8)!
        let cache = OverviewInsightCache(
            contentJSON: json,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(cache)
        try context.save()

        let state = OverviewDynamicState()
        let snapshot = HealthSnapshotData(
            todaySteps: nil,
            averageBPM: nil,
            lastNightSleep: nil,
            latestWeight: nil
        )

        await state.loadInitial(container: container, snapshot: snapshot, workouts: [])

        if case .fallback = state.layoutState {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected fallback when cache has < 3 insights")
        }
    }

    // MARK: - Pending State Management

    @Test("pendingResponse starts nil and pendingHeadline reflects it")
    @MainActor
    func pendingResponseInitialState() {
        let state = OverviewDynamicState()
        #expect(state.pendingResponse == nil)
        #expect(state.pendingHeadline == nil)
    }

    @Test("applyBackgroundRefreshResult stores pending when headline is present")
    @MainActor
    func bgRefreshWithHeadlineStoresPending() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let oldInsights = [
            OverviewInsight(key: "old", cardType: "metric", cardSize: "small", title: "Old", content: "old"),
        ]
        state.applyBackgroundRefreshResult(
            AIAnalysisResponse(headline: nil, insights: oldInsights),
            container: container
        )

        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "old")
        } else {
            #expect(Bool(false), "Expected dynamic state after no-headline apply")
        }

        let newInsights = [
            OverviewInsight(key: "new", cardType: "metric", cardSize: "small", title: "New", content: "new"),
        ]
        let response = AIAnalysisResponse(headline: "有新变化", insights: newInsights)
        state.applyBackgroundRefreshResult(response, container: container)

        #expect(state.pendingResponse != nil)
        #expect(state.pendingHeadline == "有新变化")
        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "old", "layoutState should NOT change when headline is present")
        } else {
            #expect(Bool(false), "layoutState should remain dynamic")
        }
    }

    @Test("applyBackgroundRefreshResult silently updates when headline is nil")
    @MainActor
    func bgRefreshWithoutHeadlineSilentlyUpdates() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let insights = [
            OverviewInsight(key: "silent", cardType: "metric", cardSize: "small", title: "Silent", content: "update"),
        ]
        let response = AIAnalysisResponse(headline: nil, insights: insights)
        state.applyBackgroundRefreshResult(response, container: container)

        #expect(state.pendingResponse == nil)
        #expect(state.pendingHeadline == nil)
        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "silent")
        } else {
            #expect(Bool(false), "Expected dynamic state after silent update")
        }
    }

    @Test("acceptPendingInsights replaces layoutState and clears pending")
    @MainActor
    func acceptPendingInsightsFlow() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let oldInsights = [
            OverviewInsight(key: "old", cardType: "metric", cardSize: "small", title: "Old", content: "old"),
        ]
        state.applyBackgroundRefreshResult(
            AIAnalysisResponse(headline: nil, insights: oldInsights),
            container: container
        )

        let newInsights = [
            OverviewInsight(key: "new", cardType: "metric", cardSize: "small", title: "New", content: "new"),
        ]
        state.applyBackgroundRefreshResult(
            AIAnalysisResponse(headline: "新洞察", insights: newInsights),
            container: container
        )

        #expect(state.pendingResponse != nil)
        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "old")
        }

        state.acceptPendingInsights(container: container)

        #expect(state.pendingResponse == nil)
        #expect(state.pendingHeadline == nil)
        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "new")
        } else {
            #expect(Bool(false), "Expected dynamic state after accept")
        }
    }

    @Test("acceptPendingInsights is no-op when pendingResponse is nil")
    @MainActor
    func acceptPendingInsightsNoop() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        state.acceptPendingInsights(container: container)

        #expect(state.pendingResponse == nil)
        if case .loading = state.layoutState {
            #expect(true)
        } else {
            #expect(Bool(false), "Expected loading state unchanged")
        }
    }

    @Test("clearPending removes pending response")
    @MainActor
    func clearPendingRemovesPending() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let insights = [
            OverviewInsight(key: "k", cardType: "metric", cardSize: "small", title: "T", content: "C"),
        ]
        state.applyBackgroundRefreshResult(
            AIAnalysisResponse(headline: "H", insights: insights),
            container: container
        )
        #expect(state.pendingResponse != nil)

        state.clearPending()
        #expect(state.pendingResponse == nil)
        #expect(state.pendingHeadline == nil)
    }

    @Test("background refresh failure leaves state and pending unchanged")
    @MainActor
    func bgRefreshFailureLeavesStateUnchanged() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let insights = [
            OverviewInsight(key: "cached", cardType: "metric", cardSize: "small", title: "Cached", content: "data"),
        ]
        let json = String(data: try JSONEncoder().encode(insights), encoding: .utf8)!
        let cache = OverviewInsightCache(
            contentJSON: json,
            generatedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        context.insert(cache)
        try context.save()

        let state = OverviewDynamicState()
        let snapshot = HealthSnapshotData(
            todaySteps: nil,
            averageBPM: nil,
            lastNightSleep: nil,
            latestWeight: nil
        )

        await state.loadInitial(container: container, snapshot: snapshot, workouts: [])

        if case .dynamic(let loaded, _) = state.layoutState {
            #expect(loaded[0].key == "cached")
        } else {
            #expect(Bool(false), "Expected dynamic state from stale cache")
        }
        #expect(state.pendingResponse == nil)
        #expect(state.showRefreshError == false)
    }

    // MARK: - Cache Ordering

    @Test("applyBackgroundRefreshResult with headline does NOT write cache")
    @MainActor
    func bgRefreshWithHeadlineDoesNotWriteCache() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let insights = [
            OverviewInsight(key: "pending", cardType: "metric", cardSize: "small", title: "P", content: "p"),
        ]
        let response = AIAnalysisResponse(headline: "变化", insights: insights)
        state.applyBackgroundRefreshResult(response, container: container)

        #expect(state.pendingResponse != nil)

        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        let cached = try ctx.fetch(descriptor)
        #expect(cached.isEmpty, "Cache should NOT be written when headline is present (pending flow)")
    }

    @Test("applyBackgroundRefreshResult without headline writes cache")
    @MainActor
    func bgRefreshWithoutHeadlineWritesCache() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let insights = [
            OverviewInsight(key: "silent", cardType: "metric", cardSize: "small", title: "S", content: "s"),
        ]
        let response = AIAnalysisResponse(headline: nil, insights: insights)
        state.applyBackgroundRefreshResult(response, container: container)

        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        let cached = try ctx.fetch(descriptor)
        #expect(cached.count == 1, "Cache should be written when headline is nil (silent update)")

        let decoded = try JSONDecoder().decode(
            AIAnalysisResponse.self,
            from: cached[0].contentJSON.data(using: .utf8)!
        )
        #expect(decoded.insights[0].key == "silent")
    }

    @Test("acceptPendingInsights writes pending response to cache")
    @MainActor
    func acceptPendingInsightsWritesCache() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let state = OverviewDynamicState()

        let insights = [
            OverviewInsight(key: "accepted", cardType: "metric", cardSize: "small", title: "A", content: "a"),
        ]
        let response = AIAnalysisResponse(headline: "新洞察", insights: insights)
        state.applyBackgroundRefreshResult(response, container: container)

        let ctxBefore = ModelContext(container)
        let descBefore = FetchDescriptor<OverviewInsightCache>()
        #expect(try ctxBefore.fetch(descBefore).isEmpty, "No cache before accept")

        state.acceptPendingInsights(container: container)

        #expect(state.pendingResponse == nil)

        let ctxAfter = ModelContext(container)
        let descAfter = FetchDescriptor<OverviewInsightCache>()
        let cached = try ctxAfter.fetch(descAfter)
        #expect(cached.count == 1, "Cache should be written after accept")

        let decoded = try JSONDecoder().decode(
            AIAnalysisResponse.self,
            from: cached[0].contentJSON.data(using: .utf8)!
        )
        #expect(decoded.insights[0].key == "accepted")
        #expect(decoded.headline == "新洞察")
    }
}
