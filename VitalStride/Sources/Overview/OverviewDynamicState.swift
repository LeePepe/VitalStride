import AIService
import Foundation
import OSLog
import SwiftData
import TelemetryKit
import VitalModels

private let logger = Logger(subsystem: "com.vitalstride", category: "OverviewDynamic")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "OverviewDynamic")

@Observable
@MainActor
final class OverviewDynamicState {
    private(set) var layoutState: OverviewLayoutState = .loading
    private(set) var isRefreshing = false
    private(set) var pendingResponse: AIAnalysisResponse?
    var showRefreshError = false

    var pendingHeadline: String? {
        pendingResponse?.headline
    }

    private var isBackgroundRefreshing = false

    func loadInitial(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        let cacheResult = readCache(container: container)

        if let (insights, generatedAt) = cacheResult {
            logger.debug("overview_cache_hit")
            signposter.emitEvent("overview_cache_hit")
            TelemetryService.shared.trackNonisolated(.overviewCacheHit)
            layoutState = .dynamic(insights, lastUpdated: generatedAt)

            let isExpired = isCacheExpired(container: container)
            if isExpired {
                await refreshInBackground(container: container, snapshot: snapshot, workouts: workouts)
            }
            return
        }

        logger.debug("overview_cache_miss")
        signposter.emitEvent("overview_cache_miss")
        TelemetryService.shared.trackNonisolated(.overviewCacheMiss)
        await generateFromAI(container: container, snapshot: snapshot, workouts: workouts)
    }

    func refresh(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        signposter.emitEvent("overview_manual_refresh")
        logger.debug("overview_manual_refresh")

        let start = ContinuousClock.now

        do {
            let context = buildContext(snapshot: snapshot, workouts: workouts)
            let apiKey = try KeychainHelper().load(service: AISettingsSection.apiKeyKeychainService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let service = AIAnalysisService(modelContainer: container, provider: provider)
            let response = try await service.generateInsights(context: context, forceRefresh: true)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("overview_ai_generate_success duration_ms=\(ms)")
            signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")
            TelemetryService.shared.trackNonisolated(
                .aiInsightGenerated(durationMs: Int(ms), cardCount: response.insights.count)
            )

            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(response.insights, lastUpdated: generatedAt)
            pendingResponse = nil
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_ai_generate_failure error_type=\(errorType)")
            signposter.emitEvent("overview_ai_generate_failure", "\(errorType)")
            TelemetryService.shared.trackNonisolated(.aiInsightFailed(errorType: telemetryErrorType(error)))
            showRefreshError = true
        }

        isRefreshing = false
    }

    func acceptPendingInsights(container: ModelContainer) {
        guard let response = pendingResponse else { return }
        logger.debug("overview_pending_accepted")
        signposter.emitEvent("overview_pending_accepted")

        writeInsightsCache(response: response, container: container)
        let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
        layoutState = .dynamic(response.insights, lastUpdated: generatedAt)
        pendingResponse = nil
    }

    func clearPending() {
        pendingResponse = nil
    }

    func applyBackgroundRefreshResult(_ response: AIAnalysisResponse, container: ModelContainer) {
        if response.headline != nil {
            pendingResponse = response
        } else {
            writeInsightsCache(response: response, container: container)
            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(response.insights, lastUpdated: generatedAt)
            pendingResponse = nil
        }
    }

    // MARK: - Private

    private func generateFromAI(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        layoutState = .fallback

        let start = ContinuousClock.now
        do {
            let context = buildContext(snapshot: snapshot, workouts: workouts)
            let apiKey = try KeychainHelper().load(service: AISettingsSection.apiKeyKeychainService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let service = AIAnalysisService(modelContainer: container, provider: provider)
            let response = try await service.generateInsights(context: context)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000

            guard response.insights.count >= 3 else {
                logger.info("overview_ai_generate_success duration_ms=\(ms) insights_count=\(response.insights.count) kept_fallback=true")
                signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")
                TelemetryService.shared.trackNonisolated(
                    .aiInsightGenerated(durationMs: Int(ms), cardCount: response.insights.count)
                )
                TelemetryService.shared.trackNonisolated(
                    .overviewFallbackTriggered(reason: "insufficientInsights")
                )
                return
            }

            logger.info("overview_ai_generate_success duration_ms=\(ms) insights_count=\(response.insights.count)")
            signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")
            TelemetryService.shared.trackNonisolated(
                .aiInsightGenerated(durationMs: Int(ms), cardCount: response.insights.count)
            )

            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(response.insights, lastUpdated: generatedAt)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_ai_generate_failure error_type=\(errorType)")
            signposter.emitEvent("overview_ai_generate_failure", "\(errorType)")
            TelemetryService.shared.trackNonisolated(.aiInsightFailed(errorType: telemetryErrorType(error)))
            TelemetryService.shared.trackNonisolated(
                .overviewFallbackTriggered(reason: "aiGenerateFailure")
            )
        }
    }

    private func refreshInBackground(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        guard !isBackgroundRefreshing else { return }
        isBackgroundRefreshing = true
        defer { isBackgroundRefreshing = false }

        logger.debug("overview_bg_refresh_start")
        signposter.emitEvent("overview_bg_refresh_start")
        let start = ContinuousClock.now

        do {
            let context = buildContext(snapshot: snapshot, workouts: workouts)
            let apiKey = try KeychainHelper().load(service: AISettingsSection.apiKeyKeychainService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let service = AIAnalysisService(modelContainer: container, provider: provider)
            let response = try await service.generateInsights(context: context, forceRefresh: true, skipCache: true)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000

            guard !isRefreshing else {
                logger.debug("overview_bg_refresh_discarded reason=manual_refresh_in_progress")
                return
            }

            let hasHeadline = response.headline != nil
            logger.info("overview_bg_refresh_success headline_present=\(hasHeadline) duration_ms=\(ms)")
            signposter.emitEvent("overview_bg_refresh_success", "headline=\(hasHeadline) \(ms)ms")
            TelemetryService.shared.trackNonisolated(
                .aiInsightGenerated(durationMs: Int(ms), cardCount: response.insights.count)
            )

            applyBackgroundRefreshResult(response, container: container)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_bg_refresh_failure error_type=\(errorType)")
            signposter.emitEvent("overview_bg_refresh_failure", "\(errorType)")
            TelemetryService.shared.trackNonisolated(.aiInsightFailed(errorType: telemetryErrorType(error)))
        }
    }

    private func readCache(container: ModelContainer) -> (insights: [OverviewInsight], generatedAt: Date)? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        guard let cached = try? context.fetch(descriptor).first,
              let data = cached.contentJSON.data(using: .utf8)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(AIAnalysisResponse.self, from: data),
           response.insights.count >= 3
        {
            return (response.insights, cached.generatedAt)
        }
        if let insights = try? decoder.decode([OverviewInsight].self, from: data),
           insights.count >= 3
        {
            return (insights, cached.generatedAt)
        }
        return nil
    }

    private func isCacheExpired(container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        guard let cached = try? context.fetch(descriptor).first else { return true }
        return cached.isExpired
    }

    private func readCacheGeneratedAt(container: ModelContainer) -> Date? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        return try? context.fetch(descriptor).first?.generatedAt
    }

    private func writeInsightsCache(response: AIAnalysisResponse, container: ModelContainer) {
        guard let data = try? JSONEncoder().encode(response),
              let json = String(data: data, encoding: .utf8)
        else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        let now = Date()
        let expiry = now.addingTimeInterval(3600)

        if let existing = try? context.fetch(descriptor).first {
            existing.contentJSON = json
            existing.generatedAt = now
            existing.expiresAt = expiry
        } else {
            let entry = OverviewInsightCache(contentJSON: json, generatedAt: now, expiresAt: expiry)
            context.insert(entry)
        }
        try? context.save()
    }

    private nonisolated func buildContext(snapshot: HealthSnapshotData, workouts: [Workout]) -> OverviewContext {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentWorkouts = workouts.filter { $0.startDate >= sevenDaysAgo && $0.endDate != nil }

        var muscleGroupCounts: [String: Int] = [:]
        for workout in recentWorkouts {
            for exercise in (workout.exercises ?? []) {
                if let group = exercise.exercise?.muscleGroup.rawValue {
                    muscleGroupCounts[group, default: 0] += 1
                }
            }
        }

        let sleepHours: Double? = if let sleep = snapshot.lastNightSleep {
            sleep / 3600.0
        } else {
            nil
        }

        return OverviewContext(
            todaySteps: snapshot.todaySteps,
            restingHeartRate: snapshot.averageBPM,
            lastNightSleepHours: sleepHours,
            latestWeight: snapshot.latestWeight,
            recentWorkoutCount: recentWorkouts.count,
            recentMuscleGroups: muscleGroupCounts,
            userLocale: Locale.current.identifier
        )
    }

    private nonisolated func describeErrorType(_ error: Error) -> String {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let code): return "httpError(\(code))"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is KeychainError {
            return "noApiKey"
        }
        return "unknown"
    }

    private nonisolated func telemetryErrorType(_ error: Error) -> TelemetryIdentifier {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let code): return TelemetryIdentifier(validating: "httpError_\(code)") ?? "httpError"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is KeychainError {
            return "noApiKey"
        }
        return "unknown"
    }
}
