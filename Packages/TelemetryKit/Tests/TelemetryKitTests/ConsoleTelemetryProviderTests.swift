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
        #expect(TelemetryEvent.suggestionAccepted(advice: "increase_weight").eventName == "suggestion_accepted")
        #expect(TelemetryEvent.suggestionOverridden(advice: "maintain").eventName == "suggestion_overridden")
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
        #expect(
            TelemetryEvent.suggestionAccepted(advice: "increase_weight").formattedString
                == "suggestion_accepted advice=increase_weight"
        )
        #expect(
            TelemetryEvent.suggestionOverridden(advice: "maintain").formattedString
                == "suggestion_overridden advice=maintain"
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

    // MARK: - Smart Progression suggestion events (spec 006 FR-006)
    //
    // suggestionAccepted / suggestionOverridden must expose only the `advice`
    // metadata category — never actual weight, reps, HealthKit values, or
    // free-form reason text (Constitution I / Quality Bar B).

    @Test("suggestionAccepted parameters expose only advice key")
    func suggestionAcceptedParametersOnlyAdvice() {
        let params = TelemetryEvent.suggestionAccepted(advice: "increase_weight").parameters
        #expect(params.count == 1)
        #expect(params[0].key == "advice")
        #expect(params[0].value == "increase_weight")
    }

    @Test("suggestionOverridden parameters expose only advice key")
    func suggestionOverriddenParametersOnlyAdvice() {
        let params = TelemetryEvent.suggestionOverridden(advice: "maintain").parameters
        #expect(params.count == 1)
        #expect(params[0].key == "advice")
        #expect(params[0].value == "maintain")
    }

    @Test("suggestionAccepted supports canonical advice categories")
    func suggestionAcceptedCanonicalCategories() {
        let categories: [TelemetryIdentifier] = [
            "increase_weight",
            "maintain",
            "decrease_weight",
            "increase_reps",
        ]
        for advice in categories {
            let params = TelemetryEvent.suggestionAccepted(advice: advice).parameters
            #expect(params.count == 1)
            #expect(params[0].key == "advice")
            #expect(params[0].value == advice.rawValue)
            #expect(
                TelemetryEvent.suggestionAccepted(advice: advice).formattedString
                    == "suggestion_accepted advice=\(advice.rawValue)"
            )
        }
    }

    @Test("suggestionOverridden supports canonical advice categories")
    func suggestionOverriddenCanonicalCategories() {
        let categories: [TelemetryIdentifier] = [
            "increase_weight",
            "maintain",
            "decrease_weight",
            "increase_reps",
        ]
        for advice in categories {
            let params = TelemetryEvent.suggestionOverridden(advice: advice).parameters
            #expect(params.count == 1)
            #expect(params[0].key == "advice")
            #expect(params[0].value == advice.rawValue)
            #expect(
                TelemetryEvent.suggestionOverridden(advice: advice).formattedString
                    == "suggestion_overridden advice=\(advice.rawValue)"
            )
        }
    }

    @Test("suggestion events reject free-form reason text via validating init")
    func suggestionRejectsFreeFormReason() {
        #expect(TelemetryIdentifier(validating: "Add 2.5 kg next set") == nil)
        #expect(TelemetryIdentifier(validating: "增加重量") == nil)
    }

    // MARK: - Exercise picker diagnostics (MY-1338 / MY-1339)
    //
    // `exercisePickerSectionJump` carries only canonical TelemetryIdentifier
    // values for from/to/source; `exercisePickerIndexScrubbed` carries only a
    // count. Neither may carry raw display names, localized strings, or
    // health values (Constitution I).

    @Test("exercisePickerSectionJump event name uses snake_case")
    func exercisePickerSectionJumpEventName() {
        let event = TelemetryEvent.exercisePickerSectionJump(
            from: "barbell", to: "dumbbell", source: "drag"
        )
        #expect(event.eventName == "exercise_picker_section_jump")
    }

    @Test("exercisePickerIndexScrubbed event name uses snake_case")
    func exercisePickerIndexScrubbedEventName() {
        #expect(TelemetryEvent.exercisePickerIndexScrubbed(count: 3).eventName
                == "exercise_picker_index_scrubbed")
    }

    @Test("exercisePickerSectionJump parameters carry from/to/source only")
    func exercisePickerSectionJumpParameters() {
        let params = TelemetryEvent.exercisePickerSectionJump(
            from: "barbell", to: "kettlebell", source: "scroll"
        ).parameters
        #expect(params.count == 3)
        #expect(params[0].key == "from")
        #expect(params[0].value == "barbell")
        #expect(params[1].key == "to")
        #expect(params[1].value == "kettlebell")
        #expect(params[2].key == "source")
        #expect(params[2].value == "scroll")
    }

    @Test("exercisePickerIndexScrubbed parameters carry count only")
    func exercisePickerIndexScrubbedParameters() {
        let params = TelemetryEvent.exercisePickerIndexScrubbed(count: 7).parameters
        #expect(params.count == 1)
        #expect(params[0].key == "count")
        #expect(params[0].value == "7")
    }

    @Test("exercisePickerSectionJump formatted string")
    func exercisePickerSectionJumpFormatted() {
        #expect(
            TelemetryEvent.exercisePickerSectionJump(
                from: "barbell", to: "dumbbell", source: "drag"
            ).formattedString
                == "exercise_picker_section_jump from=barbell to=dumbbell source=drag"
        )
    }

    @Test("exercisePickerIndexScrubbed formatted string")
    func exercisePickerIndexScrubbedFormatted() {
        #expect(
            TelemetryEvent.exercisePickerIndexScrubbed(count: 5).formattedString
                == "exercise_picker_index_scrubbed count=5"
        )
    }

    @Test("exercisePickerSectionJump supports both drag and scroll source identifiers")
    func exercisePickerSectionJumpSources() {
        let sources: [TelemetryIdentifier] = ["drag", "scroll"]
        for source in sources {
            let event = TelemetryEvent.exercisePickerSectionJump(
                from: "barbell", to: "dumbbell", source: source
            )
            let params = event.parameters
            #expect(params.last?.key == "source")
            #expect(params.last?.value == source.rawValue)
        }
    }

    @Test("exercisePickerSectionJump / exercisePickerIndexScrubbed Equatable + Sendable")
    func exercisePickerEventsEquatable() {
        let a: TelemetryEvent = .exercisePickerSectionJump(
            from: "barbell", to: "dumbbell", source: "drag"
        )
        let b: TelemetryEvent = .exercisePickerSectionJump(
            from: "barbell", to: "dumbbell", source: "drag"
        )
        let c: TelemetryEvent = .exercisePickerSectionJump(
            from: "barbell", to: "kettlebell", source: "drag"
        )
        #expect(a == b)
        #expect(a != c)
        #expect(TelemetryEvent.exercisePickerIndexScrubbed(count: 3)
                == .exercisePickerIndexScrubbed(count: 3))
        #expect(TelemetryEvent.exercisePickerIndexScrubbed(count: 3)
                != .exercisePickerIndexScrubbed(count: 4))
    }

    @Test("exercise picker events reject localized display names via validating init")
    func exercisePickerRejectsLocalizedNames() {
        #expect(TelemetryIdentifier(validating: "杠铃") == nil)
        #expect(TelemetryIdentifier(validating: "拖动") == nil)
        #expect(TelemetryIdentifier(validating: "barbell") != nil)
        #expect(TelemetryIdentifier(validating: "drag") != nil)
    }
}
