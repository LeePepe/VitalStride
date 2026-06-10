import AIService
import SwiftData
import SwiftUI
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

            let result = try await service.generateInsights(context: context)
            guard !Task.isCancelled else { return }
            insights = result.filter(\.isValidVariant)
        } catch {
            insights = []
        }
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

            ForEach(state.insights, id: \.key) { insight in
                CardVariantFactory.makeCard(for: insight)
            }
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
