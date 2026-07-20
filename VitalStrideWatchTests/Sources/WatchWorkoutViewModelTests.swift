// swiftlint:disable file_length type_body_length
import HealthKitService
import XCTest

@testable import VitalStrideWatch_Watch_App

// MARK: - WatchWorkoutViewModelTests
//
// Focused unit tests for the MY-1290 `WatchWorkoutViewModel` reducers
// (HR + connection transitions, snapshot/config application) and the
// MY-1292 complete-set sender seam.
//
// Strategy:
//   * A fake `WorkoutSessionManaging` (`FakeWorkoutSessionManager`) hands
//     out `AsyncStream`s whose `Continuation` handles are exposed to the
//     test so we can `.yield` values on demand.
//   * A recording `WatchSetCompletedSending` (`RecordingSender`) captures
//     `send(_:)` calls and can be primed to throw.
//   * All tests are `@MainActor` because the VM is main-actor isolated.
//   * `waitForNext(_:)` is a bounded-poll helper: it drives the runloop
//     via short sleeps until an expected condition holds or a deadline
//     is reached. Stream delivery to the VM's child tasks is asynchronous,
//     so we cannot assert immediately after `.yield(...)`.

@MainActor
final class WatchWorkoutViewModelTests: XCTestCase {
    // MARK: Fixtures

    private var manager: FakeWorkoutSessionManager!
    private var sender: RecordingSender!
    private var vm: WatchWorkoutViewModel!
    private var fixedClock: Date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        manager = FakeWorkoutSessionManager()
        sender = RecordingSender()
        let capturedClock = fixedClock
        vm = WatchWorkoutViewModel(
            manager: manager,
            sender: sender,
            clock: { capturedClock }
        )
        vm.start()
        // Give the VM's child tasks a beat to attach subscribers so
        // subsequent `.yield` calls have receivers.
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    override func tearDown() async throws {
        vm.stop()
        manager.finishAll()
        vm = nil
        sender = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: HR state transitions (spec §6a)

    func test_connection_reachable_beforeHR_yieldsConnectedNoData() async throws {
        manager.connectionContinuation?.yield(.reachable)
        try await waitForNext { self.vm.display.hr == .connectedNoData }
        XCTAssertEqual(vm.display.hr, .connectedNoData)
    }

    func test_connection_unreachable_yieldsNotConnected_dropsBpm() async throws {
        // Prime with a live HR sample so we can watch it drop on unreach.
        manager.localHRContinuation?.yield(makeHR(bpm: 130))
        try await waitForNext { self.vm.display.hr == .connected(bpm: 130, zone: nil) }

        manager.connectionContinuation?.yield(.unreachable)
        try await waitForNext { self.vm.display.hr == .notConnected }
        XCTAssertEqual(vm.display.hr, .notConnected)
    }

    func test_connection_reachableAfterLiveSample_keepsLastGoodHR() async throws {
        manager.localHRContinuation?.yield(makeHR(bpm: 128))
        try await waitForNext { self.vm.display.hr == .connected(bpm: 128, zone: nil) }

        manager.connectionContinuation?.yield(.reachable)
        // Give the connection reducer time to (potentially) rewrite HR.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.display.hr, .connected(bpm: 128, zone: nil))
    }

    func test_localHR_recomputesRunningAvgPeak() async throws {
        // (80 + 100 + 120) / 3 = 100; peak = 120.
        manager.localHRContinuation?.yield(makeHR(bpm: 80))
        try await waitForNext { self.vm.display.averageBPM == 80 }
        manager.localHRContinuation?.yield(makeHR(bpm: 100))
        try await waitForNext { self.vm.display.averageBPM == 90 }
        manager.localHRContinuation?.yield(makeHR(bpm: 120))
        try await waitForNext { self.vm.display.averageBPM == 100 }
        XCTAssertEqual(vm.display.peakBPM, 120)
    }

    func test_localHR_rejectsImplausiblePayload() async throws {
        // isPhysiologicallyPlausible: 30 <= bpm <= 220. Ship a 500 —
        // reducer should drop the sample entirely.
        manager.localHRContinuation?.yield(makeHR(bpm: 500))
        // Wait a moment; nothing should update.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(vm.display.averageBPM)
        XCTAssertNil(vm.display.peakBPM)
        XCTAssertEqual(vm.display.hr, .notConnected)
    }

    // MARK: Config + snapshot reducers

    func test_configReducer_appliesLatestConfig() async throws {
        let cfg = WatchScreenConfig(
            preset: .hrFocus,
            enabledModules: [.heartRate, .primaryAction, .clock],
            updatedAt: fixedClock
        )
        manager.configContinuation?.yield(cfg)
        try await waitForNext { self.vm.display.config == cfg }
        XCTAssertEqual(vm.display.config, cfg)
    }

    func test_snapshotReducer_appliesSnapshotAndRecordsWorkoutID()
        async throws
    {
        let snapshot = makeSnapshot()
        manager.stateContinuation?.yield(snapshot)
        try await waitForNext { self.vm.display.elapsedSeconds == snapshot.elapsedSeconds }
        XCTAssertEqual(vm.display.progress?.completedSetCount, 1)
        XCTAssertEqual(vm.display.progress?.totalSetCount, 3)
        XCTAssertEqual(vm.display.nextSet?.id, snapshot.sets[1].id)
    }

    // MARK: Complete-set sender seam (MY-1292 §5)

    func test_sendCompleteSet_guardsWhenNoWorkout() {
        // No snapshot pushed yet → currentWorkoutID is nil → sender
        // must not fire.
        vm.sendCompleteSet(actualReps: 8)
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func test_sendCompleteSet_guardsWhenNoNextSet() async throws {
        // Snapshot with all sets completed → nextSet is nil → sender
        // must not fire.
        let completed = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 0,
            targetReps: 5,
            targetWeightKg: nil,
            isCompleted: true
        )
        let done = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Overhead Press",
            sets: [completed],
            elapsedSeconds: 60,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 1, totalSetCount: 1),
            updatedAt: fixedClock
        )
        manager.stateContinuation?.yield(done)
        try await waitForNext { self.vm.display.elapsedSeconds != nil }

        vm.sendCompleteSet(actualReps: nil)
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func test_sendCompleteSet_happyPath_sendsEventWithClockTimestamp() async throws {
        let snapshot = makeSnapshot()
        manager.stateContinuation?.yield(snapshot)
        try await waitForNext { self.vm.display.nextSet?.id == snapshot.sets[1].id }

        vm.sendCompleteSet(actualReps: 9)

        XCTAssertEqual(sender.sent.count, 1)
        let event = try XCTUnwrap(sender.sent.first)
        XCTAssertEqual(event.workoutID, snapshot.workoutID)
        XCTAssertEqual(event.setID, snapshot.sets[1].id)
        XCTAssertEqual(event.actualReps, 9)
        XCTAssertEqual(event.completedAt, fixedClock)
    }

    func test_sendCompleteSet_swallowsSendError_noRethrow() async throws {
        sender.errorToThrow = WatchConnectivityBridgeError.notReachable
        let snapshot = makeSnapshot()
        manager.stateContinuation?.yield(snapshot)
        try await waitForNext { self.vm.display.nextSet?.id == snapshot.sets[1].id }

        // Should NOT throw or crash; error is logged internally.
        vm.sendCompleteSet(actualReps: nil)

        // Sender was still attempted exactly once — sent count is 0
        // because the recording sender rethrows before recording.
        XCTAssertEqual(sender.attemptCount, 1)
        XCTAssertTrue(sender.sent.isEmpty)
    }

    // MARK: Lifecycle

    func test_stopIsIdempotent_andStartIsIdempotent() {
        // Second stop should not throw or cancel again.
        vm.stop()
        vm.stop()
        // Second start after stop is allowed and re-attaches subscribers.
        vm.start()
        vm.start()
        // Just ensure no crash — real behaviour is covered by other tests.
    }

    func test_reset_returnsDisplayToInitial() async throws {
        manager.stateContinuation?.yield(makeSnapshot())
        try await waitForNext { self.vm.display.elapsedSeconds != nil }
        vm.reset()
        XCTAssertEqual(vm.display, .initial)
    }

    // MARK: - Helpers

    private func makeHR(bpm: Double) -> LiveHeartRatePayload {
        LiveHeartRatePayload(
            sampleType: .heartRate,
            bpm: bpm,
            timestamp: fixedClock,
            sourceName: nil
        )
    }

    private func makeSnapshot() -> WorkoutStateSnapshot {
        let setA = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 0,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: true
        )
        let setB = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 1,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: false
        )
        let setC = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 2,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: false
        )
        return WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Back Squat",
            sets: [setA, setB, setC],
            elapsedSeconds: 42,
            progress: WorkoutStateSnapshot.Progress(
                completedSetCount: 1,
                totalSetCount: 3
            ),
            updatedAt: fixedClock
        )
    }

    /// Bounded-poll helper: yield to the runloop in short bursts until
    /// the predicate holds or the deadline elapses. Async stream delivery
    /// to the VM's child tasks is not synchronous, so we need this shape
    /// instead of a naked assertion after `.yield(...)`.
    private func waitForNext(
        timeout: TimeInterval = 2.0,
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("waitForNext timed out after \(timeout)s", file: file, line: line)
    }
}

// MARK: - Fake collaborators

/// In-memory `WorkoutSessionManaging` that exposes each stream's
/// continuation so tests can drive values on demand. The `Sendable`
/// storage uses locked slots so both the test (main actor) and the VM's
/// child tasks can access continuations safely.
final class FakeWorkoutSessionManager: WorkoutSessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _stateContinuation: AsyncStream<WorkoutStateSnapshot>.Continuation?
    private var _configContinuation: AsyncStream<WatchScreenConfig>.Continuation?
    private var _localHRContinuation: AsyncStream<LiveHeartRatePayload>.Continuation?
    private var _connectionContinuation: AsyncStream<WatchConnectionState>.Continuation?

    var stateContinuation: AsyncStream<WorkoutStateSnapshot>.Continuation? {
        lock.lock(); defer { lock.unlock() }
        return _stateContinuation
    }

    var configContinuation: AsyncStream<WatchScreenConfig>.Continuation? {
        lock.lock(); defer { lock.unlock() }
        return _configContinuation
    }

    var localHRContinuation: AsyncStream<LiveHeartRatePayload>.Continuation? {
        lock.lock(); defer { lock.unlock() }
        return _localHRContinuation
    }

    var connectionContinuation: AsyncStream<WatchConnectionState>.Continuation? {
        lock.lock(); defer { lock.unlock() }
        return _connectionContinuation
    }

    func startSession() async throws {}
    @discardableResult
    func endSession(save _: Bool) async -> String? { nil }

    func observeInboundWorkoutState() async -> AsyncStream<WorkoutStateSnapshot> {
        AsyncStream { continuation in
            self.lock.lock()
            self._stateContinuation = continuation
            self.lock.unlock()
        }
    }

    func observeInboundWatchScreenConfig() async -> AsyncStream<WatchScreenConfig> {
        AsyncStream { continuation in
            self.lock.lock()
            self._configContinuation = continuation
            self.lock.unlock()
        }
    }

    func observeLocalHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        AsyncStream { continuation in
            self.lock.lock()
            self._localHRContinuation = continuation
            self.lock.unlock()
        }
    }

    func observeConnectionState() async -> AsyncStream<WatchConnectionState> {
        AsyncStream { continuation in
            self.lock.lock()
            self._connectionContinuation = continuation
            self.lock.unlock()
        }
    }

    func observeLiveWorkoutHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        AsyncStream { $0.finish() }
    }

    func observeSetCompleted() async -> AsyncStream<SetCompletedEvent> {
        AsyncStream { $0.finish() }
    }

    func updateWorkoutState(_: WorkoutStateSnapshot) async {}
    func updateWatchScreenConfig(_: WatchScreenConfig) async {}

    func finishAll() {
        lock.lock()
        _stateContinuation?.finish()
        _configContinuation?.finish()
        _localHRContinuation?.finish()
        _connectionContinuation?.finish()
        lock.unlock()
    }
}

/// Records every `send(_:)` call. Set `errorToThrow` before invoking to
/// simulate a transport failure — the recorder rethrows immediately and
/// leaves `sent` unchanged so tests can distinguish "attempted" from
/// "delivered" (see `attemptCount`).
final class RecordingSender: WatchSetCompletedSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [SetCompletedEvent] = []
    private var _attemptCount = 0
    var errorToThrow: (any Error)?

    var sent: [SetCompletedEvent] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    var attemptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _attemptCount
    }

    func send(_ event: SetCompletedEvent) throws {
        lock.lock()
        _attemptCount += 1
        let err = errorToThrow
        if err == nil {
            _sent.append(event)
        }
        lock.unlock()
        if let err {
            throw err
        }
    }
}
