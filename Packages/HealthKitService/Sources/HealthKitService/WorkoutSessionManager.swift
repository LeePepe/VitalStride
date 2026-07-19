import Foundation
import HealthKit
import os

// MARK: - Protocol

public protocol WorkoutSessionManaging: Sendable {
    /// Start a workout session. Throws when the underlying platform session
    /// (`HKWorkoutSession` on watchOS) cannot be constructed / activated —
    /// callers MUST surface the failure to the UI so users see an error state
    /// instead of a stuck-in-idle UI or a false `.active` transition.
    func startSession() async throws
    @discardableResult
    func endSession(save: Bool) async -> String?

    /// Realtime HR samples pushed by the paired Watch during an active workout.
    /// On the watchOS-side manager this is a finished stream (Watch produces HR
    /// via `HKLiveWorkoutBuilder` and pushes to phone, not to itself).
    /// On iPhone this drives UI. HR values MUST NOT be logged (§I).
    ///
    /// `async` because the iPhone-side implementation is actor-isolated.
    func observeLiveWorkoutHeartRate() async -> AsyncStream<LiveHeartRatePayload>

    /// Connection-state signal so UI can render three states
    /// (unpaired / unreachable / reachable) without silently stalling.
    func observeConnectionState() async -> AsyncStream<WatchConnectionState>

    /// Latest workout state (iPhone → watch, latest-wins).
    func updateWorkoutState(_ snapshot: WorkoutStateSnapshot) async

    /// Latest screen config (iPhone → watch, low-frequency).
    func updateWatchScreenConfig(_ config: WatchScreenConfig) async

    /// SetCompleted events pushed from the watch.
    func observeSetCompleted() async -> AsyncStream<SetCompletedEvent>
}

extension WorkoutSessionManaging {
    public func observeLiveWorkoutHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        AsyncStream { $0.finish() }
    }

    public func observeConnectionState() async -> AsyncStream<WatchConnectionState> {
        AsyncStream { $0.finish() }
    }

    public func updateWorkoutState(_ snapshot: WorkoutStateSnapshot) async {}
    public func updateWatchScreenConfig(_ config: WatchScreenConfig) async {}
    public func observeSetCompleted() async -> AsyncStream<SetCompletedEvent> {
        AsyncStream { $0.finish() }
    }
}

// MARK: - Connection State

public enum WatchConnectionState: Sendable, Equatable {
    /// `WCSession.isSupported()` is false (e.g. macOS or unsupported device).
    case unsupported
    /// Paired Watch not detected.
    case notPaired
    /// Watch app not installed on the paired device.
    case notInstalled
    /// Paired + installed but session not currently reachable (Watch asleep,
    /// out of range, etc.). Streams keep flowing whatever we can deliver.
    case unreachable
    /// Session active + reachable.
    case reachable
}

// MARK: - NoopWorkoutSessionManager

public struct NoopWorkoutSessionManager: WorkoutSessionManaging {
    public init() {}
    public func startSession() async throws {}
    public func endSession(save: Bool) async -> String? { nil }
    // observe*/update* inherit default no-op impls from the protocol extension.
}

// MARK: - Callback gating helper
//
// Extracted so the lifecycle gate (session ended? callback for a stale
// builder?) is unit-testable without constructing an `HKLiveWorkoutBuilder`
// (which requires a real `HKHealthStore` + workout session). The delegate
// method just forwards to this pure function.

enum WorkoutBuilderGate {
    /// Whether an HR-collection callback should be honored right now.
    /// - `sessionActive`: `session != nil` in the manager.
    /// - `activeBuilderID`: identity of the currently-owned builder, if any.
    /// - `callbackBuilderID`: identity of the builder that invoked the callback.
    static func shouldProcess(
        sessionActive: Bool,
        activeBuilderID: ObjectIdentifier?,
        callbackBuilderID: ObjectIdentifier
    ) -> Bool {
        guard sessionActive, let active = activeBuilderID else { return false }
        return active == callbackBuilderID
    }
}

// MARK: - Failure surface

/// Error thrown by `WorkoutSessionManager.startSession()` on watchOS so
/// callers can drive a `.failed` UI state instead of a silent stuck-idle.
public enum WorkoutSessionStartError: Error, Sendable, Equatable {
    /// `HKWorkoutSession` construction failed (unavailable, mis-configured).
    case sessionUnavailable(String)
    /// `HKLiveWorkoutBuilder.beginCollection(at:)` failed after the session
    /// started; the session was rolled back before this is thrown.
    case beginCollectionFailed(String)
    /// Attempted to start while another session was already active.
    case alreadyActive
}

// MARK: - WorkoutSessionManager

#if os(watchOS)

@available(watchOS 5.0, *)
public final class WorkoutSessionManager: NSObject, WorkoutSessionManaging, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let sender: any WatchToPhoneSending
    private let logger: Logger
    private let lock = NSLock()

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var activeBuilderID: ObjectIdentifier?
    private var pushedHRSampleCount = 0

    public init(
        healthStore: HKHealthStore,
        sender: any WatchToPhoneSending = NoopWatchToPhoneSender()
    ) {
        self.healthStore = healthStore
        self.sender = sender
        self.logger = Logger(subsystem: "com.vitalstride", category: "WorkoutSession")
        super.init()
    }

    public func startSession() async throws {
        guard lock.withLock({ session == nil }) else {
            logger.info("workout_session_start_skipped reason=already_active")
            throw WorkoutSessionStartError.alreadyActive
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let newSession: HKWorkoutSession
        do {
            newSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
        } catch {
            logger.error(
                "workout_session_start_failed stage=create error=\(error.localizedDescription, privacy: .private)"
            )
            throw WorkoutSessionStartError.sessionUnavailable(error.localizedDescription)
        }
        newSession.delegate = self

        let newBuilder = newSession.associatedWorkoutBuilder()
        newBuilder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        newBuilder.delegate = self

        let startDate = Date()
        newSession.startActivity(with: startDate)

        do {
            try await newBuilder.beginCollection(at: startDate)
        } catch {
            // Roll back so the manager stays in a clean idle state and the
            // caller sees the failure.
            newSession.end()
            logger.error(
                "workout_session_start_failed stage=beginCollection error=\(error.localizedDescription, privacy: .private)"
            )
            throw WorkoutSessionStartError.beginCollectionFailed(error.localizedDescription)
        }

        lock.withLock {
            self.session = newSession
            self.builder = newBuilder
            self.activeBuilderID = ObjectIdentifier(newBuilder)
            self.pushedHRSampleCount = 0
        }

        logger.info("workout_session_started activityType=traditionalStrengthTraining")
    }

    public func endSession(save: Bool) async -> String? {
        let (currentSession, currentBuilder, hrCount) = lock.withLock {
            let result = (session, builder, pushedHRSampleCount)
            session = nil
            builder = nil
            activeBuilderID = nil
            pushedHRSampleCount = 0
            return result
        }

        guard let currentSession, let currentBuilder else {
            return nil
        }

        let endDate = Date()

        currentSession.end()

        do {
            try await currentBuilder.endCollection(at: endDate)

            if save {
                let hkWorkout = try await currentBuilder.finishWorkout()
                logger.info("workout_session_ended saved=true hrPushed=\(hrCount, privacy: .public)")
                return hkWorkout?.uuid.uuidString
            } else {
                currentBuilder.discardWorkout()
                logger.info("workout_session_ended saved=false hrPushed=\(hrCount, privacy: .public)")
                return nil
            }
        } catch {
            logger.error(
                "workout_session_end_failed error=\(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    // MARK: HR push helper

    /// Extract HR quantity samples from a builder statistics update and push
    /// each via `sender`. Privacy §I: NEVER log the bpm value; count only.
    ///
    /// Callers MUST have already confirmed via `WorkoutBuilderGate` that this
    /// callback belongs to the currently-active builder — HKLiveWorkoutBuilder
    /// occasionally delivers a trailing callback after the session ends, and
    /// pushing HR from that stale callback would leak samples that don't
    /// belong to any live workout.
    private func pushHRSamplesIfAvailable(
        collectedTypes: Set<HKSampleType>,
        from builder: HKLiveWorkoutBuilder
    ) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }
        guard let stats = builder.statistics(for: hrType) else { return }
        guard let mostRecent = stats.mostRecentQuantity() else { return }
        guard let dateInterval = stats.mostRecentQuantityDateInterval() else { return }

        let bpm = mostRecent.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let payload = LiveHeartRatePayload(
            bpm: bpm,
            timestamp: dateInterval.end,
            sourceName: "Apple Watch"
        )
        guard payload.isPhysiologicallyPlausible else {
            // Never log bpm; log rejection reason only.
            logger.info("workout_hr_rejected reason=out_of_range")
            return
        }
        do {
            try sender.send(.liveHeartRate(payload))
            lock.withLock { pushedHRSampleCount += 1 }
            logger.info("workout_hr_pushed sampleType=heartRate count=1")
        } catch {
            // Do not log the value. `.notReachable` is expected when phone
            // is asleep/out of range — record kind only.
            logger.info("workout_hr_push_failed reason=\(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

@available(watchOS 5.0, *)
extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        logger.info(
            "workout_session_state from=\(fromState.rawValue) to=\(toState.rawValue)"
        )
    }

    public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: any Error
    ) {
        logger.error(
            "workout_session_error error=\(error.localizedDescription, privacy: .private)"
        )
        lock.withLock {
            session = nil
            builder = nil
            activeBuilderID = nil
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

@available(watchOS 5.0, *)
extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // Lifecycle gate — reject callbacks that belong to a builder we no
        // longer own (session ended, session was replaced, or session failed
        // with `didFailWithError`). This prevents HKLiveWorkoutBuilder's
        // trailing callbacks from pushing stray HR after end/failure.
        let (sessionActive, activeID) = lock.withLock {
            (self.session != nil, self.activeBuilderID)
        }
        let callbackID = ObjectIdentifier(workoutBuilder)
        guard WorkoutBuilderGate.shouldProcess(
            sessionActive: sessionActive,
            activeBuilderID: activeID,
            callbackBuilderID: callbackID
        ) else {
            logger.info("workout_builder_callback_ignored reason=stale_or_inactive")
            return
        }
        pushHRSamplesIfAvailable(collectedTypes: collectedTypes, from: workoutBuilder)
    }

    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No HR value — nothing to forward here. Kept to satisfy protocol.
    }
}

#endif // os(watchOS)
