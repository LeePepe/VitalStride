import HealthKitService
import SwiftData
import SwiftUI
import VitalModels

struct OverviewView: View {
    @State private var snapshotState = HealthSnapshotState()
    @State private var authCheckToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.healthDataCache) private var healthDataCache
    @Environment(\.healthKitService) private var healthKitService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if snapshotState.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        OverviewContent(snapshotState: snapshotState)
                    }
                }
                .padding()
            }
            .navigationTitle("概览")
            .task(id: authCheckToken) {
                await snapshotState.load(cache: healthDataCache, service: healthKitService)
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitAuthorizationChanged)) { _ in
                authCheckToken = UUID()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, !snapshotState.isLoading {
                    authCheckToken = UUID()
                }
            }
        }
    }
}

// MARK: - Health Snapshot State

struct HealthSnapshotData: Sendable {
    let todaySteps: Int?
    let averageBPM: Int?
    let lastNightSleep: TimeInterval?
    let latestWeight: Double?

    var hasAnyData: Bool {
        todaySteps != nil || averageBPM != nil || lastNightSleep != nil || latestWeight != nil
    }
}

@Observable
@MainActor
final class HealthSnapshotState {
    var isLoading = true
    var isAuthorized = false
    var snapshot = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)

    var hasAnyHealthData: Bool { snapshot.hasAnyData }

    func load(cache: HealthDataCache, service: HealthKitService) async {
        isLoading = true
        do {
            let status = try await service.authorizationStatus()
            isAuthorized = (status == .unnecessary)
        } catch {
            isAuthorized = false
        }

        guard isAuthorized else {
            snapshot = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
            isLoading = false
            return
        }

        let data = await Self.fetchAllHealthData(cache: cache)
        snapshot = data
        isLoading = false
    }

    private nonisolated static func fetchAllHealthData(cache: HealthDataCache) async -> HealthSnapshotData {
        async let steps = fetchSteps(cache: cache)
        async let heart = fetchHeartRate(cache: cache)
        async let sleep = fetchSleep(cache: cache)
        async let weight = fetchWeight(cache: cache)
        return await HealthSnapshotData(
            todaySteps: steps,
            averageBPM: heart,
            lastNightSleep: sleep,
            latestWeight: weight
        )
    }

    private nonisolated static func fetchSteps(cache: HealthDataCache) async -> Int? {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .stepCount, in: interval)
            guard !dataPoints.isEmpty else { return nil }
            let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            return aggregated.last?.totalSteps
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchHeartRate(cache: HealthDataCache) async -> Int? {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .heartRate, in: interval)
            let filtered = HeartRateStats.filtered(dataPoints, in: interval)
            if let avg = HeartRateStats.average(of: filtered) {
                return Int(avg.rounded())
            }
            return nil
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchSleep(cache: HealthDataCache) async -> TimeInterval? {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .sleepAnalysis, in: interval)
            let nights = SleepAggregator.aggregateByNight(dataPoints: dataPoints, in: interval)
            return nights.last?.totalSleep
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchWeight(cache: HealthDataCache) async -> Double? {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .bodyMass, in: interval)
            let points = WeightAnalyzer.extractWeightPoints(from: dataPoints, in: interval)
            return points.last?.weight
        } catch {
            return nil
        }
    }
}

// MARK: - Overview Content

private struct OverviewContent: View {
    let snapshotState: HealthSnapshotState

    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var allWorkouts: [Workout]

    private var hasWorkoutData: Bool { !allWorkouts.isEmpty }

    var body: some View {
        if snapshotState.hasAnyHealthData || hasWorkoutData {
            dataContent
        } else {
            OverviewEmptyState()
        }
    }

    @ViewBuilder
    private var dataContent: some View {
        if snapshotState.isAuthorized, snapshotState.hasAnyHealthData {
            OverviewHealthSnapshot(snapshot: snapshotState.snapshot)
        }

        if hasWorkoutData {
            OverviewTodaySummary()
            OverviewRecentWorkouts()
            OverviewTrendSection()
        }
    }
}

// MARK: - Health Snapshot Section

private struct OverviewHealthSnapshot: View {
    let snapshot: HealthSnapshotData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("健康数据")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StepsSummaryCard(preloaded: snapshot.todaySteps)
                HeartRateSummaryCard(preloaded: snapshot.averageBPM)
                SleepSummaryCard(preloaded: snapshot.lastNightSleep)
                WeightSummaryCard(preloaded: snapshot.latestWeight)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Workout Sections

private struct OverviewTodaySummary: View {
    @Query private var todayWorkouts: [Workout]

    init() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        _todayWorkouts = Query(
            filter: #Predicate<Workout> { workout in
                workout.startDate >= startOfDay && workout.endDate != nil
            },
            sort: \Workout.startDate
        )
    }

    var body: some View {
        ActivitySummaryCard(
            summary: WorkoutAggregator.computeTodaySummary(from: todayWorkouts)
        )
    }
}

private struct OverviewRecentWorkouts: View {
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var recentWorkouts: [Workout]

    var body: some View {
        RecentWorkoutsSection(workouts: Array(recentWorkouts.prefix(5)))
    }
}

private struct OverviewTrendSection: View {
    @Query private var trendWorkouts: [Workout]

    init() {
        let calendar = Calendar.current
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        _trendWorkouts = Query(
            filter: #Predicate<Workout> { workout in
                workout.startDate >= rangeStart && workout.endDate != nil
            },
            sort: \Workout.startDate
        )
    }

    var body: some View {
        WorkoutTrendChart(workouts: trendWorkouts)
    }
}

// MARK: - Empty State

struct OverviewEmptyState: View {
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("开始你的健康旅程")
                .font(.title3.bold())

            Text("授权 HealthKit 查看健康数据快照，或开始你的第一次训练。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    navigation?.selectedTab = .settings
                } label: {
                    Label("前往「设置」授权 HealthKit", systemImage: "gearshape")
                        .font(.subheadline)
                }
                .accessibilityHint("切换到设置页面以授权 HealthKit")

                Button {
                    navigation?.selectedTab = .workout
                } label: {
                    Label("前往「训练」开始第一次训练", systemImage: "figure.strengthtraining.traditional")
                        .font(.subheadline)
                }
                .accessibilityHint("切换到训练页面以开始训练")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    OverviewView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
