#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import OSLog
import os

private let logger = Logger(subsystem: "com.vitalstride.aiservice", category: "AppleIntelligenceProvider")
private let signposter = OSSignposter(subsystem: "com.vitalstride.aiservice", category: "AppleIntelligenceProvider")

public struct AppleIntelligenceProvider: AIProvider, Sendable {

    public static var isAvailable: Bool {
        guard #available(iOS 26, macOS 26, *) else { return false }
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    public init() {}

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else {
            throw AIServiceError.noProviderAvailable
        }
        return try await performChat(messages: messages)
        #else
        throw AIServiceError.noProviderAvailable
        #endif
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.noProviderAvailable) }
        }
        return performChatStream(messages: messages)
        #else
        return AsyncThrowingStream { $0.finish(throwing: AIServiceError.noProviderAvailable) }
        #endif
    }
}

// MARK: - FoundationModels Implementation

#if canImport(FoundationModels)
extension AppleIntelligenceProvider {

    @available(iOS 26, macOS 26, *)
    private func performChat(messages: [ChatMessage]) async throws -> ChatResponse {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_provider_chat", id: signpostID, "provider=apple_intelligence")
        defer { signposter.endInterval("ai_provider_chat", state) }

        let (instructions, prompt) = Self.formatMessages(messages)
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)

        return ChatResponse(content: response.content, model: "apple-intelligence")
    }

    @available(iOS 26, macOS 26, *)
    private func performChatStream(messages: [ChatMessage]) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let signpostID = signposter.makeSignpostID()
                let ttftState = signposter.beginInterval("ai_provider_stream_first_token", id: signpostID, "provider=apple_intelligence")
                var firstTokenRecorded = false

                do {
                    let (instructions, prompt) = Self.formatMessages(messages)
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
                    var previousContent = ""

                    for try await snapshot in stream {
                        let currentContent = snapshot.content
                        if !firstTokenRecorded {
                            signposter.endInterval("ai_provider_stream_first_token", ttftState)
                            firstTokenRecorded = true
                        }
                        let delta = String(currentContent.dropFirst(previousContent.count))
                        if !delta.isEmpty {
                            continuation.yield(ChatStreamChunk(content: delta))
                        }
                        previousContent = currentContent
                    }

                    if !firstTokenRecorded {
                        signposter.endInterval("ai_provider_stream_first_token", ttftState)
                    }
                    continuation.yield(ChatStreamChunk(content: "", isFinished: true))
                    continuation.finish()
                } catch {
                    if !firstTokenRecorded {
                        signposter.endInterval("ai_provider_stream_first_token", ttftState)
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
#endif

// MARK: - Message Formatting

extension AppleIntelligenceProvider {

    static func formatMessages(_ messages: [ChatMessage]) -> (instructions: String?, prompt: String) {
        let systemParts = messages.filter { $0.role == "system" }.map(\.content)
        let conversationMessages = messages.filter { $0.role != "system" }

        let instructions: String? = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n")

        if conversationMessages.count == 1, conversationMessages[0].role == "user" {
            return (instructions, conversationMessages[0].content)
        }

        let prompt = conversationMessages
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        return (instructions, prompt.isEmpty ? "" : prompt)
    }
}
