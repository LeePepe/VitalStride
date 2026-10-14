import Foundation
import Testing
@testable import TelemetryKit
import VitalModels

@testable import VitalStride

/// Pure unit tests for the small mapping layer between app-domain values
/// (AppTab, WorkoutStartSource, Exercise) and locale-independent
/// TelemetryIdentifier strings. The mapping is the centerpiece of the
/// I18n contract for MY-842: regardless of UI language, parameter values
/// must be stable ASCII identifiers.
@Suite("TelemetryHelpers mapping")
struct TelemetryHelpersTests {
    @Test("tabIdentifier maps every AppTab case to a stable English identifier")
    func tabIdentifierMapsAllCases() {
        #expect(TelemetryHelpers.tabIdentifier(.overview).rawValue == "overview")
        #expect(TelemetryHelpers.tabIdentifier(.workout).rawValue == "workout")
        #expect(TelemetryHelpers.tabIdentifier(.data).rawValue == "data")
        #expect(TelemetryHelpers.tabIdentifier(.ai).rawValue == "ai")
        #expect(TelemetryHelpers.tabIdentifier(.settings).rawValue == "settings")
    }

    @Test("sourceIdentifier maps WorkoutStartSource to canonical fixed values")
    func sourceIdentifierMapsAllCases() {
        let workout = Workout(type: .strength, startDate: Date())
        let template = WorkoutTemplate(name: "Push Day")

        #expect(TelemetryHelpers.sourceIdentifier(.blank).rawValue == "blank")
        #expect(TelemetryHelpers.sourceIdentifier(.fromWorkout(workout)).rawValue == "history")
        #expect(TelemetryHelpers.sourceIdentifier(.fromTemplate(template)).rawValue == "template")
        #expect(TelemetryHelpers.sourceIdentifier(.resume(workout)).rawValue == "resume")
    }

    @Test("exerciseIdentifier uses the canonical English name and slugifies it")
    func exerciseIdentifierUsesEnglishName() {
        let exercise = Exercise(
            nameEn: "Barbell Bench Press",
            nameZh: "杠铃卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let identifier = TelemetryHelpers.exerciseIdentifier(exercise)
        #expect(identifier.rawValue == "barbell_bench_press")
    }

    @Test("exerciseIdentifier never uses the Chinese name even when only Chinese is present")
    func exerciseIdentifierIgnoresChineseName() {
        let exercise = Exercise(
            nameEn: "",
            nameZh: "杠铃卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let identifier = TelemetryHelpers.exerciseIdentifier(exercise)
        // Empty English name slugifies to empty -> "unknown" fallback.
        #expect(identifier.rawValue == "unknown")
    }

    @Test("exerciseIdentifier returns unknown for nil exercise")
    func exerciseIdentifierNilFallback() {
        #expect(TelemetryHelpers.exerciseIdentifier(nil).rawValue == "unknown")
    }

    @Test("slugify lowercases, replaces whitespace and punctuation, strips non-ASCII")
    func slugifyCases() {
        #expect(TelemetryHelpers.slugify("Bench Press") == "bench_press")
        #expect(TelemetryHelpers.slugify("ROW (Bent-Over)") == "row_bent-over")
        #expect(TelemetryHelpers.slugify("杠铃卧推") == "")
        #expect(TelemetryHelpers.slugify("Mixed 中文 Word") == "mixed_word")
        #expect(TelemetryHelpers.slugify("v2.0") == "v2.0")
    }
}

/// Each fixture owns its service and recording provider. Waiting is based on
/// receipt, not on assumptions about Task scheduling or another fixture's events.
actor CapturingTelemetryProvider: TelemetryProvider {
    private(set) var events: [TelemetryEvent] = []
    private let deliveryDelay: Duration

    init(deliveryDelay: Duration = .zero) {
        self.deliveryDelay = deliveryDelay
    }

    nonisolated func track(_ event: TelemetryEvent) {
        Task {
            if deliveryDelay > .zero {
                do {
                    try await Task.sleep(for: deliveryDelay)
                } catch {
                    return
                }
            }
            await append(event)
        }
    }

    private func append(_ event: TelemetryEvent) {
        events.append(event)
    }

    struct DeliveryTimeout: Error, CustomStringConvertible {
        let expected: TelemetryEvent
        let observed: [TelemetryEvent]

        var description: String {
            "Timed out waiting for \(expected.eventName); received \(observed.map(\.eventName))"
        }
    }

    func wait(for event: TelemetryEvent, timeout: Duration = .seconds(2)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !events.contains(event) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw DeliveryTimeout(expected: event, observed: events)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@Suite("Telemetry call-site integration")
struct TelemetryCallSiteTests {
    @MainActor
    @Test("RestTimerController.startRest emits restTimerStarted with the duration in seconds")
    func restTimerStartEmitsEvent() async throws {
        let provider = CapturingTelemetryProvider()
        let telemetry = TelemetryService()
        await telemetry.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.01,
            notificationScheduler: mock,
            liveActivityManager: MockLiveActivityManager(),
            telemetry: telemetry
        )
        controller.startRest(duration: 75)

        try await provider.wait(for: .restTimerStarted(durationSeconds: 75))
    }

    @MainActor
    @Test("RestTimerController.skipRest while resting emits restTimerSkipped")
    func restTimerSkipEmitsEvent() async throws {
        let provider = CapturingTelemetryProvider()
        let telemetry = TelemetryService()
        await telemetry.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.01,
            notificationScheduler: mock,
            liveActivityManager: MockLiveActivityManager(),
            telemetry: telemetry
        )
        controller.startRest(duration: 60)
        controller.skipRest()

        try await provider.wait(for: .restTimerSkipped)
    }

    @MainActor
    @Test("RestTimerController natural completion emits restTimerCompleted")
    func restTimerNaturalCompletionEmitsEvent() async throws {
        let provider = CapturingTelemetryProvider()
        let telemetry = TelemetryService()
        await telemetry.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.05,
            notificationScheduler: mock,
            liveActivityManager: MockLiveActivityManager(),
            telemetry: telemetry
        )
        controller.startRest(duration: 0.05)
        await controller.handleTimerTask()

        try await provider.wait(for: .restTimerCompleted)
    }

    @MainActor
    @Test("Delayed delivery beyond the old 100ms window still satisfies the call-site check")
    func delayedSkipDelivery() async throws {
        let provider = CapturingTelemetryProvider(deliveryDelay: .milliseconds(250))
        let telemetry = TelemetryService()
        await telemetry.register(provider)
        let controller = RestTimerController(
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: MockLiveActivityManager(),
            telemetry: telemetry
        )

        let start = ContinuousClock.now
        controller.startRest(duration: 60)
        controller.skipRest()
        try await provider.wait(for: .restTimerSkipped)
        #expect(start.duration(to: .now) >= .milliseconds(250))
    }

    @MainActor
    @Test("Another controller's skipped event cannot satisfy a missing event in this fixture")
    func unrelatedSkipDoesNotSatisfyWait() async throws {
        let provider = CapturingTelemetryProvider()
        let telemetry = TelemetryService()
        await telemetry.register(provider)
        let controller = RestTimerController(
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: MockLiveActivityManager(),
            telemetry: telemetry
        )
        controller.startRest(duration: 60)
        try await provider.wait(for: .restTimerStarted(durationSeconds: 60))

        let otherProvider = CapturingTelemetryProvider()
        let otherTelemetry = TelemetryService()
        await otherTelemetry.register(otherProvider)
        let other = RestTimerController(
            notificationScheduler: MockNotificationScheduler(),
            liveActivityManager: MockLiveActivityManager(),
            telemetry: otherTelemetry
        )
        other.startRest(duration: 60)
        other.skipRest()
        try await otherProvider.wait(for: .restTimerSkipped)

        do {
            try await provider.wait(for: .restTimerSkipped, timeout: .milliseconds(50))
            Issue.record("An unrelated controller satisfied this fixture's missing skipped event")
        } catch let error as CapturingTelemetryProvider.DeliveryTimeout {
            #expect(error.expected == .restTimerSkipped)
            #expect(error.observed == [.restTimerStarted(durationSeconds: 60)])
        }
    }
}
