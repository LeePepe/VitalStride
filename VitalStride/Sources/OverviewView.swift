// Pre-existing hardcoded Chinese literals in this file (empty-state / headline
// copy) predate the `no_hardcoded_chinese` hook and are tracked under the shared
// i18n cleanup; re-skinning to DesignKit re-touched their lines but did not add
// new strings. Silenced at file scope until the i18n migration moves them to
// Localizable.xcstrings, matching DataView.swift's precedent (MY-1090).
// swiftlint:disable no_hardcoded_chinese
import AIService
import DesignKit
import HealthKitService
import OSLog
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

struct OverviewView: View {
    @State private var snapshotState = HealthSnapshotState()
    @State private var dynamicState = OverviewDynamicState()
    @State private var authCheckToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.healthDataCache) private var healthDataCache
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.routingSignalStore) private var signalStore

    @Query private var recentWorkouts: [Workout]

    init() {
        let thirtyDaysAgo = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        _recentWorkouts = Query(
            filter: #Predicate<Workout> { workout in
                workout.startDate >= thirtyDaysAgo && workout.endDate != nil
            },
            sort: \Workout.startDate,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isAnyLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else if !snapshotState.isAuthorized, !hasWorkoutData {
                        OverviewEmptyState()
                        MuscleGroupFrequencyCard(counts: dynamicState.recentMuscleGroupCounts)
                    } else {
                        dynamicContent
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.3),
                    value: dynamicState.pendingHeadline != nil
                )
                .padding()
            }
            .navigationTitle(String(localized: "overview_title", defaultValue: "概览"))
            .refreshable {
                await snapshotState.load(cache: healthDataCache, service: healthKitService, forceRefresh: true)
                await dynamicState.refresh(
                    container: modelContext.container,
                    snapshot: snapshotState.snapshot,
                    workouts: recentWorkouts
                )
            }
            .task(id: authCheckToken) {
                dynamicState.signalStore = signalStore
                await snapshotState.load(cache: healthDataCache, service: healthKitService)
            }
            .task(id: snapshotState.isLoading) {
                guard !snapshotState.isLoading else { return }
                guard snapshotState.isAuthorized || hasWorkoutData else { return }
                await dynamicState.loadInitial(
                    container: modelContext.container,
                    snapshot: snapshotState.snapshot,
                    workouts: recentWorkouts
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitAuthorizationChanged)) { _ in
                authCheckToken = UUID()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, !snapshotState.isLoading {
                    authCheckToken = UUID()
                }
            }
            .snackbar(isPresented: $dynamicState.showRefreshError, edge: .top) {
                if dynamicState.refreshErrorType == "noApiKey"
                    || dynamicState.refreshErrorType == "missingAPIKey"
                {
                    Label(
                        String(localized: "overview_missing_api_key", comment: "Snackbar shown when AI refresh fails due to missing API key"),
                        systemImage: "key"
                    )
                    .font(.subheadline)
                } else {
                    Label(
                        String(localized: "overview_refresh_failed", comment: "Snackbar shown when overview refresh fails"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.subheadline)
                }
            }
        }
    }

    private var hasWorkoutData: Bool { !recentWorkouts.isEmpty }

    /// Combined loading truth table: overview shows a single spinner while
    /// either the HealthKit snapshot or the dynamic insights phase is still
    /// loading. Normal content only reveals once both phases have finished.
    /// See MY-1276 (two spinners on same screen).
    var isAnyLoading: Bool {
        Self.isAnyLoading(
            snapshotIsLoading: snapshotState.isLoading,
            snapshotIsAuthorized: snapshotState.isAuthorized,
            hasWorkoutData: hasWorkoutData,
            dynamicLayoutState: dynamicState.layoutState
        )
    }

    /// Pure truth-table extraction for `isAnyLoading` so it can be exercised
    /// without spinning up a SwiftUI `@Query` context. See MY-1276.
    static func isAnyLoading(
        snapshotIsLoading: Bool,
        snapshotIsAuthorized: Bool,
        hasWorkoutData: Bool,
        dynamicLayoutState: OverviewLayoutState
    ) -> Bool {
        if snapshotIsLoading {
            return true
        }
        if case .loading = dynamicLayoutState {
            // Only gate on dynamic loading when we would have entered the
            // dynamic-content branch — i.e. the user is authorized OR has
            // local workout data. Otherwise the empty state renders and the
            // dynamic phase never starts.
            return snapshotIsAuthorized || hasWorkoutData
        }
        return false
    }

    @ViewBuilder
    private var dynamicContent: some View {
        switch dynamicState.layoutState {
        case .loading:
            // Loading is rendered by the top-level unified spinner; emit
            // nothing here to keep exactly one ProgressView on-screen.
            EmptyView()

        case .dynamic(let insights, let lastUpdated):
            if let headline = dynamicState.pendingHeadline {
                HeadlineBar(headline: headline) {
                    HeadlineBarTelemetry.recordTapped()
                    dynamicState.acceptPendingInsights(container: modelContext.container)
                }
                .transition(
                    reduceMotion
                        ? .identity
                        : .move(edge: .top).combined(with: .opacity)
                )
            }
            AdaptiveCardGrid(insights: insights)
            MuscleGroupFrequencyCard(counts: dynamicState.recentMuscleGroupCounts)
            if let lastUpdated {
                LastUpdatedLabel(date: lastUpdated)
            }

        case .fallback:
            OverviewFallbackContent(
                snapshotState: snapshotState,
                hasWorkoutData: hasWorkoutData,
                workouts: recentWorkouts
            )
            MuscleGroupFrequencyCard(counts: dynamicState.recentMuscleGroupCounts)
        }
    }
}

// MARK: - Last Updated Label

private struct LastUpdatedLabel: View {
    let date: Date

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        let relativeTime = Self.formatter.localizedString(for: date, relativeTo: Date())
        return Text(
            String(
                localized: "overview_last_updated",
                defaultValue: "上次更新于 \(relativeTime)"
            )
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Headline Bar Telemetry

private enum HeadlineBarTelemetry {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "OverviewCard")

    static func recordShown(headlineLength: Int) {
        logger.info("overview_headline_bar_shown headline_length=\(headlineLength)")
    }

    static func recordTapped() {
        logger.info("overview_headline_bar_tapped")
    }
}

// MARK: - Headline Bar

private struct HeadlineBar: View {
    @Environment(\.theme) private var theme
    let headline: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.primary.primary)

                Text(headline)
                    .font(.callout)
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.neutrals.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(theme.neutrals.inner)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.neutrals.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                "\(headline), \(String(localized: "headline_bar_a11y_hint", defaultValue: "Tap to view update"))"
            )
        )
        .accessibilityAddTraits(.isButton)
        .onAppear {
            HeadlineBarTelemetry.recordShown(headlineLength: headline.count)
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

    func load(cache: HealthDataCache, service: HealthKitService, forceRefresh: Bool = false) async {
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

        let data = await Self.fetchAllHealthData(cache: cache, forceRefresh: forceRefresh)
        snapshot = data
        isLoading = false
    }

    private nonisolated static func fetchAllHealthData(cache: HealthDataCache, forceRefresh: Bool) async -> HealthSnapshotData {
        async let steps = fetchSteps(cache: cache, forceRefresh: forceRefresh)
        async let heart = fetchHeartRate(cache: cache, forceRefresh: forceRefresh)
        async let sleep = fetchSleep(cache: cache, forceRefresh: forceRefresh)
        async let weight = fetchWeight(cache: cache, forceRefresh: forceRefresh)
        return await HealthSnapshotData(
            todaySteps: steps,
            averageBPM: heart,
            lastNightSleep: sleep,
            latestWeight: weight
        )
    }

    private nonisolated static func fetchSteps(cache: HealthDataCache, forceRefresh: Bool) async -> Int? {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = forceRefresh
                ? try await cache.refresh(.stepCount, in: interval)
                : try await cache.data(for: .stepCount, in: interval)
            guard !dataPoints.isEmpty else { return nil }
            let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            return aggregated.last?.totalSteps
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchHeartRate(cache: HealthDataCache, forceRefresh: Bool) async -> Int? {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = forceRefresh
                ? try await cache.refresh(.heartRate, in: interval)
                : try await cache.data(for: .heartRate, in: interval)
            let filtered = HeartRateStats.filtered(dataPoints, in: interval)
            if let avg = HeartRateStats.average(of: filtered) {
                return Int(avg.rounded())
            }
            return nil
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchSleep(cache: HealthDataCache, forceRefresh: Bool) async -> TimeInterval? {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = forceRefresh
                ? try await cache.refresh(.sleepAnalysis, in: interval)
                : try await cache.data(for: .sleepAnalysis, in: interval)
            let nights = SleepAggregator.aggregateByNight(dataPoints: dataPoints, in: interval)
            return nights.last?.totalSleep
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchWeight(cache: HealthDataCache, forceRefresh: Bool) async -> Double? {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = forceRefresh
                ? try await cache.refresh(.bodyMass, in: interval)
                : try await cache.data(for: .bodyMass, in: interval)
            let points = WeightAnalyzer.extractWeightPoints(from: dataPoints, in: interval)
            return points.last?.weight
        } catch {
            return nil
        }
    }
}

// MARK: - Fallback Content (original fixed layout)

private struct OverviewFallbackContent: View {
    let snapshotState: HealthSnapshotState
    let hasWorkoutData: Bool
    let workouts: [Workout]

    var body: some View {
        if snapshotState.isAuthorized, snapshotState.hasAnyHealthData {
            OverviewHealthSnapshot(snapshot: snapshotState.snapshot)
            OverviewInsightsSection(snapshot: snapshotState.snapshot)
        }

        if hasWorkoutData {
            ActivitySummaryCard(
                summary: WorkoutAggregator.computeTodaySummary(from: workouts)
            )
            RecentWorkoutsSection(workouts: Array(workouts.prefix(5)))
            WorkoutTrendChart(workouts: workouts)
        }
    }
}

// MARK: - Health Snapshot Section

private struct OverviewHealthSnapshot: View {
    let snapshot: HealthSnapshotData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "健康数据", comment: ""), icon: "heart.fill")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StepsSummaryCard(preloaded: snapshot.todaySteps)
                HeartRateSummaryCard(preloaded: snapshot.averageBPM)
                SleepSummaryCard(preloaded: snapshot.lastNightSleep)
                WeightSummaryCard(preloaded: snapshot.latestWeight)
            }
        }
    }
}

// MARK: - Workout Sections

// MARK: - Empty State

struct OverviewEmptyState: View {
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @Environment(\.theme) private var theme

    var body: some View {
        Card {
            VStack(spacing: 16) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.primary.primary)

                Text(String(localized: "开始你的健康旅程", comment: ""))
                    .font(.title3.bold())
                    .foregroundStyle(theme.neutrals.text1)

                Text(String(localized: "授权 HealthKit 查看健康数据快照，或开始你的第一次训练。", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button {
                        navigation?.selectedTab = .settings
                    } label: {
                        Label(String(localized: "前往「设置」授权 HealthKit", comment: ""), systemImage: "gearshape")
                            .font(.subheadline)
                    }
                    .accessibilityHint(String(localized: "切换到设置页面以授权 HealthKit", comment: "A11y hint"))

                    Button {
                        navigation?.selectedTab = .workout
                    } label: {
                        Label(String(localized: "前往「训练」开始第一次训练", comment: ""), systemImage: "figure.strengthtraining.traditional")
                            .font(.subheadline)
                    }
                    .accessibilityHint(String(localized: "切换到训练页面以开始训练", comment: "A11y hint"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

#Preview {
    OverviewView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
        .designThemePreview()
}
