import Foundation
import Observation

// MARK: - RestCompletedPresenter (MY-1446)

/// Injectable clock abstraction for deterministic testing of the rest-completed
/// auto-dismiss lifecycle. Production uses `ContinuousClock`; tests inject a
/// controllable implementation.
protocol RestCompletedClock: Sendable {
    func sleep(for duration: Duration) async throws
}

/// Production clock wrapping `ContinuousClock`.
struct ProductionRestClock: RestCompletedClock, Sendable {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(until: .now + duration)
    }
}

/// Manages the view-layer buffered rest-completed presentation lifecycle.
///
/// When the `RestTimerController` transitions to `.completed`, the view captures
/// the event via `captureCompleted()`. Even after the controller independently
/// clears phase→`.idle`, this presenter keeps the presentation active until a
/// full uninterrupted `displayDuration` of actual slot visibility (not occluded
/// by undo) has elapsed.
///
/// **Event-driven visibility (MY-1446 P1-1):** Instead of polling `slotIsVisible`
/// each tick, the view calls `markVisible()` / `markOccluded()` on every slot
/// transition. Each transition increments a generation counter. The countdown
/// sleeps for `displayDuration` in one shot and verifies the generation is
/// unchanged on wake — any `.rest → non-rest → .rest` transition, even
/// sub-millisecond, invalidates the window and requires a fresh full duration.
///
/// Extracted from `ActiveWorkoutView` so the lifecycle can be tested
/// deterministically without async timing uncertainty.
@MainActor
@Observable
final class RestCompletedPresenter {
    /// Whether the rest-completed snackbar should be presented.
    private(set) var isBuffered: Bool = false

    /// The duration the snackbar must be continuously visible before auto-dismiss.
    let displayDuration: Duration

    /// Injectable clock for deterministic testing.
    let clock: any RestCompletedClock

    /// Called when the auto-dismiss completes successfully.
    var onDismiss: (@MainActor () -> Void)?

    // MARK: - Event-driven visibility state

    /// Monotonically increasing generation counter. Incremented on every
    /// visibility transition (markVisible/markOccluded). The countdown captures
    /// the generation at start — any change means interruption occurred.
    private(set) var visibilityGeneration: UInt64 = 0

    /// Whether the slot is currently showing rest content (not occluded by undo).
    private(set) var isCurrentlyVisible: Bool = false

    private var countdownTask: Task<Void, Never>?

    init(
        displayDuration: Duration = .seconds(2),
        clock: any RestCompletedClock = ProductionRestClock()
    ) {
        self.displayDuration = displayDuration
        self.clock = clock
    }

    // MARK: - Public API

    /// Buffers the rest-completed event and starts the auto-dismiss countdown
    /// if currently visible. If a previous completion was already buffered,
    /// resets the countdown for the new rest completion.
    func captureCompleted() {
        if isBuffered {
            // New rest completed while old one still showing — restart countdown
            countdownTask?.cancel()
            countdownTask = nil
            if isCurrentlyVisible {
                startFreshDeadline()
            }
            return
        }
        isBuffered = true
        if isCurrentlyVisible {
            startFreshDeadline()
        }
    }

    /// Called by the view when the snackbar slot becomes `.rest` (visible).
    /// Starts a fresh deadline if buffered.
    func markVisible() {
        guard !isCurrentlyVisible else { return }
        isCurrentlyVisible = true
        visibilityGeneration &+= 1
        if isBuffered {
            startFreshDeadline()
        }
    }

    /// Called by the view when the snackbar slot leaves `.rest` (occluded by
    /// undo or cleared). Immediately cancels any running deadline — the next
    /// `markVisible()` will require a fresh full `displayDuration`.
    func markOccluded() {
        guard isCurrentlyVisible else { return }
        isCurrentlyVisible = false
        visibilityGeneration &+= 1
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Clears the buffer immediately (e.g., user tapped to dismiss).
    func dismiss() {
        isBuffered = false
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Cancels any running countdown and releases resources.
    /// Called by the view on disappear to prevent leaked tasks.
    /// Deliberately preserves `isBuffered` so `resume()` on reappear
    /// can restart the countdown for an existing buffered completion.
    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Resumes countdown for an existing buffered completion.
    /// Called by the view on reappear after a prior `cancel()` to ensure
    /// a buffered rest-completed notification is eventually auto-dismissed.
    func resume() {
        guard isBuffered, countdownTask == nil, isCurrentlyVisible else { return }
        startFreshDeadline()
    }

    // MARK: - Internal deadline

    /// Starts a single-shot deadline for `displayDuration`. On wake, verifies
    /// the generation hasn't changed (no visibility transitions occurred).
    private func startFreshDeadline() {
        countdownTask?.cancel()
        let capturedGeneration = visibilityGeneration
        countdownTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(for: self.displayDuration)
            } catch {
                return // cancelled or task ended
            }
            guard !Task.isCancelled else { return }
            // Verify no visibility transitions occurred during sleep
            guard self.visibilityGeneration == capturedGeneration else { return }
            guard self.isBuffered else { return }
            self.isBuffered = false
            self.onDismiss?()
            self.countdownTask = nil
        }
    }
}
