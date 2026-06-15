/// A locale-independent identifier for telemetry parameters.
///
/// Enforces that all telemetry string values are ASCII-only identifiers,
/// preventing localized or free-text values from fragmenting analytics.
/// Non-conforming characters are stripped at construction time.
public struct TelemetryIdentifier: Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(stringLiteral value: String) {
        self.rawValue = Self.normalize(value)
    }

    public init(_ value: String) {
        self.rawValue = Self.normalize(value)
    }

    private static func normalize(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            guard scalar.isASCII else { continue }
            let v = scalar.value
            let isAllowed =
                (v >= 0x30 && v <= 0x39)  // 0-9
                || (v >= 0x41 && v <= 0x5A)  // A-Z
                || (v >= 0x61 && v <= 0x7A)  // a-z
                || v == 0x5F  // _
                || v == 0x2D  // -
                || v == 0x2E  // .
            if isAllowed {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
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

    // MARK: - AI

    case aiInsightGenerated(durationMs: Int, cardCount: Int)
    case aiInsightFailed(errorType: TelemetryIdentifier)
    case aiAnalysisRequested(sampleType: TelemetryIdentifier)
    case aiModelChanged(model: TelemetryIdentifier)
    case aiChatMessageSent

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
        case .aiInsightGenerated(let durationMs, let cardCount):
            [("duration_ms", "\(durationMs)"), ("cards", "\(cardCount)")]
        case .aiInsightFailed(let errorType):
            [("error_type", errorType.rawValue)]
        case .aiAnalysisRequested(let sampleType):
            [("sample_type", sampleType.rawValue)]
        case .aiModelChanged(let model):
            [("model", model.rawValue)]
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

    private static func sanitize(_ value: String) -> String {
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
