import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// Regression tests for MY-1077 — bounded `@Query` limits.
///
/// Both `OverviewRecentWorkouts` (VitalStride/Sources/OverviewView.swift) and
/// `WorkoutListView` (VitalStride/Sources/WorkoutListView.swift) previously
/// issued unbounded `@Query`s that materialized every completed `Workout` in
/// the store, then took a `prefix(5)` in memory. Those views now build their
/// `FetchDescriptor` with a `fetchLimit`. These tests exercise the exact same
/// descriptor shape against an in-memory container to prove that SwiftData
/// honors the limit at fetch time — regardless of how many completed rows
/// exist in the store.
@Suite("Bounded Workout Query (MY-1077)")
@MainActor
struct BoundedWorkoutQueryTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    /// Descriptor that mirrors `OverviewRecentWorkouts` — 5 most-recent
    /// completed workouts in reverse chronological order.
    private static func overviewDescriptor() -> FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    /// Descriptor that mirrors `WorkoutListView`'s initial page — first
    /// `initialWorkoutFetchLimit` most-recent completed workouts.
    private static func listDescriptor(limit: Int) -> FetchDescriptor<Workout> {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    private func insertCompletedWorkouts(_ count: Int, in context: ModelContext) throws {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            // Stagger start dates by one hour so ordering is deterministic.
            let start = anchor.addingTimeInterval(TimeInterval(index) * 3600)
            let end = start.addingTimeInterval(1800)
            context.insert(
                Workout(
                    type: .strength,
                    startDate: start,
                    endDate: end,
                    totalCalories: 100.0
                )
            )
        }
        try context.save()
    }

    @Test("Overview descriptor returns at most 5 completed workouts even with 20 in store")
    func overviewLimitsToFive() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(20, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        #expect(fetched.count == 5)
    }

    @Test("Overview descriptor returns 5 in reverse chronological order")
    func overviewReverseChronological() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(20, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        let dates = fetched.map(\.startDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Overview descriptor returns fewer than 5 when store has fewer completed rows")
    func overviewUnderfilled() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(3, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        #expect(fetched.count == 3)
    }

    @Test("Overview descriptor excludes incomplete workouts (no endDate)")
    func overviewExcludesIncomplete() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(3, in: context)
        // Insert an incomplete workout that is newer than any completed one.
        let newerIncomplete = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: nil
        )
        context.insert(newerIncomplete)
        try context.save()

        let fetched = try context.fetch(Self.overviewDescriptor())
        #expect(fetched.count == 3)
        #expect(fetched.allSatisfy { $0.endDate != nil })
    }

    @Test("List descriptor caps result at fetchLimit rather than returning entire store")
    func listInitialPageBounded() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(120, in: context)

        let fetched = try context.fetch(Self.listDescriptor(limit: 50))
        #expect(fetched.count == 50)
    }

    @Test("List descriptor pagination — larger fetchLimit surfaces more rows")
    func listSecondPageBounded() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(120, in: context)

        // First page = 50, then user taps "Load more" once.
        let page1 = try context.fetch(Self.listDescriptor(limit: 50))
        let page2 = try context.fetch(Self.listDescriptor(limit: 100))
        #expect(page1.count == 50)
        #expect(page2.count == 100)
        // Newer-first ordering is preserved — page1 is the prefix of page2.
        #expect(page1.map(\.startDate) == Array(page2.prefix(50)).map(\.startDate))
    }

    @Test("List descriptor sorted newest-first")
    func listNewestFirst() throws {
        let context = ModelContext(container)
        try insertCompletedWorkouts(60, in: context)

        let fetched = try context.fetch(Self.listDescriptor(limit: 50))
        let dates = fetched.map(\.startDate)
        #expect(dates == dates.sorted(by: >))
    }
}
