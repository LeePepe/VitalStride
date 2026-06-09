import Testing
@testable import VitalUI

@Suite("SnackbarDismissScheduler")
struct SnackbarDismissSchedulerTests {

    @Test("auto-dismiss fires callback after specified duration")
    @MainActor
    func autoDismissFires() async throws {
        let scheduler = SnackbarDismissScheduler()
        var dismissed = false

        scheduler.schedule(duration: 0.1) {
            dismissed = true
        }

        #expect(scheduler.isScheduled)
        try await Task.sleep(for: .seconds(0.25))
        #expect(dismissed)
    }

    @Test("persistent mode does not schedule any dismiss")
    @MainActor
    func persistentModeNoSchedule() async throws {
        let scheduler = SnackbarDismissScheduler()
        let mode = SnackbarMode.persistent

        if case .autoDismiss(let duration) = mode {
            scheduler.schedule(duration: duration) {}
        }

        #expect(!scheduler.isScheduled)
        try await Task.sleep(for: .seconds(0.15))
        #expect(!scheduler.isScheduled)
    }

    @Test("cancel prevents dismiss callback from firing")
    @MainActor
    func cancelPreventsCallback() async throws {
        let scheduler = SnackbarDismissScheduler()
        var dismissed = false

        scheduler.schedule(duration: 0.2) {
            dismissed = true
        }

        #expect(scheduler.isScheduled)
        scheduler.cancel()
        try await Task.sleep(for: .seconds(0.35))
        #expect(!dismissed)
    }

    @Test("rescheduling cancels previous timer")
    @MainActor
    func rescheduleReplacesTimer() async throws {
        let scheduler = SnackbarDismissScheduler()
        var firstFired = false
        var secondFired = false

        scheduler.schedule(duration: 0.3) {
            firstFired = true
        }

        scheduler.schedule(duration: 0.1) {
            secondFired = true
        }

        try await Task.sleep(for: .seconds(0.25))
        #expect(!firstFired)
        #expect(secondFired)
    }
}

@Suite("SnackbarMode")
struct SnackbarModeTests {

    @Test("auto-dismiss default duration is 3 seconds")
    func defaultDuration() {
        let mode = SnackbarMode.autoDismiss()
        guard case .autoDismiss(let duration) = mode else {
            Issue.record("Expected autoDismiss")
            return
        }
        #expect(duration == 3)
    }

    @Test("auto-dismiss accepts custom duration")
    func customDuration() {
        let mode = SnackbarMode.autoDismiss(duration: 5)
        guard case .autoDismiss(let duration) = mode else {
            Issue.record("Expected autoDismiss")
            return
        }
        #expect(duration == 5)
    }

    @Test("persistent and auto-dismiss are distinct")
    func modesAreDistinct() {
        #expect(SnackbarMode.persistent != SnackbarMode.autoDismiss())
    }

    @Test("equatable compares durations")
    func equatableComparesDuration() {
        #expect(SnackbarMode.autoDismiss(duration: 3) == SnackbarMode.autoDismiss(duration: 3))
        #expect(SnackbarMode.autoDismiss(duration: 3) != SnackbarMode.autoDismiss(duration: 5))
    }
}
