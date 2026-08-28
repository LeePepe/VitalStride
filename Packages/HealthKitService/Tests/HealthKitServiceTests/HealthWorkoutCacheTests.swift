import Testing
import Foundation
import Synchronization
@testable import HealthKitService

// MARK: - Mock

actor MockWorkoutProvider: WorkoutDataProviding {
    var fetchResult: WorkoutFetchResult = WorkoutFetchResult(workouts: [], deletedObjectIDs: [])
    var fetchDelay: Duration?
    var fetchError: (any Error & Sendable)?
    var fetchCallCount: Int = 0
    var fetchDateRanges: [DateInterval?] = []

    func setFetchResult(_ result: WorkoutFetchResult) {
        fetchResult = result
    }

    func setFetchDelay(_ delay: Duration?) {
        fetchDelay = delay
    }

    func setFetchError(_ error: (any Error & Sendable)?) {
        fetchError = error
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        if let delay = fetchDelay {
            try await Task.sleep(for: delay)
        }
        if let error = fetchError {
            throw error
        }
        fetchCallCount += 1
        fetchDateRanges.append(dateRange)
        return fetchResult
    }
}

final class MockPreparedWorkoutProvider: WorkoutPreparedDataProviding, Sendable {
    private let preparedSnapshotState: Mutex<PreparedWorkoutFetch>
    private let preparedChangesState: Mutex<PreparedWorkoutFetch>
    private let acceptedState: Mutex<[PreparedWorkoutFetch]>
    private let rejectedState: Mutex<[PreparedWorkoutFetch]>
    private let fetchResultState: Mutex<WorkoutFetchResult>

    var preparedSnapshot: PreparedWorkoutFetch {
        preparedSnapshotState.withLock { $0 }
    }
    var preparedChanges: PreparedWorkoutFetch {
        preparedChangesState.withLock { $0 }
    }
    var accepted: [PreparedWorkoutFetch] {
        acceptedState.withLock { $0 }
    }
    var rejected: [PreparedWorkoutFetch] {
        rejectedState.withLock { $0 }
    }
    var fetchResult: WorkoutFetchResult {
        fetchResultState.withLock { $0 }
    }

    init() {
        self.preparedSnapshotState = Mutex(PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            checkpoint: nil
        ))
        self.preparedChangesState = Mutex(PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            checkpoint: nil
        ))
        self.acceptedState = Mutex([])
        self.rejectedState = Mutex([])
        self.fetchResultState = Mutex(WorkoutFetchResult(workouts: [], deletedObjectIDs: []))
    }

    func setPreparedSnapshot(_ value: PreparedWorkoutFetch) {
        preparedSnapshotState.withLock { $0 = value }
    }

    func setPreparedChanges(_ value: PreparedWorkoutFetch) {
        preparedChangesState.withLock { $0 = value }
    }

    func setFetchResult(_ result: WorkoutFetchResult) {
        fetchResultState.withLock { $0 = result }
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        fetchResult
    }

    func prepareWorkoutSnapshot(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        preparedSnapshot
    }

    func prepareWorkoutChanges(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        preparedChanges
    }

    func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        acceptedState.withLock { $0.append(prepared) }
    }

    func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        rejectedState.withLock { $0.append(prepared) }
    }
}

final class RangeAwarePreparedWorkoutProvider: WorkoutPreparedDataProviding, Sendable {
    private let state: Mutex<[DateInterval: PreparedWorkoutFetch]>
    private let delays: Mutex<[DateInterval: Duration]>
    private let acceptedState: Mutex<[PreparedWorkoutFetch]>
    private let rejectedState: Mutex<[PreparedWorkoutFetch]>

    init() {
        self.state = Mutex([:])
        self.delays = Mutex([:])
        self.acceptedState = Mutex([])
        self.rejectedState = Mutex([])
    }

    func register(_ prepared: PreparedWorkoutFetch, for range: DateInterval?, delay: Duration = .zero) {
        let key = range ?? DateInterval(start: Date.distantPast, end: Date.distantFuture)
        state.withLock { $0[key] = prepared }
        delays.withLock { $0[key] = delay }
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        WorkoutFetchResult(workouts: [], deletedObjectIDs: [])
    }

    func prepareWorkoutSnapshot(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        let key = dateRange ?? DateInterval(start: Date.distantPast, end: Date.distantFuture)
        let delay = delays.withLock { $0[key] ?? .zero }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return state.withLock { $0[key] ?? PreparedWorkoutFetch(workouts: [], deletedObjectIDs: [], source: .baselineSnapshot, checkpoint: nil) }
    }

    func prepareWorkoutChanges(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        let key = dateRange ?? DateInterval(start: Date.distantPast, end: Date.distantFuture)
        let delay = delays.withLock { $0[key] ?? .zero }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return state.withLock { $0[key] ?? PreparedWorkoutFetch(workouts: [], deletedObjectIDs: [], source: .anchoredChanges, checkpoint: nil) }
    }

    func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        acceptedState.withLock { $0.append(prepared) }
    }

    func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        rejectedState.withLock { $0.append(prepared) }
    }
}

final class BarrierPreparedWorkoutProvider: WorkoutPreparedDataProviding, Sendable {
    private let preparedState: Mutex<[String: PreparedWorkoutFetch]>
    private let releaseState: Mutex<[String: Bool]>
    private let continuations: Mutex<[String: [CheckedContinuation<Void, Never>]]>
    private let acceptedState: Mutex<[PreparedWorkoutFetch]>
    private let rejectedState: Mutex<[PreparedWorkoutFetch]>

    init() {
        self.preparedState = Mutex([:])
        self.releaseState = Mutex([:])
        self.continuations = Mutex([:])
        self.acceptedState = Mutex([])
        self.rejectedState = Mutex([])
    }

    func register(_ prepared: PreparedWorkoutFetch, for range: DateInterval?, gate: Bool = false) {
        let key = Self.key(for: range)
        preparedState.withLock { $0[key] = prepared }
        releaseState.withLock { if gate { $0[key] = true } else { $0.removeValue(forKey: key) } }
    }

    func release(for range: DateInterval?) {
        let key = Self.key(for: range)
        let toResume = continuations.withLock { $0.removeValue(forKey: key) ?? [] }
        for continuation in toResume {
            continuation.resume()
        }
        releaseState.withLock { $0.removeValue(forKey: key) }
    }

    func prepareWorkoutSnapshot(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        let key = Self.key(for: dateRange)
        let gated = releaseState.withLock { $0[key] ?? false }
        if gated {
            await withCheckedContinuation { continuation in
                continuations.withLock { $0[key, default: []].append(continuation) }
            }
        }
        return preparedState.withLock { $0[key] ?? PreparedWorkoutFetch(workouts: [], deletedObjectIDs: [], source: .baselineSnapshot, checkpoint: nil) }
    }

    func prepareWorkoutChanges(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        let key = Self.key(for: dateRange)
        let gated = releaseState.withLock { $0[key] ?? false }
        if gated {
            await withCheckedContinuation { continuation in
                continuations.withLock { $0[key, default: []].append(continuation) }
            }
        }
        return preparedState.withLock { $0[key] ?? PreparedWorkoutFetch(workouts: [], deletedObjectIDs: [], source: .anchoredChanges, checkpoint: nil) }
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        WorkoutFetchResult(workouts: [], deletedObjectIDs: [])
    }

    func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        acceptedState.withLock { $0.append(prepared) }
    }

    func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        rejectedState.withLock { $0.append(prepared) }
    }

    private static func key(for range: DateInterval?) -> String {
        guard let range else {
            return "default"
        }
        return "\(range.start.timeIntervalSinceReferenceDate)-\(range.end.timeIntervalSinceReferenceDate)"
    }
}

// MARK: - Helpers

private func makeWorkout(
    date: Date = Date(),
    activityType: UInt = 37,
    duration: TimeInterval = 3600
) -> HealthWorkoutRecord {
    makeWorkout(id: UUID(), date: date, activityType: activityType, duration: duration)
}

private func makeWorkout(
    id: UUID,
    date: Date = Date(),
    activityType: UInt = 37,
    duration: TimeInterval = 3600
) -> HealthWorkoutRecord {
    HealthWorkoutRecord(
        id: id,
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
        await workoutMock.setFetchResult(makeWorkoutResult(count: 3))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let result = try await cache.workoutData()

        #expect(result.count == 3)
        #expect(await workoutMock.fetchCallCount == 1)
    }

    // MARK: - Cache Hit

    @Test("Second workout query returns cached data without fetching")
    func cacheHitSkipsFetch() async throws {
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(makeWorkoutResult(count: 2))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        let second = try await cache.workoutData()

        #expect(second.count == 2)
        #expect(await workoutMock.fetchCallCount == 1)
    }

    @Test("Prepared provider results are accepted through the cache checkpoint boundary")
    func preparedProviderAcceptancePublishesAndAccepts() async throws {
        let provider = MockPreparedWorkoutProvider()
        provider.setPreparedSnapshot(
            PreparedWorkoutFetch(
                workouts: [makeWorkout(date: Date())],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: Date().addingTimeInterval(-3600), end: Date()),
                checkpoint: nil
            )
        )
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        let accepted = provider.accepted
        let rejected = provider.rejected

        #expect(result.count == 1)
        #expect(accepted.count == 1)
        #expect(rejected.isEmpty)
        #expect(await cache.hasWorkoutCache())
    }

    @Test("Compatible refreshes take the anchored changes path instead of rewriting the baseline")
    func compatibleRefreshUsesAnchoredChanges() async throws {
        let provider = MockPreparedWorkoutProvider()
        let initial = makeWorkout(date: Date().addingTimeInterval(-3600))
        let updated = makeWorkout(date: Date())
        provider.setPreparedSnapshot(
            PreparedWorkoutFetch(
                workouts: [initial],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: initial.startDate, end: initial.endDate),
                checkpoint: nil
            )
        )
        provider.setPreparedChanges(
            PreparedWorkoutFetch(
                workouts: [initial, updated],
                deletedObjectIDs: [],
                source: .anchoredChanges,
                coverage: DateInterval(start: initial.startDate, end: updated.endDate),
                checkpoint: nil
            )
        )

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        let refreshed = try await cache.refreshWorkouts()

        #expect(refreshed.count == 2)
        #expect(provider.accepted.count == 2)
        #expect(provider.rejected.isEmpty)
    }

    @Test("Different explicit-range snapshots keep the newer range authoritative")
    func differentExplicitRangeSnapshotsKeepNewerRangeAuthoritative() async throws {
        let base = Date()
        let olderRange = DateInterval(
            start: base.addingTimeInterval(-12 * 60 * 60),
            end: base.addingTimeInterval(-6 * 60 * 60)
        )
        let newerRange = DateInterval(
            start: base.addingTimeInterval(-18 * 60 * 60),
            end: base.addingTimeInterval(-12 * 60 * 60)
        )

        let olderWorkout = makeWorkout(date: olderRange.start)
        let newerWorkout = makeWorkout(date: newerRange.start)
        let provider = BarrierPreparedWorkoutProvider()
        provider.register(
            PreparedWorkoutFetch(
                workouts: [olderWorkout],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: olderRange,
                checkpoint: nil
            ),
            for: olderRange,
            gate: true
        )
        provider.register(
            PreparedWorkoutFetch(
                workouts: [newerWorkout],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: newerRange,
                checkpoint: nil
            ),
            for: newerRange,
            gate: true
        )

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        let olderTask = Task {
            try await cache.workoutData(in: olderRange)
        }
        let newerTask = Task {
            try await cache.workoutData(in: newerRange)
        }

        provider.release(for: newerRange)
        let newestResult = try await newerTask.value
        provider.release(for: olderRange)

        do {
            _ = try await olderTask.value
            Issue.record("older explicit-range result should not replace the newer accepted range")
        } catch is CancellationError {
        }

        let authoritative = try await cache.workoutData(in: newerRange)

        #expect(newestResult.count == 1)
        #expect(newestResult.first?.id == newerWorkout.id)
        #expect(authoritative.count == 1)
        #expect(authoritative.first?.id == newerWorkout.id)
    }

    @Test("Anchored empty changes preserve the current baseline")
    func anchoredEmptyChangesPreserveCurrentBaseline() async throws {
        let baselineWorkout = makeWorkout(date: Date().addingTimeInterval(-3600))
        let provider = MockPreparedWorkoutProvider()
        provider.setPreparedSnapshot(
            PreparedWorkoutFetch(
                workouts: [baselineWorkout],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: baselineWorkout.startDate, end: baselineWorkout.endDate),
                checkpoint: nil
            )
        )
        provider.setPreparedChanges(
            PreparedWorkoutFetch(
                workouts: [],
                deletedObjectIDs: [],
                source: .anchoredChanges,
                coverage: DateInterval(start: baselineWorkout.startDate, end: baselineWorkout.endDate),
                checkpoint: nil
            )
        )

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        let refreshed = try await cache.refreshWorkouts()

        #expect(refreshed.count == 1)
        #expect(refreshed.first?.id == baselineWorkout.id)
        #expect(provider.accepted.count == 2)
    }

    @Test("Same-range refresh supersedes the older in-flight request without clearing newer state")
    func sameRangeRefreshSupersedesOlderInFlightRequest() async throws {
        let base = Date()
        let range = DateInterval(start: base.addingTimeInterval(-8 * 60 * 60), end: base)
        let oldWorkout = makeWorkout(date: range.start.addingTimeInterval(60))
        let newerWorkout = makeWorkout(date: range.end.addingTimeInterval(-60))
        let provider = BarrierPreparedWorkoutProvider()
        provider.register(
            PreparedWorkoutFetch(
                workouts: [oldWorkout],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range,
                checkpoint: nil
            ),
            for: range,
            gate: true
        )
        provider.register(
            PreparedWorkoutFetch(
                workouts: [newerWorkout],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range,
                checkpoint: nil
            ),
            for: range,
            gate: true
        )

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        let first = Task { try await cache.workoutData(in: range) }
        let second = Task { try await cache.refreshWorkouts(in: range) }

        provider.release(for: range)

        let secondResult = try await second.value
        do {
            _ = try await first.value
            Issue.record("older same-range request should not publish after a newer refresh")
        } catch is CancellationError {
        }

        #expect(secondResult.count == 1)
        #expect(secondResult.first?.id == newerWorkout.id)
    }

    // MARK: - Date Range Filtering

    @Test("Cache hit filters workouts by date range")
    func cacheHitFiltersDateRange() async throws {
        let now = Date()
        let workoutMock = MockWorkoutProvider()

        let workouts = [
            makeWorkout(date: now.addingTimeInterval(-2 * 24 * 60 * 60)),
            makeWorkout(date: now.addingTimeInterval(-30 * 60)),
        ]
        await workoutMock.setFetchResult(WorkoutFetchResult(workouts: workouts, deletedObjectIDs: []))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()

        let recentRange = DateInterval(
            start: now.addingTimeInterval(-2 * 60 * 60),
            end: now.addingTimeInterval(-60)
        )
        let filtered = try await cache.workoutData(in: recentRange)

        #expect(filtered.count == 1)
        #expect(await workoutMock.fetchCallCount == 1)
    }

    @Test("Range cache hit requires full coverage, not just a matching start")
    func rangeCacheHitRequiresFullCoverage() async throws {
        let now = Date()
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(WorkoutFetchResult(
            workouts: [
                makeWorkout(date: now.addingTimeInterval(-7 * 24 * 60 * 60)),
                makeWorkout(date: now),
            ],
            deletedObjectIDs: []
        ))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        let widerRange = DateInterval(
            start: now.addingTimeInterval(-40 * 24 * 60 * 60),
            end: now.addingTimeInterval(60 * 60)
        )

        _ = try await cache.workoutData(in: widerRange)

        #expect(await workoutMock.fetchCallCount == 2)
    }

    @Test("Default baseline does not satisfy an explicit range when coverage is missing")
    func defaultBaselineDoesNotSatisfyExplicitRangeWithoutCoverage() async throws {
        let now = Date()
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(WorkoutFetchResult(
            workouts: [makeWorkout(date: now)],
            deletedObjectIDs: []
        ))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        let explicitRange = DateInterval(
            start: now.addingTimeInterval(-2 * 24 * 60 * 60),
            end: now.addingTimeInterval(2 * 24 * 60 * 60)
        )

        _ = try await cache.workoutData(in: explicitRange)

        #expect(await workoutMock.fetchCallCount == 2)
    }

    // MARK: - Refresh

    @Test("Refresh always fetches and replaces workout cache")
    func refreshAlwaysFetches() async throws {
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        #expect(await workoutMock.fetchCallCount == 1)

        await workoutMock.setFetchResult(makeWorkoutResult(count: 5))
        let refreshed = try await cache.refreshWorkouts()

        #expect(refreshed.count == 5)
        #expect(await workoutMock.fetchCallCount == 2)
    }

    @Test("Refresh supersedes an older in-flight workout fetch")
    func refreshSupersedesOlderInFlightWorkoutFetch() async throws {
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchDelay(.milliseconds(150))
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let staleTask = Task {
            try await cache.workoutData()
        }

        try await Task.sleep(for: .milliseconds(20))
        await workoutMock.setFetchResult(makeWorkoutResult(count: 4))
        let refreshed = try await cache.refreshWorkouts()
        _ = try? await staleTask.value

        #expect(refreshed.count == 4)
        #expect(await cache.hasWorkoutCache())
        let current = try await cache.workoutData()
        #expect(current.count == 4)
    }

    // MARK: - Invalidation

    @Test("InvalidateWorkouts clears workout cache")
    func invalidateWorkoutsClearsCache() async throws {
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(makeWorkoutResult(count: 2))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        _ = try await cache.workoutData()
        #expect(await cache.hasWorkoutCache())

        await cache.invalidateWorkouts()
        #expect(await !cache.hasWorkoutCache())

        _ = try await cache.workoutData()
        #expect(await workoutMock.fetchCallCount == 2)
    }

    @Test("In-flight workout fetch does not repopulate after invalidateWorkouts")
    func inFlightWorkoutFetchDiscardedAfterInvalidateWorkouts() async throws {
        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchDelay(.milliseconds(100))
        await workoutMock.setFetchResult(makeWorkoutResult(count: 3))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let fetchTask = Task {
            try await cache.workoutData()
        }

        try await Task.sleep(for: .milliseconds(20))
        await cache.invalidateWorkouts()

        _ = try? await fetchTask.value

        #expect(await !cache.hasWorkoutCache())
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
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
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
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        let workoutMock = MockWorkoutProvider()
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
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
        await workoutMock.setFetchDelay(.milliseconds(100))
        await workoutMock.setFetchResult(makeWorkoutResult(count: 3))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
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
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
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
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
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
        await workoutMock.setFetchError(HealthKitServiceError.healthDataNotAvailable)
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
        await workoutMock.setFetchResult(makeWorkoutResult(count: 1))
        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: workoutMock
        )

        let range = DateInterval(start: Date().addingTimeInterval(-3600), duration: 3600)
        _ = try await cache.workoutData(in: range)

        #expect(await workoutMock.fetchDateRanges.first as? DateInterval == range)
    }

    @Test("Prepared anchored delta reconciles UUID updates and deletions deterministically")
    func preparedAnchoredDeltaReconcilesUUIDUpdatesAndDeletes() async throws {
        let baselineStart = Date().addingTimeInterval(-8 * 3600)
        let updatedID = UUID()
        let deletedID = UUID()
        let retainedID = UUID()
        let baseline = [
            makeWorkout(id: updatedID, date: baselineStart, activityType: 37),
            makeWorkout(id: deletedID, date: baselineStart.addingTimeInterval(1800), activityType: 52)
        ]
        let updated = makeWorkout(id: updatedID, date: baselineStart.addingTimeInterval(600), activityType: 37)
        let retained = makeWorkout(id: retainedID, date: baselineStart.addingTimeInterval(900), activityType: 46)

        let provider = MockPreparedWorkoutProvider()
        provider.setPreparedSnapshot(PreparedWorkoutFetch(
            workouts: baseline,
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: nil,
            checkpoint: nil
        ))
        provider.setPreparedChanges(PreparedWorkoutFetch(
            workouts: [updated, retained],
            deletedObjectIDs: [deletedID],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        let refreshed = try await cache.refreshWorkouts()

        #expect(Set(refreshed.map(\.id)) == Set([updatedID, retainedID]))
        #expect(!refreshed.contains { $0.id == deletedID })
    }

    @Test("Repeated anchored delta is idempotent and keeps deterministic UUID ordering")
    func repeatedAnchoredDeltaIsIdempotentAndStable() async throws {
        let anchorDate = Date().addingTimeInterval(-24 * 3600)
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let baseline = [makeWorkout(id: firstID, date: anchorDate, activityType: 37)]
        let updated = [
            makeWorkout(id: thirdID, date: anchorDate.addingTimeInterval(900), activityType: 35),
            makeWorkout(id: secondID, date: anchorDate.addingTimeInterval(600), activityType: 52),
            makeWorkout(id: firstID, date: anchorDate.addingTimeInterval(300), activityType: 37)
        ]

        let provider = MockPreparedWorkoutProvider()
        provider.setPreparedSnapshot(PreparedWorkoutFetch(
            workouts: baseline,
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: nil,
            checkpoint: nil
        ))
        provider.setPreparedChanges(PreparedWorkoutFetch(
            workouts: updated,
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        let once = try await cache.refreshWorkouts()
        let twice = try await cache.refreshWorkouts()

        let orderedIDs = once.map(\.id)
        #expect(orderedIDs == [thirdID, secondID, firstID])
        #expect(twice == once)
    }

    @Test("Deletion wins when the same UUID is both updated and deleted in one delta")
    func deletionWinsWhenSameUUIDAppearsInUpsertAndDelete() async throws {
        let sharedID = UUID()
        let baseline = [makeWorkout(id: sharedID, date: Date().addingTimeInterval(-3600), activityType: 37)]
        let replacement = makeWorkout(id: sharedID, date: Date().addingTimeInterval(-1800), activityType: 52)

        let provider = MockPreparedWorkoutProvider()
        provider.setPreparedSnapshot(PreparedWorkoutFetch(
            workouts: baseline,
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: nil,
            checkpoint: nil
        ))
        provider.setPreparedChanges(PreparedWorkoutFetch(
            workouts: [replacement],
            deletedObjectIDs: [sharedID],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: makeMockDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        let refreshed = try await cache.refreshWorkouts()
        #expect(refreshed.isEmpty)
    }
}
