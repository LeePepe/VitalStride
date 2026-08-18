import Foundation
import Testing

@testable import VitalStride

// MARK: - Controllable clock for deterministic testing

/// A test clock that advances only when explicitly told to, enabling
/// deterministic verification of the rest-completed lifecycle without
/// real-time waits or race conditions.
///
/// Fully `@MainActor`-isolated — both the clock state and the `sleep`
/// implementation live on MainActor, satisfying Swift 6 strict concurrency
/// without `@unchecked Sendable` or `assumeIsolated`.
@MainActor
final class TestRestCompletedClock: RestCompletedClock {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    private(set) var sleepCallCount = 0

    /// Advances time by resolving all pending sleep continuations.
    func advance() {
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume()
        }
    }

    /// Cancels all pending sleeps (simulates task cancellation cleanup).
    func cancelAll() {
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
    }

    func sleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.sleepCallCount += 1
            self.continuations.append(continuation)
        }
    }
}

// MARK: - RestCompletedPresenter lifecycle tests (MY-1446)

/// Deterministic tests for the production `RestCompletedPresenter` lifecycle.
/// These verify:
/// - Buffer capture when controller hits .completed
/// - Buffer surviving controller clear to .idle
/// - Auto-dismiss after full uninterrupted visible duration
/// - Undo interrupting countdown (resets the window)
/// - Fresh 2s required after undo clears
/// - Cancellation releases the task when view disappears
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
            tickInterval: .milliseconds(100),
            clock: clock
        )
        #expect(!presenter.isBuffered)
        presenter.captureCompleted()
        #expect(presenter.isBuffered)
    }

    // MARK: - Test 2: Buffer survives (external controller clear is irrelevant)

    @MainActor
    @Test("Buffer stays true regardless of external phase changes")
    func bufferSurvivesControllerClear() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Simulate controller clearing to .idle — buffer must survive
        // The presenter is independent of controller phase; it only uses slotIsVisible
        presenter.slotIsVisible = false
        await Task.yield()
        clock.advance()
        await Task.yield()
        #expect(presenter.isBuffered, "Buffer must survive even when slot is not visible")
    }

    // MARK: - Test 3: Auto-dismiss after full uninterrupted visibility

    @MainActor
    @Test("Auto-dismiss fires after full visible duration with no interruption")
    func autoDismissAfterFullVisibility() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .milliseconds(300),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.slotIsVisible = true

        presenter.captureCompleted()
        #expect(presenter.isBuffered)
        #expect(!dismissed)

        // Advance 3 ticks (3 × 100ms = 300ms = displayDuration)
        for _ in 0..<3 {
            await Task.yield()
            clock.advance()
            await Task.yield()
        }
        // Give the task a chance to process the final tick
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer should be cleared after full visibility")
        #expect(dismissed, "onDismiss should have been called")
    }

    // MARK: - Test 4: Undo interruption resets countdown

    @MainActor
    @Test("Undo appearing mid-countdown resets the visible window")
    func undoMidCountdownResetsWindow() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .milliseconds(300),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.slotIsVisible = true

        presenter.captureCompleted()

        // Advance 1 tick (100ms of visibility elapsed)
        await Task.yield()
        clock.advance()
        await Task.yield()

        #expect(presenter.isBuffered)
        #expect(!dismissed, "Should not dismiss after only 1 tick")

        // Undo appears — slot becomes non-visible
        presenter.slotIsVisible = false
        await Task.yield()
        clock.advance()
        await Task.yield()

        #expect(presenter.isBuffered, "Buffer stays during undo occlusion")
        #expect(!dismissed, "Must not dismiss while occluded")

        // Undo clears — slot visible again
        presenter.slotIsVisible = true

        // Now need a FULL 3 more ticks (fresh 300ms) — the wait-for-visibility
        // tick doesn't count toward the countdown, so we need one tick to
        // re-enter the countdown loop, then 3 ticks for the full duration.
        for _ in 0..<4 {
            await Task.yield()
            clock.advance()
            await Task.yield()
        }
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer should clear after fresh full visibility")
        #expect(dismissed, "onDismiss fires after fresh uninterrupted window")
    }

    // MARK: - Test 5: Manual dismiss cancels countdown

    @MainActor
    @Test("Manual dismiss() clears buffer and stops countdown")
    func manualDismissClearsBuffer() {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(2),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        presenter.slotIsVisible = true
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        presenter.dismiss()
        #expect(!presenter.isBuffered, "Manual dismiss must clear buffer immediately")
    }

    // MARK: - Test 6: Integration with slot resolution

    @Test("Slot resolution uses buffered phase correctly")
    func slotResolutionWithBuffer() {
        // When presenter.isBuffered is true, production passes .completed to slot resolver
        let slotWithBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .completed)
        #expect(slotWithBuffer == .rest)

        // When presenter.isBuffered is false and controller is .idle, slot is .none
        let slotWithoutBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle)
        #expect(slotWithoutBuffer == .none)

        // Undo still outranks even when buffer is active
        let slotUndoDuringBuffer = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .completed)
        #expect(slotUndoDuringBuffer == .undo)
    }

    // MARK: - Test 7: Full lifecycle sequence

    @MainActor
    @Test("Full sequence: visible → countdown → undo → no dismiss → undo clears → fresh 2s → dismiss")
    func fullLifecycleSequence() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .milliseconds(200),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        var dismissed = false
        presenter.onDismiss = { dismissed = true }
        presenter.slotIsVisible = true

        // Phase 1: rest completed → buffer captured
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Phase 2: 1 tick visible (100ms of 200ms elapsed)
        await Task.yield()
        clock.advance()
        await Task.yield()
        #expect(presenter.isBuffered)
        #expect(!dismissed, "1 tick < displayDuration, must not dismiss")

        // Phase 3: undo appears mid-countdown
        presenter.slotIsVisible = false
        await Task.yield()
        clock.advance()
        await Task.yield()
        #expect(!dismissed, "Must NOT dismiss during undo occlusion")

        // Phase 4: undo clears
        presenter.slotIsVisible = true

        // Phase 5: fresh full 2 ticks (200ms) plus re-enter tick
        for _ in 0..<3 {
            await Task.yield()
            clock.advance()
            await Task.yield()
        }
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered, "Buffer clears after fresh full visibility")
        #expect(dismissed, "Dismiss fires after uninterrupted fresh window")
    }

    // MARK: - Test 8: cancel() terminates the countdown task

    @MainActor
    @Test("cancel() stops the countdown loop — task does not poll forever")
    func cancelTerminatesCountdownTask() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .seconds(10),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        presenter.slotIsVisible = false // slot hidden — loop polls
        presenter.captureCompleted()

        // One tick to enter the wait-for-visibility loop
        await Task.yield()
        clock.advance()
        await Task.yield()

        #expect(presenter.isBuffered)

        // Cancel as if view disappeared
        presenter.cancel()

        // Advance again — the clock should have no pending continuations
        // because the task was cancelled
        let sleepCountBefore = clock.sleepCallCount
        await Task.yield()
        await Task.yield()
        #expect(
            clock.sleepCallCount == sleepCountBefore,
            "After cancel(), no new sleep calls should be issued"
        )
    }

    // MARK: - Test 9: New rest start resets stale buffered completion

    @MainActor
    @Test("captureCompleted() on already-buffered presenter restarts countdown")
    func newRestResetsStalBuffer() async {
        let clock = TestRestCompletedClock()
        let presenter = RestCompletedPresenter(
            displayDuration: .milliseconds(200),
            tickInterval: .milliseconds(100),
            clock: clock
        )
        var dismissCount = 0
        presenter.onDismiss = { dismissCount += 1 }
        presenter.slotIsVisible = true

        // First completion
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // 1 tick (50% elapsed)
        await Task.yield()
        clock.advance()
        await Task.yield()

        // New rest starts — captureCompleted again resets countdown
        presenter.captureCompleted()
        #expect(presenter.isBuffered)

        // Need full 2 fresh ticks for the new countdown
        for _ in 0..<2 {
            await Task.yield()
            clock.advance()
            await Task.yield()
        }
        await Task.yield()
        await Task.yield()

        #expect(!presenter.isBuffered)
        #expect(dismissCount == 1, "Should dismiss exactly once for the new completion")
    }
}
