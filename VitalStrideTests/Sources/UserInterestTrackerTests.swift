import HealthKitService
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("UserInterestTracker Tests")
struct UserInterestTrackerTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerConfiguration.makeTestContainer()
        return ModelContext(container)
    }

    // MARK: - recordTap

    @Test("recordTap creates new record on first tap")
    func recordTapCreatesNew() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .heartRate, in: context)

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 1)
        #expect(results[0].sampleType == "heartRate")
        #expect(results[0].tapCount == 1)
    }

    @Test("recordTap increments tapCount on repeat tap")
    func recordTapIncrements() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .stepCount, in: context)
        UserInterestTracker.recordTap(for: .stepCount, in: context)
        UserInterestTracker.recordTap(for: .stepCount, in: context)

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 1)
        #expect(results[0].tapCount == 3)
    }

    @Test("recordTap updates lastTappedDate on repeat tap")
    func recordTapUpdatesDate() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .bodyMass, in: context)

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        let firstDate = results[0].lastTappedDate

        UserInterestTracker.recordTap(for: .bodyMass, in: context)

        let updated = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(updated[0].lastTappedDate >= firstDate)
    }

    @Test("recordTap creates separate records for different types")
    func recordTapSeparateTypes() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .heartRate, in: context)
        UserInterestTracker.recordTap(for: .stepCount, in: context)
        UserInterestTracker.recordTap(for: .bodyMass, in: context)

        let results = try context.fetch(FetchDescriptor<UserInterest>())
        #expect(results.count == 3)
    }

    // MARK: - topInterests

    @Test("topInterests returns sorted by tapCount descending")
    func topInterestsSorted() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .heartRate, in: context)
        for _ in 0..<5 {
            UserInterestTracker.recordTap(for: .stepCount, in: context)
        }
        for _ in 0..<3 {
            UserInterestTracker.recordTap(for: .bodyMass, in: context)
        }

        let top = UserInterestTracker.topInterests(limit: 3, in: context)
        #expect(top.count == 3)
        #expect(top[0] == .stepCount)
        #expect(top[1] == .bodyMass)
        #expect(top[2] == .heartRate)
    }

    @Test("topInterests respects limit")
    func topInterestsLimit() throws {
        let context = try makeContext()

        UserInterestTracker.recordTap(for: .heartRate, in: context)
        UserInterestTracker.recordTap(for: .stepCount, in: context)
        UserInterestTracker.recordTap(for: .bodyMass, in: context)

        let top = UserInterestTracker.topInterests(limit: 2, in: context)
        #expect(top.count == 2)
    }

    @Test("topInterests returns fallback defaults when no records exist")
    func topInterestsFallback() throws {
        let context = try makeContext()

        let top = UserInterestTracker.topInterests(limit: 3, in: context)
        #expect(top == [.bodyMass, .heartRate, .sleepAnalysis])
    }

    @Test("topInterests fallback respects limit")
    func topInterestsFallbackLimit() throws {
        let context = try makeContext()

        let top = UserInterestTracker.topInterests(limit: 1, in: context)
        #expect(top.count == 1)
        #expect(top[0] == .bodyMass)
    }
}
