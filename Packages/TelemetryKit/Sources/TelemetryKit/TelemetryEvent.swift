/// All telemetry events tracked by VitalStride.
///
/// Parameter string values MUST be locale-independent English identifiers
/// (e.g. `tab: "workout"`, `sampleType: "heartRate"`), never localized strings.
/// Remote analytics providers aggregate by parameter value — locale-dependent
/// values would fragment metrics across languages.
public enum TelemetryEvent: Sendable, Equatable {
    // MARK: - Navigation

    case tabSwitched(tab: String)
    case onboardingCompleted

    // MARK: - Workout lifecycle (CONTEXT.md: Workout / WorkoutExercise / ExerciseSet)

    case workoutStarted(source: String)
    case workoutCompleted(durationSeconds: Int, exerciseCount: Int, setCount: Int)
    case workoutDiscarded
    case exerciseAdded(name: String)
    case setCompleted(exerciseName: String)
    case setDeleted

    // MARK: - Health data

    case healthKitAuthorized
    case healthKitDenied
    case dataDetailOpened(sampleType: String)
    case dataImported(format: String)

    // MARK: - AI

    case aiInsightGenerated(durationMs: Int, cardCount: Int)
    case aiInsightFailed(errorType: String)
    case aiAnalysisRequested(sampleType: String)
    case aiModelChanged(model: String)
    case aiChatMessageSent

    // MARK: - Rest timer

    case restTimerStarted(durationSeconds: Int)
    case restTimerSkipped
    case restTimerCompleted

    // MARK: - Overview

    case overviewCacheHit
    case overviewCacheMiss
    case overviewFallbackTriggered(reason: String)
}

// MARK: - Console formatting

extension TelemetryEvent {
    var eventName: String {
        switch self {
        case .tabSwitched: "tab_switched"
        case .onboardingCompleted: "onboarding_completed"
        case .workoutStarted: "workout_started"
        case .workoutCompleted: "workout_completed"
        case .workoutDiscarded: "workout_discarded"
        case .exerciseAdded: "exercise_added"
        case .setCompleted: "set_completed"
        case .setDeleted: "set_deleted"
        case .healthKitAuthorized: "healthkit_authorized"
        case .healthKitDenied: "healthkit_denied"
        case .dataDetailOpened: "data_detail_opened"
        case .dataImported: "data_imported"
        case .aiInsightGenerated: "ai_insight_generated"
        case .aiInsightFailed: "ai_insight_failed"
        case .aiAnalysisRequested: "ai_analysis_requested"
        case .aiModelChanged: "ai_model_changed"
        case .aiChatMessageSent: "ai_chat_message_sent"
        case .restTimerStarted: "rest_timer_started"
        case .restTimerSkipped: "rest_timer_skipped"
        case .restTimerCompleted: "rest_timer_completed"
        case .overviewCacheHit: "overview_cache_hit"
        case .overviewCacheMiss: "overview_cache_miss"
        case .overviewFallbackTriggered: "overview_fallback_triggered"
        }
    }

    var parameters: [(key: String, value: String)] {
        switch self {
        case .tabSwitched(let tab):
            [("tab", tab)]
        case .workoutStarted(let source):
            [("source", source)]
        case .workoutCompleted(let duration, let exercises, let sets):
            [("duration_s", "\(duration)"), ("exercises", "\(exercises)"), ("sets", "\(sets)")]
        case .exerciseAdded(let name):
            [("name", name)]
        case .setCompleted(let exerciseName):
            [("exercise", exerciseName)]
        case .dataDetailOpened(let sampleType):
            [("sample_type", sampleType)]
        case .dataImported(let format):
            [("format", format)]
        case .aiInsightGenerated(let durationMs, let cardCount):
            [("duration_ms", "\(durationMs)"), ("cards", "\(cardCount)")]
        case .aiInsightFailed(let errorType):
            [("error_type", errorType)]
        case .aiAnalysisRequested(let sampleType):
            [("sample_type", sampleType)]
        case .aiModelChanged(let model):
            [("model", model)]
        case .restTimerStarted(let duration):
            [("duration_s", "\(duration)")]
        case .overviewFallbackTriggered(let reason):
            [("reason", reason)]
        default:
            []
        }
    }

    var formattedString: String {
        let params = parameters
        if params.isEmpty {
            return eventName
        }
        let paramString = params.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        return "\(eventName) \(paramString)"
    }
}
