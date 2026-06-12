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

    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false
    private var isAuthorized = false

    func scheduleRestComplete(afterSeconds seconds: TimeInterval) async {
        if !hasRequestedAuthorization {
            await requestAuthorization()
        }
        guard isAuthorized, seconds > 0 else { return }

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

    private func requestAuthorization() async {
        hasRequestedAuthorization = true
        do {
            isAuthorized = try await center.requestAuthorization(
                options: [.alert, .sound]
            )
            logger.info(
                "rest_notification_permission status=\(self.isAuthorized ? "granted" : "denied", privacy: .public)"
            )
        } catch {
            isAuthorized = false
            logger.error(
                "rest_notification_permission status=error error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
