import Foundation
import Synchronization
import Testing
@testable import TelemetryKit

/// Fake sink capturing signals for assertions — stands in for the real
/// TelemetryDeck SDK adapter (ADR-0012 path B).
///
/// Uses `Mutex` (Swift 6 `Synchronization`) for checked `Sendable` conformance —
/// no `@unchecked` (Constitution §II: strict concurrency, no bypass).
final class FakeSignalSink: TelemetryDeckSignalSink {
    private let storage = Mutex<[TelemetryDeckSignal]>([])
    var signals: [TelemetryDeckSignal] {
        storage.withLock { $0 }
    }
    func send(_ signal: TelemetryDeckSignal) {
        storage.withLock { $0.append(signal) }
    }
}

@Suite("TelemetryDeckSignal mapping")
struct TelemetryDeckSignalMappingTests {

    @Test("event maps to signal type + flattened parameters")
    func mapsEvent() {
        let signal = TelemetryDeckSignal(
            event: .workoutCompleted(durationSeconds: 3600, exerciseCount: 5, setCount: 20)
        )
        #expect(signal.signalType == "workout_completed")
        #expect(signal.parameters["duration_s"] == "3600")
        #expect(signal.parameters["exercises"] == "5")
        #expect(signal.parameters["sets"] == "20")
    }

    @Test("parameterless event maps to bare signal")
    func mapsParameterlessEvent() {
        let signal = TelemetryDeckSignal(event: .onboardingCompleted)
        #expect(signal.signalType == "onboarding_completed")
        #expect(signal.parameters.isEmpty)
    }

    @Test("hang diagnostic maps to diagnostic_hang with joined frames")
    func mapsHangDiagnostic() {
        let diag = TelemetryDiagnostic(
            kind: .hang,
            osVersion: "26.5.2",
            appBuild: "5",
            frames: ["VitalStride A.f() +0", "VitalStride B.g() +16"]
        )
        let signal = TelemetryDeckSignal(diagnostic: diag)
        #expect(signal.signalType == "diagnostic_hang")
        #expect(signal.parameters["kind"] == "hang")
        #expect(signal.parameters["os_version"] == "26.5.2")
        #expect(signal.parameters["app_build"] == "5")
        #expect(signal.parameters["frame_count"] == "2")
        #expect(signal.parameters["frames"] == "VitalStride A.f() +0\nVitalStride B.g() +16")
        #expect(signal.parameters["termination_reason"] == nil)
    }

    @Test("crash diagnostic includes termination reason")
    func mapsCrashDiagnostic() {
        let diag = TelemetryDiagnostic(
            kind: .crash,
            osVersion: "26.5.2",
            appBuild: "5",
            frames: ["VitalStride X.y() +8"],
            terminationReason: "EXC_BAD_ACCESS"
        )
        let signal = TelemetryDeckSignal(diagnostic: diag)
        #expect(signal.signalType == "diagnostic_crash")
        #expect(signal.parameters["termination_reason"] == "EXC_BAD_ACCESS")
        #expect(signal.parameters["frame_count"] == "1")
    }
}

@Suite("TelemetryDeckProvider")
struct TelemetryDeckProviderTests {

    @Test("track forwards a mapped event signal to the sink")
    func trackForwardsEvent() {
        let sink = FakeSignalSink()
        let provider = TelemetryDeckProvider(sink: sink)

        provider.track(.workoutStarted(source: "watch"))

        #expect(sink.signals.count == 1)
        #expect(sink.signals.first?.signalType == "workout_started")
        #expect(sink.signals.first?.parameters["source"] == "watch")
    }

    @Test("record does NOT forward a diagnostic to the sink — ADR-0013 separates crash/hang transport to sentry-cocoa")
    func recordDoesNotForwardDiagnostic() {
        let sink = FakeSignalSink()
        let provider = TelemetryDeckProvider(sink: sink)

        provider.record(
            TelemetryDiagnostic(kind: .hang, osVersion: "26.5", appBuild: "5", frames: ["A +0"])
        )

        // ADR-0013 §Decision.2 + §Decision.5: crash/hang transport is exclusive
        // to the self-hosted GlitchTip / sentry-cocoa path. TelemetryDeckProvider
        // must inherit the protocol's default no-op for `record(_:)` so that
        // registering it into `TelemetryService` cannot leak diagnostics into
        // the product-analytics channel.
        #expect(sink.signals.isEmpty)
    }

    @Test("through TelemetryService: event reaches sink, diagnostic does not (crash/hang stays off analytics channel)")
    func integratesThroughService() async {
        let sink = FakeSignalSink()
        let service = TelemetryService()
        await service.register(TelemetryDeckProvider(sink: sink))

        await service.track(.aiChatMessageSent)
        await service.record(
            TelemetryDiagnostic(kind: .crash, osVersion: "26.5", appBuild: "5",
                                frames: ["Z +0"], terminationReason: "SIGABRT")
        )

        let types = sink.signals.map(\.signalType)
        #expect(types == ["ai_chat_message_sent"])
        #expect(!types.contains("diagnostic_crash"))
        #expect(!types.contains("diagnostic_hang"))
    }
}
