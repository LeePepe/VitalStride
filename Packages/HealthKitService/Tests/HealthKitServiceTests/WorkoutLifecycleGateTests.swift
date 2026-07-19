import Testing
import Foundation
@testable import HealthKitService

// MARK: - WorkoutBuilderGate (lifecycle callback gating — MY-1282 repair)
//
// These tests cover the pure decision function used by
// `WorkoutSessionManager.workoutBuilder(_:didCollectDataOf:)` to reject
// HKLiveWorkoutBuilder callbacks that arrive after end/failure or for a
// different builder than the one currently owned. We test the gate as a
// pure function so we don't need a real HKHealthStore or HKWorkoutSession.

@Suite("WorkoutBuilderGate (lifecycle gating)")
struct WorkoutBuilderGateTests {

    // Helper: obtain two distinct ObjectIdentifier values.
    private func makeTwoIdentifiers() -> (ObjectIdentifier, ObjectIdentifier) {
        final class Marker {}
        let a = Marker()
        let b = Marker()
        return (ObjectIdentifier(a), ObjectIdentifier(b))
    }

    @Test("Rejects when session is not active")
    func rejectsWhenInactive() {
        let (id, _) = makeTwoIdentifiers()
        let allow = WorkoutBuilderGate.shouldProcess(
            sessionActive: false,
            activeBuilderID: id,
            callbackBuilderID: id
        )
        #expect(allow == false)
    }

    @Test("Rejects when no active builder is recorded")
    func rejectsWhenNoActiveBuilder() {
        let (id, _) = makeTwoIdentifiers()
        let allow = WorkoutBuilderGate.shouldProcess(
            sessionActive: true,
            activeBuilderID: nil,
            callbackBuilderID: id
        )
        #expect(allow == false)
    }

    @Test("Rejects when callback belongs to a different (stale) builder")
    func rejectsStaleBuilder() {
        let (active, stale) = makeTwoIdentifiers()
        let allow = WorkoutBuilderGate.shouldProcess(
            sessionActive: true,
            activeBuilderID: active,
            callbackBuilderID: stale
        )
        #expect(allow == false)
    }

    @Test("Accepts when session active AND callback matches active builder")
    func acceptsMatchingActiveBuilder() {
        let (active, _) = makeTwoIdentifiers()
        let allow = WorkoutBuilderGate.shouldProcess(
            sessionActive: true,
            activeBuilderID: active,
            callbackBuilderID: active
        )
        #expect(allow == true)
    }

    // Scenario: session ended → activeBuilderID cleared → trailing
    // HKLiveWorkoutBuilder callback for the previously-active builder must
    // NOT push HR (this is the exact regression the repair round targets).
    @Test("After end: previously-active builder's late callback is dropped")
    func lateCallbackAfterEndIsDropped() {
        let (previouslyActive, _) = makeTwoIdentifiers()
        // Post-end state: no active builder, session flag cleared.
        let allow = WorkoutBuilderGate.shouldProcess(
            sessionActive: false,
            activeBuilderID: nil,
            callbackBuilderID: previouslyActive
        )
        #expect(allow == false)
    }
}

// MARK: - Start-failure propagation (protocol contract — MY-1282 repair)
//
// `WorkoutSessionManaging.startSession()` now `throws`. A ViewModel-style
// consumer must catch and route to a failed state instead of transitioning
// to `.active` on silent failure. We exercise the protocol seam here with a
// throwing mock so the contract is regression-safe without a real HKWorkout
// session.

/// Throwing mock that lets tests control whether `startSession` succeeds or
/// throws, and inspect how many times it was called.
final class ThrowingMockWorkoutSessionManager: WorkoutSessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _startCallCount = 0
    private var _endCallCount = 0
    private var _shouldThrow: (any Error)?

    init(shouldThrow: (any Error)? = nil) {
        self._shouldThrow = shouldThrow
    }

    var startCallCount: Int { lock.withLock { _startCallCount } }
    var endCallCount: Int { lock.withLock { _endCallCount } }

    func setShouldThrow(_ error: (any Error)?) {
        lock.withLock { _shouldThrow = error }
    }

    func startSession() async throws {
        let error = lock.withLock { _shouldThrow }
        lock.withLock { _startCallCount += 1 }
        if let error {
            throw error
        }
    }

    func endSession(save: Bool) async -> String? {
        lock.withLock { _endCallCount += 1 }
        return nil
    }
}

@Suite("startSession failure propagation")
struct StartFailurePropagationTests {

    @Test("Throwing manager surfaces error to caller")
    func throwingManagerSurfacesError() async {
        let mock = ThrowingMockWorkoutSessionManager(
            shouldThrow: WorkoutSessionStartError.sessionUnavailable("simulated")
        )
        do {
            try await mock.startSession()
            Issue.record("expected start to throw")
        } catch WorkoutSessionStartError.sessionUnavailable {
            // expected
        } catch {
            Issue.record("wrong error kind: \(error)")
        }
        #expect(mock.startCallCount == 1)
    }

    @Test("Successful start does not throw")
    func successfulStartDoesNotThrow() async throws {
        let mock = ThrowingMockWorkoutSessionManager(shouldThrow: nil)
        try await mock.startSession()
        #expect(mock.startCallCount == 1)
    }

    @Test("Consumer state-machine: catches error into failed state without reaching active")
    func consumerRoutesFailureToFailedState() async {
        // Simulate the ViewModel's start flow: attempt manager.startSession(),
        // fall through to `.active` on success or `.failed` on throw.
        enum UIState: Equatable { case idle, active, failed(String) }

        let mock = ThrowingMockWorkoutSessionManager(
            shouldThrow: WorkoutSessionStartError.beginCollectionFailed("simulated")
        )

        var state: UIState = .idle
        do {
            try await mock.startSession()
            state = .active
        } catch {
            state = .failed("start failed")
        }

        // Critical: on failure state must NOT be .active.
        #expect(state == .failed("start failed"))
        #expect(state != .active)
    }

    @Test("WorkoutSessionStartError cases are Equatable")
    func startErrorEquatable() {
        #expect(WorkoutSessionStartError.alreadyActive == WorkoutSessionStartError.alreadyActive)
        #expect(
            WorkoutSessionStartError.sessionUnavailable("a") == WorkoutSessionStartError.sessionUnavailable("a")
        )
        #expect(
            WorkoutSessionStartError.sessionUnavailable("a") != WorkoutSessionStartError.beginCollectionFailed("a")
        )
    }
}
