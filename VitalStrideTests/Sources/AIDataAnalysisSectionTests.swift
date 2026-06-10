import AIService
import Foundation
import HealthKitService
import SwiftData
import Synchronization
import Testing
import VitalModels

@testable import VitalStride

// MARK: - AIDataAnalysisSectionTests

@Suite("AIDataAnalysisSection Tests")
struct AIDataAnalysisSectionTests {

    // MARK: - DataContext Building

    @Test("DataContext includes 7-day stats with correct structure")
    func testDataContextStructure() {
        let context = DataContext(
            sampleType: "heartRate",
            dataPointCount: 50,
            timeRangeDescription: "Recent 7 days: 50 data points, avg=72.5, vs previous 7 days: +2.0 (+3%)",
            statistics: DataContext.DataStatistics(
                average: 72.5,
                minimum: 60.0,
                maximum: 95.0,
                latestValue: 71.0,
                unit: "BPM"
            )
        )

        #expect(context.sampleType == "heartRate")
        #expect(context.dataPointCount == 50)
        #expect(context.timeRangeDescription.contains("7 days"))
        #expect(context.statistics.average == 72.5)
        #expect(context.statistics.minimum == 60.0)
        #expect(context.statistics.maximum == 95.0)
        #expect(context.statistics.latestValue == 71.0)
        #expect(context.statistics.unit == "BPM")
    }

    @Test("DataContext handles empty data gracefully")
    func testDataContextEmpty() {
        let context = DataContext(
            sampleType: "stepCount",
            dataPointCount: 0,
            timeRangeDescription: "Recent 7 days: 0 data points",
            statistics: DataContext.DataStatistics(unit: "步")
        )

        #expect(context.dataPointCount == 0)
        #expect(context.statistics.average == nil)
        #expect(context.statistics.minimum == nil)
        #expect(context.statistics.maximum == nil)
        #expect(context.statistics.latestValue == nil)
    }

    // MARK: - DataAnalysisCache TTL

    @Test("DataAnalysisCache isExpired returns false before expiry")
    func testCacheNotExpired() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = DataAnalysisCache(
            sampleType: "heartRate",
            contentJSON: "{\"sampleType\":\"heartRate\",\"summary\":\"test\",\"trend\":\"stable\"}",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(cache)
        try context.save()

        #expect(!cache.isExpired)
    }

    @Test("DataAnalysisCache isExpired returns true after expiry")
    func testCacheExpired() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = DataAnalysisCache(
            sampleType: "heartRate",
            contentJSON: "{\"sampleType\":\"heartRate\",\"summary\":\"test\",\"trend\":\"stable\"}",
            generatedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        context.insert(cache)
        try context.save()

        #expect(cache.isExpired)
    }

    @Test("DataAnalysisCache stores and retrieves by sampleType")
    func testCacheKeyBySampleType() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let heartRateCache = DataAnalysisCache(
            sampleType: "heartRate",
            contentJSON: "{\"sampleType\":\"heartRate\",\"summary\":\"hr\",\"trend\":\"stable\"}",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        let stepsCache = DataAnalysisCache(
            sampleType: "stepCount",
            contentJSON: "{\"sampleType\":\"stepCount\",\"summary\":\"steps\",\"trend\":\"upward\"}",
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        context.insert(heartRateCache)
        context.insert(stepsCache)
        try context.save()

        let hrType = "heartRate"
        let descriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate<DataAnalysisCache> { $0.sampleType == hrType }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].contentJSON.contains("hr"))

        let stepsType = "stepCount"
        let stepsDescriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate<DataAnalysisCache> { $0.sampleType == stepsType }
        )
        let fetchedSteps = try context.fetch(stepsDescriptor)
        #expect(fetchedSteps.count == 1)
        #expect(fetchedSteps[0].contentJSON.contains("steps"))
    }

    // MARK: - UserInterest Top 3 Query

    @Test("topInterests returns default types when no interests recorded")
    func testTopInterestsDefault() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let top = UserInterestTracker.topInterests(limit: 3, in: context)
        #expect(top == [.bodyMass, .heartRate, .sleepAnalysis])
    }

    @Test("topInterests returns recorded types sorted by tap count")
    func testTopInterestsSorted() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let interest1 = UserInterest(sampleType: "stepCount", tapCount: 5)
        let interest2 = UserInterest(sampleType: "heartRate", tapCount: 10)
        let interest3 = UserInterest(sampleType: "bodyMass", tapCount: 3)
        let interest4 = UserInterest(sampleType: "sleepAnalysis", tapCount: 1)
        context.insert(interest1)
        context.insert(interest2)
        context.insert(interest3)
        context.insert(interest4)
        try context.save()

        let top = UserInterestTracker.topInterests(limit: 3, in: context)
        #expect(top.count == 3)
        #expect(top[0] == .heartRate)
        #expect(top[1] == .stepCount)
        #expect(top[2] == .bodyMass)
    }

    @Test("topInterests respects limit parameter")
    func testTopInterestsLimit() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let interest1 = UserInterest(sampleType: "stepCount", tapCount: 5)
        let interest2 = UserInterest(sampleType: "heartRate", tapCount: 10)
        context.insert(interest1)
        context.insert(interest2)
        try context.save()

        let top = UserInterestTracker.topInterests(limit: 1, in: context)
        #expect(top.count == 1)
        #expect(top[0] == .heartRate)
    }

    // MARK: - DataAnalysis Model

    @Test("DataAnalysis decodes from JSON correctly")
    func testDataAnalysisDecoding() throws {
        let json = """
        {"sampleType":"heartRate","summary":"Heart rate trending upward","trend":"upward","suggestion":"Consider resting"}
        """
        let data = json.data(using: .utf8)!
        let analysis = try JSONDecoder().decode(DataAnalysis.self, from: data)

        #expect(analysis.sampleType == "heartRate")
        #expect(analysis.summary == "Heart rate trending upward")
        #expect(analysis.trend == "upward")
        #expect(analysis.suggestion == "Consider resting")
    }

    @Test("DataAnalysis decodes with nil suggestion")
    func testDataAnalysisNilSuggestion() throws {
        let json = """
        {"sampleType":"stepCount","summary":"Steps stable","trend":"stable"}
        """
        let data = json.data(using: .utf8)!
        let analysis = try JSONDecoder().decode(DataAnalysis.self, from: data)

        #expect(analysis.suggestion == nil)
    }

    @Test("DataAnalysis round-trips through JSON encoding")
    func testDataAnalysisRoundTrip() throws {
        let original = DataAnalysis(
            sampleType: "bodyMass",
            summary: "Weight stable at 72kg",
            trend: "stable",
            suggestion: "Maintain current diet"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DataAnalysis.self, from: encoded)

        #expect(original == decoded)
    }

    // MARK: - AnalysisState

    @Test("AnalysisState isIdle returns true only for idle state")
    func testAnalysisStateIsIdle() {
        let idle = AIDataAnalysisSection.AnalysisState.idle
        let loading = AIDataAnalysisSection.AnalysisState.loading
        let analysis = DataAnalysis(sampleType: "hr", summary: "test", trend: "stable")
        let loaded = AIDataAnalysisSection.AnalysisState.loaded(analysis, Date(), .fresh)
        let failed = AIDataAnalysisSection.AnalysisState.failed

        #expect(idle.isIdle)
        #expect(!loading.isIdle)
        #expect(!loaded.isIdle)
        #expect(!failed.isIdle)
    }

    // MARK: - Pregeneration with analyzeDataTrend

    @Test("analyzeDataTrend caches result for subsequent reads")
    func testAnalyzeDataTrendCachesResult() async throws {
        let callCount = Mutex(0)
        let container = try ModelContainerConfiguration.makeTestContainer()
        let provider = MockAIProvider { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(
                content: "{\"sampleType\":\"bodyMass\",\"summary\":\"stable\",\"trend\":\"stable\",\"suggestion\":\"keep going\"}"
            )
        }
        let service = AIAnalysisService(modelContainer: container, provider: provider)
        let context = DataContext(
            sampleType: "bodyMass",
            dataPointCount: 14,
            timeRangeDescription: "7 days",
            statistics: DataContext.DataStatistics(average: 72.0, unit: "kg")
        )

        let first = try await service.analyzeDataTrend(context: context)
        let second = try await service.analyzeDataTrend(context: context)

        #expect(first == second)
        #expect(callCount.withLock { $0 } == 1)
    }

    @Test("analyzeDataTrend caches independently per sample type")
    func testAnalyzeDataTrendIndependentCache() async throws {
        let callCount = Mutex(0)
        let container = try ModelContainerConfiguration.makeTestContainer()
        let provider = MockAIProvider { _, _ in
            callCount.withLock { $0 += 1 }
            return ChatResponse(
                content: "{\"sampleType\":\"bodyMass\",\"summary\":\"test\",\"trend\":\"stable\"}"
            )
        }
        let service = AIAnalysisService(modelContainer: container, provider: provider)

        let ctx1 = DataContext(sampleType: "bodyMass", dataPointCount: 10, statistics: DataContext.DataStatistics(unit: "kg"))
        let ctx2 = DataContext(sampleType: "heartRate", dataPointCount: 10, statistics: DataContext.DataStatistics(unit: "BPM"))

        _ = try await service.analyzeDataTrend(context: ctx1)
        _ = try await service.analyzeDataTrend(context: ctx2)

        #expect(callCount.withLock { $0 } == 2)
    }
}
