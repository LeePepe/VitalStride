import Testing
@testable import TelemetryKit

@Suite("TelemetryIdentifier")
struct TelemetryIdentifierTests {
    @Test("preserves valid ASCII identifiers")
    func preservesValidIdentifiers() {
        let id = TelemetryIdentifier(validating: "bench_press")
        #expect(id?.rawValue == "bench_press")
    }

    @Test("preserves hyphens and dots")
    func preservesHyphensAndDots() {
        let id = TelemetryIdentifier(validating: "glm-4.flash")
        #expect(id?.rawValue == "glm-4.flash")
    }

    @Test("rejects pure non-ASCII characters")
    func rejectsNonASCII() {
        #expect(TelemetryIdentifier(validating: "训练") == nil)
    }

    @Test("rejects mixed ASCII and non-ASCII")
    func rejectsMixedContent() {
        #expect(TelemetryIdentifier(validating: "bench_press_卧推") == nil)
    }

    @Test("rejects strings with spaces")
    func rejectsSpaces() {
        #expect(TelemetryIdentifier(validating: "bench press") == nil)
    }

    @Test("rejects strings with control characters")
    func rejectsControlChars() {
        #expect(TelemetryIdentifier(validating: "hello\tworld\n") == nil)
    }

    @Test("rejects strings with special characters")
    func rejectsSpecialChars() {
        #expect(TelemetryIdentifier(validating: "key=value&foo") == nil)
    }

    @Test("rejects empty string")
    func rejectsEmpty() {
        #expect(TelemetryIdentifier(validating: "") == nil)
    }

    @Test("string literal initialization")
    func stringLiteralInit() {
        let id: TelemetryIdentifier = "heartRate"
        #expect(id.rawValue == "heartRate")
    }

    @Test("equatable conformance")
    func equatableConformance() {
        let a = TelemetryIdentifier(validating: "workout")
        let b: TelemetryIdentifier = "workout"
        #expect(a == b)
    }

    @Test("isCanonical validates correctly")
    func isCanonicalValidation() {
        #expect(TelemetryIdentifier.isCanonical("bench_press"))
        #expect(TelemetryIdentifier.isCanonical("glm-4.flash"))
        #expect(TelemetryIdentifier.isCanonical("ABC123"))
        #expect(!TelemetryIdentifier.isCanonical("has space"))
        #expect(!TelemetryIdentifier.isCanonical("has=equals"))
        #expect(!TelemetryIdentifier.isCanonical("tab\there"))
        #expect(!TelemetryIdentifier.isCanonical("日本語"))
    }
}

@Suite("ConsoleTelemetryProvider")
struct ConsoleTelemetryProviderTests {
    @Test("can be instantiated and tracks without crash")
    func instantiationAndTrack() {
        let provider = ConsoleTelemetryProvider()
        provider.track(.healthKitDenied)
        provider.track(.onboardingCompleted)
        provider.track(.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16))
    }

    @Test("conforms to TelemetryProvider")
    func conformsToProtocol() {
        let provider: any TelemetryProvider = ConsoleTelemetryProvider()
        provider.track(.healthKitAuthorized)
    }

    @Test("output uses [Telemetry] event_name key=value format")
    func outputFormat() {
        let event = TelemetryEvent.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16)
        let expected = "[Telemetry] workout_completed duration_s=1200 exercises=4 sets=16"
        #expect("[Telemetry] \(event.formattedString)" == expected)

        let simple = TelemetryEvent.onboardingCompleted
        #expect("[Telemetry] \(simple.formattedString)" == "[Telemetry] onboarding_completed")

        let tabEvent = TelemetryEvent.tabSwitched(tab: "workout")
        #expect("[Telemetry] \(tabEvent.formattedString)" == "[Telemetry] tab_switched tab=workout")
    }
}

@Suite("TelemetryEvent formatting")
struct TelemetryEventFormattingTests {
    @Test("event name uses snake_case")
    func eventNameSnakeCase() {
        #expect(TelemetryEvent.tabSwitched(tab: "workout").eventName == "tab_switched")
        #expect(TelemetryEvent.onboardingCompleted.eventName == "onboarding_completed")
        #expect(TelemetryEvent.workoutStarted(source: "blank").eventName == "workout_started")
        #expect(TelemetryEvent.workoutCompleted(durationSeconds: 0, exerciseCount: 0, setCount: 0).eventName == "workout_completed")
        #expect(TelemetryEvent.workoutDiscarded.eventName == "workout_discarded")
        #expect(TelemetryEvent.exerciseAdded(name: "squat").eventName == "exercise_added")
        #expect(TelemetryEvent.setCompleted(exerciseName: "squat").eventName == "set_completed")
        #expect(TelemetryEvent.setDeleted.eventName == "set_deleted")
        #expect(TelemetryEvent.healthKitAuthorized.eventName == "healthkit_authorized")
        #expect(TelemetryEvent.healthKitDenied.eventName == "healthkit_denied")
        #expect(TelemetryEvent.dataDetailOpened(sampleType: "heartRate").eventName == "data_detail_opened")
        #expect(TelemetryEvent.dataImported(format: "fit").eventName == "data_imported")
        #expect(TelemetryEvent.healthSummaryLoadFailed(sampleType: "stepCount").eventName == "health_summary_load_failed")
        #expect(TelemetryEvent.aiInsightGenerated(durationMs: 0, cardCount: 0).eventName == "ai_insight_generated")
        #expect(TelemetryEvent.aiInsightFailed(errorType: "timeout").eventName == "ai_insight_failed")
        #expect(TelemetryEvent.aiAnalysisRequested(sampleType: "stepCount").eventName == "ai_analysis_requested")
        #expect(TelemetryEvent.aiModelChanged(model: "glm-4-flash").eventName == "ai_model_changed")
        #expect(TelemetryEvent.aiChatMessageSent.eventName == "ai_chat_message_sent")
        #expect(TelemetryEvent.aiCacheFailure(operation: "read", errorType: "io_error").eventName == "ai_cache_failure")
        #expect(TelemetryEvent.restTimerStarted(durationSeconds: 60).eventName == "rest_timer_started")
        #expect(TelemetryEvent.restTimerSkipped.eventName == "rest_timer_skipped")
        #expect(TelemetryEvent.restTimerCompleted.eventName == "rest_timer_completed")
        #expect(TelemetryEvent.overviewCacheHit.eventName == "overview_cache_hit")
        #expect(TelemetryEvent.overviewCacheMiss.eventName == "overview_cache_miss")
        #expect(TelemetryEvent.overviewFallbackTriggered(reason: "network").eventName == "overview_fallback_triggered")
    }

    @Test("formatted string for parameterless events")
    func formattedStringNoParams() {
        #expect(TelemetryEvent.onboardingCompleted.formattedString == "onboarding_completed")
        #expect(TelemetryEvent.workoutDiscarded.formattedString == "workout_discarded")
        #expect(TelemetryEvent.setDeleted.formattedString == "set_deleted")
        #expect(TelemetryEvent.healthKitAuthorized.formattedString == "healthkit_authorized")
        #expect(TelemetryEvent.aiChatMessageSent.formattedString == "ai_chat_message_sent")
        #expect(TelemetryEvent.restTimerSkipped.formattedString == "rest_timer_skipped")
        #expect(TelemetryEvent.restTimerCompleted.formattedString == "rest_timer_completed")
        #expect(TelemetryEvent.overviewCacheHit.formattedString == "overview_cache_hit")
        #expect(TelemetryEvent.overviewCacheMiss.formattedString == "overview_cache_miss")
    }

    @Test("formatted string for events with parameters")
    func formattedStringWithParams() {
        #expect(
            TelemetryEvent.tabSwitched(tab: "workout").formattedString
                == "tab_switched tab=workout"
        )
        #expect(
            TelemetryEvent.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16).formattedString
                == "workout_completed duration_s=1200 exercises=4 sets=16"
        )
        #expect(
            TelemetryEvent.aiInsightGenerated(durationMs: 2300, cardCount: 6).formattedString
                == "ai_insight_generated duration_ms=2300 cards=6"
        )
        #expect(
            TelemetryEvent.restTimerStarted(durationSeconds: 90).formattedString
                == "rest_timer_started duration_s=90"
        )
        #expect(
            TelemetryEvent.overviewFallbackTriggered(reason: "network_error").formattedString
                == "overview_fallback_triggered reason=network_error"
        )
        #expect(
            TelemetryEvent.aiCacheFailure(operation: "read", errorType: "decode_error").formattedString
                == "ai_cache_failure operation=read error_type=decode_error"
        )
    }

    @Test("parameters for ai cache failure events")
    func aiCacheFailureParams() {
        let params = TelemetryEvent.aiCacheFailure(operation: "write", errorType: "io_error").parameters
        #expect(params.count == 2)
        #expect(params[0].key == "operation")
        #expect(params[0].value == "write")
        #expect(params[1].key == "error_type")
        #expect(params[1].value == "io_error")
    }

    @Test("parameters for single-param events")
    func singleParamEvents() {
        let params = TelemetryEvent.exerciseAdded(name: "bench_press").parameters
        #expect(params.count == 1)
        #expect(params[0].key == "name")
        #expect(params[0].value == "bench_press")
    }

    @Test("parameters for multi-param events")
    func multiParamEvents() {
        let params = TelemetryEvent.workoutCompleted(durationSeconds: 600, exerciseCount: 3, setCount: 12).parameters
        #expect(params.count == 3)
        #expect(params[0].key == "duration_s")
        #expect(params[0].value == "600")
        #expect(params[1].key == "exercises")
        #expect(params[1].value == "3")
        #expect(params[2].key == "sets")
        #expect(params[2].value == "12")
    }

    @Test("parameters empty for no-param events")
    func noParamEvents() {
        #expect(TelemetryEvent.onboardingCompleted.parameters.isEmpty)
        #expect(TelemetryEvent.healthKitDenied.parameters.isEmpty)
        #expect(TelemetryEvent.overviewCacheHit.parameters.isEmpty)
    }

    // MARK: - Production sanitize tests (via @testable import)

    @Test("sanitize escapes spaces")
    func sanitizeSpaces() {
        #expect(TelemetryEvent.sanitize("hello world") == "hello\\_world")
    }

    @Test("sanitize escapes newlines")
    func sanitizeNewlines() {
        #expect(TelemetryEvent.sanitize("line1\nline2") == "line1\\nline2")
    }

    @Test("sanitize escapes carriage returns")
    func sanitizeCarriageReturns() {
        #expect(TelemetryEvent.sanitize("error\rtype") == "error\\rtype")
    }

    @Test("sanitize escapes equals signs")
    func sanitizeEquals() {
        #expect(TelemetryEvent.sanitize("key=value") == "key\\=value")
    }

    @Test("sanitize escapes backslashes")
    func sanitizeBackslashes() {
        #expect(TelemetryEvent.sanitize("path\\to\\file") == "path\\\\to\\\\file")
    }

    @Test("sanitize escapes tab characters")
    func sanitizeTabs() {
        #expect(TelemetryEvent.sanitize("col1\tcol2") == "col1\\tcol2")
    }

    @Test("sanitize strips control characters")
    func sanitizeStripsControlChars() {
        #expect(TelemetryEvent.sanitize("hello\u{01}\u{02}world") == "helloworld")
    }

    @Test("sanitize strips non-ASCII")
    func sanitizeStripsNonASCII() {
        #expect(TelemetryEvent.sanitize("heart_rate_心率") == "heart_rate_")
    }

    @Test("sanitize strips DEL character")
    func sanitizeStripsDEL() {
        #expect(TelemetryEvent.sanitize("abc\u{7F}def") == "abcdef")
    }

    @Test("TelemetryIdentifier rejects localized exercise names via validating init")
    func identifierRejectsLocalizedNames() {
        #expect(TelemetryIdentifier(validating: "卧推bench_press") == nil)
        #expect(TelemetryIdentifier(validating: "bench_press") != nil)
    }

    @Test("TelemetryIdentifier rejects localized sample types via validating init")
    func identifierRejectsLocalizedSampleTypes() {
        #expect(TelemetryIdentifier(validating: "心率heartRate") == nil)
        #expect(TelemetryIdentifier(validating: "heartRate") != nil)
    }
}
