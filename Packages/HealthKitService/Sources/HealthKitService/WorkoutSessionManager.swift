import Foundation
import HealthKit
import os

// MARK: - Protocol

public protocol WorkoutSessionManaging: Sendable {
    func startSession() async
    func endSession(save: Bool) async
}

// MARK: - NoopWorkoutSessionManager

public struct NoopWorkoutSessionManager: WorkoutSessionManaging {
    public init() {}
    public func startSession() async {}
    public func endSession(save: Bool) async {}
}

// MARK: - WorkoutSessionManager

#if !os(macOS)

public final class WorkoutSessionManager: NSObject, WorkoutSessionManaging, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let logger: Logger
    private let lock = NSLock()

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionStartTime: Date?

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
            try await newBuilder.beginCollection(at: startDate)

            lock.withLock {
                self.session = newSession
                self.builder = newBuilder
                self.sessionStartTime = startDate
            }

            logger.info("workout_session_started activityType=traditionalStrengthTraining")
        } catch {
            logger.error(
                "workout_session_start_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    public func endSession(save: Bool) async {
        let (currentSession, currentBuilder, startTime) = lock.withLock {
            let result = (session, builder, sessionStartTime)
            session = nil
            builder = nil
            sessionStartTime = nil
            return result
        }

        guard let currentSession, let currentBuilder else {
            return
        }

        let endDate = Date()
        let durationSeconds = startTime.map { Int(endDate.timeIntervalSince($0)) } ?? 0

        currentSession.end()

        do {
            try await currentBuilder.endCollection(at: endDate)

            if save {
                try await currentBuilder.finishWorkout()
                logger.info(
                    "workout_session_ended duration_seconds=\(durationSeconds) saved=true"
                )
            } else {
                currentBuilder.discardWorkout()
                logger.info(
                    "workout_session_ended duration_seconds=\(durationSeconds) saved=false"
                )
            }
        } catch {
            logger.error(
                "workout_session_end_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

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
            sessionStartTime = nil
        }
    }
}

#endif // !os(macOS)
