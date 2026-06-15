import Foundation
import Testing
@testable import TelemetryKit

final class MockTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _trackedEvents: [TelemetryEvent] = []

    var trackedEvents: [TelemetryEvent] {
        lock.withLock { _trackedEvents }
    }

    func track(_ event: TelemetryEvent) {
        lock.withLock { _trackedEvents.append(event) }
    }
}

@Suite("TelemetryService")
struct TelemetryServiceTests {
    @Test("tracks event to single provider")
    func trackSingleProvider() async {
        let service = TelemetryService()
        let mock = MockTelemetryProvider()
        await service.register(mock)

        await service.track(.onboardingCompleted)

        #expect(mock.trackedEvents == [.onboardingCompleted])
    }

    @Test("fan-out to multiple providers")
    func fanOutMultipleProviders() async {
        let service = TelemetryService()
        let mock1 = MockTelemetryProvider()
        let mock2 = MockTelemetryProvider()
        await service.register(mock1)
        await service.register(mock2)

        await service.track(.tabSwitched(tab: "workout"))

        #expect(mock1.trackedEvents == [.tabSwitched(tab: "workout")])
        #expect(mock2.trackedEvents == [.tabSwitched(tab: "workout")])
    }

    @Test("tracks workout completed with parameters")
    func trackWorkoutCompleted() async {
        let service = TelemetryService()
        let mock = MockTelemetryProvider()
        await service.register(mock)

        await service.track(.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16))

        #expect(mock.trackedEvents == [.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16)])
    }

    @Test("tracks multiple events in order")
    func trackMultipleEventsInOrder() async {
        let service = TelemetryService()
        let mock = MockTelemetryProvider()
        await service.register(mock)

        await service.track(.workoutStarted(source: "blank"))
        await service.track(.exerciseAdded(name: "bench_press"))
        await service.track(.setCompleted(exerciseName: "bench_press"))
        await service.track(.workoutCompleted(durationSeconds: 600, exerciseCount: 1, setCount: 1))

        let expected: [TelemetryEvent] = [
            .workoutStarted(source: "blank"),
            .exerciseAdded(name: "bench_press"),
            .setCompleted(exerciseName: "bench_press"),
            .workoutCompleted(durationSeconds: 600, exerciseCount: 1, setCount: 1),
        ]
        #expect(mock.trackedEvents == expected)
    }

    @Test("no providers registered does not crash")
    func noProvidersNoCrash() async {
        let service = TelemetryService()
        await service.track(.healthKitAuthorized)
    }

    @Test("tracks all event categories")
    func trackAllEventCategories() async {
        let service = TelemetryService()
        let mock = MockTelemetryProvider()
        await service.register(mock)

        let events: [TelemetryEvent] = [
            .tabSwitched(tab: "data"),
            .onboardingCompleted,
            .workoutStarted(source: "template"),
            .workoutCompleted(durationSeconds: 3600, exerciseCount: 5, setCount: 20),
            .workoutDiscarded,
            .exerciseAdded(name: "squat"),
            .setCompleted(exerciseName: "squat"),
            .setDeleted,
            .healthKitAuthorized,
            .healthKitDenied,
            .dataDetailOpened(sampleType: "heartRate"),
            .dataImported(format: "fit"),
            .aiInsightGenerated(durationMs: 2300, cardCount: 6),
            .aiInsightFailed(errorType: "timeout"),
            .aiAnalysisRequested(sampleType: "stepCount"),
            .aiModelChanged(model: "glm-4-flash"),
            .aiChatMessageSent,
            .restTimerStarted(durationSeconds: 60),
            .restTimerSkipped,
            .restTimerCompleted,
            .overviewCacheHit,
            .overviewCacheMiss,
            .overviewFallbackTriggered(reason: "network_error"),
        ]

        for event in events {
            await service.track(event)
        }

        #expect(mock.trackedEvents == events)
    }
}
