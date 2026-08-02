import AIService
import Foundation
import Synchronization
import Testing

@testable import VitalStride

// MARK: - Test-Local Recording Provider

/// Captured `(messages, model)` from a single provider call.
private struct Recorded: Sendable {
    var messages: [ChatMessage]
    var model: String?
}

/// Class-based recorder so we can share it between the test and the
/// value-type `AIProvider` without violating Copyable (Mutex is non-Copyable
/// and can't sit in a struct's stored properties).
private final class CallRecorder: Sendable {
    private let storage = Mutex<[Recorded]>([])

    func record(messages: [ChatMessage], model: String?) {
        storage.withLock { $0.append(Recorded(messages: messages, model: model)) }
    }

    func snapshot() -> [Recorded] {
        storage.withLock { $0 }
    }
}

/// A minimal `AIProvider` that records the arguments it receives and returns a
/// canned response. Used to verify `RouterBackedProvider` forwards intact.
private struct RecordingProvider: AIProvider, Sendable {
    let recorder: CallRecorder
    let cannedResponse: ChatResponse
    let streamChunks: [ChatStreamChunk]

    init(
        recorder: CallRecorder = CallRecorder(),
        cannedResponse: ChatResponse = ChatResponse(content: "ok"),
        streamChunks: [ChatStreamChunk] = [ChatStreamChunk(content: "hi", isFinished: true)]
    ) {
        self.recorder = recorder
        self.cannedResponse = cannedResponse
        self.streamChunks = streamChunks
    }

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        recorder.record(messages: messages, model: model)
        return cannedResponse
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        recorder.record(messages: messages, model: model)
        let chunks = streamChunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

// MARK: - Fixtures

/// Router that routes every kind to the single recording provider we register.
/// `maxQuality = .high` clears every `defaultPolicy` entry's quality bar so
/// no kind is pruned, giving us a stable single-provider surface to observe.
private func makeSingleProviderRouter(
    _ provider: RecordingProvider,
    onDevice: Bool = false
) -> AIRouter {
    AIRouter(
        providers: [
            AIRouter.RegisteredProvider(
                name: "test",
                isAvailable: { true },
                isOnDevice: onDevice,
                maxQuality: .high,
                provider: provider
            )
        ],
        deviceTier: { .appleIntelligenceCapable }
    )
}

// MARK: - RouterBackedProvider tests

@Suite("RouterBackedProvider Tests")
struct RouterBackedProviderTests {

    @Test("chat forwards messages and model to the router-selected provider")
    func chatForwardsIntact() async throws {
        let mock = RecordingProvider(cannedResponse: ChatResponse(content: "answer-42"))
        let router = makeSingleProviderRouter(mock)
        let provider = RouterBackedProvider(router: router, kind: .chat)

        let messages = [
            ChatMessage(role: "system", content: "system-prompt"),
            ChatMessage(role: "user", content: "hello router"),
        ]
        let response = try await provider.chat(messages: messages, model: "glm-4-flash")

        #expect(response.content == "answer-42")
        let calls = mock.recorder.snapshot()
        #expect(calls.count == 1)
        #expect(calls.first?.messages.map(\.content) == ["system-prompt", "hello router"])
        #expect(calls.first?.messages.map(\.role) == ["system", "user"])
        #expect(calls.first?.model == "glm-4-flash")
    }

    @Test("chatStream forwards messages/model and yields upstream chunks")
    func chatStreamForwardsIntact() async throws {
        let mock = RecordingProvider(
            streamChunks: [
                ChatStreamChunk(content: "a", isFinished: false),
                ChatStreamChunk(content: "b", isFinished: true),
            ]
        )
        let router = makeSingleProviderRouter(mock)
        let provider = RouterBackedProvider(router: router, kind: .chat)

        let messages = [ChatMessage(role: "user", content: "streamed")]
        var collected: [String] = []
        for try await chunk in provider.chatStream(messages: messages, model: "glm-4-air") {
            collected.append(chunk.content)
        }

        #expect(collected == ["a", "b"])
        let calls = mock.recorder.snapshot()
        #expect(calls.count == 1)
        #expect(calls.first?.messages.map(\.content) == ["streamed"])
        #expect(calls.first?.model == "glm-4-air")
    }

    @Test(
        "the AITaskKind bound at construction is the one used to look up policy",
        arguments: AITaskKind.allCases
    )
    func boundKindDrivesPolicy(_ kind: AITaskKind) {
        let mock = RecordingProvider()
        let router = makeSingleProviderRouter(mock)
        let provider = RouterBackedProvider(router: router, kind: kind)

        // The stored kind must be the one requirements lookup keys off.
        #expect(provider.kind == kind)
        #expect(router.requirements(for: provider.kind) == AIRouter.defaultPolicy[kind])
    }

    @Test("bound kind selects the routed provider (empty if pruned)")
    func boundKindDrivesProviderOrder() {
        let mock = RecordingProvider()
        // Two-provider router: on-device arm caps at .medium, cloud arm at .high.
        // - `.chat` quality=.high → on-device pruned, only cloud remains.
        // - `.substitute` quality=.low → both survive, on-device first.
        let router = AIRouter(
            providers: [
                AIRouter.RegisteredProvider(
                    name: "onDevice",
                    isAvailable: { true },
                    isOnDevice: true,
                    maxQuality: .medium,
                    provider: mock
                ),
                AIRouter.RegisteredProvider(
                    name: "cloud",
                    isAvailable: { true },
                    isOnDevice: false,
                    maxQuality: .high,
                    provider: mock
                ),
            ],
            deviceTier: { .appleIntelligenceCapable }
        )

        let chatProvider = RouterBackedProvider(router: router, kind: .chat)
        let substituteProvider = RouterBackedProvider(router: router, kind: .substitute)

        #expect(router.plannedProviderOrder(for: chatProvider.kind) == ["cloud"])
        #expect(router.plannedProviderOrder(for: substituteProvider.kind) == ["onDevice", "cloud"])
    }
}

// MARK: - Call-site kind mapping tests (T007-T013)

@Suite("AICallSite Kind Mapping (Stage 2 T007-T013)")
struct AICallSiteKindMappingTests {

    @Test("overviewInsights call site maps to .overviewInsights (T007)")
    func overviewInsightsMapping() {
        #expect(AICallSite.overviewInsights.kind == .overviewInsights)
    }

    @Test("chat call site maps to .chat (T008)")
    func chatMapping() {
        #expect(AICallSite.chat.kind == .chat)
    }

    @Test("trainingAdvice call site maps to .trainingAdvice (T009)")
    func trainingAdviceMapping() {
        #expect(AICallSite.trainingAdvice.kind == .trainingAdvice)
    }

    @Test("dataTrend call site maps to .dataTrend (T010)")
    func dataTrendMapping() {
        #expect(AICallSite.dataTrend.kind == .dataTrend)
    }

    @Test("substitute call site maps to .substitute (T011)")
    func substituteMapping() {
        #expect(AICallSite.substitute.kind == .substitute)
    }

    @Test("every AICallSite maps to a distinct AITaskKind covered by defaultPolicy")
    func callSitesCoverAllStage2Kinds() {
        let mapped = Set(AICallSite.allCases.map(\.kind))
        let expected: Set<AITaskKind> = [
            .overviewInsights, .chat, .trainingAdvice, .dataTrend, .substitute,
        ]
        #expect(mapped == expected)
        for kind in mapped {
            #expect(AIRouter.defaultPolicy[kind] != nil, "policy missing for kind=\(kind.rawValue)")
        }
    }
}
