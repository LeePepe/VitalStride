import Foundation
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "RestTimer")

enum RestPhase {
    case idle
    case resting
    case completed
}

@MainActor
@Observable
final class RestTimerController {
    private(set) var restEndDate: Date?
    private(set) var restTotalDuration: TimeInterval?
    private(set) var phase: RestPhase = .idle

    let completedDisplayDuration: TimeInterval
    private let notificationScheduler: any RestNotificationScheduling
    private let liveActivityManager: any RestLiveActivityManaging
    private var restGeneration = 0

    init(
        completedDisplayDuration: TimeInterval = 2,
        notificationScheduler: any RestNotificationScheduling = RestNotificationScheduler(),
        liveActivityManager: any RestLiveActivityManaging = RestLiveActivityManager()
    ) {
        self.completedDisplayDuration = completedDisplayDuration
        self.notificationScheduler = notificationScheduler
        self.liveActivityManager = liveActivityManager
    }

    func startRest(duration: TimeInterval = 60) {
        restGeneration += 1
        let generation = restGeneration
        let endDate = Date().addingTimeInterval(duration)
        restEndDate = endDate
        restTotalDuration = duration
        phase = .resting
        Task {
            await notificationScheduler.scheduleRestComplete(afterSeconds: duration)
            if restGeneration != generation {
                notificationScheduler.cancelPendingRestNotification()
            }
        }
        Task {
            await liveActivityManager.startActivity(
                totalDuration: duration,
                endDate: endDate
            )
        }
    }

    func adjustRest(by seconds: TimeInterval) {
        guard phase == .resting, let currentEnd = restEndDate else { return }
        let newEnd = currentEnd.addingTimeInterval(seconds)
        restEndDate = newEnd
        let newTotal = max(0, (restTotalDuration ?? 0) + seconds)
        restTotalDuration = newTotal
        let remaining = newEnd.timeIntervalSinceNow
        if remaining > 0 {
            restGeneration += 1
            let generation = restGeneration
            Task {
                await notificationScheduler.scheduleRestComplete(
                    afterSeconds: remaining
                )
                if restGeneration != generation {
                    notificationScheduler.cancelPendingRestNotification()
                }
            }
            Task {
                await liveActivityManager.updateActivity(
                    endDate: newEnd,
                    totalDuration: newTotal
                )
            }
            logger.info(
                "rest_notification_rescheduled remaining=\(Int(remaining), privacy: .public)"
            )
        } else {
            restGeneration += 1
            notificationScheduler.cancelPendingRestNotification()
            logger.info("rest_notification_cancelled reason=adjust_expired")
        }
    }

    func skipRest() {
        restGeneration += 1
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
        notificationScheduler.cancelPendingRestNotification()
        Task {
            await liveActivityManager.endActivity(reason: .skipped)
        }
        logger.info("rest_notification_cancelled reason=skip")
    }

    func cancelRestForWorkoutEnd() {
        restGeneration += 1
        notificationScheduler.cancelPendingRestNotification()
        if phase == .resting {
            restEndDate = nil
            restTotalDuration = nil
            phase = .idle
            Task {
                await liveActivityManager.endActivity(reason: .workoutEnded)
            }
            logger.info("rest_notification_cancelled reason=workout_ended")
        }
    }

    func dismissCompleted() {
        guard phase == .completed else { return }
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
    }

    func handleTimerTask() async {
        guard let restEnd = restEndDate, phase == .resting else { return }
        let remaining = restEnd.timeIntervalSinceNow
        if remaining > 0 {
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch { return }
        }
        guard restEndDate == restEnd else { return }
        phase = .completed
        await liveActivityManager.endActivity(reason: .completed)
        do {
            try await Task.sleep(for: .seconds(completedDisplayDuration))
        } catch { return }
        guard restEndDate == restEnd, phase == .completed else { return }
        restEndDate = nil
        restTotalDuration = nil
        phase = .idle
    }
}
