import AIService
import Foundation

/// Adapter that binds an `AIRouter` and an `AITaskKind` into a plain `AIProvider`.
///
/// Existing app-side callers (`AIAnalysisService(modelContainer:, provider:)`) accept
/// a raw `AIProvider`. Spec 019 Stage 2 requires every AI call to flow through
/// `AIRouter.execute(kind:messages:model:)`, but we want to keep the
/// `AIAnalysisService` initializer stable (its tests inject a `MockAIProvider`).
/// Wrapping `(router, kind)` in this adapter routes every underlying `.chat` /
/// `.chatStream` call back through the router while leaving the analysis-service
/// contract untouched (FR-001, FR-004).
struct RouterBackedProvider: AIProvider, Sendable {
    let router: AIRouter
    let kind: AITaskKind

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try await router.execute(kind: kind, messages: messages, model: model)
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        router.executeStream(kind: kind, messages: messages, model: model)
    }
}
