import Testing
import Foundation

@testable import VitalStride

@Suite("RestTimerController cancellation safety")
struct RestTimerCancellationTests {

    @MainActor
    @Test("Cancelled task does not nil out restEndDate")
    func cancelledTaskPreservesValue() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        #expect(controller.restEndDate != nil)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(controller.restEndDate != nil, "Cancelled timer must not nil out restEndDate")
    }

    @MainActor
    @Test("Natural expiry nils out restEndDate")
    func naturalExpiryNilsValue() async {
        let controller = RestTimerController()
        controller.startRest(duration: 0.1)

        await controller.handleTimerTask()

        #expect(controller.restEndDate == nil, "Naturally expired timer should nil out restEndDate")
    }

    @MainActor
    @Test("startRest during active timer resets to new value")
    func restartPreservesNewValue() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        let firstEnd = controller.restEndDate

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))

        controller.startRest(duration: 90)
        let secondEnd = controller.restEndDate
        #expect(secondEnd != firstEnd, "startRest should assign a new end date")

        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(controller.restEndDate == secondEnd, "Cancelled old task must not clear the new timer")
    }

    @MainActor
    @Test("Stale task completion does not clear newer restEndDate")
    func staleCompletionDoesNotClearNewer() async {
        let controller = RestTimerController()
        controller.startRest(duration: 0.1)

        let staleTask = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))

        controller.startRest(duration: 90)
        let newEnd = controller.restEndDate

        _ = await staleTask.result

        #expect(controller.restEndDate == newEnd, "Completed stale task must not clear a newer restEndDate")
    }

    @MainActor
    @Test("Rapid re-assignment preserves latest value")
    func rapidReassignmentPreservesLatest() async {
        let controller = RestTimerController()

        var tasks: [Task<Void, Never>] = []
        for _ in 0..<5 {
            controller.startRest(duration: 90)

            let task = Task { @MainActor in
                await controller.handleTimerTask()
            }
            tasks.last?.cancel()
            tasks.append(task)
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await Task.sleep(for: .milliseconds(100))

        #expect(controller.restEndDate != nil, "After rapid re-assignments, restEndDate must not be nil")

        tasks.last?.cancel()
    }

    @MainActor
    @Test("skipRest clears restEndDate")
    func skipRestClearsValue() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        #expect(controller.restEndDate != nil)

        controller.skipRest()
        #expect(controller.restEndDate == nil, "skipRest should nil out restEndDate")
    }
}
