import Foundation
import Testing
@testable import AIService

// MARK: - Test helpers

private actor SpyShadowSink: ShadowSignalSink {
    private(set) var signals: [ShadowSignal] = []

    func recordShadow(_ signal: ShadowSignal) async throws {
        signals.append(signal)
    }

    func snapshot() -> [ShadowSignal] { signals }
}

private struct FastSpyProvider: AIProvider, Sendable {
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

/// Provider that sleeps `delayNs` before returning — used to prove the main
/// result was not blocked by the candidate.
private struct SlowSpyProvider: AIProvider, Sendable {
    let name: String
    let responseContent: String
    let delayNs: UInt64

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try? await Task.sleep(nanoseconds: delayNs)
        return ChatResponse(content: responseContent, model: name)
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ChatStreamChunk(content: responseContent, isFinished: true))
            continuation.finish()
        }
    }
}

private struct ShadowFailingProvider: AIProvider, Sendable {
    let name: String

    struct Boom: Error {}

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        throw Boom()
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: Boom()) }
    }
}

private func makeShadowRouter(
    mainName: String = "apple_intelligence",
    mainContent: String = "apple-out",
    candidateName: String = "zhipu",
    candidateContent: String = "zhipu-out",
    candidateDelayNs: UInt64 = 0,
    candidateThrows: Bool = false,
    sampler: any ShadowSampler,
    sink: any ShadowSignalSink
) -> AIRouter {
    let candidate: any AIProvider
    if candidateThrows {
        candidate = ShadowFailingProvider(name: candidateName)
    } else if candidateDelayNs > 0 {
        candidate = SlowSpyProvider(name: candidateName, responseContent: candidateContent, delayNs: candidateDelayNs)
    } else {
        candidate = FastSpyProvider(name: candidateName, responseContent: candidateContent)
    }

    let providers: [AIRouter.RegisteredProvider] = [
        .init(
            name: mainName,
            isAvailable: { true },
            isOnDevice: true,
            maxQuality: .medium,
            provider: FastSpyProvider(name: mainName, responseContent: mainContent)
        ),
        .init(
            name: candidateName,
            isAvailable: { true },
            isOnDevice: false,
            maxQuality: .high,
            provider: candidate
        ),
    ]
    return AIRouter(
        providers: providers,
        deviceTier: { .appleIntelligenceCapable },
        shadowSampler: sampler,
        shadowSignalSink: sink
    )
}

private func waitForShadow(
    _ sink: SpyShadowSink,
    count expected: Int,
    timeoutNs: UInt64 = 3_000_000_000
) async -> [ShadowSignal] {
    let start = ContinuousClock().now
    let deadline = Duration.nanoseconds(Int64(timeoutNs))
    while ContinuousClock().now - start < deadline {
        let snapshot = await sink.snapshot()
        if snapshot.count >= expected { return snapshot }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await sink.snapshot()
}

// MARK: - Tests

@Suite("Shadow Sampling Tests", .serialized)
struct ShadowSamplingTests {

    // MARK: - Sampler math (SC-005)

    @Test("RatioShadowSampler at rate 0.2 fires ~20/100 (±2%)")
    func ratio20PercentHitsWithin2Percent() {
        let sampler = RatioShadowSampler(rates: [.substitute: 0.2])
        var hits = 0
        for _ in 0..<100 {
            if sampler.shouldSample(kind: .substitute) { hits += 1 }
        }
        // Deterministic accumulator produces exactly 20 in 100 draws at p=0.2.
        // SC-005 tolerance is ±2%, i.e. hits ∈ [18, 22].
        #expect(hits >= 18 && hits <= 22, "rate=0.2 fired \(hits)/100, outside SC-005 tolerance")
    }

    @Test("RatioShadowSampler at rate 0.5 fires ~50/100 (±2%)")
    func ratio50PercentHitsWithin2Percent() {
        let sampler = RatioShadowSampler(rates: [.chat: 0.5])
        var hits = 0
        for _ in 0..<100 {
            if sampler.shouldSample(kind: .chat) { hits += 1 }
        }
        #expect(hits >= 48 && hits <= 52)
    }

    @Test("RatioShadowSampler at rate 0.0 never fires")
    func ratioZeroNeverFires() {
        let sampler = RatioShadowSampler(rates: [.chat: 0.0])
        for _ in 0..<50 {
            #expect(!sampler.shouldSample(kind: .chat))
        }
    }

    @Test("RatioShadowSampler at rate 1.0 always fires")
    func ratioOneAlwaysFires() {
        let sampler = RatioShadowSampler(rates: [.chat: 1.0])
        for _ in 0..<50 {
            #expect(sampler.shouldSample(kind: .chat))
        }
    }

    @Test("RatioShadowSampler kinds without an entry never fire")
    func ratioUnconfiguredKindNeverFires() {
        let sampler = RatioShadowSampler(rates: [.chat: 1.0])
        for _ in 0..<20 {
            #expect(!sampler.shouldSample(kind: .substitute))
        }
    }

    @Test("RatioShadowSampler clamps out-of-range rates")
    func ratioClampsRates() {
        let hot = RatioShadowSampler(rates: [.chat: 1.5])
        for _ in 0..<20 { #expect(hot.shouldSample(kind: .chat)) }

        let cold = RatioShadowSampler(rates: [.chat: -0.4])
        for _ in 0..<20 { #expect(!cold.shouldSample(kind: .chat)) }
    }

    @Test("RatioShadowSampler tracks per-kind accumulators independently")
    func ratioPerKindIndependent() {
        let sampler = RatioShadowSampler(rates: [.chat: 1.0, .substitute: 0.0])
        for _ in 0..<10 {
            #expect(sampler.shouldSample(kind: .chat))
            #expect(!sampler.shouldSample(kind: .substitute))
        }
    }

    // MARK: - Main-result not blocked by candidate (FR-010)

    @Test("FR-010: interactive main result not blocked by slow candidate")
    func mainResultNotBlockedByCandidate() async throws {
        // Candidate sleeps 500ms. Main is fast. execute must return before
        // the candidate has finished. Asserting on the sink at return time
        // is deterministic; wall-clock assertions flake on loaded CI.
        let sink = SpyShadowSink()
        let router = makeShadowRouter(
            candidateDelayNs: 500_000_000,
            sampler: AlwaysShadowSampler(),
            sink: sink
        )

        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        #expect(response.content == "apple-out")

        let atReturn = await sink.snapshot()
        #expect(atReturn.isEmpty, "execute waited for the 500ms candidate before returning — fire-and-forget violated")

        let eventual = await waitForShadow(sink, count: 1)
        #expect(eventual.count == 1)
        #expect(eventual.first?.candidateSucceeded == true)
    }

    @Test("FR-010: candidate failure does not affect main result")
    func candidateFailureNeverAffectsMain() async throws {
        let sink = SpyShadowSink()
        let router = makeShadowRouter(
            candidateThrows: true,
            sampler: AlwaysShadowSampler(),
            sink: sink
        )

        let response = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )
        #expect(response.content == "apple-out",
                "candidate error corrupted the main return path")

        let signals = await waitForShadow(sink, count: 1)
        let signal = try #require(signals.first)
        #expect(signal.candidateSucceeded == false, "shadowFailed signal missing")
        #expect(signal.candidateLatencyMs == nil)
        #expect(signal.candidateErrorCategory != nil)
    }

    @Test("FR-010: sampler=Never → no shadow signal, no dual-run")
    func neverSamplerNoShadow() async throws {
        let sink = SpyShadowSink()
        let router = makeShadowRouter(
            sampler: NeverShadowSampler(),
            sink: sink
        )

        _ = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )

        // Give any accidentally-scheduled task a moment to land.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let signals = await sink.snapshot()
        #expect(signals.isEmpty, "NeverShadowSampler fired a shadow — sampling gate is not honored")
    }

    // MARK: - Signal shape

    @Test("shadow signal carries main + candidate identities and tier")
    func shadowSignalCarriesRoutingMetadata() async throws {
        let sink = SpyShadowSink()
        let router = makeShadowRouter(
            sampler: AlwaysShadowSampler(),
            sink: sink
        )

        _ = try await router.execute(
            kind: .substitute,
            messages: [ChatMessage(role: "user", content: "swap")],
            model: nil
        )

        let signals = await waitForShadow(sink, count: 1)
        let signal = try #require(signals.first)
        #expect(signal.kind == .substitute)
        #expect(signal.mainProvider == "apple_intelligence")
        #expect(signal.candidateProvider == "zhipu")
        #expect(signal.deviceTier == .appleIntelligenceCapable)
        #expect(signal.mainLatencyMs >= 0)
    }

    @Test("no candidate available → no shadow signal")
    func noCandidateNoShadow() async throws {
        // Only one eligible provider → no distinct candidate → shadow silently skipped.
        let sink = SpyShadowSink()
        let providers: [AIRouter.RegisteredProvider] = [
            .init(
                name: "zhipu",
                isAvailable: { true },
                isOnDevice: false,
                maxQuality: .high,
                provider: FastSpyProvider(name: "zhipu", responseContent: "cloud-only-out")
            ),
        ]
        let router = AIRouter(
            providers: providers,
            deviceTier: { .cloudOnly },
            shadowSampler: AlwaysShadowSampler(),
            shadowSignalSink: sink
        )

        _ = try await router.execute(
            kind: .chat,
            messages: [ChatMessage(role: "user", content: "hi")],
            model: nil
        )

        try? await Task.sleep(nanoseconds: 200_000_000)
        let signals = await sink.snapshot()
        #expect(signals.isEmpty, "shadow fired with no distinct candidate — no comparison possible")
    }

    // MARK: - FR-018 ship-gate: shadow runs carry no output text

    @Test("ShadowSignal exposes only routing metadata — no response text member")
    func shadowSignalHasNoRawMembers() throws {
        let source = try String(
            contentsOf: Self.sourcesRoot.appendingPathComponent("ShadowSignal.swift"),
            encoding: .utf8
        )
        // Scan declared members only — the doc prose legitimately says the type
        // carries "no raw prompt/response text".
        let members = source
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("public let ") else { return nil }
                return trimmed
                    .dropFirst("public let ".count)
                    .prefix(while: { $0 != ":" })
                    .trimmingCharacters(in: .whitespaces)
            }
        #expect(!members.isEmpty, "parsed no ShadowSignal members — the assertion below would be vacuous")
        for forbidden in ["mainResponse", "candidateResponse", "responseContent", "prompt"] {
            #expect(!members.contains(forbidden),
                    "ShadowSignal regrew member '\(forbidden)' — raw output text is back in the routing layer (FR-018)")
        }
    }

    @Test("shadow dual-run never binds the candidate response text")
    func shadowRunDiscardsCandidateOutput() throws {
        let source = try String(
            contentsOf: Self.sourcesRoot.appendingPathComponent("AIRouter.swift"),
            encoding: .utf8
        )
        // The candidate call must discard its result: `_ = try await ...chat`.
        // Binding it (`let response = try await candidateProvider.chat`) is how
        // the deleted raw-pair capture started.
        #expect(source.contains("_ = try await candidateProvider.chat("),
                "shadow dual-run binds the candidate response instead of discarding it — raw output re-entered the layer (FR-018)")
        #expect(!source.contains("let mainContent = mainResponse.content"),
                "AIRouter captured the main response text for shadow comparison — deleted in Stage 6d (FR-018)")
    }

    /// `Packages/AIService/Sources/AIService`, resolved from this test file.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AIServiceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AIService (package root)
            .appendingPathComponent("Sources/AIService")
    }
}
