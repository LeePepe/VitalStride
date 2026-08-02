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

/// Canonical map from the Stage 2 T007–T013 caller sites to their `AITaskKind`.
///
/// Every migrated caller reads its kind from this enum instead of hard-coding a
/// case at the construction site. This gives the mapping a single source of
/// truth that Stage 2 tests can assert against — otherwise the "did this file
/// pick the right kind?" check would only live in the spec's tasks.md.
///
/// Spec 019 tasks.md T007–T013:
/// - T007 `Overview/OverviewInsightsSection.swift` + `Overview/OverviewDynamicState.swift`
///        → `.overviewInsights`
/// - T008 `AIView.swift` + `AIChatView.swift` → `.chat`
/// - T009 `AITrainingAdviceCard.swift` → `.trainingAdvice`
/// - T010 `AIDataAnalysisSection.swift` + `DataSections/DataAISummaryState.swift`
///        → `.dataTrend`
/// - T011 `ActiveWorkoutView.swift` (`loadSubstitutes`) → `.substitute`
enum AICallSite: String, CaseIterable, Sendable {
    case overviewInsights
    case chat
    case trainingAdvice
    case dataTrend
    case substitute

    var kind: AITaskKind {
        switch self {
        case .overviewInsights: return .overviewInsights
        case .chat: return .chat
        case .trainingAdvice: return .trainingAdvice
        case .dataTrend: return .dataTrend
        case .substitute: return .substitute
        }
    }
}
