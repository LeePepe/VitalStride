import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "RestTimer")

@MainActor
protocol RestLiveActivityManaging: Sendable {
    func startActivity(totalDuration: TimeInterval, endDate: Date) async
    func updateActivity(endDate: Date, totalDuration: TimeInterval) async
    func endActivity(reason: RestLiveActivityEndReason) async
}

enum RestLiveActivityEndReason: String, Sendable {
    case completed
    case skipped
    case workoutEnded
}

@MainActor
final class RestLiveActivityManager: RestLiveActivityManaging {
    private var currentActivity: Activity<RestTimerAttributes>?

    func startActivity(totalDuration: TimeInterval, endDate: Date) async {
        await endActivityIfNeeded()

        let attributes = RestTimerAttributes(totalDuration: totalDuration)
        let state = RestTimerAttributes.ContentState(
            endDate: endDate,
            totalDuration: totalDuration,
            phase: .resting
        )

        do {
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endDate),
                pushType: nil
            )
            currentActivity = activity
            logger.info(
                "rest_live_activity_started duration=\(Int(totalDuration), privacy: .public)"
            )
        } catch {
            logger.error(
                "rest_live_activity_start_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func updateActivity(endDate: Date, totalDuration: TimeInterval) async {
        guard let activity = currentActivity else { return }
        let state = RestTimerAttributes.ContentState(
            endDate: endDate,
            totalDuration: totalDuration,
            phase: .resting
        )
        nonisolated(unsafe) let unsafeActivity = activity
        await unsafeActivity.update(.init(state: state, staleDate: endDate))
        logger.info(
            "rest_live_activity_updated remaining=\(Int(endDate.timeIntervalSinceNow), privacy: .public)"
        )
    }

    func endActivity(reason: RestLiveActivityEndReason) async {
        guard let activity = currentActivity else { return }
        let finalState = RestTimerAttributes.ContentState(
            endDate: .now,
            totalDuration: 0,
            phase: .completed
        )
        nonisolated(unsafe) let unsafeActivity = activity
        await unsafeActivity.end(
            .init(state: finalState, staleDate: nil),
            dismissalPolicy: .default
        )
        currentActivity = nil
        logger.info(
            "rest_live_activity_ended reason=\(reason.rawValue, privacy: .public)"
        )
    }

    private func endActivityIfNeeded() async {
        guard let activity = currentActivity else { return }
        let finalState = RestTimerAttributes.ContentState(
            endDate: .now,
            totalDuration: 0,
            phase: .completed
        )
        nonisolated(unsafe) let unsafeActivity = activity
        await unsafeActivity.end(
            .init(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        currentActivity = nil
    }
}
