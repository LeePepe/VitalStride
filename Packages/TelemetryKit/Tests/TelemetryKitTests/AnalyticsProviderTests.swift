import Foundation
import Synchronization
import Testing
@testable import TelemetryKit

/// Fake sink capturing signals for assertions — stands in for the real
/// analytics SDK adapter (the `AptabaseAdapter` product).
///
/// Uses `Mutex` (Swift 6 `Synchronization`) for checked `Sendable` conformance —
/// no `@unchecked` (Constitution §II: strict concurrency, no bypass).
final class FakeSignalSink: AnalyticsSignalSink {
    private let storage = Mutex<[AnalyticsSignal]>([])
    var signals: [AnalyticsSignal] {
        storage.withLock { $0 }
    }
    func send(_ signal: AnalyticsSignal) {
        storage.withLock { $0.append(signal) }
    }
}

@Suite("AnalyticsSignal mapping")
struct AnalyticsSignalMappingTests {

    @Test("event maps to name + flattened parameters")
    func mapsEvent() {
        let signal = AnalyticsSignal(
            event: .workoutCompleted(durationSeconds: 3600, exerciseCount: 5, setCount: 20)
        )
        #expect(signal.name == "workout_completed")
        #expect(signal.parameters["duration_s"] == "3600")
        #expect(signal.parameters["exercises"] == "5")
        #expect(signal.parameters["sets"] == "20")
    }

    @Test("parameterless event maps to bare signal")
    func mapsParameterlessEvent() {
        let signal = AnalyticsSignal(event: .onboardingCompleted)
        #expect(signal.name == "onboarding_completed")
        #expect(signal.parameters.isEmpty)
    }
}

@Suite("AnalyticsProvider")
struct AnalyticsProviderTests {

    @Test("track forwards a mapped event signal to the sink")
    func trackForwardsEvent() {
        let sink = FakeSignalSink()
        let provider = AnalyticsProvider(sink: sink)

        provider.track(.workoutStarted(source: "watch"))

        #expect(sink.signals.count == 1)
        #expect(sink.signals.first?.name == "workout_started")
        #expect(sink.signals.first?.parameters["source"] == "watch")
    }

    @Test("record does NOT forward a diagnostic to the sink — ADR-0013 separates crash/hang transport to sentry-cocoa")
    func recordDoesNotForwardDiagnostic() {
        let sink = FakeSignalSink()
        let provider = AnalyticsProvider(sink: sink)

        provider.record(
            TelemetryDiagnostic(kind: .hang, osVersion: "26.5", appBuild: "5", frames: ["A +0"])
        )

        // ADR-0013 §Decision.2 + §Decision.5: crash/hang transport is exclusive
        // to the self-hosted GlitchTip / sentry-cocoa path. AnalyticsProvider
        // must inherit the protocol's default no-op for `record(_:)` so that
        // registering it into `TelemetryService` cannot leak diagnostics into
        // the product-analytics channel.
        #expect(sink.signals.isEmpty)
    }

    @Test("through TelemetryService: event reaches sink, diagnostic does not (crash/hang stays off analytics channel)")
    func integratesThroughService() async {
        let sink = FakeSignalSink()
        let service = TelemetryService()
        await service.register(AnalyticsProvider(sink: sink))

        await service.track(.aiChatMessageSent)
        await service.record(
            TelemetryDiagnostic(kind: .crash, osVersion: "26.5", appBuild: "5",
                                frames: ["Z +0"], terminationReason: "SIGABRT")
        )

        let names = sink.signals.map(\.name)
        #expect(names == ["ai_chat_message_sent"])
        #expect(!names.contains("diagnostic_crash"))
        #expect(!names.contains("diagnostic_hang"))
    }
}
