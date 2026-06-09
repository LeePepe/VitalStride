import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("AI Cache Models Tests")
struct AICacheModelsTests {

    // MARK: - Container Registration

    @Test("aiCacheModelTypes contains all three cache models")
    func aiCacheModelTypesContent() {
        let typeNames = ModelContainerConfiguration.aiCacheModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("OverviewInsightCache"))
        #expect(typeNames.contains("TrainingAdviceCache"))
        #expect(typeNames.contains("DataAnalysisCache"))
        #expect(typeNames.count == 3)
    }

    @Test("allModelTypes includes AI cache models")
    func allModelTypesIncludesAICacheModels() {
        let typeNames = ModelContainerConfiguration.allModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("OverviewInsightCache"))
        #expect(typeNames.contains("TrainingAdviceCache"))
        #expect(typeNames.contains("DataAnalysisCache"))
    }

    @Test("makeTestContainer succeeds with AI cache models")
    func makeTestContainerSuccess() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        #expect(container != nil)
    }

    @Test("trainingModelTypes does not include AI cache models")
    func trainingModelTypesExcludesAICacheModels() {
        let typeNames = ModelContainerConfiguration.trainingModelTypes.map { String(describing: $0) }
        #expect(!typeNames.contains("OverviewInsightCache"))
        #expect(!typeNames.contains("TrainingAdviceCache"))
        #expect(!typeNames.contains("DataAnalysisCache"))
    }

    // MARK: - OverviewInsightCache CRUD

    @Test("insert and fetch OverviewInsightCache")
    func overviewInsightCacheInsertAndFetch() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let json = "[{\"key\":\"test\",\"cardType\":\"metric\",\"cardSize\":\"small\",\"title\":\"T\",\"content\":\"C\"}]"
        let now = Date()
        let expires = Date(timeIntervalSinceNow: 86400)

        let cache = OverviewInsightCache(
            contentJSON: json,
            generatedAt: now,
            expiresAt: expires
        )
        context.insert(cache)
        try context.save()

        let results = try context.fetch(FetchDescriptor<OverviewInsightCache>())
        #expect(results.count == 1)
        #expect(results[0].contentJSON == json)
    }

    @Test("OverviewInsightCache isExpired returns true for past date")
    func overviewInsightCacheExpired() {
        let cache = OverviewInsightCache(
            contentJSON: "[]",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        #expect(cache.isExpired)
    }

    @Test("OverviewInsightCache isExpired returns false for future date")
    func overviewInsightCacheNotExpired() {
        let cache = OverviewInsightCache(
            contentJSON: "[]",
            expiresAt: Date(timeIntervalSinceNow: 86400)
        )
        #expect(!cache.isExpired)
    }

    @Test("delete OverviewInsightCache")
    func overviewInsightCacheDelete() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = OverviewInsightCache(
            contentJSON: "[]",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        context.insert(cache)
        try context.save()

        var results = try context.fetch(FetchDescriptor<OverviewInsightCache>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<OverviewInsightCache>())
        #expect(results.count == 0)
    }

    // MARK: - TrainingAdviceCache CRUD

    @Test("insert and fetch TrainingAdviceCache")
    func trainingAdviceCacheInsertAndFetch() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let json = "{\"title\":\"T\",\"muscleGroups\":[],\"exercises\":[],\"reasoning\":\"R\"}"
        let cache = TrainingAdviceCache(
            contentJSON: json,
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        context.insert(cache)
        try context.save()

        let results = try context.fetch(FetchDescriptor<TrainingAdviceCache>())
        #expect(results.count == 1)
        #expect(results[0].contentJSON == json)
    }

    @Test("TrainingAdviceCache isExpired")
    func trainingAdviceCacheExpired() {
        let expired = TrainingAdviceCache(
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        #expect(expired.isExpired)

        let valid = TrainingAdviceCache(
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSinceNow: 86400)
        )
        #expect(!valid.isExpired)
    }

    @Test("delete TrainingAdviceCache")
    func trainingAdviceCacheDelete() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = TrainingAdviceCache(
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        context.insert(cache)
        try context.save()

        var results = try context.fetch(FetchDescriptor<TrainingAdviceCache>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<TrainingAdviceCache>())
        #expect(results.count == 0)
    }

    // MARK: - DataAnalysisCache CRUD

    @Test("insert and fetch DataAnalysisCache")
    func dataAnalysisCacheInsertAndFetch() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let json = "{\"sampleType\":\"bodyMass\",\"summary\":\"S\",\"trend\":\"stable\"}"
        let cache = DataAnalysisCache(
            sampleType: "bodyMass",
            contentJSON: json,
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        context.insert(cache)
        try context.save()

        let results = try context.fetch(FetchDescriptor<DataAnalysisCache>())
        #expect(results.count == 1)
        #expect(results[0].sampleType == "bodyMass")
        #expect(results[0].contentJSON == json)
    }

    @Test("DataAnalysisCache query by sampleType with predicate")
    func dataAnalysisCacheQueryBySampleType() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let types = ["bodyMass", "heartRate", "stepCount"]
        for type in types {
            let cache = DataAnalysisCache(
                sampleType: type,
                contentJSON: "{\"sampleType\":\"\(type)\"}",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            )
            context.insert(cache)
        }
        try context.save()

        let targetType = "heartRate"
        let descriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate { $0.sampleType == targetType }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].sampleType == "heartRate")
    }

    @Test("DataAnalysisCache isExpired")
    func dataAnalysisCacheExpired() {
        let expired = DataAnalysisCache(
            sampleType: "bodyMass",
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        #expect(expired.isExpired)

        let valid = DataAnalysisCache(
            sampleType: "bodyMass",
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSinceNow: 86400)
        )
        #expect(!valid.isExpired)
    }

    @Test("delete DataAnalysisCache")
    func dataAnalysisCacheDelete() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let cache = DataAnalysisCache(
            sampleType: "stepCount",
            contentJSON: "{}",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        context.insert(cache)
        try context.save()

        var results = try context.fetch(FetchDescriptor<DataAnalysisCache>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<DataAnalysisCache>())
        #expect(results.count == 0)
    }

    @Test("multiple DataAnalysisCache entries for different sampleTypes")
    func dataAnalysisCacheMultipleEntries() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let types = ["bodyMass", "heartRate", "stepCount", "sleepAnalysis", "activeEnergyBurned"]
        for type in types {
            let cache = DataAnalysisCache(
                sampleType: type,
                contentJSON: "{}",
                expiresAt: Date(timeIntervalSinceNow: 3600)
            )
            context.insert(cache)
        }
        try context.save()

        let results = try context.fetch(FetchDescriptor<DataAnalysisCache>())
        #expect(results.count == 5)
    }

    // MARK: - Field Defaults

    @Test("OverviewInsightCache init preserves all fields")
    func overviewInsightCacheFieldPreservation() {
        let now = Date()
        let expires = Date(timeIntervalSinceNow: 3600)
        let cache = OverviewInsightCache(
            contentJSON: "[{\"key\":\"test\"}]",
            generatedAt: now,
            expiresAt: expires
        )
        #expect(cache.contentJSON == "[{\"key\":\"test\"}]")
        #expect(cache.generatedAt == now)
        #expect(cache.expiresAt == expires)
    }

    @Test("TrainingAdviceCache init preserves all fields")
    func trainingAdviceCacheFieldPreservation() {
        let now = Date()
        let expires = Date(timeIntervalSinceNow: 3600)
        let cache = TrainingAdviceCache(
            contentJSON: "{\"title\":\"T\"}",
            generatedAt: now,
            expiresAt: expires
        )
        #expect(cache.contentJSON == "{\"title\":\"T\"}")
        #expect(cache.generatedAt == now)
        #expect(cache.expiresAt == expires)
    }

    @Test("DataAnalysisCache init preserves all fields")
    func dataAnalysisCacheFieldPreservation() {
        let now = Date()
        let expires = Date(timeIntervalSinceNow: 3600)
        let cache = DataAnalysisCache(
            sampleType: "heartRate",
            contentJSON: "{\"trend\":\"rising\"}",
            generatedAt: now,
            expiresAt: expires
        )
        #expect(cache.sampleType == "heartRate")
        #expect(cache.contentJSON == "{\"trend\":\"rising\"}")
        #expect(cache.generatedAt == now)
        #expect(cache.expiresAt == expires)
    }
}
