import Foundation
import Testing
@testable import AIService

@Suite("AIProviderChain Tests", .serialized)
struct AIProviderChainTests {

    @Test("selects first available provider")
    func selectsFirstAvailable() async throws {
        let provider1 = MockAIProvider(name: "first", response: "from-first")
        let provider2 = MockAIProvider(name: "second", response: "from-second")

        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { true }, provider: provider1),
            .init(name: "second", isAvailable: { true }, provider: provider2),
        ])

        let result = try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        #expect(result.content == "from-first")
    }

    @Test("falls back to second provider when first is unavailable")
    func fallbackToSecond() async throws {
        let provider1 = MockAIProvider(name: "first", response: "from-first")
        let provider2 = MockAIProvider(name: "second", response: "from-second")

        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { false }, provider: provider1),
            .init(name: "second", isAvailable: { true }, provider: provider2),
        ])

        let result = try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        #expect(result.content == "from-second")
    }

    @Test("throws noProviderAvailable when all providers are unavailable")
    func allUnavailable() async throws {
        let provider1 = MockAIProvider(name: "first", response: "from-first")
        let provider2 = MockAIProvider(name: "second", response: "from-second")

        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { false }, provider: provider1),
            .init(name: "second", isAvailable: { false }, provider: provider2),
        ])

        await #expect(throws: AIServiceError.self) {
            try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("throws noProviderAvailable with empty entries")
    func emptyEntries() async throws {
        let chain = AIProviderChain(entries: [])

        await #expect(throws: AIServiceError.self) {
            try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("passes messages and model to selected provider")
    func passesParameters() async throws {
        let provider = MockAIProvider(name: "test", response: "ok")
        let chain = AIProviderChain(entries: [
            .init(name: "test", isAvailable: { true }, provider: provider),
        ])

        let messages = [
            ChatMessage(role: "system", content: "You are helpful"),
            ChatMessage(role: "user", content: "Hello"),
        ]
        _ = try await chain.chat(messages: messages, model: "custom-model")

        #expect(provider.lastCapturedMessages?.count == 2)
        #expect(provider.lastCapturedMessages?[0].role == "system")
        #expect(provider.lastCapturedMessages?[1].content == "Hello")
        #expect(provider.lastCapturedModel == "custom-model")
    }

    @Test("chatStream selects first available provider")
    func streamSelectsFirst() async throws {
        let provider1 = MockAIProvider(name: "first", response: "streamed")
        let provider2 = MockAIProvider(name: "second", response: "not-this")

        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { true }, provider: provider1),
            .init(name: "second", isAvailable: { true }, provider: provider2),
        ])

        let stream = chain.chatStream(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk.content)
        }
        #expect(chunks.contains("streamed"))
    }

    @Test("chatStream throws noProviderAvailable when all unavailable")
    func streamAllUnavailable() async throws {
        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { false }, provider: MockAIProvider(name: "first", response: "")),
        ])

        let stream = chain.chatStream(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        await #expect(throws: AIServiceError.self) {
            for try await _ in stream {}
        }
    }

    @Test("noProviderAvailable has non-empty localized description")
    func errorLocalizedDescription() {
        let error = AIServiceError.noProviderAvailable
        let description = error.localizedDescription
        #expect(!description.isEmpty)
    }

    // MARK: - Runtime Error Fallback Tests

    @Test("falls back to next provider when first throws at runtime")
    func runtimeFallback() async throws {
        let failing = MockAIProvider(name: "failing", response: "")
        failing.shouldThrow = true
        let fallback = MockAIProvider(name: "fallback", response: "from-fallback")

        let chain = AIProviderChain(entries: [
            .init(name: "failing", isAvailable: { true }, provider: failing),
            .init(name: "fallback", isAvailable: { true }, provider: fallback),
        ])

        let result = try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        #expect(result.content == "from-fallback")
    }

    @Test("throws last runtime error when all available providers fail")
    func allRuntimeFailures() async throws {
        let failing1 = MockAIProvider(name: "first", response: "")
        failing1.shouldThrow = true
        let failing2 = MockAIProvider(name: "second", response: "")
        failing2.shouldThrow = true

        let chain = AIProviderChain(entries: [
            .init(name: "first", isAvailable: { true }, provider: failing1),
            .init(name: "second", isAvailable: { true }, provider: failing2),
        ])

        await #expect(throws: MockProviderError.self) {
            try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        }
    }

    @Test("skips unavailable providers then falls back on runtime error")
    func mixedUnavailableAndRuntimeFailure() async throws {
        let unavailable = MockAIProvider(name: "unavailable", response: "")
        let failing = MockAIProvider(name: "failing", response: "")
        failing.shouldThrow = true
        let working = MockAIProvider(name: "working", response: "from-working")

        let chain = AIProviderChain(entries: [
            .init(name: "unavailable", isAvailable: { false }, provider: unavailable),
            .init(name: "failing", isAvailable: { true }, provider: failing),
            .init(name: "working", isAvailable: { true }, provider: working),
        ])

        let result = try await chain.chat(messages: [ChatMessage(role: "user", content: "test")], model: nil)
        #expect(result.content == "from-working")
    }
}

// MARK: - Mock Provider

enum MockProviderError: Error {
    case simulatedFailure
}

private final class MockAIProvider: AIProvider, @unchecked Sendable {
    let name: String
    let responseContent: String
    nonisolated(unsafe) var lastCapturedMessages: [ChatMessage]?
    nonisolated(unsafe) var lastCapturedModel: String?
    nonisolated(unsafe) var shouldThrow = false

    init(name: String, response: String) {
        self.name = name
        self.responseContent = response
    }

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        if shouldThrow { throw MockProviderError.simulatedFailure }
        lastCapturedMessages = messages
        lastCapturedModel = model
        return ChatResponse(content: responseContent, model: name)
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
