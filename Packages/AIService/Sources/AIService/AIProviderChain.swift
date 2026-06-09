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
        let availableEntries = filterAvailable()
        guard !availableEntries.isEmpty else {
            logger.error("noProviderAvailable: all providers checked, none available")
            throw AIServiceError.noProviderAvailable
        }

        var lastError: Error = AIServiceError.noProviderAvailable
        for entry in availableEntries {
            let signpostID = signposter.makeSignpostID()
            let state = signposter.beginInterval("ai_provider_chat", id: signpostID, "provider=\(entry.name)")
            do {
                let response = try await entry.provider.chat(messages: messages, model: model)
                signposter.endInterval("ai_provider_chat", state)
                return response
            } catch {
                signposter.endInterval("ai_provider_chat", state)
                let category = Self.errorCategory(error)
                logger.log("Fallback: provider=\(entry.name) failed at runtime, reason=\(category)")
                lastError = error
            }
        }

        logger.error("noProviderAvailable: all available providers failed at runtime")
        throw lastError
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let availableEntries = filterAvailable()
        guard let entry = availableEntries.first else {
            logger.error("noProviderAvailable: all providers checked, none available")
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.noProviderAvailable) }
        }

        logger.info("Provider selected: \(entry.name)")
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_provider_stream_first_token", id: signpostID, "provider=\(entry.name)")

        let upstream = entry.provider.chatStream(messages: messages, model: model)
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
    }

    // MARK: - Private

    private func filterAvailable() -> [ProviderEntry] {
        var available: [ProviderEntry] = []
        for entry in entries {
            if entry.isAvailable() {
                available.append(entry)
            } else {
                logger.log("Fallback: skipping provider=\(entry.name), reason=unavailable")
            }
        }
        if let selected = available.first {
            logger.info("Provider selected: \(selected.name)")
        }
        return available
    }

    private static func errorCategory(_ error: Error) -> String {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let code): return "httpError(\(code))"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is URLError { return "networkError" }
        return "unknown"
    }
}
