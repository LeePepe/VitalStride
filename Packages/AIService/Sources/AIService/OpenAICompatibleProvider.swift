import Foundation

/// A small OpenAI-compatible client implemented with URLSession only.
public struct OpenAICompatibleProvider: AIProvider, Sendable {
    public let baseURL: URL
    public let defaultModel: String
    private let apiKey: String?
    private let keychainService: String?
    private let keychain: KeychainHelper
    private let session: URLSession
    private let requiresAPIKey: Bool

    public init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        keychainService: String? = nil,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.defaultModel = model
        self.apiKey = apiKey
        self.keychainService = keychainService
        self.keychain = keychain
        self.session = session
        self.requiresAPIKey = true
    }

    fileprivate init(
        baseURL: URL,
        model: String,
        token: String?,
        keychainService: String?,
        keychain: KeychainHelper,
        session: URLSession,
        requiresAPIKey: Bool
    ) {
        self.baseURL = baseURL
        self.defaultModel = model
        self.apiKey = token
        self.keychainService = keychainService
        self.keychain = keychain
        self.session = session
        self.requiresAPIKey = requiresAPIKey
    }

    public init(
        baseURL: URL,
        modelID: String,
        keychainService: String,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) {
        self.init(
            baseURL: baseURL,
            model: modelID,
            keychainService: keychainService,
            keychain: keychain,
            session: session
        )
    }

    public init(
        baseURL: URL,
        modelID: String,
        apiKeyKeychainService: String,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) {
        self.init(
            baseURL: baseURL,
            model: modelID,
            keychainService: apiKeyKeychainService,
            keychain: keychain,
            session: session
        )
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        let request = try makeRequest(messages: messages, model: model ?? defaultModel, stream: false)
        let (data, response) = try await perform(request)
        try validate(response)
        guard let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let choice = decoded.choices.first else {
            throw AIServiceError.responseParsingFailed
        }
        let usage = decoded.usage.map {
            ChatResponse.Usage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens)
        }
        return ChatResponse(content: choice.message.content, model: decoded.model ?? model ?? defaultModel, usage: usage)
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let selectedModel = model ?? defaultModel
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages, model: selectedModel, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    for try await line in bytes.lines {
                        guard let chunk = try parseSSELine(line) else { continue }
                        continuation.yield(chunk)
                        if chunk.isFinished { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func parseSSELine(_ line: String) throws -> ChatStreamChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return ChatStreamChunk(content: "", isFinished: true) }
        guard !payload.isEmpty, let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
            if payload.isEmpty { return nil }
            throw AIServiceError.responseParsingFailed
        }
        let choice = chunk.choices.first
        return ChatStreamChunk(
            content: choice?.delta.content ?? "",
            isFinished: choice?.finishReason != nil
        )
    }

    private func makeRequest(messages: [ChatMessage], model: String, stream: Bool) throws -> URLRequest {
        let key = try resolvedAPIKey()
        var request = URLRequest(url: endpointURL())
        request.httpMethod = "POST"
        if let key {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIChatRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            stream: stream
        ))
        return request
    }

    private func resolvedAPIKey() throws -> String? {
        let value: String?
        if let apiKey {
            value = apiKey
        } else if let keychainService {
            value = try? keychain.load(service: keychainService)
        } else {
            value = nil
        }
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if requiresAPIKey { throw AIServiceError.missingAPIKey }
            return nil
        }
        return value
    }

    private func endpointURL() -> URL {
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") { return baseURL }
        return baseURL.appendingPathComponent("chat/completions")
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw AIServiceError.networkError(underlying: error)
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

public struct JevGatewayProvider: AIProvider, Sendable {
    private let provider: OpenAICompatibleProvider

    public init(
        baseURL: URL,
        model: String,
        token: String? = nil,
        keychainService: String? = nil,
        keychain: KeychainHelper = KeychainHelper(),
        session: URLSession = .shared
    ) {
        provider = OpenAICompatibleProvider(
            baseURL: baseURL,
            model: model,
            token: token,
            keychainService: keychainService,
            keychain: keychain,
            session: session,
            requiresAPIKey: false
        )
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try await provider.chat(messages: messages, model: model)
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        provider.chatStream(messages: messages, model: model)
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]
    let model: String?
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
    }
}
