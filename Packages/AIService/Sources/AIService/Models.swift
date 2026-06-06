import Foundation

public struct ChatMessage: Sendable, Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatResponse: Sendable {
    public let content: String
    public let model: String?
    public let usage: Usage?

    public init(content: String, model: String? = nil, usage: Usage? = nil) {
        self.content = content
        self.model = model
        self.usage = usage
    }

    public struct Usage: Sendable {
        public let promptTokens: Int
        public let completionTokens: Int

        public init(promptTokens: Int, completionTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
        }
    }
}

public struct ChatStreamChunk: Sendable {
    public let content: String
    public let isFinished: Bool

    public init(content: String, isFinished: Bool = false) {
        self.content = content
        self.isFinished = isFinished
    }
}
