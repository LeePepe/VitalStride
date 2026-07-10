import Foundation
import HealthKitService
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// Regression tests for MY-1077 — bounded queries in the Overview "recent"
/// card and paged rendering in `WorkoutListView`.
///
/// Design:
/// - `OverviewRecentWorkouts` (VitalStride/Sources/OverviewView.swift)
///   caps its SwiftData `@Query` at 5 rows via a `FetchDescriptor` — the
///   overview descriptor tests exercise that shape directly.
/// - `WorkoutListView` (VitalStride/Sources/WorkoutListView.swift) keeps its
///   underlying `@Query` unbounded so HealthKit dedup and the calendar mode
///   see the full completed history, then slices only the *rendered* rows
///   in list mode. The list-side tests below exercise that slicing shape
///   plus the merge/partition seams — proving that:
///     1. Mirrored HealthKit records are deduplicated against the FULL
///        local history (P0 regression fix — previously merged only the
///        loaded page, so mirrored workouts beyond the page reappeared).
///     2. Calendar mode receives every unified workout regardless of the
///        list-mode display limit (P0 regression fix — previously calendar
///        was fed the paged slice).
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

    /// Descriptor that mirrors the unbounded fetch `WorkoutListView` performs.
    /// The list view keeps the fetch unbounded (dedup + calendar need full
    /// history) and pages only the visible rows — the tests below simulate
    /// that behavior against this descriptor.
    private static func fullHistoryDescriptor() -> FetchDescriptor<Workout> {
        FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
    }

    private func insertCompletedWorkouts(
        _ count: Int,
        in context: ModelContext,
        withHealthKitUUIDsFromIndex mirrorIndices: Set<Int> = [],
        healthKitUUIDs mirroredUUIDs: [Int: UUID] = [:]
    ) throws -> [Workout] {
        var workouts: [Workout] = []
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            // Stagger start dates by one hour so ordering is deterministic.
            let start = anchor.addingTimeInterval(TimeInterval(index) * 3600)
            let end = start.addingTimeInterval(1800)
            let workout = Workout(
                type: .strength,
                startDate: start,
                endDate: end,
                totalCalories: 100.0
            )
            if mirrorIndices.contains(index) {
                workout.healthKitUUID = (mirroredUUIDs[index] ?? UUID()).uuidString
            }
            context.insert(workout)
            workouts.append(workout)
        }
        try context.save()
        return workouts
    }

    private func makeHealthKitRecord(
        id: UUID,
        startDate: Date,
        duration: TimeInterval = 1800
    ) -> HealthWorkoutRecord {
        HealthWorkoutRecord(
            id: id,
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: duration,
            totalEnergyBurned: 300,
            totalDistance: 5000,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            sourceName: "Apple Watch"
        )
    }

    // MARK: - Overview (fetchLimit = 5)

    @Test("Overview descriptor returns at most 5 completed workouts even with 20 in store")
    func overviewLimitsToFive() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(20, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        #expect(fetched.count == 5)
    }

    @Test("Overview descriptor returns 5 in reverse chronological order")
    func overviewReverseChronological() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(20, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        let dates = fetched.map(\.startDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Overview descriptor returns fewer than 5 when store has fewer completed rows")
    func overviewUnderfilled() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(3, in: context)

        let fetched = try context.fetch(Self.overviewDescriptor())
        #expect(fetched.count == 3)
    }

    @Test("Overview descriptor excludes incomplete workouts (no endDate)")
    func overviewExcludesIncomplete() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(3, in: context)
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

    // MARK: - List view: paged local display, full-history dedup + calendar

    /// Simulates the WorkoutListView pipeline: fetch full history, merge with
    /// HealthKit, then slice only the rows the list ForEach renders.
    private func simulateListPipeline(
        appWorkouts: [Workout],
        healthKitRecords: [HealthWorkoutRecord],
        listDisplayLimit: Int
    ) -> (visibleApp: [UnifiedWorkout], healthKit: [UnifiedWorkout], calendar: [UnifiedWorkout], canLoadMore: Bool) {
        let unified = WorkoutListMerger.merge(
            appWorkouts: appWorkouts,
            healthKitRecords: healthKitRecords
        ).unified
        let partitioned = WorkoutListMerger.partitionBySource(unified)
        let visibleApp = Array(partitioned.app.prefix(listDisplayLimit))
        let canLoadMore = partitioned.app.count > visibleApp.count
        return (visibleApp, partitioned.healthKit, unified, canLoadMore)
    }

    @Test("List slice: only rows the list renders are bounded, full fetch stays unbounded")
    func listDisplaySliceBounded() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(120, in: context)

        let full = try context.fetch(Self.fullHistoryDescriptor())
        #expect(full.count == 120)

        let pipeline = simulateListPipeline(
            appWorkouts: full,
            healthKitRecords: [],
            listDisplayLimit: 50
        )
        #expect(pipeline.visibleApp.count == 50)
        #expect(pipeline.canLoadMore)
        // Calendar mode still sees every workout.
        #expect(pipeline.calendar.count == 120)
    }

    @Test("List slice: `Load more` grows the visible window while dedup input stays full")
    func listPaginationGrowsDisplay() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(120, in: context)
        let full = try context.fetch(Self.fullHistoryDescriptor())

        let page1 = simulateListPipeline(
            appWorkouts: full,
            healthKitRecords: [],
            listDisplayLimit: 50
        )
        let page2 = simulateListPipeline(
            appWorkouts: full,
            healthKitRecords: [],
            listDisplayLimit: 100
        )
        #expect(page1.visibleApp.count == 50)
        #expect(page2.visibleApp.count == 100)
        // Newer-first ordering is preserved — page1 is the prefix of page2.
        #expect(page1.visibleApp.map(\.startDate) == Array(page2.visibleApp.prefix(50)).map(\.startDate))
    }

    /// P0 regression fix — MY-1077 review round 1: mirrored HealthKit records
    /// beyond the loaded local page previously re-appeared in the Apple Health
    /// section because dedup only saw UUIDs from the paged slice. With the
    /// fix, the merge sees the FULL local fetch and dedups everything.
    @Test("Merge dedups mirrored HealthKit records that only exist beyond the display page")
    func mergeDedupsMirroredWorkoutsBeyondPage() throws {
        let context = ModelContext(container)

        // Mirror indices 0–19: the 20 OLDEST local workouts each have a
        // healthKitUUID pointing at a HealthKit record. Indices 20–99 have
        // no HealthKit mirror. Ordering: index 0 = oldest.
        let mirrorIndices: Set<Int> = Set(0..<20)
        let mirroredUUIDs = Dictionary(uniqueKeysWithValues: mirrorIndices.map { ($0, UUID()) })

        let workouts = try insertCompletedWorkouts(
            100,
            in: context,
            withHealthKitUUIDsFromIndex: mirrorIndices,
            healthKitUUIDs: mirroredUUIDs
        )

        // Build the HealthKit record set: one record per mirrored UUID.
        let hkRecords: [HealthWorkoutRecord] = mirrorIndices.map { index in
            makeHealthKitRecord(
                id: mirroredUUIDs[index] ?? UUID(),
                startDate: workouts[index].startDate
            )
        }

        // The full fetch is descending-by-startDate, so mirrored indices 0–19
        // (oldest) fall at the TAIL of the local list. With a display limit
        // of 50, the visible slice covers only the NEWEST 50 — none of the
        // mirrored rows are in the slice. Under the pre-fix behavior, dedup
        // would see zero mirrored UUIDs and every HealthKit record would
        // appear in the Apple Health section.
        let full = try context.fetch(Self.fullHistoryDescriptor())
        let pipeline = simulateListPipeline(
            appWorkouts: full,
            healthKitRecords: hkRecords,
            listDisplayLimit: 50
        )

        // Every HealthKit record was mirrored, so the Apple Health section
        // must be empty under the fixed pipeline.
        #expect(pipeline.healthKit.isEmpty)
        // Sanity: none of the visible-app rows carry a HealthKit UUID
        // (the visible slice is the newest, un-mirrored 50).
        let visibleAppUUIDs = pipeline.visibleApp.compactMap { item -> String? in
            if case .app(let workout) = item { return workout.healthKitUUID }
            return nil
        }
        #expect(visibleAppUUIDs.isEmpty)
        // Calendar mode still receives all 100 app workouts.
        let calendarAppCount = pipeline.calendar.reduce(into: 0) { count, item in
            if case .app = item { count += 1 }
        }
        #expect(calendarAppCount == 100)
    }

    /// P0 regression fix — MY-1077 review round 1: calendar mode must render
    /// every workout regardless of the list-mode display limit. Prior to the
    /// fix, calendar received the paged slice and lost months of history
    /// once the store exceeded the initial display limit.
    @Test("Calendar mode receives the full unified history regardless of list display limit")
    func calendarSeesFullHistory() throws {
        let context = ModelContext(container)
        _ = try insertCompletedWorkouts(200, in: context)
        let full = try context.fetch(Self.fullHistoryDescriptor())

        // A HealthKit-only record that is older than every local workout —
        // asserts the calendar sees HealthKit history too.
        let ancientHK = makeHealthKitRecord(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_600_000_000)
        )

        let pipeline = simulateListPipeline(
            appWorkouts: full,
            healthKitRecords: [ancientHK],
            listDisplayLimit: 50
        )
        // Calendar sees every workout, HealthKit-only ones included.
        #expect(pipeline.calendar.count == 201)
        // List display stays bounded.
        #expect(pipeline.visibleApp.count == 50)
    }

    @Test("Empty local store still shows HealthKit-only workouts unpaged")
    func healthKitOnlyIsNotPaged() throws {
        let hkRecords = (0..<25).map { index in
            makeHealthKitRecord(
                id: UUID(),
                startDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600)
            )
        }

        let pipeline = simulateListPipeline(
            appWorkouts: [],
            healthKitRecords: hkRecords,
            listDisplayLimit: 50
        )
        #expect(pipeline.visibleApp.isEmpty)
        #expect(pipeline.healthKit.count == 25)
        #expect(pipeline.canLoadMore == false)
    }
}
