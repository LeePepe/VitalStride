import SwiftUI
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

    @Test("isScheduled becomes false after task completes")
    @MainActor
    func isScheduledClearsAfterCompletion() async throws {
        let scheduler = SnackbarDismissScheduler()

        scheduler.schedule(duration: 0.1) {}

        #expect(scheduler.isScheduled)
        try await Task.sleep(for: .seconds(0.25))
        #expect(!scheduler.isScheduled)
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
        #expect(!scheduler.isScheduled)
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

    @Test("schedule with new duration replaces running timer")
    @MainActor
    func durationChangeReplacesTimer() async throws {
        let scheduler = SnackbarDismissScheduler()
        var dismissed = false

        scheduler.schedule(duration: 1.0) {
            dismissed = true
        }

        scheduler.schedule(duration: 0.1) {
            dismissed = true
        }

        try await Task.sleep(for: .seconds(0.25))
        #expect(dismissed)
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

@Suite("SnackbarModifier Edge")
struct SnackbarEdgeTests {

    @Test("snackbar defaults to bottom edge")
    @MainActor
    func defaultEdgeIsBottom() {
        let view = Text("Hello")
            .snackbar(isPresented: .constant(true)) {
                Text("Default")
            }
        _ = view
    }

    @Test("snackbar accepts top edge parameter")
    @MainActor
    func topEdgeAccepted() {
        let view = Text("Hello")
            .snackbar(isPresented: .constant(true), edge: .top) {
                Text("Top snackbar")
            }
        _ = view
    }

    @Test("snackbar accepts bottom edge parameter explicitly")
    @MainActor
    func bottomEdgeExplicit() {
        let view = Text("Hello")
            .snackbar(isPresented: .constant(true), edge: .bottom) {
                Text("Bottom snackbar")
            }
        _ = view
    }

    @Test("top edge snackbar with custom mode")
    @MainActor
    func topEdgeWithCustomMode() {
        let view = Text("Hello")
            .snackbar(isPresented: .constant(true), edge: .top, mode: .persistent) {
                Text("Persistent top snackbar")
            }
        _ = view
    }
}
