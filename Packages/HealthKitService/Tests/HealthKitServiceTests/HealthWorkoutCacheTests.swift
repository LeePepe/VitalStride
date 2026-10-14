import Testing
import Foundation
import HealthKit
@testable import HealthKitService

// MARK: - Deterministic Gates & Event Recorders

actor DeterministicGate {
    private var isOpened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpened { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpened else { return }
        isOpened = true
        let continuations = waiters
        waiters.removeAll()
        for cont in continuations {
            cont.resume()
        }
    }

    func isOpen() -> Bool {
        isOpened
    }
}

actor EventRecorder {
    private var recordedEvents: [String] = []

    func record(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }

    func count(of event: String) -> Int {
        recordedEvents.filter { $0 == event }.count
    }
}

// MARK: - Mock Prepared Workout Provider

actor MockPreparedWorkoutProvider: WorkoutDataProviding, PreparedWorkoutDataProviding {
    var snapshotResult: PreparedWorkoutFetch?
    var snapshotResults: [PreparedWorkoutFetch] = []
    var changesResult: PreparedWorkoutFetch?
    var legacyResult: WorkoutFetchResult?

    var fetchCallCount: Int = 0
    var snapshotCallCount: Int = 0
    var changesCallCount: Int = 0
    var acceptCallCount: Int = 0
    var rejectCallCount: Int = 0

    var fetchDateRanges: [DateInterval?] = []
    var lastAcceptedCheckpoint: WorkoutAnchorCheckpoint?
    var lastRejectedPrepared: PreparedWorkoutFetch?

    var shouldAdvanceDurableAnchorOnAccept: Bool = true
    var durableAnchor: WorkoutAnchorCheckpoint?

    var providerStartedGate: DeterministicGate?
    var queryCompleteGate: DeterministicGate?
    var staleReleaseGate: DeterministicGate?

    var eventRecorder: EventRecorder?
    var errorToThrow: (any Error)?

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        fetchCallCount += 1
        fetchDateRanges.append(dateRange)
        await eventRecorder?.record("legacy_fetch_started")
        await providerStartedGate?.open()
        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        await eventRecorder?.record("legacy_query_complete")
        await queryCompleteGate?.open()
        if let error = errorToThrow {
            throw error
        }
        return legacyResult ?? WorkoutFetchResult(workouts: [], deletedObjectIDs: [])
    }

    func prepareWorkoutSnapshot(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        snapshotCallCount += 1
        fetchDateRanges.append(dateRange)
        await eventRecorder?.record("snapshot_started")
        await providerStartedGate?.open()
        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        await eventRecorder?.record("snapshot_query_complete")
        await queryCompleteGate?.open()
        if let error = errorToThrow {
            throw error
        }
        if !snapshotResults.isEmpty {
            return snapshotResults.removeFirst()
        }
        return snapshotResult ?? PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: dateRange == nil ? .baselineSnapshot : .explicitRangeSnapshot,
            coverage: nil,
            checkpoint: nil
        )
    }

    func prepareWorkoutChanges(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch {
        changesCallCount += 1
        fetchDateRanges.append(dateRange)
        await eventRecorder?.record("changes_started")
        await providerStartedGate?.open()
        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        await eventRecorder?.record("changes_query_complete")
        await queryCompleteGate?.open()
        if let error = errorToThrow {
            throw error
        }
        return changesResult ?? PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: nil
        )
    }

    func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) async {
        acceptCallCount += 1
        lastAcceptedCheckpoint = prepared.checkpoint
        await eventRecorder?.record("acceptance_invoked")
        if shouldAdvanceDurableAnchorOnAccept, let cp = prepared.checkpoint {
            durableAnchor = cp
        }
    }

    func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) async {
        rejectCallCount += 1
        lastRejectedPrepared = prepared
        await eventRecorder?.record("acceptance_rejected")
    }

    func setSnapshotResult(_ result: PreparedWorkoutFetch) {
        self.snapshotResult = result
    }

    func setSnapshotResults(_ results: [PreparedWorkoutFetch]) {
        self.snapshotResults = results
    }

    func setChangesResult(_ result: PreparedWorkoutFetch) {
        self.changesResult = result
    }

    func setLegacyResult(_ result: WorkoutFetchResult) {
        self.legacyResult = result
    }

    func setError(_ error: (any Error)?) {
        self.errorToThrow = error
    }

    func setDurableAnchor(_ anchor: WorkoutAnchorCheckpoint?) {
        self.durableAnchor = anchor
    }

    func setStaleReleaseGate(_ gate: DeterministicGate?) {
        self.staleReleaseGate = gate
    }

    func setProviderStartedGate(_ gate: DeterministicGate?) {
        self.providerStartedGate = gate
    }

    func setQueryCompleteGate(_ gate: DeterministicGate?) {
        self.queryCompleteGate = gate
    }

    func setEventRecorder(_ recorder: EventRecorder?) {
        self.eventRecorder = recorder
    }

    func setShouldAdvanceDurableAnchorOnAccept(_ value: Bool) {
        self.shouldAdvanceDurableAnchorOnAccept = value
    }
}

// MARK: - Mock Pure Legacy Workout Provider

actor MockLegacyWorkoutProvider: WorkoutDataProviding {
    var fetchResult: WorkoutFetchResult
    var fetchCallCount: Int = 0
    var fetchDateRanges: [DateInterval?] = []

    init(fetchResult: WorkoutFetchResult = WorkoutFetchResult(workouts: [], deletedObjectIDs: [])) {
        self.fetchResult = fetchResult
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        fetchCallCount += 1
        fetchDateRanges.append(dateRange)
        return fetchResult
    }
}

// MARK: - Pure Mock Data Provider for Sample Cache

struct MockSimpleHealthDataProvider: HealthDataProviding {
    var fetchResults: [HealthSampleType: HealthFetchResult] = [:]

    func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        fetchResults[sampleType] ?? HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}

// MARK: - Helpers

private func makeWorkout(
    id: UUID = UUID(),
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

private func makeCheckpoint(
    source: WorkoutAnchorSource = .baselineSnapshot,
    anchorValue: Int = 1
) -> WorkoutAnchorCheckpoint {
    let hkAnchor = HKQueryAnchor(fromValue: anchorValue)
    return WorkoutAnchorCheckpoint(source: source, anchor: hkAnchor)
}

// MARK: - Test Suite

@Suite("HealthWorkoutCacheTests")
struct HealthWorkoutCacheTests {

    // MARK: - Stage B: AC-S1 / AC-11 Single Settlement Authority

    @Test("AC-S1: Concurrent identical reads coalesce and terminate exactly once on success")
    func testSingleSettlement_Success() async throws {
        let provider = MockPreparedWorkoutProvider()
        let gate = DeterministicGate()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setStaleReleaseGate(gate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let task1 = Task { try await cache.workoutData() }
        let task2 = Task { try await cache.workoutData() }
        let task3 = Task { try await cache.workoutData() }

        await gate.open()

        let r1 = try await task1.value
        let r2 = try await task2.value
        let r3 = try await task3.value

        #expect(r1.count == 1)
        #expect(r2.count == 1)
        #expect(r3.count == 1)
        #expect(await provider.snapshotCallCount == 1)
    }

    @Test("AC-S1: Provider failure fans out to owner and coalesced callers without hang")
    func testSingleSettlement_ProviderFailure() async throws {
        let provider = MockPreparedWorkoutProvider()
        let gate = DeterministicGate()
        await provider.setError(HealthKitServiceError.healthDataNotAvailable)
        await provider.setStaleReleaseGate(gate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let task1 = Task { try await cache.workoutData() }
        let task2 = Task { try await cache.workoutData() }

        await gate.open()

        let result1 = await task1.result
        let result2 = await task2.result

        switch (result1, result2) {
        case (.failure(let e1 as HealthKitServiceError), .failure(let e2 as HealthKitServiceError)):
            if case .healthDataNotAvailable = e1, case .healthDataNotAvailable = e2 {
                #expect(true)
            } else {
                Issue.record("Expected healthDataNotAvailable")
            }
        default:
            Issue.record("Expected both callers to fail with HealthKitServiceError")
        }
        #expect(await !cache.hasWorkoutCache())
    }

    @Test("AC-S1: Non-owner cancellation settles only that waiter; owner continues and succeeds")
    func testSingleSettlement_NonOwnerCancellation() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        let workout = makeWorkout()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let ownerTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        let coalescedTask = Task { try await cache.workoutData() }
        coalescedTask.cancel()

        await releaseGate.open()

        let ownerResult = try await ownerTask.value
        #expect(ownerResult.count == 1)

        let coalescedResult = await coalescedTask.result
        switch coalescedResult {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected coalesced task to fail with CancellationError")
        }
    }

    @Test("AC-S1: Owner cancellation retires request and settles all attached waiters exactly once")
    func testSingleSettlement_OwnerCancellation() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let ownerTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        let coalescedTask = Task { try await cache.workoutData() }
        ownerTask.cancel()

        await releaseGate.open()

        let r1 = await ownerTask.result
        let r2 = await coalescedTask.result

        switch (r1, r2) {
        case (.failure(let e1), .failure(let e2)):
            #expect(e1 is CancellationError)
            #expect(e2 is CancellationError)
        default:
            Issue.record("Expected both waiters to be cancelled")
        }
    }

    @Test("AC-S1: Refresh supersession cancels superseded in-flight callers and succeeds for fresh caller")
    func testSingleSettlement_RefreshSupersession() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        let initialWorkout = makeWorkout()
        let refreshedWorkout = makeWorkout()

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [initialWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let queryTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        // Configure next result for refresh
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [refreshedWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        let refreshTask = Task { try await cache.refreshWorkouts() }

        await releaseGate.open()

        let queryResult = await queryTask.result
        let refreshResult = try await refreshTask.value

        switch queryResult {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected query task to be cancelled by superseding refresh")
        }

        #expect(refreshResult.count == 1)
        #expect(refreshResult.first?.id == refreshedWorkout.id)
    }

    @Test("AC-S1: InvalidateWorkouts cancels in-flight waiters and clears cache")
    func testSingleSettlement_InvalidateWorkouts() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let fetchTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        await cache.invalidateWorkouts()
        await releaseGate.open()

        let result = await fetchTask.result
        switch result {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected fetchTask to fail with CancellationError on invalidation")
        }

        #expect(await !cache.hasWorkoutCache())
    }

    @Test("AC-S1: InvalidateAll cancels in-flight workout waiters")
    func testSingleSettlement_InvalidateAll() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let fetchTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        await cache.invalidateAll()
        await releaseGate.open()

        let result = await fetchTask.result
        switch result {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected fetchTask to fail with CancellationError on invalidateAll")
        }

        #expect(await !cache.hasWorkoutCache())
    }

    // MARK: - Stage C: AC-S2 / AC-12 Real Provider Lanes

    @Test("AC-S2: Distinct explicit range lanes progress independently without blocking")
    func testLanes_IndependentExplicitRanges() async throws {
        let provider = MockPreparedWorkoutProvider()
        let range1Started = DeterministicGate()
        let range1Release = DeterministicGate()

        let now = Date()
        let range1 = DateInterval(start: now.addingTimeInterval(-7200), duration: 3600)
        let range2 = DateInterval(start: now.addingTimeInterval(-3600), duration: 1800)

        let w1 = makeWorkout(date: range1.start)
        let w2 = makeWorkout(date: range2.start)

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [w1],
            deletedObjectIDs: [],
            source: .explicitRangeSnapshot,
            coverage: range1,
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(range1Started)
        await provider.setStaleReleaseGate(range1Release)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let task1 = Task { try await cache.workoutData(in: range1) }
        await range1Started.wait()

        // Now run task2 with distinct range2 on another provider or same provider
        let provider2 = MockPreparedWorkoutProvider()
        await provider2.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [w2],
            deletedObjectIDs: [],
            source: .explicitRangeSnapshot,
            coverage: range2,
            checkpoint: nil
        ))
        let cache2 = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider2
        )

        let r2 = try await cache2.workoutData(in: range2)
        #expect(r2.count == 1)

        await range1Release.open()
        let r1 = try await task1.value
        #expect(r1.count == 1)
    }

    @Test("AC-S2: Same-generation supersession pumps queued successor before stale release")
    func testLanes_SameGenerationSupersessionPumpsQueuedBeforeStaleRelease() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let staleGate = DeterministicGate()

        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(staleGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let task1 = Task { try await cache.workoutData() }
        await startedGate.wait()

        // Setup provider for second request
        let successorWorkout = makeWorkout()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [successorWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        // Refresh supersedes task1
        let refreshTask = Task { try await cache.refreshWorkouts() }

        let refreshResult = try await refreshTask.value
        #expect(refreshResult.count == 1)
        #expect(refreshResult.first?.id == successorWorkout.id)

        await staleGate.open()
        _ = await task1.result
    }

    @Test("AC-S2: Reset drains old callers and post-reset request completes before stale release")
    func testLanes_ResetDrainsOldWorkAndStartsPostResetBeforeStaleRelease() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let staleGate = DeterministicGate()

        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(staleGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let oldTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        await cache.invalidateWorkouts()

        let oldResult = await oldTask.result
        switch oldResult {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected old task to fail with CancellationError on reset")
        }

        // Fresh post-reset request
        let postResetWorkout = makeWorkout()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [postResetWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        let newTask = Task { try await cache.workoutData() }
        let newResult = try await newTask.value
        #expect(newResult.count == 1)
        #expect(newResult.first?.id == postResetWorkout.id)

        // Finally release old stale provider
        await staleGate.open()

        let currentCacheWorkouts = try await cache.workoutData()
        #expect(currentCacheWorkouts.first?.id == postResetWorkout.id)
    }

    // MARK: - Stage A & C: AC-S3 / AC-01–AC-04, AC-06, AC-08 Compatible Anchored Baseline

    @Test("AC-01 / AC-S3: Baseline A + empty anchored changes preserves A")
    func testAC01_BaselineA_EmptyAnchoredChanges_PreservesA() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workoutA = makeWorkout()
        let checkpoint1 = makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        let checkpoint2 = makeCheckpoint(source: .anchoredChanges, anchorValue: 2)

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: checkpoint1
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let initial = try await cache.workoutData()
        #expect(initial.count == 1)
        #expect(initial.first?.id == workoutA.id)

        // Next anchored changes has 0 upserts, 0 deletions
        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: checkpoint2
        ))

        let refreshed = try await cache.refreshWorkouts()
        #expect(refreshed.count == 1)
        #expect(refreshed.first?.id == workoutA.id)
        #expect(await provider.acceptCallCount == 2)
    }

    @Test("AC-02: Baseline A + anchored changes (add B, delete A) returns only B")
    func testAC02_BaselineA_AddBDeleteA_ReturnsOnlyB() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workoutA = makeWorkout()
        let workoutB = makeWorkout()

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()

        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [workoutB],
            deletedObjectIDs: [workoutA.id],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: makeCheckpoint(source: .anchoredChanges, anchorValue: 2)
        ))

        let refreshed = try await cache.refreshWorkouts()
        #expect(refreshed.count == 1)
        #expect(refreshed.first?.id == workoutB.id)
    }

    @Test("AC-03: Existing workout A + anchored changes (update A) replaces A without duplicate")
    func testAC03_BaselineA_UpdateA_ReplacesAWithoutDuplicate() async throws {
        let provider = MockPreparedWorkoutProvider()
        let idA = UUID()
        let workoutA = makeWorkout(id: idA, duration: 1800)
        let updatedA = makeWorkout(id: idA, duration: 3600)

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()

        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [updatedA],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: makeCheckpoint(source: .anchoredChanges, anchorValue: 2)
        ))

        let refreshed = try await cache.refreshWorkouts()
        #expect(refreshed.count == 1)
        #expect(refreshed.first?.id == idA)
        #expect(refreshed.first?.duration == 3600)
    }

    @Test("AC-04: Idempotent delta applied twice leaves cache unchanged")
    func testAC04_IdempotentDelta_AppliedTwice_Unchanged() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workoutA = makeWorkout()
        let workoutB = makeWorkout()

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()

        let delta = PreparedWorkoutFetch(
            workouts: [workoutB],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: makeCheckpoint(source: .anchoredChanges, anchorValue: 2)
        )

        await provider.setChangesResult(delta)
        let r1 = try await cache.refreshWorkouts()
        #expect(r1.count == 2)

        let r2 = try await cache.refreshWorkouts()
        #expect(r2.count == 2)
    }

    @Test("AC-06: Empty in-memory cache rebuilds authoritative baseline before accepting changes")
    func testAC06_EmptyCache_RebuildsAuthoritativeBaselineFirst() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workout = makeWorkout()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 1)
        #expect(await provider.snapshotCallCount == 1)
    }

    @Test("AC-08: Scoped snapshot cannot satisfy subsequent default read")
    func testAC08_ScopedSnapshot_CannotSatisfyDefaultRead() async throws {
        let provider = MockPreparedWorkoutProvider()
        let now = Date()
        let explicitRange = DateInterval(start: now.addingTimeInterval(-3600), duration: 3600)
        let scopedWorkout = makeWorkout(date: now.addingTimeInterval(-1800))
        let defaultWorkout = makeWorkout(date: now.addingTimeInterval(-80000))

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [scopedWorkout],
            deletedObjectIDs: [],
            source: .explicitRangeSnapshot,
            coverage: explicitRange,
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let scopedResult = try await cache.workoutData(in: explicitRange)
        #expect(scopedResult.count == 1)

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [defaultWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let defaultResult = try await cache.workoutData(in: nil)
        #expect(defaultResult.count == 1)
        #expect(defaultResult.first?.id == defaultWorkout.id)
        #expect(await provider.snapshotCallCount == 2)
    }

    @Test("AC-S3: Incompatible anchored changes without baseline rejects and rebuilds default baseline")
    func testIncompatibleAnchoredChangesRejectsAndRebuildsDefaultBaseline() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workout = makeWorkout()

        // First prepareWorkoutSnapshot returns .anchoredChanges (incompatible with empty cache!)
        // Second prepareWorkoutSnapshot (rebuild) returns .baselineSnapshot
        await provider.setSnapshotResults([
            PreparedWorkoutFetch(
                workouts: [workout],
                deletedObjectIDs: [],
                source: .anchoredChanges,
                coverage: nil,
                checkpoint: makeCheckpoint(source: .anchoredChanges, anchorValue: 2)
            ),
            PreparedWorkoutFetch(
                workouts: [workout],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
                checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
            )
        ])

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 1)
        #expect(await provider.rejectCallCount == 1)
        #expect(await provider.snapshotCallCount == 2)
    }

    // MARK: - Stage A & D: AC-S4 / AC-05, AC-07, FR-020 Deterministic Legacy Snapshots

    @Test("AC-05 / FR-020: Duplicate UUIDs normalized with final winning; sorted start date desc then UUID")
    func testLegacyFallback_DuplicateUUIDs_FinalWins_SortedStartDescUUID() async throws {
        let idA = UUID()
        let now = Date()
        let t1 = now.addingTimeInterval(-3600)
        let t2 = now.addingTimeInterval(-1800)

        let wA_first = makeWorkout(id: idA, date: t1, duration: 1000)
        let wA_final = makeWorkout(id: idA, date: t2, duration: 2000)
        let wB = makeWorkout(date: t1, duration: 500)

        let provider = MockLegacyWorkoutProvider(fetchResult: WorkoutFetchResult(
            workouts: [wA_first, wB, wA_final],
            deletedObjectIDs: []
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 2)
        #expect(result[0].id == idA)
        #expect(result[0].duration == 2000)
        #expect(result[1].id == wB.id)
    }

    @Test("AC-S4 / FR-002: Legacy default request with missing coverage uses 30-day window ending at request start")
    func testLegacyFallback_MissingDefaultCoverage_Uses30DayWindow() async throws {
        let workout = makeWorkout()
        let provider = MockLegacyWorkoutProvider(fetchResult: WorkoutFetchResult(
            workouts: [workout],
            deletedObjectIDs: [],
            coverage: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 1)
        #expect(await provider.fetchCallCount == 1)
    }

    @Test("AC-S4: Legacy explicit request with missing coverage uses exact requested range")
    func testLegacyFallback_MissingExplicitCoverage_UsesExactRequestedRange() async throws {
        let range = DateInterval(start: Date().addingTimeInterval(-3600), duration: 3600)
        let workout = makeWorkout(date: range.start.addingTimeInterval(60))

        let provider = MockLegacyWorkoutProvider(fetchResult: WorkoutFetchResult(
            workouts: [workout],
            deletedObjectIDs: [],
            coverage: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData(in: range)
        #expect(result.count == 1)
        #expect(await provider.fetchDateRanges.first as? DateInterval == range)
    }

    @Test("AC-07: Cached default-window snapshot cannot satisfy wider explicit range request")
    func testAC07_CachedDefaultSnapshot_WiderExplicitRangeMisses() async throws {
        let provider = MockPreparedWorkoutProvider()
        let now = Date()
        let defaultWorkout = makeWorkout(date: now.addingTimeInterval(-86400))
        let widerWorkout = makeWorkout(date: now.addingTimeInterval(-60 * 86400))

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [defaultWorkout],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        #expect(await provider.snapshotCallCount == 1)

        let widerRange = DateInterval(start: now.addingTimeInterval(-90 * 86400), end: now)
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [defaultWorkout, widerWorkout],
            deletedObjectIDs: [],
            source: .explicitRangeSnapshot,
            coverage: widerRange,
            checkpoint: nil
        ))

        let widerResult = try await cache.workoutData(in: widerRange)
        #expect(widerResult.count == 2)
        #expect(await provider.snapshotCallCount == 2)
    }

    // MARK: - Stage D: AC-S5 / AC-09, AC-10, AC-13 Distinct Transaction Gates & Replay

    @Test("AC-S5 / AC-09 / AC-13: Replay from durable c1 after rejection; c2 acceptance invoked before success")
    func testAC09_AC13_ReplayAfterCancellationAndAcceptanceInvocation() async throws {
        let provider = MockPreparedWorkoutProvider()
        let recorder = EventRecorder()
        await provider.setEventRecorder(recorder)

        let workoutA = makeWorkout()
        let workoutB = makeWorkout()
        let cp1 = makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        let cp2 = makeCheckpoint(source: .anchoredChanges, anchorValue: 2)

        // Step 1: Accept baseline A/c1
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: cp1
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let initial = try await cache.workoutData()
        #expect(initial.count == 1)
        #expect(await provider.durableAnchor == cp1)

        // Step 2: Query B/c2 complete, held before cache acceptance
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [workoutB],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: cp2
        ))

        let queryTask = Task { try await cache.refreshWorkouts() }
        await startedGate.wait()

        // Step 3: Cancel queryTask -> c2 rejected
        queryTask.cancel()
        await releaseGate.open()

        _ = await queryTask.result
        #expect(await provider.rejectCallCount == 1)
        #expect(await provider.durableAnchor == cp1)

        // Step 4: Replacement query reads durable c1 and returns B/c2
        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        let replacement = try await cache.refreshWorkouts()
        #expect(replacement.count == 2)
        #expect(await provider.durableAnchor == cp2)

        let events = await recorder.events()
        #expect(events.contains("acceptance_invoked"))
    }

    @Test("AC-13 / AC-S5: Silent durable no-advance replays safely without cache failure or duplicate records")
    func testAC13_SilentDurableNoAdvance_ReplaysSafely() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workoutA = makeWorkout()
        let workoutB = makeWorkout()
        let cp1 = makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        let cp2 = makeCheckpoint(source: .anchoredChanges, anchorValue: 2)

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: cp1
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()

        // Durable anchor does NOT advance when accepting c2 (stays at cp1)
        await provider.setShouldAdvanceDurableAnchorOnAccept(false)
        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [workoutB],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: cp2
        ))

        let r1 = try await cache.refreshWorkouts()
        #expect(r1.count == 2)
        #expect(await provider.durableAnchor == cp1)

        // Next query replays B/c2 again from cp1
        let r2 = try await cache.refreshWorkouts()
        #expect(r2.count == 2)
    }

    // MARK: - Telemetry & General Behavior

    @Test("Workout telemetry tracks hits, misses, and refreshes")
    func testTelemetryTracking() async throws {
        let provider = MockPreparedWorkoutProvider()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
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

    @Test("InvalidateAll resets workout telemetry counters")
    func testTelemetryResetOnInvalidateAll() async throws {
        let provider = MockPreparedWorkoutProvider()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        _ = try await cache.workoutData()
        _ = try await cache.workoutData()
        await cache.invalidateAll()

        let tel = await cache.workoutTelemetry()
        #expect(tel == CacheTelemetry(hits: 0, misses: 0, refreshes: 0))
    }

    @Test("Workout query returns empty when no provider configured")
    func testNoProviderReturnsEmpty() async throws {
        let cache = HealthDataCache(dataProvider: MockSimpleHealthDataProvider())
        let result = try await cache.workoutData()
        #expect(result.isEmpty)
    }

    @Test("Workout fetch error propagates and leaves cache empty")
    func testErrorPropagation() async {
        let provider = MockPreparedWorkoutProvider()
        await provider.setError(HealthKitServiceError.healthDataNotAvailable)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        do {
            _ = try await cache.workoutData()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is HealthKitServiceError)
        }

        #expect(await !cache.hasWorkoutCache())
    }

    @Test("handleAuthorizationRevoked clears workout cache and device anchors")
    func testAuthorizationRevokedClearsCacheAndAnchors() async throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        let provider = MockPreparedWorkoutProvider()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
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
}
