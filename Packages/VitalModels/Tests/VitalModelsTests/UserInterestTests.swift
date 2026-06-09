import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("UserInterest Tests")
struct UserInterestTests {

    // MARK: - Container Registration

    @Test("trainingModelTypes includes UserInterest")
    func trainingModelTypesContainsUserInterest() {
        let typeNames = ModelContainerConfiguration.trainingModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("UserInterest"))
    }

    @Test("allModelTypes includes UserInterest")
    func allModelTypesContainsUserInterest() {
        let typeNames = ModelContainerConfiguration.allModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("UserInterest"))
    }

    @Test("healthCacheModelTypes does not include UserInterest")
    func healthCacheModelTypesExcludesUserInterest() {
        let typeNames = ModelContainerConfiguration.healthCacheModelTypes.map { String(describing: $0) }
        #expect(!typeNames.contains("UserInterest"))
    }

    // MARK: - Init & Fields

    @Test("init sets all fields correctly")
    func initSetsFields() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let interest = UserInterest(
            sampleType: "heartRate",
            tapCount: 5,
            lastTappedDate: date
        )
        #expect(interest.sampleType == "heartRate")
        #expect(interest.tapCount == 5)
        #expect(interest.lastTappedDate == date)
    }

    @Test("init defaults tapCount to 1")
    func initDefaultTapCount() {
        let interest = UserInterest(sampleType: "bodyMass")
        #expect(interest.tapCount == 1)
    }

    // MARK: - CRUD

    @Test("insert and fetch UserInterest")
    func insertAndFetch() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let interest = UserInterest(sampleType: "stepCount")
        context.insert(interest)
        try context.save()

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 1)
        #expect(results[0].sampleType == "stepCount")
        #expect(results[0].tapCount == 1)
    }

    @Test("delete UserInterest")
    func deleteInterest() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let interest = UserInterest(sampleType: "heartRate")
        context.insert(interest)
        try context.save()

        var results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 0)
    }

    @Test("insert multiple entries with different sampleTypes")
    func insertMultiple() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let types = ["heartRate", "stepCount", "bodyMass"]
        for type in types {
            context.insert(UserInterest(sampleType: type))
        }
        try context.save()

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 3)
    }

    @Test("fetch with predicate filters by sampleType")
    func fetchWithPredicate() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        context.insert(UserInterest(sampleType: "heartRate", tapCount: 3))
        context.insert(UserInterest(sampleType: "stepCount", tapCount: 1))
        try context.save()

        let targetType = "heartRate"
        var descriptor = FetchDescriptor<UserInterest>(
            predicate: #Predicate { $0.sampleType == targetType }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].sampleType == "heartRate")
        #expect(results[0].tapCount == 3)
    }

    // MARK: - Sort

    @Test("fetch sorted by tapCount descending")
    func fetchSortedByTapCount() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        context.insert(UserInterest(sampleType: "heartRate", tapCount: 2))
        context.insert(UserInterest(sampleType: "stepCount", tapCount: 10))
        context.insert(UserInterest(sampleType: "bodyMass", tapCount: 5))
        try context.save()

        let descriptor = FetchDescriptor<UserInterest>(
            sortBy: [SortDescriptor(\.tapCount, order: .reverse)]
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 3)
        #expect(results[0].sampleType == "stepCount")
        #expect(results[1].sampleType == "bodyMass")
        #expect(results[2].sampleType == "heartRate")
    }
}
