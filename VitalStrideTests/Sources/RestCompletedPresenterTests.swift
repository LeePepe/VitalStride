import Foundation
import Testing

@testable import VitalStride

// MARK: - Controllable clock for deterministic testing (P1-4: identity-based)

/// A test clock that advances only when explicitly told to, enabling
/// deterministic verification of the rest-completed lifecycle without
/// real-time waits or race conditions.
///
/// **P1-4 fix:** Each sleeping task gets a unique identity. Cancel/resume
/// targets the specific continuation rather than `popLast()`, preventing
/// a replacement task from being woken by a stale cancel, and proving
/// that canceled waiters drain correctly.
@MainActor
final class TestRestCompletedClock: RestCompletedClock {
    private struct PendingSleep: Identifiable {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var nextID: UInt64 = 0
    private var pendingSleeps: [PendingSleep] = []
    private(set) var sleepCallCount = 0

    /// Number of pending (unresolved) continuations — used by tests to verify
    /// that cancellation properly drained all waiters.
    var pendingCount: Int { pendingSleeps.count }

    /// Advances time by resolving all pending sleep continuations.
    func advance() {
        let pending = pendingSleeps
        pendingSleeps = []
        for sleep in pending {
            sleep.continuation.resume()
        }
    }

    /// Cancels a specific pending sleep by ID.
    func cancelSleep(id: UInt64) {
        guard let idx = pendingSleeps.firstIndex(where: { $0.id == id }) else { return }
        let sleep = pendingSleeps.remove(at: idx)
        sleep.continuation.resume(throwing: CancellationError())
    }

    /// Cancels all pending sleeps (simulates task cancellation cleanup).
    func cancelAll() {
        let pending = pendingSleeps
        pendingSleeps = []
        for sleep in pending {
            sleep.continuation.resume(throwing: CancellationError())
        }
    }

    func sleep(for duration: Duration) async throws {
        let myID = nextID
        nextID += 1
        sleepCallCount += 1

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.pendingSleeps.append(PendingSleep(id: myID, continuation: continuation))
            }
        } onCancel: {
            // Task.cancel() triggers this handler; schedule on MainActor for safe mutation.
            Task { @MainActor in
                self.cancelSleep(id: myID)
            }
        }
    }
}

// MARK: - RestCompletedPresenter lifecycle tests (MY-1446)

/// Deterministic tests for the production `RestCompletedPresenter` lifecycle.
/// These verify the event-driven visibility contract (P1-1):
/// - Buffer capture when controller hits .completed
/// - Event-driven markVisible/markOccluded (no polling)
/// - Generation-based interruption detection (sub-tick precision)
/// - Auto-dismiss after full uninterrupted visible duration
/// - Undo interrupting countdown (resets the window)
/// - Cancellation releases tasks correctly (identity-based, P1-4)
/// - New rest start resets stale buffered completion
@Suite("RestCompletedPresenter lifecycle (MY-1446)")
struct RestCompletedPresenterLifecycleTests {

    // MARK: - Test 1: Buffer capture

    @MainActor
    @Test("captureCompleted sets isBuffered to true")
    func captureCompletedSetsBuffer() {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        #expect(!presenter.isBuffered)
        presenter.captureCompleted()
        #expect(presenter.isBuffered)
    }

    // MARK: - Test 2: Buffer survives occlusion (event-driven)

    @MainActor
    @Test("Buffer stays true when markOccluded is called (presenter remains buffered)")
    func bufferSurvivesOcclusion() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        presenter.markVisible()
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Occlude — deadline cancels but buffer survives
        presenter.markOccluded()
        await Task.yield()
        #expect(presenter.isBuffered, "Buffer must survive occlusion")
    }

    // MARK: - Test 3: Auto-dismiss after full uninterrupted visibility

    @MainActor
    @Test("Auto-dismiss fires after full visible duration with no interruption")
    func autoDismissAfterFullVisibility() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .milliseconds(2000),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.markVisible()
        presenter.captureCompleted()
        #expect(presenter.isBuffered)
        #expect(!dismissed)

        // Advance the single deadline sleep
        await Task.yield()
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer should be cleared after full visibility")
        #expect(dismissed, "onDismiss should have been called")
    }

    // MARK: - Test 4: Undo interruption resets countdown (event-driven)

    @MainActor
    @Test("markOccluded mid-countdown resets the visible window (generation-based)")
    func undoMidCountdownResetsWindow() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.markVisible()
        presenter.captureCompleted()

        #expect(presenter.isBuffered)
        let genBefore = presenter.visibilityGeneration

        // Occlude — cancels the deadline, bumps generation
        presenter.markOccluded()
        await Task.yield()
        await Task.yield()
        #expect(presenter.visibilityGeneration > genBefore, "Generation must increment on occlusion")
        #expect(presenter.isBuffered, "Buffer stays during undo occlusion")
        #expect(!dismissed, "Must not dismiss while occluded")

        // Mark visible again — starts a fresh deadline
        presenter.markVisible()
        await Task.yield()

        // Advance the fresh deadline
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer should clear after fresh full visibility")
        #expect(dismissed, "onDismiss fires after fresh uninterrupted window")
    }

    // MARK: - Test 5: Sub-tick interruption detection (P1-1 deterministic coverage)

    @MainActor
    @Test("Rapid .rest→undo→.rest within one sleep invalidates the window")
    func subTickInterruptionInvalidatesWindow() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.markVisible()
        presenter.captureCompleted()

        // Rapid transition: visible → occluded → visible (sub-tick, no clock advance)
        presenter.markOccluded()
        presenter.markVisible()

        await Task.yield()
        // The first deadline was cancelled by markOccluded, a new one started by markVisible.
        // Generation is now +2 from the original — the old deadline (if it somehow resolved)
        // would see a generation mismatch and not fire.

        // Advance the new deadline
        clock.advance()
        await Task.yield()
        await Task.yield()

        // The dismiss should fire because the NEW deadline ran for full duration
        #expect(!presenter.isBuffered, "Fresh deadline should dismiss after full duration")
        #expect(dismissed, "onDismiss should fire for the new uninterrupted window")
    }

    // MARK: - Test 6: Manual dismiss cancels countdown

    @MainActor
    @Test("Manual dismiss() clears buffer and stops countdown")
    func manualDismissClearsBuffer() {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        presenter.markVisible()
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        presenter.dismiss()
        #expect(!presenter.isBuffered, "Manual dismiss must clear buffer immediately")
    }

    // MARK: - Test 7: Integration with slot resolution

    @Test("Slot resolution uses buffered phase correctly")
    func slotResolutionWithBuffer() {
        let slotWithBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .completed)
        #expect(slotWithBuffer == .rest)

        let slotWithoutBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle)
        #expect(slotWithoutBuffer == .none)

        let slotUndoDuringBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .completed)
        #expect(slotUndoDuringBuffer == .undo)
    }

    // MARK: - Test 8: Full lifecycle with event-driven API

    @MainActor
    @Test("Full sequence: visible → deadline → undo occlusion → no dismiss → visible again → fresh deadline → dismiss")
    func fullLifecycleSequence() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }

        // Phase 1: mark visible, capture rest completed
        presenter.markVisible()
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Phase 2: undo appears — occlude
        presenter.markOccluded()
        await Task.yield()
        await Task.yield()
        #expect(!dismissed, "Must NOT dismiss during undo occlusion")
        #expect(presenter.isBuffered)

        // Phase 3: undo clears — mark visible again
        presenter.markVisible()
        await Task.yield()

        // Phase 4: fresh full deadline completes
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer clears after fresh full visibility")
        #expect(dismissed, "Dismiss fires after uninterrupted fresh window")
    }

    // MARK: - Test 9: cancel() terminates the countdown task (P1-4 identity proof)

    @MainActor
    @Test("cancel() stops the countdown — task terminates, no continuations leak, identity-based drain")
    func cancelTerminatesCountdownTask() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(10),
            clock: clock
        )
        presenter.markVisible()
        presenter.captureCompleted()

        // One sleep should be pending (the deadline)
        await Task.yield()
        #expect(clock.pendingCount == 1, "Deadline sleep should be pending")

        // Cancel — the identity-based handler drains the specific continuation
        presenter.cancel()
        await Task.yield()
        await Task.yield()
        await Task.yield()

        #expect(
            clock.pendingCount == 0,
            "After cancel(), no pending continuations should remain (got \(clock.pendingCount))"
        )

        // Verify no new sleep calls after cancellation
        let sleepCountAfterCancel = clock.sleepCallCount
        await Task.yield()
        await Task.yield()
        #expect(
            clock.sleepCallCount == sleepCountAfterCancel,
            "After cancel(), no new sleep calls should be issued"
        )
    }

    // MARK: - Test 10: New rest start resets stale buffered completion

    @MainActor
    @Test("captureCompleted() on already-buffered presenter restarts deadline")
    func newRestResetsStalBuffer() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissCount = 0
        presenter.onDismiss = { dismissCount += 1 }
        presenter.markVisible()

        // First completion
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // New rest starts — captureCompleted again resets deadline
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        await Task.yield()
        // Advance the fresh deadline
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered)
        #expect(dismissCount == 1, "Should dismiss exactly once for the new completion")
    }

    // MARK: - Test 11: Disappear/reappear lifecycle

    @MainActor
    @Test("Buffered completion survives cancel+resume and auto-dismisses after fresh deadline")
    func disappearReappearLifecycle() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.markVisible()

        // Phase 1: completion captured, deadline running
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Phase 2: view disappears — cancel() preserves buffer
        presenter.cancel()
        await Task.yield()
        await Task.yield()
        #expect(presenter.isBuffered, "Buffer must survive cancel()")
        #expect(!dismissed, "Must not dismiss on cancel()")

        // Phase 3: view reappears — resume() restarts deadline
        presenter.onDismiss = { dismissed = true }
        presenter.resume()
        await Task.yield()

        // Advance the resumed deadline
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer should clear after resumed countdown completes")
        #expect(dismissed, "onDismiss should fire after full interval post-resume")
    }

    // MARK: - Test 12: P1-4 identity — canceled waiter cannot wake replacement

    @MainActor
    @Test("Canceled continuation cannot wake a replacement task (identity isolation)")
    func canceledWaiterCannotWakeReplacement() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.markVisible()
        presenter.captureCompleted()
        await Task.yield()

        // First deadline is sleeping — cancel it
        presenter.cancel()
        await Task.yield()
        await Task.yield()
        #expect(clock.pendingCount == 0, "Cancel should drain the pending sleep")

        // Start a new deadline via resume
        presenter.resume()
        await Task.yield()
        #expect(clock.pendingCount == 1, "Resume should start a new sleep")

        // The old cancel already drained — verify advancing fires only the new one
        clock.advance()
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "New deadline should fire correctly")
        #expect(dismissed, "Dismiss fires from the replacement, not the stale cancel")
    }
}
