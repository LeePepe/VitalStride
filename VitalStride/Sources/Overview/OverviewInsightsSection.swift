import AIService
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels

@Observable
@MainActor
final class OverviewInsightsState {
    var insights: [OverviewInsight] = []
    var isLoading = false
    private var hasLoaded = false

    private var loadTask: Task<Void, Never>?
    private let keychainHelper = KeychainHelper()
    private let apiKeyService = AISettingsSection.apiKeyKeychainService

    func loadIfNeeded(snapshot: HealthSnapshotData, workoutCount: Int, modelContext: ModelContext) {
        guard !hasLoaded, !isLoading else { return }
        loadTask?.cancel()
        loadTask = Task {
            await performLoad(snapshot: snapshot, workoutCount: workoutCount, modelContext: modelContext)
        }
    }

    private func performLoad(
        snapshot: HealthSnapshotData,
        workoutCount: Int,
        modelContext: ModelContext
    ) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let container = modelContext.container

            let context = OverviewContext(
                todaySteps: snapshot.todaySteps,
                restingHeartRate: snapshot.averageBPM,
                lastNightSleepHours: snapshot.lastNightSleep.map { $0 / 3600.0 },
                latestWeight: snapshot.latestWeight,
                recentWorkoutCount: workoutCount
            )

            let service = AIAnalysisService(
                modelContainer: container,
                provider: provider
            )

            let start = ContinuousClock.now
            let result = try await service.generateInsights(context: context)
            guard !Task.isCancelled else { return }
            let elapsed = ContinuousClock.now - start
            let ms = Int(elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000)
            TelemetryService.shared.trackNonisolated(
                .aiInsightGenerated(durationMs: ms, cardCount: result.insights.count)
            )
            insights = result.insights
        } catch {
            TelemetryService.shared.trackNonisolated(
                .aiInsightFailed(errorType: Self.telemetryErrorType(error))
            )
            insights = []
        }
    }

    private nonisolated static func telemetryErrorType(_ error: Error) -> TelemetryIdentifier {
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

struct OverviewInsightsSection: View {
    let snapshot: HealthSnapshotData

    @State private var state = OverviewInsightsState()

    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var recentWorkouts: [Workout]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if state.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(String(localized: "ai_analyzing", defaultValue: "AI Analyzing..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            AdaptiveCardGrid(insights: state.insights)
        }
        .task {
            state.loadIfNeeded(
                snapshot: snapshot,
                workoutCount: recentWorkouts.count,
                modelContext: modelContext
            )
        }
    }
}
