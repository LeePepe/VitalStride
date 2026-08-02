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
        // return well before that.
        let sinkDelayNs: UInt64 = 500_000_000
        let sink = SpyRoutingSignalSink(recordDelayNs: sinkDelayNs)
        let router = makeRouter(sink: sink)

        let clock = ContinuousClock()
        let start = clock.now
        _ = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        let elapsed = clock.now - start

        // execute must return without waiting for the 500ms sink sleep.
        // We give a very generous 200ms upper bound to cover CI jitter, still
        // clearly under the 500ms sink delay.
        #expect(elapsed < .milliseconds(200), "execute returned in \(elapsed) but sink delay is 500ms — fire-and-forget violated")
    }

    // MARK: - FR-018: raw fields captured, sink is the ONLY sink

    @Test("FR-018: rawPromptDebug + rawResponseDebug captured on the signal")
    func rawFieldsCapturedOnSignal() async throws {
        let sink = SpyRoutingSignalSink()
        let router = makeRouter(sink: sink)

        let messages: [ChatMessage] = [
            ChatMessage(role: "system", content: "sys"),
            ChatMessage(role: "user", content: "hello"),
        ]
        _ = try await router.execute(kind: .substitute, messages: messages, model: nil)

        let signals = await waitForSignals(sink, count: 1)
        let signal = try #require(signals.first)
        let prompt = try #require(signal.rawPromptDebug)
        #expect(prompt.contains("system: sys"))
        #expect(prompt.contains("user: hello"))
        #expect(signal.rawResponseDebug == "apple-out")
    }

    @Test("FR-018 static assertion: raw fields never emitted via print / os_log / Aptabase / GlitchTip")
    func rawFieldsHaveNoAlternateEmission() throws {
        // Grep AIRouter + RoutingSignal source for suspicious emitters near
        // the raw-field context. The invariant: rawPromptDebug/rawResponseDebug
        // ONLY appear in-package as (a) property declarations on RoutingSignal,
        // and (b) as let-bindings that get handed to the injected sink.
        // If ANY of these tokens appear in the same source as CODE (not
        // documentation): fail loud.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AIServiceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AIService (package root)
            .appendingPathComponent("Sources/AIService")

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
            #expect(!codeOnly.contains("print(rawPromptDebug"),
                    "\(name): print()s rawPromptDebug — FR-018 violation")
            #expect(!codeOnly.contains("print(rawResponseDebug"),
                    "\(name): print()s rawResponseDebug — FR-018 violation")
            #expect(!codeOnly.contains("os_log(rawPrompt"),
                    "\(name): emits rawPrompt via os_log — FR-018 violation")
            #expect(!codeOnly.contains("os_log(rawResponse"),
                    "\(name): emits rawResponse via os_log — FR-018 violation")
            #expect(!codeOnly.contains("logger.log(rawPrompt"),
                    "\(name): logs rawPrompt via logger — FR-018 violation")
            #expect(!codeOnly.contains("logger.log(rawResponse"),
                    "\(name): logs rawResponse via logger — FR-018 violation")
        }
    }

    // MARK: - FR-019: Apple LanguageModelFeedback API MUST NOT be imported

    @Test("FR-019: AIService does not import LanguageModelFeedback / logFeedbackAttachment")
    func fr019NoAppleFeedbackAPI() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AIService")

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
