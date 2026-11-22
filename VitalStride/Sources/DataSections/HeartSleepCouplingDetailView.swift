// swiftlint:disable no_hardcoded_chinese
import AIService
import DesignKit
import HealthKitService
import Observation
import SwiftData
import SwiftUI
import VitalModels

@MainActor
@Observable
final class HeartSleepCouplingState {
    enum LoadState: Equatable { case populated, empty, loading, error }

    private(set) var loadState: LoadState
    private(set) var snapshot: VitalModels.PhysiologicalSnapshot?
    private(set) var report: AIService.HolisticFourLayerReport?
    private(set) var provider: PluggableAIProvider
    private(set) var heart: VitalModels.HeartDomainSnapshot
    private(set) var sleep: VitalModels.SleepDomainSnapshot
    private(set) var isRefreshing: Bool = false
    var onRetry: (() -> Void)?
    private(set) var hasLoaded: Bool

    init(
        preloadedSnapshot: VitalModels.PhysiologicalSnapshot? = nil,
        report: AIService.HolisticFourLayerReport? = nil,
        provider: PluggableAIProvider = .deterministicFallback,
        loadState: LoadState = .loading
    ) {
        self.snapshot = preloadedSnapshot
        self.report = report
        self.provider = provider
        self.loadState = loadState
        self.heart = preloadedSnapshot?.heart ?? Self.emptyHeart
        self.sleep = preloadedSnapshot?.sleep ?? Self.emptySleep
        self.hasLoaded = preloadedSnapshot != nil || report != nil || loadState != .loading
    }

    func load(cache: HealthDataCache, workouts: [Workout] = [], generatedAt: Date = Date()) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        loadState = .loading
        hasLoaded = false
        let interval = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -59, to: generatedAt) ?? generatedAt,
            end: generatedAt
        )
        let requested: Set<HealthSampleType> = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate, .sleepAnalysis,
            .stepCount, .activeEnergyBurned, .vo2Max
        ]
        var points: [HealthDataPoint] = []
        for type in requested {
            guard !Task.isCancelled else { return }
            if let values = try? await cache.data(for: type, in: interval) { points.append(contentsOf: values) }
        }
        let healthWorkouts = (try? await cache.workoutData(in: interval)) ?? []
        let strengthWorkouts = workouts.compactMap(\.strengthSummaryInput)
        guard let (vitalSnapshot, aiSnapshot) = await Self.synthesizeSnapshotsOffMainActor(
            points: points,
            workouts: healthWorkouts,
            strengthWorkouts: strengthWorkouts,
            generatedAt: generatedAt
        ) else {
            self.snapshot = nil
            self.report = nil
            self.heart = Self.emptyHeart
            self.sleep = Self.emptySleep
            self.loadState = .empty
            self.hasLoaded = true
            return
        }

        snapshot = vitalSnapshot
        heart = vitalSnapshot.heart
        sleep = vitalSnapshot.sleep
        let configuration = HolisticDashboardState.resolveConfiguration()
        provider = configuration.provider
        if configuration.provider == .deterministicFallback || !isConfigured(configuration) {
            report = await FourLayerAdviceEngine().generate(snapshot: aiSnapshot, model: configuration.modelID)
            provider = .deterministicFallback
            loadState = .populated
            hasLoaded = true
            return
        }

        do {
            report = try await FourLayerAdviceEngine(provider: configuration.makeProvider()).generateCancellable(snapshot: aiSnapshot, model: configuration.modelID)
            loadState = .populated
            hasLoaded = true
        } catch {
            report = await FourLayerAdviceEngine().generate(snapshot: aiSnapshot, model: configuration.modelID)
            provider = .deterministicFallback
            loadState = .error
            hasLoaded = true
            onRetry = { [weak self, cache] in
                guard let self, !self.isRefreshing else { return }
                Task { @MainActor in await self.load(cache: cache, workouts: workouts) }
            }
        }
    }

    nonisolated private static func synthesizeSnapshotsOffMainActor(
        points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord],
        strengthWorkouts: [VitalModels.StrengthWorkoutSummaryInput],
        generatedAt: Date
    ) async -> (VitalModels.PhysiologicalSnapshot, AIService.PhysiologicalSnapshot)? {
        let hasHeartOrSleep = points.contains { point in
            point.sampleType == .restingHeartRate
                || point.sampleType == .heartRateVariabilitySDNN
                || point.sampleType == .heartRate
                || point.sampleType == .sleepAnalysis
        }
        guard hasHeartOrSleep,
              let vitalSnapshot = HealthMetricsCalculator().physiologicalSnapshot(
                from: points,
                workouts: workouts,
                strengthWorkouts: strengthWorkouts,
                generatedAt: generatedAt
              ),
              let data = try? JSONEncoder().encode(vitalSnapshot),
              let aiSnapshot = try? JSONDecoder().decode(AIService.PhysiologicalSnapshot.self, from: data) else {
            return nil
        }
        return (vitalSnapshot, aiSnapshot)
    }

    func markEmpty() { report = nil; loadState = .empty; hasLoaded = true }
    func markLoading() { report = nil; loadState = .loading; hasLoaded = true }
    func markError(onRetry: (() -> Void)? = nil) { report = nil; loadState = .error; hasLoaded = true; self.onRetry = onRetry }

    static func preview() -> HeartSleepCouplingState {
        let state = HeartSleepCouplingState(provider: .deterministicFallback, loadState: .populated)
        state.heart = previewHeart
        state.sleep = previewSleep
        state.report = previewReport
        state.hasLoaded = true
        return state
    }

    static var previewHeart: VitalModels.HeartDomainSnapshot {
        .init(
            restingHeartRate: .init(averageBPM: 53, minimumBPM: 50, maximumBPM: 58, sampleCount: 60, currentBPM: 52, sevenDayAverageBPM: 53, baselineBPM: 55, baselineDayCount: 52),
            hrvCorridor: .init(baselineMilliseconds: 63, lowerBoundMilliseconds: 54, upperBoundMilliseconds: 72, sampleCount: 60, currentMilliseconds: 68, sevenDayAverageMilliseconds: 65, sevenDaySampleCount: 7, baselineDayCount: 52),
            zoneDistribution: .init(zone1: 12 * 60, zone2: 28 * 60, zone3: 42 * 60, zone4: 18 * 60, zone5: 6 * 60, resolvedMaximumHeartRateBPM: 190),
            recovery: .init(baselineBPM: 164, oneMinuteBPM: 132, twoMinuteBPM: 115)
        )
    }

    static var previewSleep: VitalModels.SleepDomainSnapshot {
        let architecture = VitalModels.SleepArchitectureSnapshot(deepDuration: 1.8 * 3600, remDuration: 1.9 * 3600, coreDuration: 3.7 * 3600, awakeDuration: 20 * 60, totalSleepDuration: 7.4 * 3600, sleepEfficiency: 0.92, inBedDuration: 8 * 3600)
        let debt = VitalModels.SleepDebtSummary(sevenDayDebt: 1.4 * 3600, fourteenDayDebt: 2.6 * 3600, baselineSleepDuration: 7.8 * 3600, targetSleepDuration: 8 * 3600, observedNightCount7d: 7, observedNightCount14d: 14)
        return .init(architecture: architecture, debt: debt, recentNights: Array(repeating: architecture, count: 7))
    }

    static var previewReport: AIService.HolisticFourLayerReport {
        .init(l1: [], l2: [.init(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling", message: "Deep and REM restoration support a controlled strength session. Keep high-CNS work below today's ceiling and finish with easy aerobic recovery.")], l3: .init(readinessScore: 84, autonomicScore: 86, sleepRestorationScore: 81, mesocyclePhase: .intensification, recommendedIntensityCap: 0.85), l4: .init(northStarScore: 86, directive: "Controlled training with recovery support."))
    }

    private static let emptyHeart = VitalModels.HeartDomainSnapshot(
        restingHeartRate: .init(averageBPM: 0),
        hrvCorridor: .init(baselineMilliseconds: 0, lowerBoundMilliseconds: 0, upperBoundMilliseconds: 0),
        zoneDistribution: .init(),
        recovery: .init(baselineBPM: 0)
    )
    private static let emptySleep = VitalModels.SleepDomainSnapshot(architecture: .init(), debt: .init(sevenDayDebt: 0, fourteenDayDebt: 0, baselineSleepDuration: 0, targetSleepDuration: 8 * 3600, observedNightCount7d: 0, missingNightCount7d: 7, observedNightCount14d: 0, missingNightCount14d: 14, isAvailable: false))

    private func isConfigured(_ configuration: UserAIModelConfiguration) -> Bool {
        switch configuration.provider {
        case .foundationModels: return AIModelSettingsStore.isFoundationModelsAvailable
        case .jevGateway, .customOpenAICompatible:
            guard let url = configuration.baseURL, url.host != nil, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
            if configuration.provider == .jevGateway && configuration.allowsUnauthenticatedGateway { return true }
            guard let service = configuration.keychainService else { return false }
            return AIModelSettingsStore.hasSecretCached(for: service)
        case .deterministicFallback: return true
        }
    }
}

enum HeartSleepCopy {
    static let detailTitle = String(localized: "heart_sleep_detail_title", defaultValue: "Heart & Sleep", comment: "Heart and sleep detail title")
    static let loadingTitle = String(localized: "heart_sleep_loading_title", defaultValue: "Loading detail", comment: "Heart and sleep loading title")
    static let loadingMessage = String(localized: "heart_sleep_loading_message", defaultValue: "Gathering heart and sleep evidence.", comment: "Heart and sleep loading message")
    static let emptyTitle = String(localized: "heart_sleep_empty_title", defaultValue: "Build your baseline", comment: "Heart and sleep empty title")
    static let emptyMessage = String(localized: "heart_sleep_empty_message", defaultValue: "Authorize Health data to unlock heart and sleep evidence.", comment: "Heart and sleep empty message")
    static let settingsAction = String(localized: "heart_sleep_settings_action", defaultValue: "Open Health Settings", comment: "Open Health Settings action")
    static let errorTitle = String(localized: "heart_sleep_error_title", defaultValue: "Detail unavailable", comment: "Heart and sleep error title")
    static let errorMessage = String(localized: "heart_sleep_error_message", defaultValue: "Your local data is safe. Retry when the source is available.", comment: "Heart and sleep error message")
    static let retryAction = String(localized: "heart_sleep_retry_action", defaultValue: "Retry", comment: "Retry action")
    static let couplingHeader = String(localized: "heart_sleep_coupling_header", defaultValue: "Sleep × training coupling · L2", comment: "Coupling card header")
    static let intensityCap = String(localized: "heart_sleep_intensity_cap", defaultValue: "Recommended intensity ceiling", comment: "Intensity cap label")
    static let autonomic = String(localized: "heart_sleep_autonomic", defaultValue: "Autonomic", comment: "Autonomic score label")
    static let sleepRestoration = String(localized: "heart_sleep_sleep_restoration", defaultValue: "Sleep restoration", comment: "Sleep restoration score label")
    static let autonomicHeader = String(localized: "heart_sleep_autonomic_header", defaultValue: "Autonomic corridor · L1", comment: "Autonomic card header")
    static let hrvSDNN = String(localized: "heart_sleep_hrv_sdnn", defaultValue: "HRV SDNN", comment: "HRV metric label")
    static let restingHeartRate = String(localized: "heart_sleep_resting_heart_rate", defaultValue: "Resting heart rate", comment: "Resting heart rate label")
    static let recovery = String(localized: "heart_sleep_recovery", defaultValue: "HRR (1m)", comment: "One minute heart rate recovery label")
    static let heartRateZones = String(localized: "heart_sleep_heart_rate_zones", defaultValue: "Heart rate zones", comment: "Heart rate zones label")
    static let architectureHeader = String(localized: "heart_sleep_architecture_header", defaultValue: "Sleep architecture & debt · L1", comment: "Sleep architecture header")
    static let deep = String(localized: "heart_sleep_deep", defaultValue: "Deep", comment: "Deep sleep label")
    static let rem = String(localized: "heart_sleep_rem", defaultValue: "REM", comment: "REM sleep label")
    static let core = String(localized: "heart_sleep_core", defaultValue: "Core", comment: "Core sleep label")
    static let awake = String(localized: "heart_sleep_awake", defaultValue: "Awake", comment: "Awake sleep label")
    static let sevenDayDebt = String(localized: "heart_sleep_7d_debt", defaultValue: "7d debt", comment: "Seven day sleep debt label")
    static let fourteenDayDebt = String(localized: "heart_sleep_14d_debt", defaultValue: "14d debt", comment: "Fourteen day sleep debt label")
    static let nights = String(localized: "heart_sleep_nights", defaultValue: "nights", comment: "Sleep debt nights label")
    static let target = String(localized: "heart_sleep_target", defaultValue: "Target", comment: "Sleep target label")
    static let inBed = String(localized: "heart_sleep_in_bed", defaultValue: "In bed", comment: "Time in bed label")
    static let exploreDomains = String(localized: "heart_sleep_explore_domains", defaultValue: "Explore domains", comment: "Domain drill down header")
    static let heartAutonomicDetail = String(localized: "heart_sleep_heart_autonomic_detail", defaultValue: "Heart autonomic detail", comment: "Heart drill down label")
    static let sleepArchitectureDetail = String(localized: "heart_sleep_sleep_architecture_detail", defaultValue: "Sleep architecture detail", comment: "Sleep drill down label")

    static func readiness(_ value: Int) -> String { String(localized: "heart_sleep_readiness", defaultValue: "Readiness \(value)", comment: "Readiness score") }
    static func withinCorridor(_ isWithin: Bool) -> String { isWithin ? String(localized: "heart_sleep_within_corridor", defaultValue: "Within corridor", comment: "Normal corridor status") : String(localized: "heart_sleep_outside_corridor", defaultValue: "Outside corridor", comment: "Outside corridor status") }
    static func phase(_ phase: AIService.MesocyclePhase) -> String {
        switch phase {
        case .accumulation: String(localized: "heart_sleep_phase_accumulation", defaultValue: "Accumulation", comment: "Mesocycle phase")
        case .intensification: String(localized: "heart_sleep_phase_intensification", defaultValue: "Intensification", comment: "Mesocycle phase")
        case .realization: String(localized: "heart_sleep_phase_realization", defaultValue: "Realization", comment: "Mesocycle phase")
        case .deload: String(localized: "heart_sleep_phase_deload", defaultValue: "Deload", comment: "Mesocycle phase")
        }
    }
    static func provider(_ provider: PluggableAIProvider) -> String {
        switch provider {
        case .foundationModels: String(localized: "heart_sleep_provider_foundation", defaultValue: "On-device AI", comment: "AI provider label")
        case .customOpenAICompatible: String(localized: "heart_sleep_provider_custom", defaultValue: "Custom API", comment: "AI provider label")
        case .jevGateway: String(localized: "heart_sleep_provider_jev", defaultValue: "Jev Gateway", comment: "AI provider label")
        case .deterministicFallback: String(localized: "heart_sleep_provider_fallback", defaultValue: "Local rules", comment: "AI provider label")
        }
    }
    static func severity(_ severity: AIService.InsightSeverity) -> (String, PillTone) {
        switch severity {
        case .normal: (String(localized: "heart_sleep_within_corridor", defaultValue: "Within corridor", comment: "Normal corridor status"), .success)
        case .watch: (String(localized: "heart_sleep_watch_load", defaultValue: "Watch load", comment: "Watch load status"), .warning)
        case .warning: (String(localized: "heart_sleep_moderate_strain", defaultValue: "Moderate strain", comment: "Moderate strain status"), .warning)
        case .critical: (String(localized: "heart_sleep_high_strain", defaultValue: "High strain", comment: "High strain status"), .danger)
        }
    }
    static func duration(_ value: TimeInterval) -> String {
        let minutes = max(0, Int(value.rounded())) / 60
        return String(localized: "heart_sleep_duration", defaultValue: "\(minutes / 60)h \(minutes % 60)m", comment: "Duration formatted in hours and minutes")
    }
    static func number(_ value: Double?) -> String { value.map { Int($0.rounded()).formatted() } ?? "—" }
    static func signed(_ value: Double?) -> String { guard let value else { return "—" }; return "\(value >= 0 ? "+" : "")\(Int(value.rounded()))" }
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func ms(_ value: String) -> String { String(localized: "heart_sleep_ms_value", defaultValue: "\(value) ms", comment: "Milliseconds metric") }
    static func bpm(_ value: String) -> String { String(localized: "heart_sleep_bpm_value", defaultValue: "\(value) bpm", comment: "Beats per minute metric") }
    static func corridor(lower: String, upper: String) -> String { String(localized: "heart_sleep_corridor_value", defaultValue: "\(lower)–\(upper) ms", comment: "HRV corridor range") }
    static func average7d(_ value: String) -> String { String(localized: "heart_sleep_7d_average", defaultValue: "7d \(value)", comment: "Seven day average") }
    static func baseline60d(_ value: Int) -> String { String(localized: "heart_sleep_60d_baseline", defaultValue: "60d \(value)d", comment: "Sixty day baseline count") }
    static func restingDetail(average: String, delta: String) -> String { String(localized: "heart_sleep_resting_detail", defaultValue: "7d \(average) · Δ \(delta) bpm", comment: "Resting heart rate detail") }
    static func recoveryValue(_ value: String) -> String { String(localized: "heart_sleep_recovery_1m", defaultValue: "-\(value) bpm", comment: "One minute heart rate recovery value") }
    static func recoveryDetail(twoMinute: String, peak: String) -> String { String(localized: "heart_sleep_recovery_detail", defaultValue: "2m -\(twoMinute) · peak \(peak)", comment: "Two minute heart rate recovery detail") }
    static func coverage(_ count: Int, total: Int) -> String { String(localized: "heart_sleep_coverage", defaultValue: "\(count)/\(total) nights", comment: "Observed sleep nights") }
    static func targetAndBed(target: String, inBed: String) -> String { String(localized: "heart_sleep_target_and_bed", defaultValue: "Target \(target) · In bed \(inBed)", comment: "Sleep target and time in bed") }
    static func zone(_ value: Int) -> String { String(localized: "heart_sleep_zone", defaultValue: "Z\(value)", comment: "Heart rate zone label") }
}

enum HeartSleepFormatting {
    static func duration(_ value: TimeInterval) -> String { HeartSleepCopy.duration(value) }
    static func number(_ value: Double?) -> String { HeartSleepCopy.number(value) }
    static func signed(_ value: Double?) -> String { HeartSleepCopy.signed(value) }
    static func percent(_ value: Double) -> String { HeartSleepCopy.percent(value) }
    static func phase(_ phase: AIService.MesocyclePhase) -> String { HeartSleepCopy.phase(phase) }
    static func provider(_ provider: PluggableAIProvider) -> String { HeartSleepCopy.provider(provider) }
    static func severity(_ severity: AIService.InsightSeverity) -> (String, PillTone) { HeartSleepCopy.severity(severity) }
}

struct HeartSleepCouplingDetailView: View {
    @State private var state: HeartSleepCouplingState
    @Query(sort: \Workout.startDate, order: .reverse) private var workouts: [Workout]
    @Environment(\.healthDataCache) private var cache
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @Environment(\.theme) private var theme

    init(state: HeartSleepCouplingState? = nil) { _state = State(initialValue: state ?? HeartSleepCouplingState()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                switch state.loadState {
                case .populated:
                    if let report = state.report { populated(report: report) } else { stateView(.loading, title: HeartSleepCopy.loadingTitle, message: HeartSleepCopy.loadingMessage) }
                case .loading: stateView(.loading, title: HeartSleepCopy.loadingTitle, message: HeartSleepCopy.loadingMessage)
                case .empty: stateView(.empty, title: HeartSleepCopy.emptyTitle, message: HeartSleepCopy.emptyMessage, actionTitle: HeartSleepCopy.settingsAction) {
                    #if os(iOS)
                    navigation?.selectedTab = .settings
                    #endif
                }
                case .error: stateView(.error, title: HeartSleepCopy.errorTitle, message: HeartSleepCopy.errorMessage, actionTitle: HeartSleepCopy.retryAction, action: state.onRetry)
                }
            }
            .padding(Space.md)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }
        .background(theme.canvas)
        .navigationTitle(HeartSleepCopy.detailTitle)
        .task {
            guard !state.hasLoaded else { return }
            await state.load(cache: cache, workouts: workouts)
        }
    }

    @ViewBuilder private func stateView(_ style: DesignStateView.State, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack { Spacer(minLength: Space.lg); DesignStateView(style, title: title, message: message, actionTitle: actionTitle, action: action ?? {}); Spacer(minLength: Space.lg) }.frame(maxWidth: .infinity, minHeight: 760)
    }

    @ViewBuilder private func populated(report: AIService.HolisticFourLayerReport) -> some View {
        let coupling = report.l2.first(where: { $0.relationship == "sleepTrainingCoupling" }) ?? report.l2.first
        if let coupling { L2SleepTrainingCouplingCard(report: report, insight: coupling, provider: state.provider) }
        HeartAutonomicCorridorCard(snapshot: state.heart)
        SleepArchitectureAndDebtCard(snapshot: state.sleep)
        DomainDrillDownLinksCard()
    }
}

private struct L2SleepTrainingCouplingCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport
    let insight: AIService.L2CoupledInsight
    let provider: PluggableAIProvider
    var body: some View {
        Card {
            HStack { SectionHeader(HeartSleepCopy.couplingHeader, icon: "bolt.heart.fill"); Spacer(minLength: Space.xs); StatusPill(HeartSleepFormatting.provider(provider), tone: .primary) }
            CardInner {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(HeartSleepCopy.intensityCap).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                    Text(HeartSleepFormatting.percent(report.l3.recommendedIntensityCap)).font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1)
                    ProgressView(value: report.l3.recommendedIntensityCap).tint(theme.accent)
                    HStack { StatusPill(HeartSleepFormatting.phase(report.l3.mesocyclePhase), tone: .primary); StatusPill(HeartSleepFormatting.severity(insight.severity).0, tone: HeartSleepFormatting.severity(insight.severity).1); Spacer(); Text(HeartSleepCopy.readiness(report.l3.readinessScore)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow { ScoreCell(title: HeartSleepCopy.autonomic, value: report.l3.autonomicScore, color: theme.chart(1)); ScoreCell(title: HeartSleepCopy.sleepRestoration, value: report.l3.sleepRestorationScore, color: theme.chart(3)) }
            }
            Text(insight.message).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScoreCell: View { let title: String; let value: Int; let color: Color; var body: some View { CardInner { VStack(alignment: .leading) { Text(title).font(TypeScale.meta).minimumScaleFactor(0.85); Text("\(value)").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(color) } } } }

struct HeartAutonomicCorridorCard: View {
    @Environment(\.theme) private var theme
    let snapshot: VitalModels.HeartDomainSnapshot
    var body: some View {
        Card {
            SectionHeader(HeartSleepCopy.autonomicHeader, icon: "waveform.path.ecg")
            let corridor = snapshot.hrvCorridor
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { HStack { Text(HeartSleepCopy.hrvSDNN).font(TypeScale.title); Spacer(); StatusPill(HeartSleepCopy.withinCorridor(corridor.isWithinCorridor), tone: corridor.isWithinCorridor ? .success : .warning) }; Text(HeartSleepCopy.ms(HeartSleepFormatting.number(corridor.currentMilliseconds))).font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); GeometryReader { proxy in corridorBar(corridor, width: proxy.size.width) }.frame(height: 18); HStack { Text(HeartSleepCopy.corridor(lower: HeartSleepFormatting.number(corridor.lowerBoundMilliseconds), upper: HeartSleepFormatting.number(corridor.upperBoundMilliseconds))); Spacer(); Text("\(HeartSleepCopy.average7d(HeartSleepFormatting.number(corridor.sevenDayAverageMilliseconds))) · \(HeartSleepCopy.baseline60d(corridor.baselineDayCount))") }.font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.secondaryForeground) } }
            Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) { GridRow { HeartMetricCell(title: HeartSleepCopy.restingHeartRate, value: HeartSleepCopy.bpm(HeartSleepFormatting.number(snapshot.restingHeartRate.currentBPM)), detail: HeartSleepCopy.restingDetail(average: HeartSleepFormatting.number(snapshot.restingHeartRate.sevenDayAverageBPM), delta: HeartSleepFormatting.signed(snapshot.restingHeartRate.deltaFromBaselineBPM))); HeartMetricCell(title: HeartSleepCopy.recovery, value: HeartSleepCopy.recoveryValue(HeartSleepFormatting.number(snapshot.recovery.oneMinuteDropBPM)), detail: HeartSleepCopy.recoveryDetail(twoMinute: HeartSleepFormatting.number(snapshot.recovery.twoMinuteDropBPM), peak: HeartSleepFormatting.number(snapshot.recovery.baselineBPM))) } }
            ZoneDistributionBar(distribution: snapshot.zoneDistribution)
        }
    }
    private func corridorBar(_ corridor: VitalModels.HRVCorridorSnapshot, width: CGFloat) -> some View { let span = max(1, corridor.upperBoundMilliseconds - corridor.lowerBoundMilliseconds); let scale: (Double) -> CGFloat = { CGFloat(($0 - corridor.lowerBoundMilliseconds) / span) * width }; return ZStack(alignment: .leading) { Capsule().fill(theme.neutrals.border); Capsule().fill(theme.accentSubtle).frame(width: width); Rectangle().fill(theme.secondaryForeground).frame(width: 1).offset(x: min(max(0, scale(corridor.baselineMilliseconds)), width)); Circle().fill(theme.accent).frame(width: 10, height: 10).offset(x: min(max(0, scale(corridor.currentMilliseconds ?? corridor.baselineMilliseconds) - 5), width - 10)) } }
}

private struct HeartMetricCell: View { @Environment(\.theme) private var theme; let title: String; let value: String; let detail: String; var body: some View { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.meta); Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85); Text(detail).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(theme.secondaryForeground) } } } }

private struct ZoneDistributionBar: View {
    @Environment(\.theme) private var theme
    let distribution: VitalModels.HeartRateZoneDistribution
    var body: some View { VStack(alignment: .leading, spacing: Space.xs) { SectionHeader(HeartSleepCopy.heartRateZones, icon: "chart.bar.xaxis"); GeometryReader { proxy in HStack(spacing: 2) { ForEach(Array(VitalModels.HeartRateZone.allCases.enumerated()), id: \.offset) { index, zone in Rectangle().fill(theme.chart(index + 4)).frame(width: max(2, proxy.size.width * ratio(zone))) } }.clipShape(Capsule()) }.frame(height: 12); HStack { ForEach(1...5, id: \.self) { Text(HeartSleepCopy.zone($0)).font(TypeScale.meta).frame(maxWidth: .infinity) } } } }
    private func ratio(_ zone: VitalModels.HeartRateZone) -> CGFloat { let total = distribution.totalDuration; return total > 0 ? CGFloat(distribution.duration(in: zone) / total) : 0 }
}

struct SleepArchitectureAndDebtCard: View {
    @Environment(\.theme) private var theme
    let snapshot: VitalModels.SleepDomainSnapshot
    var body: some View { Card { SectionHeader(HeartSleepCopy.architectureHeader, icon: "bed.double.fill"); let architecture = snapshot.architecture; CardInner { VStack(alignment: .leading, spacing: Space.sm) { HStack { Text(HeartSleepFormatting.duration(architecture.totalSleepDuration)).font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); Spacer(); Text(HeartSleepFormatting.percent(architecture.sleepEfficiency)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1) }; SleepStageBar(architecture: architecture); Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { StageCell(title: HeartSleepCopy.deep, duration: architecture.deepDuration, color: theme.chart(3)); StageCell(title: HeartSleepCopy.rem, duration: architecture.remDuration, color: theme.chart(2)) }; GridRow { StageCell(title: HeartSleepCopy.core, duration: architecture.coreDuration, color: theme.chart(0)); StageCell(title: HeartSleepCopy.awake, duration: architecture.awakeDuration, color: theme.secondaryForeground) } } } }; HStack(spacing: Space.sm) { DebtCell(title: HeartSleepCopy.sevenDayDebt, value: snapshot.debt.sevenDayDebt, coverage: HeartSleepCopy.coverage(snapshot.debt.observedNightCount7d, total: 7)); DebtCell(title: HeartSleepCopy.fourteenDayDebt, value: snapshot.debt.fourteenDayDebt, coverage: HeartSleepCopy.coverage(snapshot.debt.observedNightCount14d, total: 14)) }; Text(HeartSleepCopy.targetAndBed(target: HeartSleepFormatting.duration(snapshot.debt.targetSleepDuration), inBed: HeartSleepFormatting.duration(architecture.totalInBedDuration))).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.secondaryForeground) } }
}
private struct SleepStageBar: View { @Environment(\.theme) private var theme; let architecture: VitalModels.SleepArchitectureSnapshot; var body: some View { GeometryReader { proxy in let total = max(1, architecture.totalSleepDuration + architecture.awakeDuration); HStack(spacing: 2) { Rectangle().fill(theme.chart(3)).frame(width: proxy.size.width * architecture.deepDuration / total); Rectangle().fill(theme.chart(2)).frame(width: proxy.size.width * architecture.remDuration / total); Rectangle().fill(theme.chart(0)).frame(width: proxy.size.width * architecture.coreDuration / total); Rectangle().fill(theme.secondaryForeground).frame(width: max(2, proxy.size.width * architecture.awakeDuration / total)) } }.frame(height: 12).clipShape(Capsule()) } }
private struct StageCell: View { @Environment(\.theme) private var theme; let title: String; let duration: TimeInterval; let color: Color; var body: some View { CardInner { HStack { Circle().fill(color).frame(width: 8, height: 8); VStack(alignment: .leading) { Text(title).font(TypeScale.meta); Text(HeartSleepFormatting.duration(duration)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } } } } }
private struct DebtCell: View { let title: String; let value: TimeInterval; let coverage: String; var body: some View { CardInner { VStack(alignment: .leading) { Text(title).font(TypeScale.meta).minimumScaleFactor(0.85); Text(HeartSleepFormatting.duration(value)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85); Text(coverage).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85) } } } }

private struct DomainDrillDownLinksCard: View {
    var body: some View { Card { SectionHeader(HeartSleepCopy.exploreDomains, icon: "arrow.forward"); NavigationLink { HeartRateDetailView() } label: { Label(HeartSleepCopy.heartAutonomicDetail, systemImage: "heart.fill").frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading).contentShape(Rectangle()) }; NavigationLink { SleepDetailView() } label: { Label(HeartSleepCopy.sleepArchitectureDetail, systemImage: "bed.double.fill").frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading).contentShape(Rectangle()) } } }
}

#Preview("Heart sleep populated") { NavigationStack { HeartSleepCouplingDetailView(state: .preview()) }.designThemePreview(seed: .teal, neutral: .slate) }
#Preview("Heart sleep dark") { NavigationStack { HeartSleepCouplingDetailView(state: .preview()) }.preferredColorScheme(.dark).designThemePreview(seed: .teal, neutral: .slate) }
