// swiftlint:disable file_length
import Combine
import Foundation
import HealthKit
import HealthKitService
import os

// MARK: - Sender seam
//
// The VM sends `SetCompletedEvent` through this narrow seam so tests can
// substitute a no-transport recorder without touching WatchConnectivity.
// The concrete `WatchToPhoneSending` from HealthKitService satisfies the
// production seam directly.
//
// NB: This is a protocol on top of an existing protocol so the VM stays
// decoupled from `WatchToPhoneSending` details (isReachable, transport
// routing). The VM only needs "here's an event, deliver it or record why
// you couldn't".
public protocol WatchSetCompletedSending: Sendable {
    func send(_ event: SetCompletedEvent) throws
}

/// Adapter: any `WatchToPhoneSending` fulfils `WatchSetCompletedSending`
/// by wrapping the event into a `WatchConnectivityMessage`.
struct WatchToPhoneSetCompletedAdapter: WatchSetCompletedSending {
    let underlying: any WatchToPhoneSending

    func send(_ event: SetCompletedEvent) throws {
        try underlying.send(.setCompleted(event))
    }
}

// MARK: - WatchWorkoutViewModel
//
// MainActor presentation adapter over the merged HealthKitService streams
// (MY-1288 shipped `observeInbound*` + `observeLocalHeartRate` + existing
// `observeConnectionState`). Owns the `WatchWorkoutDisplayState`
// snapshot the watch screen renders from.
//
// Concurrency (§Constitution II — Swift 6 strict concurrency):
//   * `@MainActor` isolated class: all state mutation is main-actor
//     bound.
//   * Stream subscribers are child tasks under a `Task { … }` we own —
//     started in `start()`, cancelled in `stop()`. No detached tasks,
//     no unchecked-Sendable escapes.
//   * Streams and events are already `Sendable` at the protocol level.
//     Injected `manager` / `sender` are `Sendable`, so `sendCompleteSet`
//     can call across the actor boundary without capture-list tricks.
//
// Privacy §I:
//   * The VM holds bpm values in the display state (they render), but
//     nothing in this file logs the bpm — only `hr_state`, `zone`, and
//     sample counters.
//   * `elapsed`, `progress`, `nextSet` etc. are training data and may
//     appear in log context; they are not HK-restricted values.
@MainActor
public final class WatchWorkoutViewModel: ObservableObject {
    // MARK: Published surface

    @Published public private(set) var display: WatchWorkoutDisplayState = .initial

    // MARK: Dependencies

    private let manager: any WorkoutSessionManaging
    private let sender: any WatchSetCompletedSending
    private let clock: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.vitalstride", category: "WatchWorkoutVM")

    // MARK: Task ownership

    private var streamTask: Task<Void, Never>?
    private var isRunning = false

    // MARK: Running HR aggregates
    //
    // Kept out of `WatchWorkoutDisplayState` so the display type stays
    // presentation-only. The VM recomputes avg/peak on each sample.
    private var hrSampleCount: Int = 0
    private var hrSampleSum: Double = 0

    // MARK: Current workout id (for SetCompletedEvent)

    /// Last-seen workoutID from an inbound snapshot. `sendCompleteSet`
    /// refuses to fire when nil (no workout to attribute the event to).
    private var currentWorkoutID: UUID?

    // MARK: Init

    public init(
        manager: any WorkoutSessionManaging,
        sender: any WatchSetCompletedSending,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.manager = manager
        self.sender = sender
        self.clock = clock
    }

    /// Convenience initializer for the production wiring where the same
    /// `WatchToPhoneSending` seam serves both HR/state (inside the
    /// manager) and set-completed (outward from the VM).
    public convenience init(
        manager: any WorkoutSessionManaging,
        toPhoneSender: any WatchToPhoneSending
    ) {
        self.init(
            manager: manager,
            sender: WatchToPhoneSetCompletedAdapter(underlying: toPhoneSender)
        )
    }

    // MARK: Lifecycle

    /// Start subscribing to the manager streams. Idempotent — calling
    /// twice does not spawn a second task.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let manager = self.manager

        streamTask = Task { [weak self] in
            // Fan out to independent child tasks so a slow subscriber
            // never blocks the others. All children share the parent's
            // cancellation; when `stop()` cancels `streamTask`, they
            // all wind down together.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    let stream = await manager.observeInboundWorkoutState()
                    for await snapshot in stream {
                        await self?.applyInboundWorkoutState(snapshot)
                    }
                }
                group.addTask { [weak self] in
                    let stream = await manager.observeInboundWatchScreenConfig()
                    for await config in stream {
                        await self?.applyInboundConfig(config)
                    }
                }
                group.addTask { [weak self] in
                    let stream = await manager.observeLocalHeartRate()
                    for await payload in stream {
                        await self?.applyLocalHR(payload)
                    }
                }
                group.addTask { [weak self] in
                    let stream = await manager.observeConnectionState()
                    for await state in stream {
                        await self?.applyConnectionState(state)
                    }
                }
            }
        }

        logger.info("watch_vm_started")
    }

    /// Cancel every child stream and drop task ownership. Idempotent.
    /// After `stop()`, the display remains at its last value so the
    /// screen doesn't flash to `.initial` — call `reset()` if a fresh
    /// state is required.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        streamTask?.cancel()
        streamTask = nil
        logger.info("watch_vm_stopped")
    }

    /// Reset the display to `.initial` and clear HR aggregates. Safe to
    /// call before `start()` or after `stop()`; not required in the
    /// normal path.
    public func reset() {
        display = .initial
        hrSampleCount = 0
        hrSampleSum = 0
        currentWorkoutID = nil
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: Actions

    /// Primary-action / "complete set" tap. Sends a `SetCompletedEvent`
    /// through the sender seam using the current `nextSet` id and the
    /// last-seen `workoutID`. iPhone remains source of truth — this is
    /// an optimistic forward event.
    ///
    /// - Parameter actualReps: optional user-adjusted reps; nil means
    ///   use the planned target on the iPhone side.
    public func sendCompleteSet(actualReps: Int? = nil) {
        guard let workoutID = currentWorkoutID else {
            logger.info("watch_set_completed_skipped reason=no_workout")
            return
        }
        guard let nextSet = display.nextSet else {
            logger.info("watch_set_completed_skipped reason=no_next_set")
            return
        }
        let event = SetCompletedEvent(
            workoutID: workoutID,
            setID: nextSet.id,
            actualReps: actualReps,
            completedAt: clock()
        )
        do {
            try sender.send(event)
            logger.info(
                "watch_set_completed_sent index=\(nextSet.index, privacy: .public)/\(nextSet.total, privacy: .public)"
            )
        } catch {
            // Never log HR / reps values; log the transport-failure kind only.
            logger.info(
                "watch_set_completed_send_failed reason=\(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: Stream reducers (MainActor)

    private func applyInboundWorkoutState(_ snapshot: WorkoutStateSnapshot) {
        currentWorkoutID = snapshot.workoutID
        display = display.with(snapshot: snapshot)
        // Privacy §I: log kind + counts only; never reps/weights.
        logger.info(
            "watch_vm_state_applied setCount=\(snapshot.sets.count, privacy: .public) progress=\(snapshot.progress.completedSetCount, privacy: .public)/\(snapshot.progress.totalSetCount, privacy: .public)"
        )
    }

    private func applyInboundConfig(_ config: WatchScreenConfig) {
        display = display.with(config: config)
        logger.info(
            "watch_vm_config_applied preset=\(config.preset.rawValue, privacy: .public) modules=\(config.enabledModules.count, privacy: .public)"
        )
    }

    private func applyLocalHR(_ payload: LiveHeartRatePayload) {
        // Never log bpm. HR aggregate maintenance runs on the main
        // actor because the VM's snapshot lives here.
        guard payload.isPhysiologicallyPlausible else {
            logger.info("watch_vm_hr_rejected reason=implausible")
            return
        }
        let bpmInt = Int(payload.bpm.rounded())
        hrSampleCount += 1
        hrSampleSum += payload.bpm
        let mean = Int((hrSampleSum / Double(hrSampleCount)).rounded())
        let peak = max(display.peakBPM ?? bpmInt, bpmInt)
        // Zone is not carried by the local stream — the iPhone would
        // push zone alongside HR post-MY-1290; until then, .connected
        // renders with a nil zone (pill hidden per spec §6a).
        let nextHR: HRDisplayState = .connected(bpm: bpmInt, zone: nil)
        display = display.with(hr: nextHR).withAvgPeak(bpm: bpmInt, runningMean: mean, peak: peak)
        logger.info("watch_vm_hr_sample count=\(self.hrSampleCount, privacy: .public)")
    }

    private func applyConnectionState(_ state: WatchConnectionState) {
        display = display.with(connection: state)
        // Downgrade HR to "not connected" when transport goes cold and
        // we haven't yet seen a local sample. Once we have one we keep
        // showing it — Apple's Workout app follows the same "last-good"
        // convention on the watch's own screen.
        if state != .reachable, case .notConnected = display.hr {
            // stays notConnected
        }
        logger.info("watch_vm_connection_state state=\(String(describing: state), privacy: .public)")
    }
}
