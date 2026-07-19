import Foundation
import HealthKit
import os

// MARK: - Protocol

public protocol WorkoutSessionManaging: Sendable {
    func startSession() async
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
    public func startSession() async {}
    public func endSession(save: Bool) async -> String? { nil }
    // observe*/update* inherit default no-op impls from the protocol extension.
}

// MARK: - WorkoutSessionManager

#if os(watchOS)

@available(watchOS 5.0, *)
public final class WorkoutSessionManager: NSObject, WorkoutSessionManaging, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let logger: Logger
    private let lock = NSLock()

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        self.logger = Logger(subsystem: "com.vitalstride", category: "WorkoutSession")
        super.init()
    }

    public func startSession() async {
        guard lock.withLock({ session == nil }) else {
            logger.info("workout_session_start_skipped reason=already_active")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        do {
            let newSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            newSession.delegate = self

            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let startDate = Date()
            newSession.startActivity(with: startDate)

            do {
                try await newBuilder.beginCollection(at: startDate)
            } catch {
                newSession.end()
                throw error
            }

            lock.withLock {
                self.session = newSession
                self.builder = newBuilder
            }

            logger.info("workout_session_started activityType=traditionalStrengthTraining")
        } catch {
            logger.error(
                "workout_session_start_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    public func endSession(save: Bool) async -> String? {
        let (currentSession, currentBuilder) = lock.withLock {
            let result = (session, builder)
            session = nil
            builder = nil
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
                logger.info("workout_session_ended saved=true")
                return hkWorkout?.uuid.uuidString
            } else {
                currentBuilder.discardWorkout()
                logger.info("workout_session_ended saved=false")
                return nil
            }
        } catch {
            logger.error(
                "workout_session_end_failed error=\(error.localizedDescription, privacy: .private)"
            )
            return nil
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
        }
    }
}

#endif // os(watchOS)
