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

    // MARK: - Smart progression (spec 006-smart-progression FR-006)

    /// The user tap-filled a Smart Progression suggestion and left the row
    /// unedited through the relevant save/commit point.
    ///
    /// `advice` is the advice-kind category (e.g. `increase_weight`,
    /// `maintain`, `decrease_weight`, `increase_reps`) — Constitution I /
    /// Quality Bar B forbid embedding actual weight / reps / HealthKit values
    /// or free-form reason text here. Callers MUST pass a canonical ASCII
    /// identifier, never the localized reason string.
    case suggestionAccepted(advice: TelemetryIdentifier)

    /// The user tap-filled a Smart Progression suggestion but then manually
    /// edited weight or reps before the save/commit point.
    ///
    /// See ``suggestionAccepted(advice:)`` for the same privacy constraint on
    /// the `advice` parameter.
    case suggestionOverridden(advice: TelemetryIdentifier)

    // MARK: - Exercise picker diagnostics (MY-1338)

    /// The ExercisePicker's side index bar resolved a new highlight target for
    /// a different equipment section. Emitted whenever the picker moves the
    /// visible-highlight from one equipment `from` to another `to`, tagged
    /// with the canonical `source` identifier (`"drag"` when the change came
    /// from the side-bar drag gesture, `"scroll"` when it came from natural
    /// scroll-target visibility).
    ///
    /// Used to diagnose the highlight-mismatch bug where drag `onSelect` and
    /// `onScrollTargetVisibilityChange` race and produce a short-lived
    /// intermediate highlight on the wrong equipment. Sampling `from → to`
    /// transitions plus the source lets us see churn without needing raw
    /// coordinates or timings.
    ///
    /// Privacy: `from` / `to` / `source` are all canonical `TelemetryIdentifier`
    /// values — Constitution §I forbids raw display names, localized strings,
    /// or health values in this payload.
    case exercisePickerSectionJump(
        from: TelemetryIdentifier,
        to: TelemetryIdentifier,
        source: TelemetryIdentifier
    )

    /// The user completed one side-bar index scrub gesture. `count` is the
    /// number of distinct equipment sections the scrub visited within that
    /// single gesture — a burst high-`count` value is the signal that the
    /// highlight is racing / jumping through neighbors instead of settling.
    ///
    /// Privacy: `count` is a pure event counter; no equipment identifiers or
    /// health values are recorded here.
    case exercisePickerIndexScrubbed(count: Int)

    // MARK: - App performance (MetricKit MXMetricPayload, ADR-0015 §perf)
    //
    // Coarse, already-aggregated performance histograms Apple delivers via
    // MetricKit. All payloads are Ints (millis / MB / permille); no PII, no
    // health values — §I holds by construction. Emitted by
    // `MetricKitDiagnosticCollector.didReceive(_ payloads: [MXMetricPayload])`.

    /// Time-to-first-draw at launch (`applicationLaunchMetrics`, average, ms).
    case appLaunchTimeMeasured(millisToFirstDraw: Int)

    /// Cumulative hang time per hour of foreground use
    /// (`applicationResponsivenessMetrics` hang histogram → total ms, hourly).
    case appHangTimeMeasured(hangMillisPerHour: Int)

    /// Peak resident memory during the reporting window
    /// (`memoryMetrics.peakMemoryUsage`, MB).
    case appMemoryPeakMeasured(peakMemoryMB: Int)

    /// Cumulative foreground CPU time in the reporting window
    /// (`cpuMetrics.cumulativeCPUTime`, ms).
    case appCPUTimeMeasured(cpuMillis: Int)
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
        case .suggestionAccepted: "suggestion_accepted"
        case .suggestionOverridden: "suggestion_overridden"
        case .exercisePickerSectionJump: "exercise_picker_section_jump"
        case .exercisePickerIndexScrubbed: "exercise_picker_index_scrubbed"
        case .appLaunchTimeMeasured: "app_launch_time_measured"
        case .appHangTimeMeasured: "app_hang_time_measured"
        case .appMemoryPeakMeasured: "app_memory_peak_measured"
        case .appCPUTimeMeasured: "app_cpu_time_measured"
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
        case .suggestionAccepted(let advice):
            [("advice", advice.rawValue)]
        case .suggestionOverridden(let advice):
            [("advice", advice.rawValue)]
        case .exercisePickerSectionJump(let from, let to, let source):
            [("from", from.rawValue), ("to", to.rawValue), ("source", source.rawValue)]
        case .exercisePickerIndexScrubbed(let count):
            [("count", "\(count)")]
        case .appLaunchTimeMeasured(let millis):
            [("millis_to_first_draw", "\(millis)")]
        case .appHangTimeMeasured(let millis):
            [("hang_millis_per_hour", "\(millis)")]
        case .appMemoryPeakMeasured(let mb):
            [("peak_memory_mb", "\(mb)")]
        case .appCPUTimeMeasured(let millis):
            [("cpu_millis", "\(millis)")]
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
