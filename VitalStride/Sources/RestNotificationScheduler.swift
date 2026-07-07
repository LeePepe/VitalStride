import UserNotifications
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "RestTimer")

@MainActor
protocol RestNotificationScheduling {
    func scheduleRestComplete(afterSeconds seconds: TimeInterval) async
    func cancelPendingRestNotification()
}

@MainActor
final class RestNotificationScheduler: RestNotificationScheduling {
    static let notificationIdentifier = "rest-timer-complete"

    // UNUserNotificationCenter.current() returns a process-wide singleton that Apple documents as
    // thread-safe. Marking the stored reference `nonisolated(unsafe)` lets async methods like
    // `add(_:)` and `requestAuthorization(options:)` receive it across the MainActor boundary
    // without a spurious "Sending 'self.center' risks causing data races" Swift 6 diagnostic,
    // without weakening isolation for the rest of the type.
    nonisolated(unsafe) private let center = UNUserNotificationCenter.current()
    private var authorizationTask: Task<Bool, Never>?

    func scheduleRestComplete(afterSeconds seconds: TimeInterval) async {
        let authorized = await ensureAuthorized()
        guard authorized else {
            logger.info("rest_notification_skipped reason=not_authorized")
            return
        }
        guard seconds > 0 else {
            logger.info("rest_notification_skipped reason=invalid_duration")
            return
        }

        center.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier]
        )

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "rest_notification_title",
            comment: "Rest complete notification title"
        )
        content.body = String(
            localized: "rest_notification_body",
            comment: "Rest complete notification body"
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: seconds,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info(
                "rest_notification_scheduled duration=\(Int(seconds), privacy: .public)"
            )
        } catch {
            logger.error(
                "rest_notification_schedule_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func cancelPendingRestNotification() {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier]
        )
    }

    private func ensureAuthorized() async -> Bool {
        if let task = authorizationTask {
            return await task.value
        }
        let task = Task<Bool, Never> {
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound]
                )
                logger.info(
                    "rest_notification_permission status=\(granted ? "granted" : "denied", privacy: .public)"
                )
                return granted
            } catch {
                logger.error(
                    "rest_notification_permission status=error error=\(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }
        authorizationTask = task
        return await task.value
    }
}
