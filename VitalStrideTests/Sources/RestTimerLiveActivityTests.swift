import Testing
import Foundation

@testable import VitalStride

@MainActor
final class MockLiveActivityManager: RestLiveActivityManaging {
    var startCalls: [(totalDuration: TimeInterval, endDate: Date)] = []
    var updateCalls: [(endDate: Date, totalDuration: TimeInterval)] = []
    var endCalls: [RestLiveActivityEndReason] = []

    func startActivity(totalDuration: TimeInterval, endDate: Date) async {
        startCalls.append((totalDuration, endDate))
    }

    func updateActivity(endDate: Date, totalDuration: TimeInterval) async {
        updateCalls.append((endDate, totalDuration))
    }

    func endActivity(reason: RestLiveActivityEndReason) async {
        endCalls.append(reason)
    }
}

@Suite("RestTimerAttributes encoding/decoding")
struct RestTimerAttributesTests {

    @Test("ContentState round-trips through JSON encoding")
    func contentStateRoundTrip() throws {
        let state = RestTimerAttributes.ContentState(
            endDate: Date(timeIntervalSince1970: 1000),
            totalDuration: 60,
            phase: .resting
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            RestTimerAttributes.ContentState.self,
            from: data
        )
        #expect(decoded.totalDuration == 60)
        #expect(decoded.phase == .resting)
        #expect(decoded.endDate == Date(timeIntervalSince1970: 1000))
    }

    @Test("ContentState encodes completed phase")
    func contentStateCompletedPhase() throws {
        let state = RestTimerAttributes.ContentState(
            endDate: .now,
            totalDuration: 0,
            phase: .completed
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            RestTimerAttributes.ContentState.self,
            from: data
        )
        #expect(decoded.phase == .completed)
    }

    @Test("RestActivityPhase raw values are correct")
    func phaseRawValues() {
        #expect(RestActivityPhase.resting.rawValue == "resting")
        #expect(RestActivityPhase.completed.rawValue == "completed")
    }

    @Test("ContentState conforms to Hashable")
    func contentStateHashable() {
        let state1 = RestTimerAttributes.ContentState(
            endDate: Date(timeIntervalSince1970: 1000),
            totalDuration: 60,
            phase: .resting
        )
        let state2 = RestTimerAttributes.ContentState(
            endDate: Date(timeIntervalSince1970: 1000),
            totalDuration: 60,
            phase: .resting
        )
        #expect(state1 == state2)
        #expect(state1.hashValue == state2.hashValue)
    }
}

@Suite("RestTimerController Live Activity integration")
struct RestTimerLiveActivityIntegrationTests {

    @MainActor
    @Test("startRest starts Live Activity with correct parameters")
    func startRestStartsLiveActivity() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.startCalls.count == 1)
        #expect(mock.startCalls[0].totalDuration == 60)
    }

    @MainActor
    @Test("adjustRest updates Live Activity")
    func adjustRestUpdatesLiveActivity() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        controller.adjustRest(by: 10)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.updateCalls.count == 1)
        #expect(mock.updateCalls[0].totalDuration == 70)
    }

    @MainActor
    @Test("skipRest ends Live Activity with skipped reason")
    func skipRestEndsLiveActivity() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 60)
        controller.skipRest()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.endCalls.count == 1)
        #expect(mock.endCalls[0] == .skipped)
    }

    @MainActor
    @Test("cancelRestForWorkoutEnd ends Live Activity with workoutEnded reason")
    func cancelRestEndsLiveActivity() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 60)
        controller.cancelRestForWorkoutEnd()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.endCalls.count == 1)
        #expect(mock.endCalls[0] == .workoutEnded)
    }

    @MainActor
    @Test("handleTimerTask ends Live Activity on natural completion")
    func handleTimerTaskEndsLiveActivity() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 0.1)
        await controller.handleTimerTask()

        #expect(mock.endCalls.count == 1)
        #expect(mock.endCalls[0] == .completed)
    }

    @MainActor
    @Test("cancelRestForWorkoutEnd while idle does not end Live Activity")
    func cancelRestWhileIdleNoEnd() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.cancelRestForWorkoutEnd()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.endCalls.isEmpty)
    }

    @MainActor
    @Test("adjustRest with negative offset does not update when expired")
    func adjustRestExpiredNoUpdate() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 5)
        controller.adjustRest(by: -10)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.updateCalls.isEmpty)
    }

    @MainActor
    @Test("Multiple startRest calls each start a new Live Activity")
    func multipleStartRestStartsEach() async {
        let mock = MockLiveActivityManager()
        let controller = RestTimerController(
            completedDisplayDuration: 0.1,
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: mock
        )

        controller.startRest(duration: 60)
        try? await Task.sleep(for: .milliseconds(50))

        controller.startRest(duration: 90)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(mock.startCalls.count == 2)
        #expect(mock.startCalls[0].totalDuration == 60)
        #expect(mock.startCalls[1].totalDuration == 90)
    }
}
