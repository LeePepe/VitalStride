import Testing
import Foundation

@testable import VitalStride

@MainActor
final class MockNotificationScheduler: RestNotificationScheduling {
    var scheduledDurations: [TimeInterval] = []
    var cancelCount = 0

    func scheduleRestComplete(afterSeconds seconds: TimeInterval) async {
        scheduledDurations.append(seconds)
    }

    func cancelPendingRestNotification() {
        cancelCount += 1
    }
}

@Suite("RestTimerController notification integration")
struct RestTimerNotificationTests {

    @MainActor
    @Test("Default rest duration is 60 seconds")
    func defaultDurationIs60() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest()

        #expect(controller.restTotalDuration == 60)
    }

    @MainActor
    @Test("startRest schedules notification with correct duration")
    func startRestSchedulesNotification() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.scheduledDurations == [60])
    }

    @MainActor
    @Test("skipRest cancels pending notification")
    func skipRestCancelsNotification() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest(duration: 60)
        controller.skipRest()

        #expect(mock.cancelCount == 1)
    }

    @MainActor
    @Test("adjustRest reschedules notification with new remaining time")
    func adjustRestReschedulesNotification() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        controller.adjustRest(by: 10)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.scheduledDurations.count == 2)
        #expect(mock.scheduledDurations[0] == 60)
        let rescheduled = mock.scheduledDurations[1]
        #expect(rescheduled > 60, "Rescheduled duration should be roughly 70 (60 + 10 minus elapsed)")
        #expect(rescheduled <= 70)
    }

    @MainActor
    @Test("adjustRest with negative offset beyond remaining cancels notification")
    func adjustRestExpiredCancelsNotification() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest(duration: 5)
        controller.adjustRest(by: -10)

        #expect(mock.cancelCount >= 1)
    }

    @MainActor
    @Test("Multiple startRest calls each schedule a notification")
    func multipleStartRestSchedulesEach() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        controller.startRest(duration: 90)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.scheduledDurations.count == 2)
        #expect(mock.scheduledDurations[0] == 60)
        #expect(mock.scheduledDurations[1] == 90)
    }

    @MainActor
    @Test("dismissCompleted does not cancel notification")
    func dismissCompletedNoNotificationCancel() async {
        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 10,
            notificationScheduler: mock
        )

        controller.startRest(duration: 0.1)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.phase == .completed)

        controller.dismissCompleted()
        #expect(mock.cancelCount == 0)

        task.cancel()
    }
}
