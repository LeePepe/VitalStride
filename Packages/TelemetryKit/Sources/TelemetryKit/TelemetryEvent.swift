/// A locale-independent identifier for telemetry parameters.
///
/// Only ASCII alphanumerics, underscores, hyphens, and dots are allowed.
/// Use ``init?(validating:)`` for dynamic strings — it returns `nil` on
/// non-canonical input instead of silently normalizing, so PII and
/// localized text cannot be logged as telemetry values.
/// String literals are validated via `precondition` in debug builds.
public struct TelemetryIdentifier: Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(stringLiteral value: String) {
        precondition(
            Self.isCanonical(value),
            "TelemetryIdentifier literal contains non-canonical characters: \(value)"
        )
        self.rawValue = value
    }

    public init?(validating value: String) {
        guard !value.isEmpty, Self.isCanonical(value) else { return nil }
        self.rawValue = value
    }

    static func isCanonical(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39)    // 0-9
                || (byte >= 0x41 && byte <= 0x5A)  // A-Z
                || (byte >= 0x61 && byte <= 0x7A)  // a-z
                || byte == 0x5F                     // _
                || byte == 0x2D                     // -
                || byte == 0x2E                     // .
        }
    }
}

/// All telemetry events tracked by VitalStride.
///
/// String-typed parameters use `TelemetryIdentifier` to enforce
/// locale-independent ASCII identifiers at construction time.
/// Remote analytics providers aggregate by parameter value — locale-dependent
/// values would fragment metrics across languages.
///
/// For `exerciseAdded(name:)` and `setCompleted(exerciseName:)`, callers MUST
/// pass the exercise's canonical English identifier (e.g. `"bench_press"`),
/// NOT the user-facing display name or any localized/custom string.
public enum TelemetryEvent: Sendable, Equatable {
    // MARK: - Navigation

    case tabSwitched(tab: TelemetryIdentifier)
    case onboardingCompleted

    // MARK: - Workout lifecycle (CONTEXT.md: Workout / WorkoutExercise / ExerciseSet)

    case workoutStarted(source: TelemetryIdentifier)
    case workoutCompleted(durationSeconds: Int, exerciseCount: Int, setCount: Int)
    case workoutDiscarded
    case exerciseAdded(name: TelemetryIdentifier)
    case setCompleted(exerciseName: TelemetryIdentifier)
    case setDeleted

    // MARK: - Health data

    case healthKitAuthorized
    case healthKitDenied
    case dataDetailOpened(sampleType: TelemetryIdentifier)
    case dataImported(format: TelemetryIdentifier)
    case healthSummaryLoadFailed(sampleType: TelemetryIdentifier)

    // MARK: - AI

    case aiInsightGenerated(durationMs: Int, cardCount: Int)
    case aiInsightFailed(errorType: TelemetryIdentifier)
    case aiAnalysisRequested(sampleType: TelemetryIdentifier)
    case aiModelChanged(model: TelemetryIdentifier)
    case aiChatMessageSent
    /// AI cache/decode persistence failure.
    ///
    /// `operation` identifies the failing cache action (e.g. `read`, `write`,
    /// `decode`, `encode`, `delete`). `errorType` identifies the failure class
    /// (e.g. `io_error`, `decode_error`, `not_found`).
    ///
    /// Both parameters MUST be canonical ASCII identifiers — never raw error
    /// messages, HealthKit values, AI response content, prompt text, cache
    /// JSON, or localized strings.
    case aiCacheFailure(operation: TelemetryIdentifier, errorType: TelemetryIdentifier)

    // MARK: - Rest timer

    case restTimerStarted(durationSeconds: Int)
    case restTimerSkipped
    case restTimerCompleted

    // MARK: - Overview

    case overviewCacheHit
    case overviewCacheMiss
    case overviewFallbackTriggered(reason: TelemetryIdentifier)
}

// MARK: - Console formatting

extension TelemetryEvent {
    public var eventName: String {
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
        case .healthSummaryLoadFailed: "health_summary_load_failed"
        case .aiInsightGenerated: "ai_insight_generated"
        case .aiInsightFailed: "ai_insight_failed"
        case .aiAnalysisRequested: "ai_analysis_requested"
        case .aiModelChanged: "ai_model_changed"
        case .aiChatMessageSent: "ai_chat_message_sent"
        case .aiCacheFailure: "ai_cache_failure"
        case .restTimerStarted: "rest_timer_started"
        case .restTimerSkipped: "rest_timer_skipped"
        case .restTimerCompleted: "rest_timer_completed"
        case .overviewCacheHit: "overview_cache_hit"
        case .overviewCacheMiss: "overview_cache_miss"
        case .overviewFallbackTriggered: "overview_fallback_triggered"
        }
    }

    public var parameters: [(key: String, value: String)] {
        switch self {
        case .tabSwitched(let tab):
            [("tab", tab.rawValue)]
        case .workoutStarted(let source):
            [("source", source.rawValue)]
        case .workoutCompleted(let duration, let exercises, let sets):
            [("duration_s", "\(duration)"), ("exercises", "\(exercises)"), ("sets", "\(sets)")]
        case .exerciseAdded(let name):
            [("name", name.rawValue)]
        case .setCompleted(let exerciseName):
            [("exercise", exerciseName.rawValue)]
        case .dataDetailOpened(let sampleType):
            [("sample_type", sampleType.rawValue)]
        case .dataImported(let format):
            [("format", format.rawValue)]
        case .healthSummaryLoadFailed(let sampleType):
            [("sample_type", sampleType.rawValue)]
        case .aiInsightGenerated(let durationMs, let cardCount):
            [("duration_ms", "\(durationMs)"), ("cards", "\(cardCount)")]
        case .aiInsightFailed(let errorType):
            [("error_type", errorType.rawValue)]
        case .aiAnalysisRequested(let sampleType):
            [("sample_type", sampleType.rawValue)]
        case .aiModelChanged(let model):
            [("model", model.rawValue)]
        case .aiCacheFailure(let operation, let errorType):
            [("operation", operation.rawValue), ("error_type", errorType.rawValue)]
        case .restTimerStarted(let duration):
            [("duration_s", "\(duration)")]
        case .overviewFallbackTriggered(let reason):
            [("reason", reason.rawValue)]
        default:
            []
        }
    }

    public var formattedString: String {
        let params = parameters
        if params.isEmpty {
            return eventName
        }
        let paramString = params
            .map { "\($0.key)=\(Self.sanitize($0.value))" }
            .joined(separator: " ")
        return "\(eventName) \(paramString)"
    }

    static func sanitize(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            guard scalar.isASCII else { continue }
            let v = scalar.value
            switch v {
            case 0x5C:  // backslash
                result += "\\\\"
            case 0x20:  // space
                result += "\\_"
            case 0x0A:  // newline
                result += "\\n"
            case 0x0D:  // carriage return
                result += "\\r"
            case 0x3D:  // equals
                result += "\\="
            case 0x09:  // tab
                result += "\\t"
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F:
                continue
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
