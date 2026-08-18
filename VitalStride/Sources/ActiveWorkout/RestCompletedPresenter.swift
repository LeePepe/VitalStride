import Foundation

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
/// Extracted from `ActiveWorkoutView` so the lifecycle can be tested
/// deterministically without async timing uncertainty.
@MainActor
@Observable
final class RestCompletedPresenter {
    /// Whether the rest-completed snackbar should be presented.
    private(set) var isBuffered: Bool = false

    /// Set by the view each time the slot changes. `true` when the snackbar
    /// slot is `.rest` (not occluded by undo). The countdown loop reads this
    /// each tick to detect interruption.
    var slotIsVisible: Bool = false

    /// The duration the snackbar must be continuously visible before auto-dismiss.
    let displayDuration: Duration

    /// Injectable clock for deterministic testing.
    let clock: any RestCompletedClock

    /// The polling interval used to check slot state during countdown.
    let tickInterval: Duration

    /// Called when the auto-dismiss completes successfully.
    var onDismiss: (@MainActor () -> Void)?

    private var countdownTask: Task<Void, Never>?

    init(
        displayDuration: Duration = .seconds(2),
        tickInterval: Duration = .milliseconds(100),
        clock: any RestCompletedClock = ProductionRestClock()
    ) {
        self.displayDuration = displayDuration
        self.tickInterval = tickInterval
        self.clock = clock
    }

    /// Buffers the rest-completed event and starts the auto-dismiss countdown.
    func captureCompleted() {
        guard !isBuffered else { return }
        isBuffered = true
        startCountdown()
    }

    /// Clears the buffer immediately (e.g., user tapped to dismiss).
    func dismiss() {
        isBuffered = false
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Restarts the countdown (called when `isBuffered` becomes true or when
    /// external state changes require re-evaluation).
    func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            await self.runCountdown()
        }
    }

    // MARK: - Internal countdown loop

    /// The core auto-dismiss loop. Waits for the slot to be visible, then counts
    /// elapsed visible time. If undo interrupts (slot becomes non-visible), resets
    /// and waits again. Only dismisses after a full uninterrupted `displayDuration`.
    private func runCountdown() async {
        while !Task.isCancelled && isBuffered {
            // Wait until the slot is actually showing rest
            while !slotIsVisible {
                guard !Task.isCancelled, isBuffered else { return }
                do { try await clock.sleep(for: tickInterval) } catch { return }
            }

            // Start the visible countdown
            var elapsed: Duration = .zero
            var interrupted = false

            while elapsed < displayDuration {
                guard !Task.isCancelled, isBuffered else { return }
                do { try await clock.sleep(for: tickInterval) } catch { return }
                elapsed += tickInterval

                // If undo took over the slot mid-countdown, restart
                if !slotIsVisible {
                    interrupted = true
                    break
                }
            }

            if !interrupted {
                // Full duration elapsed while visible — auto-dismiss
                guard !Task.isCancelled, isBuffered else { return }
                isBuffered = false
                onDismiss?()
                countdownTask = nil
                return
            }
            // interrupted — loop again and wait for visibility
        }
    }
}
