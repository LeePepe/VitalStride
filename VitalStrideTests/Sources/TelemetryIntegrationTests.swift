import Foundation
import Testing
import TelemetryKit

@testable import VitalStride

/// Verifies telemetry events emitted by the Logger-migration sites (MY-843)
/// use locale-independent ASCII identifiers and the correct event shapes.
/// We can't easily invoke the production call sites (most are inside SwiftUI
/// `@MainActor` views or actor-isolated services driven by real Keychain/AI),
/// so these tests pin the contract: the identifiers / event values we emit
/// at those sites are well-formed and match the spec.
@Suite("Telemetry migration event contract (MY-843)")
struct TelemetryMigrationContractTests {

    actor RecordingProvider: TelemetryProvider {
        private(set) var events: [TelemetryEvent] = []
        nonisolated func track(_ event: TelemetryEvent) {
            Task { await append(event) }
        }
        private func append(_ event: TelemetryEvent) { events.append(event) }
        func snapshot() -> [TelemetryEvent] { events }
    }

    @Test("AI insight generated event carries duration + card count")
    func aiInsightGenerated() {
        let event = TelemetryEvent.aiInsightGenerated(durationMs: 1234, cardCount: 5)
        #expect(event.eventName == "ai_insight_generated")
        let params = Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key, $0.value) })
        #expect(params["duration_ms"] == "1234")
        #expect(params["cards"] == "5")
    }

    @Test("AI insight failed events use stable English error identifiers")
    func aiInsightFailedIdentifiers() {
        let identifiers: [TelemetryIdentifier] = [
            "noProviderAvailable",
            "networkError",
            "missingAPIKey",
            "responseParsingFailed",
            "streamingInterrupted",
            "noApiKey",
            "unknown",
        ]
        for id in identifiers {
            let event = TelemetryEvent.aiInsightFailed(errorType: id)
            #expect(event.eventName == "ai_insight_failed")
            let params = Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key, $0.value) })
            #expect(params["error_type"] == id.rawValue)
        }
    }

    @Test("httpError code is sanitized into a valid TelemetryIdentifier")
    func httpErrorIdentifierIsValid() {
        // OverviewDynamicState.telemetryErrorType formats httpError as "httpError_<code>"
        // since "httpError(404)" contains parens which are rejected by the validator.
        let id = TelemetryIdentifier(validating: "httpError_404")
        #expect(id != nil)
        #expect(id?.rawValue == "httpError_404")
    }

    @Test("overview cache hit / miss / fallback events have correct names")
    func overviewCacheEvents() {
        #expect(TelemetryEvent.overviewCacheHit.eventName == "overview_cache_hit")
        #expect(TelemetryEvent.overviewCacheMiss.eventName == "overview_cache_miss")
        let fallback = TelemetryEvent.overviewFallbackTriggered(reason: "aiGenerateFailure")
        #expect(fallback.eventName == "overview_fallback_triggered")
        let params = Dictionary(uniqueKeysWithValues: fallback.parameters.map { ($0.key, $0.value) })
        #expect(params["reason"] == "aiGenerateFailure")
    }

    @Test("data detail opened uses raw sample type (English identifier)")
    func dataDetailOpenedSampleType() {
        // HealthSampleType raw values are Swift enum case names: pure ASCII camelCase.
        let id = TelemetryIdentifier(validating: "heartRate")
        #expect(id != nil)
        let event = TelemetryEvent.dataDetailOpened(sampleType: id!)
        #expect(event.eventName == "data_detail_opened")
        let params = Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key, $0.value) })
        #expect(params["sample_type"] == "heartRate")
    }

    @Test("AI analysis requested includes sample type")
    func aiAnalysisRequested() {
        let event = TelemetryEvent.aiAnalysisRequested(sampleType: "stepCount")
        #expect(event.eventName == "ai_analysis_requested")
        let params = Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key, $0.value) })
        #expect(params["sample_type"] == "stepCount")
    }

    @Test("AI model changed accepts both GLM model identifiers as-is")
    func aiModelChangedAcceptsGLMIds() {
        // AIModel.glm4Flash.rawValue = "glm-4-flash" — hyphens are valid
        let flash = TelemetryIdentifier(validating: "glm-4-flash")
        let plus = TelemetryIdentifier(validating: "glm-4-plus")
        #expect(flash != nil)
        #expect(plus != nil)
        #expect(TelemetryEvent.aiModelChanged(model: flash!).eventName == "ai_model_changed")
    }

    @Test("AI chat message sent is parameterless")
    func aiChatMessageSent() {
        let event = TelemetryEvent.aiChatMessageSent
        #expect(event.eventName == "ai_chat_message_sent")
        #expect(event.parameters.isEmpty)
    }

    @Test("TelemetryService.shared.trackNonisolated forwards to registered providers")
    func trackNonisolatedDelivers() async throws {
        let provider = RecordingProvider()
        await TelemetryService.shared.register(provider)

        TelemetryService.shared.trackNonisolated(.overviewCacheHit)
        TelemetryService.shared.trackNonisolated(.aiChatMessageSent)
        TelemetryService.shared.trackNonisolated(.dataDetailOpened(sampleType: "heartRate"))

        // Allow the detached Task in trackNonisolated to drain.
        try await Task.sleep(nanoseconds: 200_000_000)

        let events = await provider.snapshot()
        #expect(events.contains(.overviewCacheHit))
        #expect(events.contains(.aiChatMessageSent))
        #expect(events.contains(.dataDetailOpened(sampleType: "heartRate")))
    }
}
