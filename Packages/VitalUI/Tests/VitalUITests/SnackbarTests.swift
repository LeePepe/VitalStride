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

    @MainActor
    private func makeModifier(edge: VerticalEdge) -> SnackbarModifier<Text> {
        SnackbarModifier(
            isPresented: .constant(true),
            edge: edge,
            mode: .autoDismiss(),
            onDismiss: nil,
            snackbarContent: { Text("Test") }
        )
    }

    @Test("top edge produces top-aligned overlay and transition")
    @MainActor
    func topEdgeConfiguration() {
        let modifier = makeModifier(edge: .top)
        #expect(modifier.overlayAlignment == .top)
        #expect(modifier.transitionEdge == .top)
        #expect(modifier.edgePaddingEdge == .top)
    }

    @Test("bottom edge produces bottom-aligned overlay and transition")
    @MainActor
    func bottomEdgeConfiguration() {
        let modifier = makeModifier(edge: .bottom)
        #expect(modifier.overlayAlignment == .bottom)
        #expect(modifier.transitionEdge == .bottom)
        #expect(modifier.edgePaddingEdge == .bottom)
    }

    @Test("shadow always casts downward regardless of edge")
    @MainActor
    func shadowAlwaysDownward() {
        let top = makeModifier(edge: .top)
        let bottom = makeModifier(edge: .bottom)
        #expect(top.shadowYOffset == 4)
        #expect(bottom.shadowYOffset == 4)
        #expect(top.shadowYOffset == bottom.shadowYOffset)
    }

    @Test("snackbar view extension defaults to bottom edge")
    @MainActor
    func defaultEdgeIsBottom() {
        let modifier = makeModifier(edge: .bottom)
        #expect(modifier.edge == .bottom)
        #expect(modifier.overlayAlignment == .bottom)
    }
}
