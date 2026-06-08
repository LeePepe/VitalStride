import Testing
import Foundation
@testable import HealthKitService

// MARK: - Mock

final class MockWorkoutProvider: WorkoutDataProviding, @unchecked Sendable {
    var fetchResult: WorkoutFetchResult = WorkoutFetchResult(workouts: [], deletedObjectIDs: [])
    var fetchDelay: Duration?
    var fetchError: (any Error)?
    private let lock = NSLock()
    private var _fetchCallCount: Int = 0
    private var _fetchDateRanges: [DateInterval?] = []

    var fetchCallCount: Int {
        lock.withLock { _fetchCallCount }
    }

    var fetchDateRanges: [DateInterval?] {
        lock.withLock { _fetchDateRanges }
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        if let delay = fetchDelay {
            try await Task.sleep(for: delay)
        }
        if let error = fetchError {
            throw error
        }
        lock.withLock {
            _fetchCallCount += 1
            _fetchDateRanges.append(dateRange)
        }
        return fetchResult
    }
}

// MARK: - Helpers

private func makeWorkout(
    date: Date = Date(),
    activityType: UInt = 37,
    duration: TimeInterval = 3600
) -> HealthWorkoutRecord {
    HealthWorkoutRecord(
        id: UUID(),
        activityTypeRawValue: activityType,
        duration: duration,
        totalEnergyBurned: 500,
        totalDistance: 10_000,
        startDate: date,
        endDate: date.addingTimeInterval(duration),
        sourceName: "TestSource"
    )
}

private func makeWorkoutResult(
    count: Int = 1,
    baseDate: Date = Date()
) -> WorkoutFetchResult {
    let workouts = (0..<count).map { i in
        makeWorkout(date: baseDate.addingTimeInterval(Double(i) * 3600))
    }
    return WorkoutFetchResult(workouts: workouts, deletedObjectIDs: [])
}

private func makeMockDataProvider() -> MockHealthDataProvider {
    MockHealthDataProvider()
}

// MARK: - Tests

@Suite("HealthDataCache — Workout")
struct HealthWorkoutCacheTests {

    // MARK: - Cache Miss

    @Test("First workout query triggers fetch")
    func cacheMissFetches() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 3)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let result = try await cache.workoutData()

        #expect(result.count == 3)
        #expect(workoutMock.fetchCallCount == 1)
    }

    // MARK: - Cache Hit

    @Test("Second workout query returns cached data without fetching")
    func cacheHitSkipsFetch() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 2)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        let second = try await cache.workoutData()

        #expect(second.count == 2)
        #expect(workoutMock.fetchCallCount == 1)
    }

    // MARK: - Date Range Filtering

    @Test("Cache hit filters workouts by date range")
    func cacheHitFiltersDateRange() async throws {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let workoutMock = MockWorkoutProvider()

        let workouts = [
            makeWorkout(date: yesterday),
            makeWorkout(date: now),
        ]
        workoutMock.fetchResult = WorkoutFetchResult(workouts: workouts, deletedObjectIDs: [])
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()

        let todayRange = DateInterval(
            start: Calendar.current.startOfDay(for: now),
            end: now.addingTimeInterval(3600)
        )
        let filtered = try await cache.workoutData(in: todayRange)

        #expect(filtered.count == 1)
        #expect(workoutMock.fetchCallCount == 1)
    }

    // MARK: - Refresh

    @Test("Refresh always fetches and replaces workout cache")
    func refreshAlwaysFetches() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        #expect(workoutMock.fetchCallCount == 1)

        workoutMock.fetchResult = makeWorkoutResult(count: 5)
        let refreshed = try await cache.refreshWorkouts()

        #expect(refreshed.count == 5)
        #expect(workoutMock.fetchCallCount == 2)
    }

    // MARK: - Invalidation

    @Test("InvalidateWorkouts clears workout cache")
    func invalidateWorkoutsClearsCache() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 2)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        #expect(await cache.hasWorkoutCache())

        await cache.invalidateWorkouts()
        #expect(await !cache.hasWorkoutCache())

        _ = try await cache.workoutData()
        #expect(workoutMock.fetchCallCount == 2)
    }

    @Test("InvalidateAll clears both sample and workout caches")
    func invalidateAllClearsBothCaches() async throws {
        let dataMock = makeMockDataProvider()
        dataMock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: [
                HealthDataPoint(
                    id: UUID(),
                    sampleType: .stepCount,
                    startDate: Date(),
                    endDate: Date(),
                    value: 1000,
                    unit: "count",
                    sleepStage: nil,
                    sourceName: nil
                ),
            ],
            deletedObjectIDs: []
        )

        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: dataMock,
            workoutProvider: workoutMock
        )

        _ = try await cache.data(for: .stepCount)
        _ = try await cache.workoutData()

        #expect(await cache.cachedTypes().contains(.stepCount))
        #expect(await cache.hasWorkoutCache())

        await cache.invalidateAll()

        #expect(await cache.cachedTypes().isEmpty)
        #expect(await !cache.hasWorkoutCache())
    }

    // MARK: - Authorization Revoked

    @Test("handleAuthorizationRevoked clears workout cache and anchors")
    func authorizationRevokedClearsWorkouts() async throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        #expect(await cache.hasWorkoutCache())

        let anchorData = Data(repeating: 0xAB, count: 16)
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setWorkoutAnchor(record, for: "test-device")
        #expect(anchorStore.workoutAnchor(for: "test-device") != nil)

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        #expect(await !cache.hasWorkoutCache())
        #expect(anchorStore.workoutAnchor(for: "test-device") == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("In-flight workout fetch does not repopulate after invalidateAll")
    func inFlightWorkoutFetchDiscardedAfterInvalidation() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchDelay = .milliseconds(100)
        workoutMock.fetchResult = makeWorkoutResult(count: 3)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        let fetchTask = Task {
            try await cache.workoutData()
        }

        try await Task.sleep(for: .milliseconds(20))

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        _ = try? await fetchTask.value

        #expect(await !cache.hasWorkoutCache())

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Telemetry

    @Test("Workout telemetry tracks hits, misses, and refreshes")
    func workoutTelemetryTracking() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        _ = try await cache.workoutData()
        _ = try await cache.workoutData()
        _ = try await cache.refreshWorkouts()

        let tel = await cache.workoutTelemetry()
        #expect(tel.misses == 1)
        #expect(tel.hits == 2)
        #expect(tel.refreshes == 1)
    }

    @Test("InvalidateAll resets workout telemetry")
    func invalidateAllResetsWorkoutTelemetry() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        _ = try await cache.workoutData()
        await cache.invalidateAll()

        let tel = await cache.workoutTelemetry()
        #expect(tel == CacheTelemetry(hits: 0, misses: 0, refreshes: 0))
    }

    // MARK: - No Provider

    @Test("Workout query returns empty when no provider configured")
    func noProviderReturnsEmpty() async throws {
        let cache = HealthDataCache(dataProvider: makeMockDataProvider())

        let result = try await cache.workoutData()
        #expect(result.isEmpty)
    }

    // MARK: - Error Propagation

    @Test("Workout fetch error propagates to caller")
    func workoutFetchErrorPropagates() async {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchError = HealthKitServiceError.healthDataNotAvailable
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        do {
            _ = try await cache.workoutData()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is HealthKitServiceError)
        }

        #expect(await !cache.hasWorkoutCache())
    }

    // MARK: - Date Range Passed to Provider

    @Test("Date range is passed to workout provider on cache miss")
    func dateRangePassedToProvider() async throws {
        let workoutMock = MockWorkoutProvider()
        workoutMock.fetchResult = makeWorkoutResult(count: 1)
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let range = DateInterval(start: Date().addingTimeInterval(-3600), duration: 3600)
        _ = try await cache.workoutData(in: range)

        #expect(workoutMock.fetchDateRanges.first as? DateInterval == range)
    }
}
