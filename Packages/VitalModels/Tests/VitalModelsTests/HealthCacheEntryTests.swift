import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("HealthCacheEntry Tests")
struct HealthCacheEntryTests {

    // MARK: - Container Creation

    @Test("makeContainer creates container with dual configurations")
    func makeContainerSuccess() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        #expect(container != nil)
    }

    @Test("allModelTypes includes HealthCacheEntry")
    func allModelTypesContainsHealthCacheEntry() {
        let typeNames = ModelContainerConfiguration.allModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("HealthCacheEntry"))
    }

    @Test("trainingModelTypes does not include HealthCacheEntry")
    func trainingModelTypesExcludesHealthCacheEntry() {
        let typeNames = ModelContainerConfiguration.trainingModelTypes.map { String(describing: $0) }
        #expect(!typeNames.contains("HealthCacheEntry"))
    }

    @Test("healthCacheModelTypes contains HealthCacheEntry and AvailableTypesEntry")
    func healthCacheModelTypesContent() {
        let typeNames = Set(ModelContainerConfiguration.healthCacheModelTypes.map { String(describing: $0) })
        #expect(typeNames == ["HealthCacheEntry", "AvailableTypesEntry"])
    }

    // MARK: - CRUD

    @Test("insert and fetch HealthCacheEntry")
    func insertAndFetch() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let sampleData = Data("{\"test\":true}".utf8)
        let now = Date()
        let rangeStart = Date(timeIntervalSince1970: 1_000_000)
        let rangeEnd = Date(timeIntervalSince1970: 2_000_000)

        let entry = HealthCacheEntry(
            sampleType: "heartRate",
            dataPointsData: sampleData,
            fetchedAt: now,
            coveredRangeStart: rangeStart,
            coveredRangeEnd: rangeEnd
        )
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<HealthCacheEntry>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)

        let fetched = results[0]
        #expect(fetched.sampleType == "heartRate")
        #expect(fetched.dataPointsData == sampleData)
        #expect(fetched.coveredRangeStart == rangeStart)
        #expect(fetched.coveredRangeEnd == rangeEnd)
    }

    @Test("delete HealthCacheEntry")
    func deleteEntry() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry = HealthCacheEntry(
            sampleType: "stepCount",
            dataPointsData: Data()
        )
        context.insert(entry)
        try context.save()

        var results = try context.fetch(FetchDescriptor<HealthCacheEntry>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<HealthCacheEntry>())
        #expect(results.count == 0)
    }

    @Test("insert multiple entries with different sampleTypes")
    func insertMultipleEntries() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let types = ["heartRate", "stepCount", "bodyMass"]
        for type in types {
            let entry = HealthCacheEntry(
                sampleType: type,
                dataPointsData: Data()
            )
            context.insert(entry)
        }
        try context.save()

        let results = try context.fetch(FetchDescriptor<HealthCacheEntry>())
        #expect(results.count == 3)
    }

    @Test("fetch with predicate filters by sampleType")
    func fetchWithPredicate() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let heartRateEntry = HealthCacheEntry(
            sampleType: "heartRate",
            dataPointsData: Data()
        )
        let stepEntry = HealthCacheEntry(
            sampleType: "stepCount",
            dataPointsData: Data()
        )
        context.insert(heartRateEntry)
        context.insert(stepEntry)
        try context.save()

        let targetType = "heartRate"
        var descriptor = FetchDescriptor<HealthCacheEntry>(
            predicate: #Predicate { $0.sampleType == targetType }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].sampleType == "heartRate")
    }

    // MARK: - Field Defaults

    @Test("init preserves all fields")
    func initPreservesFields() {
        let data = Data([0x01, 0x02])
        let now = Date()
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)

        let entry = HealthCacheEntry(
            sampleType: "sleepAnalysis",
            dataPointsData: data,
            fetchedAt: now,
            coveredRangeStart: start,
            coveredRangeEnd: end
        )
        #expect(entry.sampleType == "sleepAnalysis")
        #expect(entry.dataPointsData == data)
        #expect(entry.fetchedAt == now)
        #expect(entry.coveredRangeStart == start)
        #expect(entry.coveredRangeEnd == end)
    }

    @Test("optional range fields default to nil")
    func optionalFieldsDefaultNil() {
        let entry = HealthCacheEntry(
            sampleType: "bodyMass",
            dataPointsData: Data()
        )
        #expect(entry.coveredRangeStart == nil)
        #expect(entry.coveredRangeEnd == nil)
    }

    // MARK: - Unique Constraint

    @Test("unique constraint allows different sampleType same range")
    func uniqueConstraintDifferentType() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        let entry1 = HealthCacheEntry(
            sampleType: "heartRate",
            dataPointsData: Data(),
            coveredRangeStart: start,
            coveredRangeEnd: end
        )
        let entry2 = HealthCacheEntry(
            sampleType: "stepCount",
            dataPointsData: Data(),
            coveredRangeStart: start,
            coveredRangeEnd: end
        )
        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        let results = try context.fetch(FetchDescriptor<HealthCacheEntry>())
        #expect(results.count == 2)
    }

    @Test("unique constraint allows same sampleType different range")
    func uniqueConstraintDifferentRange() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry1 = HealthCacheEntry(
            sampleType: "heartRate",
            dataPointsData: Data(),
            coveredRangeStart: Date(timeIntervalSince1970: 1_000),
            coveredRangeEnd: Date(timeIntervalSince1970: 2_000)
        )
        let entry2 = HealthCacheEntry(
            sampleType: "heartRate",
            dataPointsData: Data(),
            coveredRangeStart: Date(timeIntervalSince1970: 3_000),
            coveredRangeEnd: Date(timeIntervalSince1970: 4_000)
        )
        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        let results = try context.fetch(FetchDescriptor<HealthCacheEntry>())
        #expect(results.count == 2)
    }
}
