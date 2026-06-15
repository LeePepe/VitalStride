import Testing
@testable import TelemetryKit

@Suite("ConsoleTelemetryProvider")
struct ConsoleTelemetryProviderTests {
    @Test("can be instantiated and used")
    func instantiation() {
        let provider = ConsoleTelemetryProvider()
        provider.track(.healthKitDenied)
    }

    @Test("tracks event without crash")
    func trackDoesNotCrash() {
        let provider = ConsoleTelemetryProvider()
        provider.track(.onboardingCompleted)
        provider.track(.tabSwitched(tab: "workout"))
        provider.track(.workoutCompleted(durationSeconds: 1200, exerciseCount: 4, setCount: 16))
    }

    @Test("conforms to TelemetryProvider")
    func conformsToProtocol() {
        let provider: any TelemetryProvider = ConsoleTelemetryProvider()
        provider.track(.healthKitAuthorized)
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
        #expect(TelemetryEvent.aiInsightGenerated(durationMs: 0, cardCount: 0).eventName == "ai_insight_generated")
        #expect(TelemetryEvent.aiInsightFailed(errorType: "timeout").eventName == "ai_insight_failed")
        #expect(TelemetryEvent.aiAnalysisRequested(sampleType: "stepCount").eventName == "ai_analysis_requested")
        #expect(TelemetryEvent.aiModelChanged(model: "glm-4-flash").eventName == "ai_model_changed")
        #expect(TelemetryEvent.aiChatMessageSent.eventName == "ai_chat_message_sent")
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
}
