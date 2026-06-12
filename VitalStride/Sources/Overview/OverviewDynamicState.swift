import AIService
import Foundation
import OSLog
import SwiftData
import VitalModels

private let logger = Logger(subsystem: "com.vitalstride", category: "OverviewDynamic")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "OverviewDynamic")

@Observable
@MainActor
final class OverviewDynamicState {
    private(set) var layoutState: OverviewLayoutState = .loading
    private(set) var isRefreshing = false
    var showRefreshError = false

    func loadInitial(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        let cacheResult = readCache(container: container)

        if let (insights, generatedAt) = cacheResult {
            logger.debug("overview_cache_hit")
            signposter.emitEvent("overview_cache_hit")
            layoutState = .dynamic(insights, lastUpdated: generatedAt)

            let isExpired = isCacheExpired(container: container)
            if isExpired {
                await refreshInBackground(container: container, snapshot: snapshot, workouts: workouts)
            }
            return
        }

        logger.debug("overview_cache_miss")
        signposter.emitEvent("overview_cache_miss")
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
            let insights = try await service.generateInsights(context: context, forceRefresh: true)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("overview_ai_generate_success duration_ms=\(ms)")
            signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")

            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(insights, lastUpdated: generatedAt)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_ai_generate_failure error_type=\(errorType)")
            signposter.emitEvent("overview_ai_generate_failure", "\(errorType)")
            showRefreshError = true
        }

        isRefreshing = false
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
            let insights = try await service.generateInsights(context: context)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000

            guard insights.count >= 3 else {
                logger.info("overview_ai_generate_success duration_ms=\(ms) insights_count=\(insights.count) kept_fallback=true")
                signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")
                return
            }

            logger.info("overview_ai_generate_success duration_ms=\(ms) insights_count=\(insights.count)")
            signposter.emitEvent("overview_ai_generate_success", "\(ms)ms")

            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(insights, lastUpdated: generatedAt)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_ai_generate_failure error_type=\(errorType)")
            signposter.emitEvent("overview_ai_generate_failure", "\(errorType)")
        }
    }

    private func refreshInBackground(container: ModelContainer, snapshot: HealthSnapshotData, workouts: [Workout]) async {
        let start = ContinuousClock.now

        do {
            let context = buildContext(snapshot: snapshot, workouts: workouts)
            let apiKey = try KeychainHelper().load(service: AISettingsSection.apiKeyKeychainService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let service = AIAnalysisService(modelContainer: container, provider: provider)
            let insights = try await service.generateInsights(context: context, forceRefresh: true)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("overview_ai_generate_success duration_ms=\(ms) source=background_refresh")

            let generatedAt = readCacheGeneratedAt(container: container) ?? Date()
            layoutState = .dynamic(insights, lastUpdated: generatedAt)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("overview_ai_generate_failure error_type=\(errorType) source=background_refresh")
        }
    }

    private func readCache(container: ModelContainer) -> (insights: [OverviewInsight], generatedAt: Date)? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        guard let cached = try? context.fetch(descriptor).first,
              let data = cached.contentJSON.data(using: .utf8),
              let insights = try? JSONDecoder().decode([OverviewInsight].self, from: data),
              insights.count >= 3
        else {
            return nil
        }
        return (insights, cached.generatedAt)
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
}
