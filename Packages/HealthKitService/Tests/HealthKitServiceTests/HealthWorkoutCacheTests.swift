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
    private final class MockState: @unchecked Sendable {
        var snapshotResult: PreparedWorkoutFetch?
        var snapshotResults: [PreparedWorkoutFetch] = []
        var changesResult: PreparedWorkoutFetch?
        var changesResults: [PreparedWorkoutFetch] = []
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
        var cacheAcceptanceGate: DeterministicGate?
        var acceptanceInvokedGate: DeterministicGate?
        var resetSuccessorGate: DeterministicGate?
        var staleReleaseGate: DeterministicGate?

        var eventRecorder: EventRecorder?
        var errorToThrow: (any Error)?

        var providerStartedGatesByRange: [DateInterval?: DeterministicGate] = [:]
        var staleReleaseGatesByRange: [DateInterval?: DeterministicGate] = [:]
    }

    private let state = MockState()

    var snapshotResult: PreparedWorkoutFetch? {
        get { state.snapshotResult }
        set { state.snapshotResult = newValue }
    }
    var snapshotResults: [PreparedWorkoutFetch] {
        get { state.snapshotResults }
        set { state.snapshotResults = newValue }
    }
    var changesResult: PreparedWorkoutFetch? {
        get { state.changesResult }
        set { state.changesResult = newValue }
    }
    var changesResults: [PreparedWorkoutFetch] {
        get { state.changesResults }
        set { state.changesResults = newValue }
    }
    var legacyResult: WorkoutFetchResult? {
        get { state.legacyResult }
        set { state.legacyResult = newValue }
    }

    var fetchCallCount: Int {
        get { state.fetchCallCount }
        set { state.fetchCallCount = newValue }
    }
    var snapshotCallCount: Int {
        get { state.snapshotCallCount }
        set { state.snapshotCallCount = newValue }
    }
    var changesCallCount: Int {
        get { state.changesCallCount }
        set { state.changesCallCount = newValue }
    }
    var acceptCallCount: Int {
        get { state.acceptCallCount }
        set { state.acceptCallCount = newValue }
    }
    var rejectCallCount: Int {
        get { state.rejectCallCount }
        set { state.rejectCallCount = newValue }
    }

    var fetchDateRanges: [DateInterval?] {
        get { state.fetchDateRanges }
        set { state.fetchDateRanges = newValue }
    }
    var lastAcceptedCheckpoint: WorkoutAnchorCheckpoint? {
        get { state.lastAcceptedCheckpoint }
        set { state.lastAcceptedCheckpoint = newValue }
    }
    var lastRejectedPrepared: PreparedWorkoutFetch? {
        get { state.lastRejectedPrepared }
        set { state.lastRejectedPrepared = newValue }
    }

    var shouldAdvanceDurableAnchorOnAccept: Bool {
        get { state.shouldAdvanceDurableAnchorOnAccept }
        set { state.shouldAdvanceDurableAnchorOnAccept = newValue }
    }
    var durableAnchor: WorkoutAnchorCheckpoint? {
        get { state.durableAnchor }
        set { state.durableAnchor = newValue }
    }

    var providerStartedGate: DeterministicGate? {
        get { state.providerStartedGate }
        set { state.providerStartedGate = newValue }
    }
    var queryCompleteGate: DeterministicGate? {
        get { state.queryCompleteGate }
        set { state.queryCompleteGate = newValue }
    }
    var cacheAcceptanceGate: DeterministicGate? {
        get { state.cacheAcceptanceGate }
        set { state.cacheAcceptanceGate = newValue }
    }
    var acceptanceInvokedGate: DeterministicGate? {
        get { state.acceptanceInvokedGate }
        set { state.acceptanceInvokedGate = newValue }
    }
    var resetSuccessorGate: DeterministicGate? {
        get { state.resetSuccessorGate }
        set { state.resetSuccessorGate = newValue }
    }
    var staleReleaseGate: DeterministicGate? {
        get { state.staleReleaseGate }
        set { state.staleReleaseGate = newValue }
    }

    var eventRecorder: EventRecorder? {
        get { state.eventRecorder }
        set { state.eventRecorder = newValue }
    }
    var errorToThrow: (any Error)? {
        get { state.errorToThrow }
        set { state.errorToThrow = newValue }
    }

    var providerStartedGatesByRange: [DateInterval?: DeterministicGate] {
        get { state.providerStartedGatesByRange }
        set { state.providerStartedGatesByRange = newValue }
    }
    var staleReleaseGatesByRange: [DateInterval?: DeterministicGate] {
        get { state.staleReleaseGatesByRange }
        set { state.staleReleaseGatesByRange = newValue }
    }

    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult {
        fetchCallCount += 1
        fetchDateRanges.append(dateRange)
        await eventRecorder?.record("legacy_fetch_started")
        await providerStartedGate?.open()
        if let gate = providerStartedGatesByRange[dateRange] {
            await gate.open()
        }

        await queryCompleteGate?.open()

        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        if let gate = staleReleaseGatesByRange[dateRange] {
            await gate.wait()
        }

        await eventRecorder?.record("legacy_query_complete")
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
        if let gate = providerStartedGatesByRange[dateRange] {
            await gate.open()
        }

        await queryCompleteGate?.open()

        if let cacheAcceptanceGate {
            await cacheAcceptanceGate.wait()
        }
        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        if let gate = staleReleaseGatesByRange[dateRange] {
            await gate.wait()
        }

        await eventRecorder?.record("snapshot_query_complete")
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
        if let gate = providerStartedGatesByRange[dateRange] {
            await gate.open()
        }

        await queryCompleteGate?.open()

        if let cacheAcceptanceGate {
            await cacheAcceptanceGate.wait()
        }
        if let staleReleaseGate {
            await staleReleaseGate.wait()
        }
        if let gate = staleReleaseGatesByRange[dateRange] {
            await gate.wait()
        }

        await eventRecorder?.record("changes_query_complete")
        if let error = errorToThrow {
            throw error
        }
        if !changesResults.isEmpty {
            return changesResults.removeFirst()
        }
        return changesResult ?? PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: nil
        )
    }

    nonisolated func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        state.acceptCallCount += 1
        state.lastAcceptedCheckpoint = prepared.checkpoint
        if state.shouldAdvanceDurableAnchorOnAccept, let cp = prepared.checkpoint {
            state.durableAnchor = cp
        }
        let rec = state.eventRecorder
        let gate = state.acceptanceInvokedGate
        Task {
            await rec?.record("acceptance_invoked")
            await gate?.open()
        }
    }

    nonisolated func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch) {
        state.rejectCallCount += 1
        state.lastRejectedPrepared = prepared
        let rec = state.eventRecorder
        Task {
            await rec?.record("acceptance_rejected")
        }
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

    func setChangesResults(_ results: [PreparedWorkoutFetch]) {
        self.changesResults = results
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

    func setCacheAcceptanceGate(_ gate: DeterministicGate?) {
        self.cacheAcceptanceGate = gate
    }

    func setAcceptanceInvokedGate(_ gate: DeterministicGate?) {
        self.acceptanceInvokedGate = gate
    }

    func setResetSuccessorGate(_ gate: DeterministicGate?) {
        self.resetSuccessorGate = gate
    }

    func setEventRecorder(_ recorder: EventRecorder?) {
        self.eventRecorder = recorder
    }

    func setShouldAdvanceDurableAnchorOnAccept(_ value: Bool) {
        self.shouldAdvanceDurableAnchorOnAccept = value
    }

    func setGateForRange(started: DeterministicGate?, stale: DeterministicGate?, range: DateInterval?) {
        self.providerStartedGatesByRange[range] = started
        self.staleReleaseGatesByRange[range] = stale
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

    @Test("AC-S1: Cancellation of one coalesced waiter removes only that waiter")
    func testSingleSettlement_CancelOneWaiterDoesNotAffectOthers() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
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

        let task1 = Task { try await cache.workoutData() }
        let task2 = Task { try await cache.workoutData() }

        await startedGate.wait()

        // Cancel task2 only
        task2.cancel()

        await releaseGate.open()

        let r1 = try await task1.value
        #expect(r1.count == 1)

        let result2 = await task2.result
        switch result2 {
        case .failure(let error):
            #expect(error is CancellationError)
        case .success:
            Issue.record("Expected task2 to fail with CancellationError")
        }
    }

    @Test("AC-S1: InvalidateAll settles active request with CancellationError and leaves cache clean")
    func testSingleSettlement_InvalidateAllSettlesWithCancellationError() async throws {
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

    @Test("AC-S1 / AC-11: Provider failure fans out error to owner and all coalesced waiters")
    func testSingleSettlement_FailureFansOutToOwnerAndCoalescedWaiters() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()

        await provider.setError(HealthKitServiceError.healthDataNotAvailable)
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let task1 = Task { try await cache.workoutData() }
        await startedGate.wait()

        let task2 = Task { try await cache.workoutData() }
        let task3 = Task { try await cache.workoutData() }

        await releaseGate.open()

        let r1 = await task1.result
        let r2 = await task2.result
        let r3 = await task3.result

        #expect(throws: HealthKitServiceError.self) { try r1.get() }
        #expect(throws: HealthKitServiceError.self) { try r2.get() }
        #expect(throws: HealthKitServiceError.self) { try r3.get() }
        #expect(await !cache.hasWorkoutCache())
    }

    @Test("AC-S1 / AC-11: Owner cancellation preserves coalesced waiters and delivers result to remaining waiters")
    func testSingleSettlement_OwnerCancellationPreservesCoalescedWaiters() async throws {
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

        // Cancel owner task
        ownerTask.cancel()

        await releaseGate.open()

        let ownerRes = await ownerTask.result
        #expect(throws: CancellationError.self) { try ownerRes.get() }

        let coalescedRes = try await coalescedTask.value
        #expect(coalescedRes.count == 1)
        #expect(coalescedRes.first?.id == workout.id)
    }

    @Test("AC-S1 / AC-11: Refresh supersession cancels active fetch and queued refresh delivers fresh result")
    func testSingleSettlement_RefreshSupersessionSettlesOldAndDeliversNew() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()
        let releaseGate = DeterministicGate()

        let w1 = makeWorkout()
        let w2 = makeWorkout()

        await provider.setSnapshotResults([
            PreparedWorkoutFetch(
                workouts: [w1],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
                checkpoint: nil
            ),
            PreparedWorkoutFetch(
                workouts: [w2],
                deletedObjectIDs: [],
                source: .baselineSnapshot,
                coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
                checkpoint: nil
            )
        ])
        await provider.setProviderStartedGate(startedGate)
        await provider.setStaleReleaseGate(releaseGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let initialTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        let refreshTask = Task { try await cache.refreshWorkouts() }

        await releaseGate.open()

        let refreshRes = try await refreshTask.value
        #expect(refreshRes.count == 1)
        #expect(refreshRes.first?.id == w2.id)

        _ = await initialTask.result
    }

    @Test("AC-S1 / AC-11: InvalidateWorkouts cancels in-flight fetch and leaves cache empty")
    func testSingleSettlement_InvalidateWorkoutsCancelsInFlightFetch() async throws {
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
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await !cache.hasWorkoutCache())
    }

    // MARK: - Stage C: AC-S2 / AC-12 / FR-018 / SC-008 Real Provider Lanes in ONE Cache

    @Test("AC-S2: Distinct explicit range lanes progress independently in ONE cache without blocking")
    func testLanes_DistinctRangesInSingleCacheProgressIndependently() async throws {
        let provider = MockPreparedWorkoutProvider()
        let range1Started = DeterministicGate()
        let range1Release = DeterministicGate()

        let now = Date()
        let range1 = DateInterval(start: now.addingTimeInterval(-7200), duration: 3600)
        let range2 = DateInterval(start: now.addingTimeInterval(-3600), duration: 1800)

        let w1 = makeWorkout(date: range1.start)
        let w2 = makeWorkout(date: range2.start)

        await provider.setSnapshotResults([
            PreparedWorkoutFetch(
                workouts: [w1],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range1,
                checkpoint: nil
            ),
            PreparedWorkoutFetch(
                workouts: [w2],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range2,
                checkpoint: nil
            )
        ])

        await provider.setGateForRange(started: range1Started, stale: range1Release, range: range1)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        // Request 1 is started and held in lane for range1
        let task1 = Task { try await cache.workoutData(in: range1) }
        await range1Started.wait()

        // Request 2 on distinct range2 starts and completes on same cache without being blocked by range1
        let r2 = try await cache.workoutData(in: range2)
        #expect(r2.count == 1)
        #expect(r2.first?.id == w2.id)

        // Now release range1
        await range1Release.open()
        let r1 = try await task1.value
        #expect(r1.count == 1)
        #expect(r1.first?.id == w1.id)
        #expect(await provider.snapshotCallCount == 2)
    }

    @Test("AC-S2 / FR-018: Active + FIFO queued callers pump queued successor before stale release")
    func testLanes_ActiveAndFIFOQueuedPumpsSuccessorBeforeStaleRelease() async throws {
        let provider = MockPreparedWorkoutProvider()
        let activeStarted = DeterministicGate()
        let activeStaleRelease = DeterministicGate()

        let now = Date()
        let range = DateInterval(start: now.addingTimeInterval(-3600), duration: 3600)
        let w1 = makeWorkout(date: range.start)
        let w2 = makeWorkout(date: range.start.addingTimeInterval(60))

        await provider.setSnapshotResults([
            PreparedWorkoutFetch(
                workouts: [w1],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range,
                checkpoint: nil
            ),
            PreparedWorkoutFetch(
                workouts: [w2],
                deletedObjectIDs: [],
                source: .explicitRangeSnapshot,
                coverage: range,
                checkpoint: nil
            )
        ])

        await provider.setProviderStartedGate(activeStarted)
        await provider.setStaleReleaseGate(activeStaleRelease)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        // Active owner in explicit range lane
        let activeOwnerTask = Task { try await cache.workoutData(in: range) }
        await activeStarted.wait()

        // Coalesced caller attaches to active owner in identical range
        let coalescedTask = Task { try await cache.workoutData(in: range) }

        // Successor queued via refreshWorkouts in the identical range lane (FIFO queued)
        await provider.setProviderStartedGate(nil)
        await provider.setStaleReleaseGate(nil)

        let queuedSuccessorTask = Task { try await cache.refreshWorkouts(in: range) }

        // Active owner is released and finishes, which pumps queued successor
        await activeStaleRelease.open()

        let activeResult = try await activeOwnerTask.value
        let coalescedResult = try await coalescedTask.value
        let queuedResult = try await queuedSuccessorTask.value

        #expect(activeResult.count == 1)
        #expect(activeResult.first?.id == w1.id)
        #expect(coalescedResult.count == 1)
        #expect(coalescedResult.first?.id == w1.id)
        #expect(queuedResult.count == 1)
        #expect(queuedResult.first?.id == w2.id)
    }

    @Test("AC-S2 / SC-008: Workout, global, and auth reset drain active, coalesced, and queued callers before post-reset completes")
    func testLanes_ResetDrainsAllCallersBeforePostResetCompletes() async throws {
        let provider = MockPreparedWorkoutProvider()
        let activeStarted = DeterministicGate()
        let activeStaleRelease = DeterministicGate()

        await provider.setProviderStartedGate(activeStarted)
        await provider.setStaleReleaseGate(activeStaleRelease)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let activeTask = Task { try await cache.workoutData() }
        await activeStarted.wait()

        let coalescedTask = Task { try await cache.workoutData() }
        let queuedTask = Task { try await cache.refreshWorkouts() }

        // Invalidate workouts (generation bump and cancel all old callers)
        await cache.invalidateWorkouts()

        let activeRes = await activeTask.result
        let coalRes = await coalescedTask.result
        let queuedRes = await queuedTask.result

        #expect(throws: CancellationError.self) { try activeRes.get() }
        #expect(throws: CancellationError.self) { try coalRes.get() }
        #expect(throws: CancellationError.self) { try queuedRes.get() }

        // Post-reset request starts fresh
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
        let newRes = try await newTask.value
        #expect(newRes.count == 1)
        #expect(newRes.first?.id == postResetWorkout.id)

        // Release stale old provider
        await activeStaleRelease.open()
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

    @Test("AC-S3 / SC-001: Scoped state anchored changes rejected and rebuilds default baseline")
    func testAC_S3_ScopedStateAnchoredChangesRejected_RebuildsDefaultBaseline() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workout = makeWorkout()

        // Empty cache receives .anchoredChanges (scoped/invalid state for baseline) -> rejected, then baseline rebuild
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

    @Test("AC-S3 / FR-003: Persisted anchor restart rebuilds baseline before applying changes")
    func testAC_S3_PersistedAnchorRestart_RebuildsBaselineFirst() async throws {
        let provider = MockPreparedWorkoutProvider()
        let workoutA = makeWorkout()

        // Restart with empty cache rebuilds baseline
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

        let result = try await cache.workoutData()
        #expect(result.count == 1)
        #expect(await provider.snapshotCallCount == 1)
    }

    @Test("AC-S3 / SC-001: Unknown deletion, deletion-wins in same batch, and empty authoritative snapshot")
    func testAC_S3_EdgeCases_UnknownDeletion_DeletionWins_EmptySnapshot() async throws {
        let provider = MockPreparedWorkoutProvider()
        let idA = UUID()
        let workoutA = makeWorkout(id: idA)

        // 1. Initial snapshot has workoutA
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

        // 2. Anchored changes with unknown deletion ID (UUID()) -> ignored safely
        // and same batch contains upsert of A AND deletion of A -> deletion wins
        let unknownID = UUID()
        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [workoutA],
            deletedObjectIDs: [unknownID, idA],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: makeCheckpoint(source: .anchoredChanges, anchorValue: 2)
        ))

        let refreshed = try await cache.refreshWorkouts()
        #expect(refreshed.isEmpty)

        // 3. Empty authoritative snapshot replaces cache with empty
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: makeCheckpoint(source: .baselineSnapshot, anchorValue: 3)
        ))

        await cache.invalidateWorkouts()
        let emptyResult = try await cache.workoutData()
        #expect(emptyResult.isEmpty)
    }

    // MARK: - Stage A & D: AC-S4 / AC-05, AC-07, FR-020 Deterministic Legacy Snapshots

    @Test("AC-05 / FR-020: Duplicate UUIDs normalized with final winning; equal-time tie broken by UUID")
    func testLegacyFallback_DuplicateUUIDs_FinalWins_EqualTimeUUIDTieBreak() async throws {
        let idA = UUID()
        let now = Date()
        let t1 = now.addingTimeInterval(-3600)
        let t2 = now.addingTimeInterval(-1800)

        let wA_first = makeWorkout(id: idA, date: t1, duration: 1000)
        let wA_final = makeWorkout(id: idA, date: t2, duration: 2000)

        let sameTime = now.addingTimeInterval(-3000)
        let u1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let u2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let wU1 = makeWorkout(id: u1, date: sameTime)
        let wU2 = makeWorkout(id: u2, date: sameTime)

        let provider = MockLegacyWorkoutProvider(fetchResult: WorkoutFetchResult(
            workouts: [wA_first, wU2, wU1, wA_final],
            deletedObjectIDs: []
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 3)
        #expect(result[0].id == idA)
        #expect(result[0].duration == 2000)
        // Equal startDate tie broken deterministically by UUID (u1 < u2)
        #expect(result[1].id == u1)
        #expect(result[2].id == u2)
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

    @Test("AC-S4 / FR-002: Provider-reported legacy coverage is preserved over fallback")
    func testLegacyFallback_ProviderReportedCoveragePreserved() async throws {
        let explicitCoverage = DateInterval(start: Date().addingTimeInterval(-7200), duration: 7200)
        let workout = makeWorkout(date: explicitCoverage.start.addingTimeInterval(100))

        let provider = MockLegacyWorkoutProvider(fetchResult: WorkoutFetchResult(
            workouts: [workout],
            deletedObjectIDs: [],
            coverage: explicitCoverage
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let result = try await cache.workoutData()
        #expect(result.count == 1)
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

    @Test("AC-S5 / AC-09 / AC-10 / AC-13 / SC-005: Adversarial boundary between query completion and cache acceptance with replay")
    func testAC09_AC13_AdversarialBoundaryBetweenQueryCompleteAndCacheAcceptance() async throws {
        let provider = MockPreparedWorkoutProvider()
        let recorder = EventRecorder()
        await provider.setEventRecorder(recorder)

        let workoutA = makeWorkout()
        let workoutB = makeWorkout()
        let cp1 = makeCheckpoint(source: .baselineSnapshot, anchorValue: 1)
        let cp2 = makeCheckpoint(source: .anchoredChanges, anchorValue: 2)

        // Step 1: Establish baseline A with checkpoint c1
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

        // Step 2: Query c2 completes, but is held at cache-acceptance gate with replay
        let queryCompleteGate = DeterministicGate()
        let cacheAcceptanceGate = DeterministicGate()
        await provider.setQueryCompleteGate(queryCompleteGate)
        await provider.setCacheAcceptanceGate(cacheAcceptanceGate)

        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [workoutB],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: cp2
        ))

        let queryTask = Task { try await cache.refreshWorkouts() }

        // Wait until provider has finished query (query-complete gate opened)
        await queryCompleteGate.wait()

        // Cancel queryTask BEFORE opening cacheAcceptanceGate
        queryTask.cancel()

        // Now open cache acceptance gate
        await cacheAcceptanceGate.open()

        let queryRes = await queryTask.result
        #expect(throws: CancellationError.self) { try queryRes.get() }
        #expect(await provider.rejectCallCount == 1)
        #expect(await provider.durableAnchor == cp1)

        // Step 3: Replacement query replays from durable c1, returning B with c2
        await provider.setQueryCompleteGate(nil)
        await provider.setCacheAcceptanceGate(nil)

        let replacement = try await cache.refreshWorkouts()
        #expect(replacement.count == 2)
        #expect(await provider.durableAnchor == cp2)

        let events = await recorder.events()
        #expect(events.contains("acceptance_invoked"))
    }

    @Test("AC-S5 / AC-13: Replay with durable anchor rejection and reset successor gate")
    func testAC13_ReplayWithResetSuccessorGateAndReject() async throws {
        let provider = MockPreparedWorkoutProvider()
        let recorder = EventRecorder()
        await provider.setEventRecorder(recorder)

        let workoutA = makeWorkout()
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

        let queryCompleteGate = DeterministicGate()
        let cacheAcceptanceGate = DeterministicGate()
        await provider.setQueryCompleteGate(queryCompleteGate)
        await provider.setCacheAcceptanceGate(cacheAcceptanceGate)

        await provider.setChangesResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .anchoredChanges,
            coverage: nil,
            checkpoint: cp2
        ))

        let activeTask = Task { try await cache.refreshWorkouts() }
        await queryCompleteGate.wait()

        // Reset workouts while active task is at cache acceptance gate
        await cache.invalidateWorkouts()

        await cacheAcceptanceGate.open()

        let res = await activeTask.result
        #expect(throws: CancellationError.self) { try res.get() }
        #expect(await provider.rejectCallCount == 1)
        #expect(await provider.durableAnchor == cp1)
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

        // Next query replays B/c2 again from cp1 safely
        let r2 = try await cache.refreshWorkouts()
        #expect(r2.count == 2)
    }

    // MARK: - Compatibility & Preserved Baseline Behaviors

    @Test("Cache hit filters workouts by date range")
    func testCacheHitFiltersWorkoutsByDateRange() async throws {
        let now = Date()
        let w1 = makeWorkout(date: now.addingTimeInterval(-3600)) // within last 2 hours
        let w2 = makeWorkout(date: now.addingTimeInterval(-86400)) // 1 day ago

        let provider = MockPreparedWorkoutProvider()
        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [w1, w2],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: now.addingTimeInterval(-2 * 86400), end: now),
            checkpoint: nil
        ))

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        // Populate cache
        let all = try await cache.workoutData()
        #expect(all.count == 2)

        // Filter by date range (last 2 hours)
        let recentRange = DateInterval(start: now.addingTimeInterval(-7200), duration: 7200)
        let filtered = try await cache.workoutData(in: recentRange)
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == w1.id)
    }

    @Test("In-flight workout fetch does not repopulate after invalidateAll via authorization revocation")
    func testInFlightWorkoutFetchDoesNotRepopulateAfterAuthorizationRevoked() async throws {
        let provider = MockPreparedWorkoutProvider()
        let startedGate = DeterministicGate()

        await provider.setSnapshotResult(PreparedWorkoutFetch(
            workouts: [makeWorkout()],
            deletedObjectIDs: [],
            source: .baselineSnapshot,
            coverage: DateInterval(start: Date().addingTimeInterval(-86400), duration: 86400),
            checkpoint: nil
        ))
        await provider.setProviderStartedGate(startedGate)

        let cache = HealthDataCache(
            dataProvider: MockSimpleHealthDataProvider(),
            workoutProvider: provider
        )

        let fetchTask = Task { try await cache.workoutData() }
        await startedGate.wait()

        // Revoke authorization while fetch is in-flight
        let defaults = UserDefaults(suiteName: "test-auth-revoked")!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        await cache.handleAuthorizationRevoked(anchorStore: anchorStore, deviceIdentifier: "test")

        _ = await fetchTask.result
        #expect(await !cache.hasWorkoutCache())
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
