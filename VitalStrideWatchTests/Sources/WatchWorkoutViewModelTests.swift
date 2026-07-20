// swiftlint:disable file_length type_body_length
import HealthKitService
import XCTest
import os

@testable import VitalStrideWatch_Watch_App

// MARK: - WatchWorkoutViewModelTests
//
// Focused unit tests for the MY-1290 `WatchWorkoutViewModel` reducers
// (HR + connection transitions, snapshot/config application) and the
// MY-1292 complete-set sender seam.
//
// Strict-concurrency design (§Constitution II — Swift 6):
//   * `FakeWorkoutSessionManager` is an `actor` — its mutable
//     continuation storage is protected by actor isolation, not
//     `@unchecked Sendable`. The protocol methods are already `async`
//     so an actor satisfies them naturally.
//   * `RecordingSender` uses `OSAllocatedUnfairLock<State>` (available
//     watchOS 10+) to satisfy `Sendable` without unchecked escapes.
//     `send(_:)` is a synchronous protocol requirement so an actor
//     cannot satisfy it directly.
//   * Setup does NOT sleep for a fixed budget. `manager` publishes
//     `awaitAllSubscribersReady()` — a `CheckedContinuation` that
//     resolves when the VM's four child tasks have each called their
//     `observe*` method, so subsequent `yieldX` calls are guaranteed
//     to have a live continuation. No slow-CI silent-miss window.
//   * "Wait for a value" is done via `vm.$display.values` async
//     iteration (deterministic — the loop wakes on every publish, not
//     on a wall-clock poll). A single racing sleep provides a hard
//     timeout so a mis-wired predicate still surfaces as a failure
//     instead of a hang.
//   * "Wait for the ABSENCE of an event" (e.g. implausible payloads
//     must be silently dropped) is proven by yielding a follow-up
//     valid event and asserting only the follow-up landed — no
//     fixed-time gamble.

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
        // Deterministic readiness: the actor signals when the VM's four
        // stream subscribers have attached, so subsequent yields are
        // guaranteed to be delivered. Bounded so a wiring regression
        // fails loudly (2s) instead of hanging.
        //
        // `awaitAllSubscribersReady()` is cancellation-aware — the
        // sibling deadline task in `withTimeout` cancels the enclosing
        // task group, and the readiness continuation throws
        // `CancellationError` so the group actually returns instead of
        // waiting forever on a stranded `CheckedContinuation`.
        try await withTimeout(seconds: 2.0) { [manager] in
            guard let manager else { return }
            try await manager.awaitAllSubscribersReady()
        }
    }

    override func tearDown() async throws {
        vm.stop()
        await manager.finishAll()
        vm = nil
        sender = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: HR state transitions (spec §6a)

    func test_connection_reachable_beforeHR_yieldsConnectedNoData() async throws {
        await manager.yieldConnection(.reachable)
        try await waitForDisplay { $0.hr == .connectedNoData }
        XCTAssertEqual(vm.display.hr, .connectedNoData)
    }

    func test_connection_unreachable_yieldsNotConnected_dropsBpm() async throws {
        // Prime with a live HR sample so we can watch it drop on unreach.
        await manager.yieldLocalHR(makeHR(bpm: 130))
        try await waitForDisplay { $0.hr == .connected(bpm: 130, zone: nil) }

        await manager.yieldConnection(.unreachable)
        try await waitForDisplay { $0.hr == .notConnected }
        XCTAssertEqual(vm.display.hr, .notConnected)
    }

    func test_connection_reachableAfterLiveSample_keepsLastGoodHR() async throws {
        await manager.yieldLocalHR(makeHR(bpm: 128))
        try await waitForDisplay { $0.hr == .connected(bpm: 128, zone: nil) }

        await manager.yieldConnection(.reachable)
        // Wait for the connection reducer to actually run (it writes
        // `display.connection`), then assert HR was NOT clobbered.
        // No fixed-time sleep — we key off a real state transition.
        try await waitForDisplay { $0.connection == .reachable }
        XCTAssertEqual(vm.display.hr, .connected(bpm: 128, zone: nil))
    }

    func test_localHR_recomputesRunningAvgPeak() async throws {
        // (80 + 100 + 120) / 3 = 100; peak = 120.
        await manager.yieldLocalHR(makeHR(bpm: 80))
        try await waitForDisplay { $0.averageBPM == 80 }
        await manager.yieldLocalHR(makeHR(bpm: 100))
        try await waitForDisplay { $0.averageBPM == 90 }
        await manager.yieldLocalHR(makeHR(bpm: 120))
        try await waitForDisplay { $0.averageBPM == 100 }
        XCTAssertEqual(vm.display.peakBPM, 120)
    }

    func test_localHR_rejectsImplausiblePayload() async throws {
        // isPhysiologicallyPlausible: 30 <= bpm <= 220. Send an
        // out-of-range value first, then a valid one. AsyncStream
        // guarantees FIFO delivery, so once the valid follow-up lands
        // we know the reducer already processed (and dropped) the
        // implausible one. No fixed wall-clock wait.
        await manager.yieldLocalHR(makeHR(bpm: 500))
        await manager.yieldLocalHR(makeHR(bpm: 80))
        try await waitForDisplay { $0.averageBPM == 80 }
        XCTAssertEqual(vm.display.averageBPM, 80)
        XCTAssertEqual(vm.display.peakBPM, 80)
        XCTAssertEqual(vm.display.hr, .connected(bpm: 80, zone: nil))
    }

    // MARK: Config + snapshot reducers

    func test_configReducer_appliesLatestConfig() async throws {
        let cfg = WatchScreenConfig(
            preset: .hrFocus,
            enabledModules: [.heartRate, .primaryAction, .clock],
            updatedAt: fixedClock
        )
        await manager.yieldConfig(cfg)
        try await waitForDisplay { $0.config == cfg }
        XCTAssertEqual(vm.display.config, cfg)
    }

    func test_snapshotReducer_appliesSnapshotAndRecordsWorkoutID()
        async throws
    {
        let snapshot = makeSnapshot()
        await manager.yieldState(snapshot)
        try await waitForDisplay { $0.elapsedSeconds == snapshot.elapsedSeconds }
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
        await manager.yieldState(done)
        try await waitForDisplay { $0.elapsedSeconds != nil }

        vm.sendCompleteSet(actualReps: nil)
        XCTAssertTrue(sender.sent.isEmpty)
    }

    func test_sendCompleteSet_happyPath_sendsEventWithClockTimestamp() async throws {
        let snapshot = makeSnapshot()
        await manager.yieldState(snapshot)
        try await waitForDisplay { $0.nextSet?.id == snapshot.sets[1].id }

        vm.sendCompleteSet(actualReps: 9)

        XCTAssertEqual(sender.sent.count, 1)
        let event = try XCTUnwrap(sender.sent.first)
        XCTAssertEqual(event.workoutID, snapshot.workoutID)
        XCTAssertEqual(event.setID, snapshot.sets[1].id)
        XCTAssertEqual(event.actualReps, 9)
        XCTAssertEqual(event.completedAt, fixedClock)
    }

    func test_sendCompleteSet_swallowsSendError_noRethrow() async throws {
        sender.primeError(WatchConnectivityBridgeError.notReachable)
        let snapshot = makeSnapshot()
        await manager.yieldState(snapshot)
        try await waitForDisplay { $0.nextSet?.id == snapshot.sets[1].id }

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
        await manager.yieldState(makeSnapshot())
        try await waitForDisplay { $0.elapsedSeconds != nil }
        vm.reset()
        XCTAssertEqual(vm.display, .initial)
    }

    // MARK: Readiness-timeout regression (MY-1300)

    /// Regression: before MY-1300 `awaitAllSubscribersReady()` awaited a
    /// non-cancellation-aware `CheckedContinuation`, so cancelling the
    /// caller (as `withTimeout`'s sibling deadline branch does via
    /// `group.cancelAll()`) left the continuation stranded and hung the
    /// enclosing task group forever. This test cancels the caller task
    /// directly and asserts that (a) the wait DOES return (bounded
    /// elapsed time proves cancellation escapes), and (b) it surfaces
    /// as `CancellationError` from the throwing continuation — i.e. the
    /// cancel path resumed the continuation exactly once with the
    /// expected error type.
    func test_awaitAllSubscribersReady_isCancellationAware() async throws {
        let orphan = FakeWorkoutSessionManager()
        let start = Date()
        let task = Task { try await orphan.awaitAllSubscribersReady() }
        // Small delay so the task actually suspends inside the checked
        // continuation before we cancel — otherwise we'd only be
        // exercising the pre-suspension re-check path.
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do {
            try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "cancellation did not propagate through the continuation")
    }

    /// Regression: even under an ATTACH-then-CANCEL race the checked
    /// continuation must be resumed exactly once. We prime a manager
    /// with all four subscribers already attached BEFORE the waiter
    /// suspends — the re-check inside `awaitAllSubscribersReady()`
    /// resumes synchronously, and a subsequent cancel must be a no-op
    /// rather than a second resume (which would trap the checked
    /// runtime). Running many iterations amplifies any latent race.
    func test_awaitAllSubscribersReady_singleShotUnderRace() async throws {
        for _ in 0..<64 {
            let m = FakeWorkoutSessionManager()
            _ = await m.observeInboundWorkoutState()
            _ = await m.observeInboundWatchScreenConfig()
            _ = await m.observeLocalHeartRate()
            _ = await m.observeConnectionState()

            let task = Task { try await m.awaitAllSubscribersReady() }
            task.cancel()
            do {
                try await task.value
            } catch is CancellationError {
                // acceptable — cancel may have beaten the fast-path
            }
        }
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

    /// Deterministic wait: iterate `@Published`'s async publisher until
    /// the predicate holds. No wall-clock polling; the loop wakes on
    /// each real publish. A hard-timeout task cancels the observing
    /// task so a broken predicate surfaces as `XCTFail`, not a hang.
    ///
    /// Uses a `Task` + `Task.sleep` deadline instead of a mixed-
    /// isolation task group — the latter tripped a Swift 6 region-based
    /// isolation checker bug ("pattern that the region-based isolation
    /// checker does not understand how to check") when a `@MainActor`
    /// child was combined with a non-isolated deadline child.
    private func waitForDisplay(
        timeout: TimeInterval = 2.0,
        _ predicate: @escaping @MainActor (WatchWorkoutDisplayState) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        if predicate(vm.display) { return }
        let currentVM = try XCTUnwrap(vm, file: file, line: line)
        let observer = Task { @MainActor in
            var matched = false
            for await display in currentVM.$display.values {
                if Task.isCancelled { break }
                if predicate(display) { matched = true; break }
            }
            return matched
        }
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            observer.cancel()
        }
        let matched = await observer.value
        deadline.cancel()
        if !matched {
            XCTFail(
                "waitForDisplay timed out after \(timeout)s",
                file: file,
                line: line
            )
        }
    }

    /// Race `operation` against a hard deadline. Used only for actor
    /// awaits in setup so a wiring regression cannot hang the suite.
    ///
    /// `operation` must itself honour cancellation — if it awaits a
    /// bare `CheckedContinuation`, the deadline branch will win the
    /// race but the operation branch will remain suspended forever,
    /// hanging the task group. See
    /// `FakeWorkoutSessionManager.awaitAllSubscribersReady()` for the
    /// cancellation-aware pattern used here (throwing continuation
    /// resumed on `withTaskCancellationHandler`'s cancel branch).
    private func withTimeout(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let ok: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await operation()
                    return true
                } catch {
                    // Cancellation (or any thrown error) is treated as
                    // "did not complete on its own", but critically the
                    // task RETURNS so the group can make progress.
                    return false
                }
            }
            group.addTask {
                (try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))) ?? ()
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if !ok {
            XCTFail(
                "withTimeout: operation exceeded \(seconds)s",
                file: file,
                line: line
            )
        }
    }
}

// MARK: - Fake collaborators

/// Actor-isolated fake `WorkoutSessionManaging`. All mutable stream
/// state lives inside the actor; test drivers yield through `yieldX`
/// methods that hop into the actor's serial executor, so there is no
/// data race and no need for `@unchecked Sendable`.
///
/// Test drivers must `await manager.awaitAllSubscribersReady()` before
/// any `yieldX` — the actor tracks how many of the VM's four `observe*`
/// child tasks have attached and resumes the waiter once all four are
/// live. This replaces the previous fixed-time setup sleep with a real
/// happens-before signal.
final actor FakeWorkoutSessionManager: WorkoutSessionManaging {
    private var stateCont: AsyncStream<WorkoutStateSnapshot>.Continuation?
    private var configCont: AsyncStream<WatchScreenConfig>.Continuation?
    private var localHRCont: AsyncStream<LiveHeartRatePayload>.Continuation?
    private var connectionCont: AsyncStream<WatchConnectionState>.Continuation?

    private static let expectedSubscribers = 4
    private var attachedCount = 0
    /// Holds the throwing continuation for exactly one waiter. Setting
    /// this back to `nil` is the single-shot guard: both the ready
    /// branch (`markSubscriberAttached`) and the cancel branch
    /// (installed by `withTaskCancellationHandler`) atomically clear it
    /// on the actor's serial executor before calling `resume`, so a
    /// `CheckedContinuation` can never be resumed twice — even if
    /// cancellation and the final subscriber attach race.
    private var readyContinuation: CheckedContinuation<Void, any Error>?

    // MARK: Test-driver API

    /// Suspend until the VM has attached all four stream subscribers.
    /// Idempotent: returns immediately if the fan-out is already live.
    ///
    /// Cancellation-aware: if the caller's task is cancelled (e.g.
    /// because a sibling deadline task in `withTimeout` won the race
    /// and cancelled the enclosing task group), the continuation is
    /// resumed with `CancellationError` so the group can actually
    /// return instead of stranding a suspended waiter. Single-shot by
    /// construction — both the success and cancel paths clear
    /// `readyContinuation` before resuming, so the checked continuation
    /// runtime cannot observe a double-resume even if the final
    /// subscriber attaches at the same instant cancellation fires.
    func awaitAllSubscribersReady() async throws {
        if attachedCount >= Self.expectedSubscribers { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Re-check on the actor after suspension: a rapid
                // attach that beat us here would otherwise leave the
                // continuation stranded until the next attach.
                if attachedCount >= Self.expectedSubscribers {
                    continuation.resume()
                    return
                }
                // Assert single-waiter contract; overwriting a live
                // continuation would leak it (never resumed) and trap
                // the checked-continuation runtime later.
                assert(readyContinuation == nil, "awaitAllSubscribersReady is single-waiter")
                readyContinuation = continuation
            }
        } onCancel: {
            // Hop back onto the actor so the take-and-resume is a
            // single serial step relative to `markSubscriberAttached`.
            Task { await self.cancelReadyWait() }
        }
    }

    private func cancelReadyWait() {
        guard let cont = readyContinuation else { return }
        readyContinuation = nil
        cont.resume(throwing: CancellationError())
    }

    func yieldState(_ snapshot: WorkoutStateSnapshot) {
        guard let stateCont else {
            preconditionFailure("yieldState called before state subscriber attached")
        }
        stateCont.yield(snapshot)
    }

    func yieldConfig(_ config: WatchScreenConfig) {
        guard let configCont else {
            preconditionFailure("yieldConfig called before config subscriber attached")
        }
        configCont.yield(config)
    }

    func yieldLocalHR(_ payload: LiveHeartRatePayload) {
        guard let localHRCont else {
            preconditionFailure("yieldLocalHR called before localHR subscriber attached")
        }
        localHRCont.yield(payload)
    }

    func yieldConnection(_ state: WatchConnectionState) {
        guard let connectionCont else {
            preconditionFailure("yieldConnection called before connection subscriber attached")
        }
        connectionCont.yield(state)
    }

    func finishAll() {
        stateCont?.finish()
        configCont?.finish()
        localHRCont?.finish()
        connectionCont?.finish()
    }

    // MARK: WorkoutSessionManaging

    func startSession() async throws {}

    @discardableResult
    func endSession(save _: Bool) async -> String? { nil }

    func observeInboundWorkoutState() async -> AsyncStream<WorkoutStateSnapshot> {
        let (stream, continuation) = AsyncStream<WorkoutStateSnapshot>.makeStream()
        stateCont = continuation
        markSubscriberAttached()
        return stream
    }

    func observeInboundWatchScreenConfig() async -> AsyncStream<WatchScreenConfig> {
        let (stream, continuation) = AsyncStream<WatchScreenConfig>.makeStream()
        configCont = continuation
        markSubscriberAttached()
        return stream
    }

    func observeLocalHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        let (stream, continuation) = AsyncStream<LiveHeartRatePayload>.makeStream()
        localHRCont = continuation
        markSubscriberAttached()
        return stream
    }

    func observeConnectionState() async -> AsyncStream<WatchConnectionState> {
        let (stream, continuation) = AsyncStream<WatchConnectionState>.makeStream()
        connectionCont = continuation
        markSubscriberAttached()
        return stream
    }

    func observeLiveWorkoutHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        AsyncStream { $0.finish() }
    }

    func observeSetCompleted() async -> AsyncStream<SetCompletedEvent> {
        AsyncStream { $0.finish() }
    }

    func updateWorkoutState(_: WorkoutStateSnapshot) async {}
    func updateWatchScreenConfig(_: WatchScreenConfig) async {}

    // MARK: Internals

    private func markSubscriberAttached() {
        attachedCount += 1
        guard attachedCount >= Self.expectedSubscribers,
              let cont = readyContinuation else { return }
        // Single-shot: clear BEFORE resume so a concurrent cancel path
        // can't observe a live continuation and try to resume it again.
        readyContinuation = nil
        cont.resume()
    }
}

/// Records every `send(_:)` call. Set an error via `primeError(_:)`
/// before invoking to simulate a transport failure — the recorder
/// rethrows immediately and leaves `sent` unchanged so tests can
/// distinguish "attempted" from "delivered" (see `attemptCount`).
///
/// State is protected by `OSAllocatedUnfairLock<State>` (watchOS 10+)
/// so the class is `Sendable` without `@unchecked`. `send(_:)` is a
/// synchronous protocol requirement, so an actor cannot satisfy it —
/// the lock is the strict-concurrency-safe alternative.
final class RecordingSender: WatchSetCompletedSending {
    private struct State: Sendable {
        var sent: [SetCompletedEvent] = []
        var attemptCount: Int = 0
        var errorToThrow: (any Error & Sendable)?
    }

    private let storage = OSAllocatedUnfairLock<State>(initialState: State())

    var sent: [SetCompletedEvent] {
        storage.withLock { $0.sent }
    }

    var attemptCount: Int {
        storage.withLock { $0.attemptCount }
    }

    func primeError(_ error: (any Error & Sendable)?) {
        storage.withLock { $0.errorToThrow = error }
    }

    func send(_ event: SetCompletedEvent) throws {
        let error: (any Error & Sendable)? = storage.withLock { state in
            state.attemptCount += 1
            let err = state.errorToThrow
            if err == nil {
                state.sent.append(event)
            }
            return err
        }
        if let error {
            throw error
        }
    }
}
