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

    @MainActor
    @Test("startRest sets restTotalDuration")
    func startRestSetsTotal() async {
        let controller = RestTimerController()
        controller.startRest(duration: 60)
        #expect(controller.restTotalDuration == 60)
    }

    @MainActor
    @Test("restTotalDuration updates on restart with different duration")
    func restartUpdatesTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 60)
        #expect(controller.restTotalDuration == 60)

        controller.startRest(duration: 120)
        #expect(controller.restTotalDuration == 120)
    }

    @MainActor
    @Test("skipRest clears restTotalDuration")
    func skipRestClearsTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        #expect(controller.restTotalDuration == 90)

        controller.skipRest()
        #expect(controller.restTotalDuration == nil, "skipRest should nil out restTotalDuration")
    }

    @MainActor
    @Test("Natural expiry clears restTotalDuration")
    func naturalExpiryClearsTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 0.1)
        #expect(controller.restTotalDuration == 0.1)

        await controller.handleTimerTask()

        #expect(controller.restTotalDuration == nil, "Naturally expired timer should nil out restTotalDuration")
    }

    @MainActor
    @Test("Cancelled task preserves restTotalDuration")
    func cancelledTaskPreservesTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        #expect(controller.restTotalDuration == 90)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(controller.restTotalDuration == 90, "Cancelled timer must not nil out restTotalDuration")
    }

    // MARK: - adjustRest(by:)

    @MainActor
    @Test("+10s extends restEndDate by 10 seconds")
    func adjustPositiveExtendsEndDate() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        let originalEnd = controller.restEndDate!

        controller.adjustRest(by: 10)

        let expected = originalEnd.addingTimeInterval(10)
        #expect(controller.restEndDate == expected)
    }

    @MainActor
    @Test("+10s updates restTotalDuration")
    func adjustPositiveUpdatesTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)

        controller.adjustRest(by: 10)

        #expect(controller.restTotalDuration == 100)
    }

    @MainActor
    @Test("-10s reduces restEndDate by 10 seconds")
    func adjustNegativeReducesEndDate() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        let originalEnd = controller.restEndDate!

        controller.adjustRest(by: -10)

        let expected = originalEnd.addingTimeInterval(-10)
        #expect(controller.restEndDate == expected)
    }

    @MainActor
    @Test("-10s updates restTotalDuration")
    func adjustNegativeUpdatesTotalDuration() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)

        controller.adjustRest(by: -10)

        #expect(controller.restTotalDuration == 80)
    }

    @MainActor
    @Test("-10s with remaining ≤10s ends rest")
    func adjustNegativeEndsRestWhenRemainingLow() async {
        let controller = RestTimerController()
        controller.startRest(duration: 5)

        controller.adjustRest(by: -10)

        #expect(controller.restEndDate == nil, "Rest should end when remaining ≤ 0 after -10s")
        #expect(controller.restTotalDuration == nil, "Total duration should be cleared when rest ends")
    }

    @MainActor
    @Test("adjustRest is no-op without active timer")
    func adjustRestNoOpWithoutTimer() async {
        let controller = RestTimerController()

        controller.adjustRest(by: 10)

        #expect(controller.restEndDate == nil)
        #expect(controller.restTotalDuration == nil)
    }

    @MainActor
    @Test("Multiple adjustments accumulate correctly")
    func multipleAdjustmentsAccumulate() async {
        let controller = RestTimerController()
        controller.startRest(duration: 90)
        let originalEnd = controller.restEndDate!

        controller.adjustRest(by: 10)
        controller.adjustRest(by: 10)
        controller.adjustRest(by: -10)

        let expected = originalEnd.addingTimeInterval(10)
        #expect(controller.restEndDate == expected)
        #expect(controller.restTotalDuration == 100)
    }

    @MainActor
    @Test("restTotalDuration does not go below zero")
    func totalDurationFlooredAtZero() async {
        let controller = RestTimerController()
        controller.startRest(duration: 5)

        controller.adjustRest(by: 10)

        #expect(controller.restTotalDuration! >= 0)
    }
}
