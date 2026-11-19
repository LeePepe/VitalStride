import Foundation

public struct JevGatewayProvider: AIProvider, Sendable {
    private let provider: OpenAICompatibleProvider

    public init(
        baseURL: URL,
        model: String,
        token: String? = nil,
        allowsUnauthenticated: Bool = false,
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
            requiresAPIKey: !allowsUnauthenticated
        )
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try await provider.chat(messages: messages, model: model)
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        provider.chatStream(messages: messages, model: model)
    }
}

