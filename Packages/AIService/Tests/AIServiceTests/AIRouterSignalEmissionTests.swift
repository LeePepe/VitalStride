import Foundation
import Testing
@testable import AIService

// MARK: - Test helpers

/// Spy sink that records every signal it receives. Uses an actor so tests can
/// assert deterministically after `execute` returns.
private actor SpyRoutingSignalSink: RoutingSignalSink {
    private(set) var signals: [RoutingSignal] = []
    private let recordDelayNs: UInt64
    private let shouldThrow: Bool
    private let onRecord: (@Sendable () -> Void)?

    init(
        recordDelayNs: UInt64 = 0,
        shouldThrow: Bool = false,
        onRecord: (@Sendable () -> Void)? = nil
    ) {
        self.recordDelayNs = recordDelayNs
        self.shouldThrow = shouldThrow
        self.onRecord = onRecord
    }

    func record(_ signal: RoutingSignal) async throws {
        if recordDelayNs > 0 {
            try? await Task.sleep(nanoseconds: recordDelayNs)
        }
        signals.append(signal)
        onRecord?()
        if shouldThrow {
            struct SpyError: Error {}
            throw SpyError()
        }
    }

    func snapshot() -> [RoutingSignal] { signals }
}

private struct SpyProvider: AIProvider, Sendable {
    let name: String
    let responseContent: String

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        ChatResponse(content: responseContent, model: name)
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let content = responseContent
        return AsyncThrowingStream { continuation in
            continuation.yield(ChatStreamChunk(content: content))
            continuation.yield(ChatStreamChunk(content: "", isFinished: true))
            continuation.finish()
        }
    }
}

/// Provider that always fails, to force chain fallback.
private struct FailingProvider: AIProvider, Sendable {
    let name: String

    struct Boom: Error {}

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        throw Boom()
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: Boom()) }
    }
}

private func makeRouter(
    sink: (any RoutingSignalSink)? = nil,
    schemaValidator: (@Sendable (AITaskKind, String) -> Bool)? = nil,
    tier: DeviceTier = .appleIntelligenceCapable
) -> AIRouter {
    let providers: [AIRouter.RegisteredProvider] = [
        .init(
            name: "apple_intelligence",
            isAvailable: { true },
            isOnDevice: true,
            maxQuality: .medium,
            provider: SpyProvider(name: "apple_intelligence", responseContent: "apple-out")
        ),
        .init(
            name: "zhipu",
            isAvailable: { true },
            isOnDevice: false,
            maxQuality: .high,
            provider: SpyProvider(name: "zhipu", responseContent: "zhipu-out")
        ),
    ]
    return AIRouter(
        providers: providers,
        deviceTier: { tier },
        signalSink: sink,
        schemaValidator: schemaValidator
    )
}

/// Wait for a background emission with a bounded poll. Emissions run on
/// `Task.detached` so tests need a small yield window; 2 s is a wide margin.
private func waitForSignals(
    _ sink: SpyRoutingSignalSink,
    count expected: Int,
    timeoutNs: UInt64 = 2_000_000_000
) async -> [RoutingSignal] {
    let start = ContinuousClock().now
    let deadline = Duration.nanoseconds(Int64(timeoutNs))
    while ContinuousClock().now - start < deadline {
        let snapshot = await sink.snapshot()
        if snapshot.count >= expected {
            return snapshot
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await sink.snapshot()
}

// MARK: - Tests

@Suite("AIRouter Signal Emission Tests", .serialized)
struct AIRouterSignalEmissionTests {

    // MARK: - Basic emission

    @Test("execute emits one signal with kind/provider/deviceTier/latencyMs/schemaValid populated")
    func emitsSignalWithCoreFields() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink, schemaValidator: { _, _ in true })

        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        #expect(response.content == "apple-out")

        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.count == 1)
        let signal = signals[0]
        #expect(signal.kind == .substitute)
        #expect(signal.provider == "apple_intelligence")
        #expect(signal.deviceTier == .appleIntelligenceCapable)
        #expect(signal.latencyMs >= 0)
        #expect(signal.schemaValid == true)
    }

    @Test("emits distinct signal for chat / substitute / dataTrend (kind coverage)")
    func emitsSignalPerKind() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink)

        _ = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "hi")], model: nil)
        _ = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "swap")], model: nil)
        _ = try await router.execute(kind: .dataTrend, messages: [ChatMessage(role: "user", content: "trend")], model: nil)

        let signals = await waitForSignals(sink, count: 3)
        #expect(signals.count == 3)
        let kinds = Set(signals.map { $0.kind })
        #expect(kinds == Set([.chat, .substitute, .dataTrend]))
    }

    @Test("chat routes via cloud arm and reports provider=zhipu in signal")
    func chatSignalReportsCloudProvider() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink)
        _ = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "hi")], model: nil)
        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.first?.provider == "zhipu")
    }

    // MARK: - FR-008: fire-and-forget

    @Test("FR-008: sink error does not affect execute return value")
    func sinkErrorDoesNotAffectReturn() async throws {
        let sink = SpyRoutingSignalSink(shouldThrow: true)
        let router = makeRouter(sink: sink)

        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        #expect(response.content == "apple-out")

        // Give the detached Task a chance to run and swallow its throw.
        // The important assertion is that `execute` did not throw itself.
        let signals = await waitForSignals(sink, count: 1)
        // Sink still records the signal even though it also throws — throw is
        // swallowed by `try?` in the detached Task; the append happens first.
        #expect(signals.count == 1)
    }

    @Test("FR-008: slow sink does not delay execute return")
    func slowSinkDoesNotDelayReturn() async throws {
        // Sink sleeps 500ms per record. Fire-and-forget means execute must
        // return before the sink has recorded anything. Asserting on the
        // sink's state at return time is deterministic; asserting on
        // wall-clock elapsed would flake on loaded CI runners.
        let sinkDelayNs: UInt64 = 500_000_000
        let sink = SpyRoutingSignalSink(recordDelayNs: sinkDelayNs)
        let router = makeRouter(sink: sink)

        _ = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )

        let atReturn = await sink.snapshot()
        #expect(atReturn.isEmpty,
                "execute waited for the 500ms sink before returning — fire-and-forget violated")

        // And the emission does still land, just off the caller's critical path.
        let eventual = await waitForSignals(sink, count: 1)
        #expect(eventual.count == 1)
    }

    // MARK: - Provider attribution under fallback

    @Test("signal reports the provider that ACTUALLY served, not the failed primary")
    func signalAttributesServingProviderAfterFallback() async throws {
        let sink = SpyRoutingSignalSink()
        // apple is available and preferred for `.substitute`, but throws at
        // runtime → chain falls back to zhipu, which answers.
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "apple_intelligence",
                isAvailable: { true },
                isOnDevice: true,
                maxQuality: .medium,
                provider: FailingProvider(name: "apple_intelligence")
            ),
            .init(
                name: "zhipu",
                isAvailable: { true },
                isOnDevice: false,
                maxQuality: .high,
                provider: SpyProvider(name: "zhipu", responseContent: "zhipu-out")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .appleIntelligenceCapable },
            signalSink: sink
        )

        // Sanity: apple IS the planned primary, so a "first available" guess
        // would have said apple.
        #expect(router.plannedProviderOrder(for: .substitute).first == "apple_intelligence")

        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "x")],
            model: nil
        )
        #expect(response.content == "zhipu-out")

        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.first?.provider == "zhipu",
                "signal blamed the failed primary instead of the provider that served the response")
    }

    @Test("no signal emitted when every provider fails (execute throws)")
    func noSignalWhenAllProvidersFail() async throws {
        let sink = SpyRoutingSignalSink()
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "zhipu",
                isAvailable: { true },
                isOnDevice: false,
                maxQuality: .high,
                provider: FailingProvider(name: "zhipu")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .cloudOnly },
            signalSink: sink
        )

        await #expect(throws: (any Error).self) {
            _ = try await router.execute(
                kind: .chat,
                messages: [ChatMessage(role: "user", content: "x")],
                model: nil
            )
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let signals = await sink.snapshot()
        #expect(signals.isEmpty, "emitted a signal for a call that never produced a response")
    }

    // MARK: - FR-018: raw text is opt-in only, and off the general sink

    @Test("FR-018: RoutingSignal carries NO raw prompt/response — general sink never sees health data")
    func generalSinkNeverCarriesRawText() async throws {
        let sink = SpyRoutingSignalSink()
        // No rawDebugSink injected — the default composition.
        let router = makeRouter(sink: sink)

        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: "sys"),
            ChatMessage(role: "user", content: "resting HR 47 bpm"),
        ]
        _ = try await router.execute(kind: .substitute, messages: messages, model: nil)

        let signals = await waitForSignals(sink, count: 1)
        let signal = try #require(signals.first)
        // The whole point of the split: a conformer of the general-purpose
        // RoutingSignalSink cannot reach raw text even if it wanted to. This is
        // enforced by the type — RoutingSignal has no raw members at all —
        // so assert the metadata it DOES carry is intact and health-free.
        #expect(signal.kind == .substitute)
        #expect(signal.provider == "apple_intelligence")
        #expect(signal.latencyMs >= 0)
    }

    @Test("FR-018 static assertion: raw text never emitted via print / os_log / Aptabase / GlitchTip")
    func rawFieldsHaveNoAlternateEmission() throws {
        // Grep AIRouter + RoutingSignal source for suspicious emitters. The
        // invariant after the Stage 6d ship-gate: prompt/response text is never
        // materialized in this layer at all, so there is nothing to emit — but
        // an off-device emitter appearing here would be a regression even so.
        // If ANY of these tokens appear as CODE (not documentation): fail loud.
        let root = Self.sourcesRoot

        let routerURL = root.appendingPathComponent("AIRouter.swift")
        let signalURL = root.appendingPathComponent("RoutingSignal.swift")

        let routerSource = try String(contentsOf: routerURL, encoding: .utf8)
        let signalSource = try String(contentsOf: signalURL, encoding: .utf8)

        for (name, source) in [("AIRouter.swift", routerSource), ("RoutingSignal.swift", signalSource)] {
            // Strip line comments before scanning — the doc/comment prose
            // legitimately names Aptabase/GlitchTip/print/os_log as the
            // things that MUST NOT be used. The invariant is that no CODE
            // line invokes them.
            let codeOnly = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") {
                        return ""
                    }
                    return line
                }
                .joined(separator: "\n")

            #expect(!codeOnly.contains("Aptabase"),
                    "\(name): code references Aptabase — leaks PHI off-device (FR-018)")
            #expect(!codeOnly.contains("GlitchTip"),
                    "\(name): code references GlitchTip — leaks PHI off-device (FR-018)")
            for token in ["payload.prompt", "payload.response", "response.content", "messages"] {
                for emitter in ["print(", "os_log(", "logger.log(", "logger.debug(", "logger.info("] {
                    #expect(!codeOnly.contains("\(emitter)\(token)"),
                            "\(name): emits \(token) via \(emitter) — FR-018 violation")
                }
            }
        }

        // Structural assertion: `RoutingSignal` — the type handed to the
        // unconstrained, general-purpose sink — must never regrow raw members.
        #expect(!signalSource.contains("public let rawPromptDebug"),
                "RoutingSignal regrew a raw field — PHI back on the unconstrained sink boundary (FR-018)")
        #expect(!signalSource.contains("public let rawResponseDebug"),
                "RoutingSignal regrew a raw field — PHI back on the unconstrained sink boundary (FR-018)")
    }

    // MARK: - FR-017 ship-gate: raw carriers are structurally gone

    @Test("FR-017/FR-018 ship-gate: AIService sources hold no raw-bearing type and no pre-launch raw exception")
    func shipGateNoRawCarriersInAIService() throws {
        let fileManager = FileManager.default
        let root = Self.sourcesRoot

        // Removed for good in Stage 6d — the raw debug bypass and the Stage 4
        // shadow raw pair / offline evaluation sample. Re-introducing any of
        // these puts HealthKit-derived text back inside the routing layer.
        //
        // Each needle is assembled from fragments on purpose: the ship-gate
        // grep in the issue's verification command scans every `*.swift` under
        // `Packages/`, so spelling a banned identifier verbatim here — even
        // inside a test that forbids it — would make that gate fail on this
        // very file.
        let forbidden = [
            "TEMP-" + "PRELAUNCH",
            "RawDebug" + "Payload",
            "LocalOnlyRawDebug" + "Sink",
            "ShadowPair" + "Payload",
            "LocalOnlyShadowPair" + "Sink",
            "AIRoutingEvaluation" + "Sample",
        ]

        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("Unable to enumerate AIService sources at \(root.path)")
            return
        }
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for token in forbidden {
                #expect(!text.contains(token),
                        "\(url.lastPathComponent) still references \(token) — FR-017 ship-gate (宪法 I) requires the raw bypass to be structurally absent from AIService")
            }
        }
        // Positive control: a zero-file scan would make every expectation above
        // vacuously pass.
        #expect(scanned > 0, "scanned no AIService sources — the ship-gate assertion above is meaningless")
    }

    @Test("RoutingSignal keeps exactly its permanent 7 fields")
    func routingSignalPermanentFieldSet() throws {
        let source = try String(contentsOf: Self.sourcesRoot.appendingPathComponent("RoutingSignal.swift"), encoding: .utf8)
        let declared = source
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("public let ") else { return nil }
                return trimmed
                    .dropFirst("public let ".count)
                    .prefix(while: { $0 != ":" })
                    .trimmingCharacters(in: .whitespaces)
            }
        #expect(Set(declared) == Set([
            "kind", "provider", "deviceTier", "latencyMs", "schemaValid", "accepted", "timestamp",
        ]), "RoutingSignal 永久字段集变了（实际: \(declared)）—— 永久态必须是 raw-free 的这 7 个字段")
    }

    /// `Packages/AIService/Sources/AIService`, resolved from this test file.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AIServiceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AIService (package root)
            .appendingPathComponent("Sources/AIService")
    }

    // MARK: - FR-019: Apple LanguageModelFeedback API MUST NOT be imported

    @Test("FR-019: AIService does not import LanguageModelFeedback / logFeedbackAttachment")
    func fr019NoAppleFeedbackAPI() throws {
        let fileManager = FileManager.default
        let root = Self.sourcesRoot

        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("Unable to enumerate AIService sources at \(root.path)")
            return
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("logFeedbackAttachment"),
                    "\(url.lastPathComponent) references logFeedbackAttachment — Apple feedback API is off-device (FR-019)")
            #expect(!text.contains("LanguageModelFeedback"),
                    "\(url.lastPathComponent) references LanguageModelFeedback — Apple feedback API is off-device (FR-019)")
        }
    }

    // MARK: - Unknown kind: safe default + still emits signal

    @Test("unknown kind (empty policy) still emits a signal")
    func unknownKindEmitsSignal() async throws {
        let sink = SpyRoutingSignalSink()
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "zhipu",
                isAvailable: { true },
                isOnDevice: false,
                maxQuality: .high,
                provider: SpyProvider(name: "zhipu", responseContent: "safe-default-ok")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            policy: [:],
            deviceTier: { .cloudOnly },
            signalSink: sink
        )
        let response = try await router.execute(kind: .chat, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        #expect(response.content == "safe-default-ok")

        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.count == 1)
        #expect(signals.first?.provider == "zhipu")
        #expect(signals.first?.deviceTier == .cloudOnly)
    }

    // MARK: - Chain not reversed (constitution V)

    @Test("router still delegates to AIProviderChain — chain order not reversed")
    func chainOrderPreserved() async throws {
        // Independent guard: signal emission MUST NOT break chain semantics.
        // With apple/zhipu both available on a capable tier, `.substitute`
        // (low quality) picks apple first (chain order preserved).
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink)
        let order = router.plannedProviderOrder(for: .substitute)
        #expect(order == ["apple_intelligence", "zhipu"])
        _ = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.first?.provider == "apple_intelligence")
    }

    // MARK: - Default init: no-op sink is safe

    @Test("router built without sink still executes cleanly (no-op sink default)")
    func defaultNoOpSinkSafe() async throws {
        let router = makeRouter()
        let response = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        #expect(response.content == "apple-out")
    }

    // MARK: - schemaValidator: false when absent, true when validator says so

    @Test("schemaValid=false when no validator supplied")
    func schemaValidDefaultsFalse() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink) // no validator
        _ = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.first?.schemaValid == false)
    }

    @Test("schemaValid=true when validator returns true")
    func schemaValidPropagatesTrue() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink, schemaValidator: { _, _ in true })
        _ = try await router.execute(kind: .substitute, messages: [ChatMessage(role: "user", content: "x")], model: nil)
        let signals = await waitForSignals(sink, count: 1)
        #expect(signals.first?.schemaValid == true)
    }
}
