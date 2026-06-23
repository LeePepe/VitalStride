import Foundation
import Testing
import TelemetryKit
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

/// Integration-style tests that verify our app code wires events into
/// the TelemetryService correctly via a MockTelemetryProvider.
final class CapturingTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [TelemetryEvent] = []

    var events: [TelemetryEvent] {
        lock.withLock { _events }
    }

    func track(_ event: TelemetryEvent) {
        lock.withLock { _events.append(event) }
    }
}

@Suite("Telemetry call-site integration")
struct TelemetryCallSiteTests {
    @MainActor
    @Test("RestTimerController.startRest emits restTimerStarted with the duration in seconds")
    func restTimerStartEmitsEvent() async {
        let provider = CapturingTelemetryProvider()
        await TelemetryService.shared.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.01,
            notificationScheduler: mock
        )
        controller.startRest(duration: 75)

        // Telemetry fires from a detached Task — wait briefly for delivery.
        try? await Task.sleep(for: .milliseconds(100))

        let started = provider.events.contains { event in
            if case .restTimerStarted(let secs) = event { return secs == 75 }
            return false
        }
        #expect(started, "Expected restTimerStarted(durationSeconds: 75)")
    }

    @MainActor
    @Test("RestTimerController.skipRest while resting emits restTimerSkipped")
    func restTimerSkipEmitsEvent() async {
        let provider = CapturingTelemetryProvider()
        await TelemetryService.shared.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.01,
            notificationScheduler: mock
        )
        controller.startRest(duration: 60)
        controller.skipRest()

        try? await Task.sleep(for: .milliseconds(100))

        #expect(provider.events.contains(.restTimerSkipped))
    }

    @MainActor
    @Test("RestTimerController natural completion emits restTimerCompleted")
    func restTimerNaturalCompletionEmitsEvent() async {
        let provider = CapturingTelemetryProvider()
        await TelemetryService.shared.register(provider)

        let mock = MockNotificationScheduler()
        let controller = RestTimerController(
            completedDisplayDuration: 0.05,
            notificationScheduler: mock
        )
        controller.startRest(duration: 0.05)
        await controller.handleTimerTask()

        try? await Task.sleep(for: .milliseconds(100))

        #expect(provider.events.contains(.restTimerCompleted))
    }
}
