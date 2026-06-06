import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vitalstride.aiservice", category: "ZhipuProvider")

public struct ZhipuProvider: AIProvider, Sendable {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
    private let defaultModel = "glm-4-flash"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        let selectedModel = model ?? defaultModel
        logger.info("Starting chat request: model=\(selectedModel), mode=normal")
        let startTime = CFAbsoluteTimeGetCurrent()

        let request = try buildRequest(messages: messages, model: selectedModel, stream: false)
        let (data, urlResponse) = try await performRequest(request)
        try validateHTTPResponse(urlResponse)

        guard let body = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            logger.error("Response parsing failed for model=\(selectedModel)")
            throw AIServiceError.responseParsingFailed
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let usage = body.usage.map { ChatResponse.Usage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens) }
        if let u = body.usage {
            logger.info("Chat completed: elapsed=\(String(format: "%.2f", elapsed))s, promptTokens=\(u.promptTokens), completionTokens=\(u.completionTokens)")
        } else {
            logger.info("Chat completed: elapsed=\(String(format: "%.2f", elapsed))s")
        }

        let content = body.choices.first?.message.content ?? ""
        return ChatResponse(content: content, model: body.model, usage: usage)
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let selectedModel = model ?? defaultModel
        logger.info("Starting chat request: model=\(selectedModel), mode=streaming")

        return AsyncThrowingStream { continuation in
            let task = Task {
                var chunksReceived = 0
                do {
                    let request = try buildRequest(messages: messages, model: selectedModel, stream: true)
                    let (bytes, urlResponse) = try await session.bytes(for: request)
                    try validateHTTPResponse(urlResponse)

                    for try await line in bytes.lines {
                        guard let chunk = parseSSELine(line) else { continue }
                        if chunk.isFinished {
                            logger.info("Streaming completed: chunksReceived=\(chunksReceived)")
                            continuation.finish()
                            return
                        }
                        chunksReceived += 1
                        continuation.yield(chunk)
                    }

                    logger.info("Streaming completed: chunksReceived=\(chunksReceived)")
                    continuation.finish()
                } catch {
                    logger.error("Streaming interrupted: chunksReceived=\(chunksReceived), error=\(error.localizedDescription)")
                    if chunksReceived > 0 {
                        continuation.finish(throwing: AIServiceError.streamingInterrupted(chunksReceived: chunksReceived, underlying: error))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private func buildRequest(messages: [ChatMessage], model: String, stream: Bool) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw AIServiceError.networkError(underlying: error)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("HTTP error: statusCode=\(httpResponse.statusCode)")
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - SSE Parsing

extension ZhipuProvider {
    func parseSSELine(_ line: String) -> ChatStreamChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" {
            return ChatStreamChunk(content: "", isFinished: true)
        }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(StreamChunkResponse.self, from: data) else {
            return nil
        }

        let content = chunk.choices.first?.delta.content ?? ""
        let finished = chunk.choices.first?.finishReason != nil
        return ChatStreamChunk(content: content, isFinished: finished)
    }
}

// MARK: - API Request/Response Models

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [MessagePayload]
    let stream: Bool

    struct MessagePayload: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let model: String?
    let usage: UsageResponse?

    struct Choice: Decodable {
        let message: Message

        struct Message: Decodable {
            let content: String
        }
    }

    struct UsageResponse: Decodable {
        let promptTokens: Int
        let completionTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct StreamChunkResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }

        struct Delta: Decodable {
            let content: String?
        }
    }
}
