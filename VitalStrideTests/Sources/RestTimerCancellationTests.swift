import Testing
import Foundation

@testable import VitalStride

@Suite("RestTimerController cancellation safety")
struct RestTimerCancellationTests {

    @MainActor
    @Test("Cancelled task does not nil out restEndDate")
    func cancelledTaskPreservesValue() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        #expect(controller.restEndDate != nil)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(controller.restEndDate != nil, "Cancelled timer must not nil out restEndDate")
        #expect(controller.phase == .resting, "Cancelled timer must preserve resting phase")
    }

    @MainActor
    @Test("Natural expiry nils out restEndDate after completed display")
    func naturalExpiryNilsValue() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 0.1)

        await controller.handleTimerTask()

        #expect(controller.restEndDate == nil, "After full lifecycle, restEndDate should be nil")
        #expect(controller.phase == .idle, "After full lifecycle, phase should be idle")
    }

    @MainActor
    @Test("startRest during active timer resets to new value")
    func restartPreservesNewValue() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
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
        #expect(controller.phase == .resting, "Phase should remain resting after restart")
    }

    @MainActor
    @Test("Stale task completion does not clear newer restEndDate")
    func staleCompletionDoesNotClearNewer() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 0.1)

        let staleTask = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(50))

        controller.startRest(duration: 90)
        let newEnd = controller.restEndDate

        _ = await staleTask.result

        #expect(controller.restEndDate == newEnd, "Completed stale task must not clear a newer restEndDate")
        #expect(controller.phase == .resting, "Phase should remain resting for the new timer")
    }

    @MainActor
    @Test("Rapid re-assignment preserves latest value")
    func rapidReassignmentPreservesLatest() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)

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
        #expect(controller.phase == .resting, "Phase should remain resting")

        tasks.last?.cancel()
    }

    @MainActor
    @Test("skipRest clears restEndDate")
    func skipRestClearsValue() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        #expect(controller.restEndDate != nil)

        controller.skipRest()
        #expect(controller.restEndDate == nil, "skipRest should nil out restEndDate")
        #expect(controller.phase == .idle, "skipRest should set phase to idle")
    }

    @MainActor
    @Test("startRest sets restTotalDuration")
    func startRestSetsTotal() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 60)
        #expect(controller.restTotalDuration == 60)
    }

    @MainActor
    @Test("restTotalDuration updates on restart with different duration")
    func restartUpdatesTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 60)
        #expect(controller.restTotalDuration == 60)

        controller.startRest(duration: 120)
        #expect(controller.restTotalDuration == 120)
    }

    @MainActor
    @Test("skipRest clears restTotalDuration")
    func skipRestClearsTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        #expect(controller.restTotalDuration == 90)

        controller.skipRest()
        #expect(controller.restTotalDuration == nil, "skipRest should nil out restTotalDuration")
    }

    @MainActor
    @Test("Natural expiry clears restTotalDuration after completed display")
    func naturalExpiryClearsTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 0.1)
        #expect(controller.restTotalDuration == 0.1)

        await controller.handleTimerTask()

        #expect(controller.restTotalDuration == nil, "After full lifecycle, restTotalDuration should be nil")
    }

    @MainActor
    @Test("Cancelled task preserves restTotalDuration")
    func cancelledTaskPreservesTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
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
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        let originalEnd = controller.restEndDate!

        controller.adjustRest(by: 10)

        let expected = originalEnd.addingTimeInterval(10)
        #expect(controller.restEndDate == expected)
    }

    @MainActor
    @Test("+10s updates restTotalDuration")
    func adjustPositiveUpdatesTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)

        controller.adjustRest(by: 10)

        #expect(controller.restTotalDuration == 100)
    }

    @MainActor
    @Test("-10s reduces restEndDate by 10 seconds")
    func adjustNegativeReducesEndDate() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        let originalEnd = controller.restEndDate!

        controller.adjustRest(by: -10)

        let expected = originalEnd.addingTimeInterval(-10)
        #expect(controller.restEndDate == expected)
    }

    @MainActor
    @Test("-10s updates restTotalDuration")
    func adjustNegativeUpdatesTotalDuration() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)

        controller.adjustRest(by: -10)

        #expect(controller.restTotalDuration == 80)
    }

    @MainActor
    @Test("-10s with remaining ≤10s transitions through completed phase")
    func adjustNegativeEndsRestWhenRemainingLow() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 5)

        controller.adjustRest(by: -10)

        #expect(controller.restEndDate != nil, "restEndDate set to past date, not nil — handleTimerTask handles lifecycle")
        #expect(controller.phase == .resting, "Phase stays resting until handleTimerTask processes it")

        await controller.handleTimerTask()

        #expect(controller.restEndDate == nil, "After full lifecycle, restEndDate should be nil")
        #expect(controller.restTotalDuration == nil, "After full lifecycle, restTotalDuration should be nil")
        #expect(controller.phase == .idle, "Phase should be idle after completed display")
    }

    @MainActor
    @Test("-10s crossing zero enters completed phase before clearing")
    func adjustNegativeEntersCompletedPhase() async {
        let controller = RestTimerController(completedDisplayDuration: 10)
        controller.startRest(duration: 5)

        controller.adjustRest(by: -10)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(200))

        #expect(controller.phase == .completed, "Adjustment crossing zero should enter completed phase")
        #expect(controller.restEndDate != nil, "restEndDate preserved during completed display")

        task.cancel()
    }

    @MainActor
    @Test("adjustRest is no-op without active timer")
    func adjustRestNoOpWithoutTimer() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)

        controller.adjustRest(by: 10)

        #expect(controller.restEndDate == nil)
        #expect(controller.restTotalDuration == nil)
    }

    @MainActor
    @Test("Multiple adjustments accumulate correctly")
    func multipleAdjustmentsAccumulate() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
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
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 5)

        controller.adjustRest(by: 10)

        #expect(controller.restTotalDuration! >= 0)
    }
}

@Suite("RestTimerController rest completed state")
struct RestTimerCompletedTests {

    @MainActor
    @Test("Natural expiry enters completed phase before clearing")
    func naturalExpiryEntersCompleted() async {
        let controller = RestTimerController(completedDisplayDuration: 10)
        controller.startRest(duration: 0.1)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(300))

        #expect(controller.phase == .completed, "Timer should enter completed phase after expiry")
        #expect(controller.restEndDate != nil, "restEndDate preserved during completed display")
        #expect(controller.restTotalDuration != nil, "restTotalDuration preserved during completed display")

        task.cancel()
    }

    @MainActor
    @Test("Skip does not trigger completed phase")
    func skipDoesNotTriggerCompleted() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        #expect(controller.phase == .resting)

        controller.skipRest()

        #expect(controller.phase == .idle, "skipRest should go directly to idle, not completed")
        #expect(controller.restEndDate == nil)
    }

    @MainActor
    @Test("Completed phase auto-clears after display duration")
    func completedAutoClears() async {
        let controller = RestTimerController(completedDisplayDuration: 0.2)
        controller.startRest(duration: 0.1)

        await controller.handleTimerTask()

        #expect(controller.phase == .idle, "Phase should auto-clear to idle")
        #expect(controller.restEndDate == nil, "restEndDate should be nil after auto-clear")
        #expect(controller.restTotalDuration == nil, "restTotalDuration should be nil after auto-clear")
    }

    @MainActor
    @Test("startRest during completed transitions to resting")
    func startRestDuringCompleted() async {
        let controller = RestTimerController(completedDisplayDuration: 10)
        controller.startRest(duration: 0.1)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.phase == .completed)

        controller.startRest(duration: 60)

        #expect(controller.phase == .resting, "startRest should override completed with resting")
        #expect(controller.restTotalDuration == 60)

        task.cancel()
    }

    @MainActor
    @Test("dismissCompleted clears completed state")
    func dismissCompletedClears() async {
        let controller = RestTimerController(completedDisplayDuration: 10)
        controller.startRest(duration: 0.1)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.phase == .completed)

        controller.dismissCompleted()

        #expect(controller.phase == .idle, "dismissCompleted should set phase to idle")
        #expect(controller.restEndDate == nil)
        #expect(controller.restTotalDuration == nil)

        task.cancel()
    }

    @MainActor
    @Test("dismissCompleted is no-op when not in completed phase")
    func dismissCompletedNoOpWhenIdle() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        controller.startRest(duration: 90)
        let endDate = controller.restEndDate

        controller.dismissCompleted()

        #expect(controller.phase == .resting, "dismissCompleted should not affect resting phase")
        #expect(controller.restEndDate == endDate)
    }

    @MainActor
    @Test("adjustRest is no-op during completed phase")
    func adjustRestNoOpDuringCompleted() async {
        let controller = RestTimerController(completedDisplayDuration: 10)
        controller.startRest(duration: 0.1)

        let task = Task { @MainActor in
            await controller.handleTimerTask()
        }

        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.phase == .completed)

        let endDateBefore = controller.restEndDate
        controller.adjustRest(by: 10)

        #expect(controller.restEndDate == endDateBefore, "adjustRest should be no-op during completed")
        #expect(controller.phase == .completed)

        task.cancel()
    }

    @MainActor
    @Test("startRest sets phase to resting")
    func startRestSetsResting() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        #expect(controller.phase == .idle)

        controller.startRest(duration: 60)

        #expect(controller.phase == .resting)
    }

    @MainActor
    @Test("Initial phase is idle")
    func initialPhaseIsIdle() async {
        let controller = RestTimerController(completedDisplayDuration: 0.1)
        #expect(controller.phase == .idle)
        #expect(controller.restEndDate == nil)
        #expect(controller.restTotalDuration == nil)
    }
}
