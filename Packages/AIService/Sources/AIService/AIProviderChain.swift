import Foundation
import OSLog
import os

private let logger = Logger(subsystem: "com.vitalstride.aiservice", category: "AIProviderChain")
private let signposter = OSSignposter(subsystem: "com.vitalstride.aiservice", category: "AIProviderChain")

public struct AIProviderChain: AIProvider, Sendable {

    public struct ProviderEntry: Sendable {
        public let name: String
        public let isAvailable: @Sendable () -> Bool
        public let provider: any AIProvider

        public init(name: String, isAvailable: @escaping @Sendable () -> Bool, provider: any AIProvider) {
            self.name = name
            self.isAvailable = isAvailable
            self.provider = provider
        }
    }

    private let entries: [ProviderEntry]

    public init(entries: [ProviderEntry]) {
        self.entries = entries
    }

    public static func makeDefault(zhipuAPIKey: String?) -> AIProviderChain {
        var entries: [ProviderEntry] = []

        entries.append(ProviderEntry(
            name: "apple_intelligence",
            isAvailable: { AppleIntelligenceProvider.isAvailable },
            provider: AppleIntelligenceProvider()
        ))

        if let key = zhipuAPIKey {
            entries.append(ProviderEntry(
                name: "zhipu",
                isAvailable: { !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                provider: ZhipuProvider(apiKey: key)
            ))
        }

        return AIProviderChain(entries: entries)
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        let (name, provider) = try selectProvider()
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_provider_chat", id: signpostID, "provider=\(name)")
        do {
            let response = try await provider.chat(messages: messages, model: model)
            signposter.endInterval("ai_provider_chat", state)
            return response
        } catch {
            signposter.endInterval("ai_provider_chat", state)
            throw error
        }
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        do {
            let (name, provider) = try selectProvider()
            let signpostID = signposter.makeSignpostID()
            let state = signposter.beginInterval("ai_provider_stream_first_token", id: signpostID, "provider=\(name)")

            let upstream = provider.chatStream(messages: messages, model: model)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var firstTokenRecorded = false
                    do {
                        for try await chunk in upstream {
                            if !firstTokenRecorded {
                                signposter.endInterval("ai_provider_stream_first_token", state)
                                firstTokenRecorded = true
                            }
                            continuation.yield(chunk)
                        }
                        if !firstTokenRecorded {
                            signposter.endInterval("ai_provider_stream_first_token", state)
                        }
                        continuation.finish()
                    } catch {
                        if !firstTokenRecorded {
                            signposter.endInterval("ai_provider_stream_first_token", state)
                        }
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - Private

    private func selectProvider() throws -> (name: String, provider: any AIProvider) {
        for entry in entries {
            if entry.isAvailable() {
                logger.info("Provider selected: \(entry.name)")
                return (entry.name, entry.provider)
            }
            logger.log("Fallback: skipping provider=\(entry.name), reason=unavailable")
        }
        logger.error("noProviderAvailable: all providers checked, none available")
        throw AIServiceError.noProviderAvailable
    }
}
