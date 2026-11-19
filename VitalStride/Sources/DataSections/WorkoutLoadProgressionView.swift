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
final class WorkoutLoadProgressionState {
    enum LoadState: Equatable { case populated, empty, loading, error }

    private(set) var loadState: LoadState
    private(set) var snapshot: VitalModels.PhysiologicalSnapshot?
    private(set) var report: AIService.HolisticFourLayerReport?
    private(set) var provider: PluggableAIProvider
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
        self.hasLoaded = preloadedSnapshot != nil || report != nil || loadState != .loading
    }

    func load(cache: HealthDataCache, workouts: [Workout] = [], generatedAt: Date = Date()) async {
        loadState = .loading
        hasLoaded = false
        let interval = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -59, to: generatedAt) ?? generatedAt,
            end: generatedAt
        )
        let requested: Set<HealthSampleType> = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .distanceWalkingRunning,
            .vo2Max, .sleepAnalysis, .stepCount, .activeEnergyBurned
        ]
        var points: [HealthDataPoint] = []
        for type in requested {
            guard !Task.isCancelled else { return }
            if let values = try? await cache.data(for: type, in: interval) {
                points.append(contentsOf: values)
            }
        }
        let healthWorkouts = (try? await cache.workoutData(in: interval)) ?? []
        let strengthWorkouts = workouts.compactMap(\.strengthSummaryInput)
        let calculator = HealthMetricsCalculator()
        guard let vitalSnapshot = calculator.physiologicalSnapshot(
            from: points,
            workouts: healthWorkouts,
            strengthWorkouts: strengthWorkouts,
            generatedAt: generatedAt
        ),
        vitalSnapshot.trainingLoad.isAvailable || vitalSnapshot.aerobic.isAvailable || vitalSnapshot.heart.zoneDistribution.totalDuration > 0,
        let aiSnapshot = bridge(vitalSnapshot) else {
            snapshot = nil
            report = nil
            loadState = .empty
            hasLoaded = true
            return
        }

        snapshot = vitalSnapshot
        let configuration = Self.resolveConfiguration()
        provider = configuration.provider
        if configuration.provider == .deterministicFallback || !isConfigured(configuration) {
            report = await FourLayerAdviceEngine().generate(snapshot: aiSnapshot, model: configuration.modelID)
            provider = .deterministicFallback
            loadState = .populated
            hasLoaded = true
            return
        }
        do {
            report = try await FourLayerAdviceEngine(provider: configuration.makeProvider())
                .generateCancellable(snapshot: aiSnapshot, model: configuration.modelID)
            loadState = .populated
            hasLoaded = true
        } catch {
            report = await FourLayerAdviceEngine().generate(snapshot: aiSnapshot, model: configuration.modelID)
            provider = .deterministicFallback
            loadState = .error
            hasLoaded = true
            onRetry = { [weak self, cache] in
                Task { @MainActor in await self?.load(cache: cache, workouts: workouts) }
            }
        }
    }

    func markEmpty() { snapshot = nil; report = nil; loadState = .empty; hasLoaded = true }
    func markLoading() { report = nil; loadState = .loading; hasLoaded = true }
    func markError(onRetry: (() -> Void)? = nil) { report = nil; loadState = .error; hasLoaded = true; self.onRetry = onRetry }

    static func preview() -> WorkoutLoadProgressionState {
        let snapshot = previewSnapshot
        let state = WorkoutLoadProgressionState(
            preloadedSnapshot: snapshot,
            report: previewReport,
            provider: .deterministicFallback,
            loadState: .populated
        )
        return state
    }

    static let previewSnapshot: VitalModels.PhysiologicalSnapshot = {
        let now = Date()
        let trajectory = (0..<14).map { index in
            let day = Calendar.current.date(byAdding: .day, value: -13 + index, to: now) ?? now
            let ctl = 57.0 + Double(index) * 0.11
            let atl = 55.0 + Double(index % 5) * 0.8
            return VitalModels.TrainingLoadDailyPoint(date: day, dailyLoad: 42 + Double(index * 3), acuteTrainingLoad: atl, chronicTrainingLoad: ctl, trainingStressBalance: ctl - atl)
        }
        let load = VitalModels.TrainingLoadSnapshot(
            acuteTrainingLoad: 58.4, chronicTrainingLoad: 64.7, trainingStressBalance: 6.3,
            acuteChronicWorkloadRatio: 0.90, trimp: 312, tss: 268, atlDelta7d: -4.2,
            ctlDelta7d: 3.1, ctlDelta14d: 5.8, tsbDelta7d: 7.3, deduplicatedWorkoutCount: 9,
            recentTrajectory: trajectory
        )
        let zones = VitalModels.HeartRateZoneDistribution(zone1: 36 * 60, zone2: 108 * 60, zone3: 22 * 60, zone4: 26 * 60, zone5: 8 * 60, resolvedMaximumHeartRateBPM: 190)
        let heart = HeartDomainSnapshot(
            restingHeartRate: .init(averageBPM: 53, minimumBPM: 50, maximumBPM: 58, sampleCount: 12, currentBPM: 52, sevenDayAverageBPM: 53, baselineBPM: 55, baselineDayCount: 12),
            hrvCorridor: .init(baselineMilliseconds: 63, lowerBoundMilliseconds: 54, upperBoundMilliseconds: 72, sampleCount: 12, currentMilliseconds: 68, sevenDayAverageMilliseconds: 65, sevenDaySampleCount: 7, baselineDayCount: 12),
            zoneDistribution: zones,
            recovery: .init(baselineBPM: 164, oneMinuteBPM: 132, twoMinuteBPM: 115)
        )
        let sleep = VitalModels.SleepDomainSnapshot(architecture: VitalModels.SleepArchitectureSnapshot(), debt: VitalModels.SleepDebtSummary(sevenDayDebt: 0, fourteenDayDebt: 0, baselineSleepDuration: 0, targetSleepDuration: 8 * 3600, observedNightCount7d: 0, missingNightCount7d: 7, observedNightCount14d: 0, missingNightCount14d: 14, isAvailable: false))
        return PhysiologicalSnapshot(
            heart: heart, sleep: sleep, neat: VitalModels.NEATActivitySnapshot(dailySteps: 0, nonExerciseActiveEnergy: 0, basalEnergy: 0, hourlyMovementConsistency: 0, flightsClimbed: 0),
            aerobic: .init(efficiencyFactor: 0.086, aerobicDecouplingPercentage: 3.4, vo2Max: 51.4, vo2MaxTrend: 1.8, sampleCount: 12),
            trainingLoad: load, generatedAt: now
        )
    }()

    static let previewReport = AIService.HolisticFourLayerReport(
        l1: [],
        l2: [.init(primaryDomain: .aerobic, secondaryDomain: .trainingLoad, relationship: "loadPrescription", message: "Stable aerobic coupling supports a controlled progression session.")],
        l3: .init(readinessScore: 84, autonomicScore: 86, sleepRestorationScore: 81, fatigueBalanceScore: 83, mesocyclePhase: .intensification, recommendedIntensityCap: 0.85, contributingInsights: ["Maintain the planned intensity ceiling."]),
        l4: .init(northStarScore: 86, directive: "Controlled progression with recovery support.")
    )

    private static func resolveConfiguration(defaults: UserDefaults = .standard, keychain: KeychainHelper = KeychainHelper()) -> UserAIModelConfiguration {
        if let data = defaults.data(forKey: "userAIModelConfiguration"), let stored = try? JSONDecoder().decode(UserAIModelConfiguration.self, from: data) { return stored }
        if AppleIntelligenceProvider.isAvailable { return UserAIModelConfiguration(provider: .foundationModels) }
        let service = "\(KeychainHelper.defaultServicePrefix).apikey"
        if let key = try? keychain.load(service: service), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return UserAIModelConfiguration(provider: .customOpenAICompatible, baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4"), modelID: "glm-4-flash", keychainService: service)
        }
        return UserAIModelConfiguration(provider: .deterministicFallback)
    }

    private func isConfigured(_ configuration: UserAIModelConfiguration) -> Bool {
        switch configuration.provider {
        case .foundationModels: return AppleIntelligenceProvider.isAvailable
        case .deterministicFallback: return true
        case .jevGateway, .customOpenAICompatible:
            guard let url = configuration.baseURL, let host = url.host, !host.isEmpty, ["http", "https"].contains(url.scheme?.lowercased()), let service = configuration.keychainService else { return false }
            if configuration.provider == .jevGateway, configuration.allowsUnauthenticatedGateway { return true }
            guard let key = try? KeychainHelper().load(service: service) else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func bridge(_ value: VitalModels.PhysiologicalSnapshot) -> AIService.PhysiologicalSnapshot? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(AIService.PhysiologicalSnapshot.self, from: data)
    }
}

enum WorkoutLoadCopy {
    static let title = String(localized: "workout_load_title", defaultValue: "Workout Load & Progression", comment: "Workout load detail title")
    static let periodization = String(localized: "workout_load_periodization", defaultValue: "Specialized fitness periodization · L3", comment: "Periodization card header")
    static let pmc = String(localized: "workout_load_pmc", defaultValue: "Training load PMC · ATL / CTL / TSB", comment: "Training load card header")
    static let zones = String(localized: "workout_load_zones", defaultValue: "Heart-rate zones · Zone 1–5", comment: "Heart rate zones card header")
    static let aerobic = String(localized: "workout_load_aerobic", defaultValue: "Aerobic efficiency · EF / VO2max", comment: "Aerobic card header")
    static let intensity = String(localized: "workout_load_intensity", defaultValue: "Recommended intensity ceiling", comment: "Intensity cap label")
    static let readiness = String(localized: "workout_load_readiness", defaultValue: "Readiness", comment: "Readiness label")
    static let fatigueBalance = String(localized: "workout_load_fatigue_balance", defaultValue: "Fatigue balance", comment: "Fatigue balance label")
    static let prescription = String(localized: "workout_load_prescription", defaultValue: "Next-session prescription", comment: "Prescription label")
    static let emptyTitle = String(localized: "workout_load_empty_title", defaultValue: "Build your load baseline", comment: "Empty state title")
    static let emptyMessage = String(localized: "workout_load_empty_message", defaultValue: "Complete a workout or authorize health data to unlock training load, zones, and aerobic efficiency.", comment: "Empty state message")
    static let loadingTitle = String(localized: "workout_load_loading_title", defaultValue: "Preparing load detail", comment: "Loading state title")
    static let loadingMessage = String(localized: "workout_load_loading_message", defaultValue: "Gathering recent training evidence.", comment: "Loading state message")
    static let errorTitle = String(localized: "workout_load_error_title", defaultValue: "Load detail unavailable", comment: "Error state title")
    static let errorMessage = String(localized: "workout_load_error_message", defaultValue: "Your local data is safe. Retry when the source is available.", comment: "Error state message")
    static let retry = String(localized: "workout_load_retry", defaultValue: "Retry", comment: "Retry action")
    static let settings = String(localized: "workout_load_settings", defaultValue: "Open Health Settings", comment: "Health settings action")
    static let providerOnDevice = String(localized: "workout_load_provider_on_device", defaultValue: "On-device AI", comment: "AI provider label")
    static let providerLocal = String(localized: "workout_load_provider_local", defaultValue: "Local rules", comment: "AI provider label")
    static let nextSession = String(localized: "workout_load_next_session", defaultValue: "Hold the 85% ceiling and progress with controlled volume.", comment: "Next session prescription")
    static let coupled = String(localized: "workout_load_coupled", defaultValue: "Coupled", comment: "Aerobic decoupling status")
    static let drift = String(localized: "workout_load_drift", defaultValue: "Watch drift", comment: "Aerobic decoupling status")
    static let sweetSpot = String(localized: "workout_load_sweet_spot", defaultValue: "Sweet spot", comment: "ACWR status")
    static let caution = String(localized: "workout_load_caution", defaultValue: "Watch", comment: "ACWR status")
    static let overreaching = String(localized: "workout_load_overreaching", defaultValue: "Overreaching", comment: "ACWR status")
    static let optimal = String(localized: "workout_load_optimal", defaultValue: "Optimal form", comment: "TSB status")
    static let fatigue = String(localized: "workout_load_fatigue", defaultValue: "Fatigue watch", comment: "TSB status")
    static let zoneBase = String(localized: "workout_load_zone_base", defaultValue: "Low aerobic base", comment: "Polarization label")
    static let zoneHigh = String(localized: "workout_load_zone_high", defaultValue: "High stimulus", comment: "Polarization label")
    static let units = String(localized: "workout_load_units", defaultValue: "units", comment: "Stress units")
    static let sampleCount = String(localized: "workout_load_sample_count", defaultValue: "samples", comment: "Sample count label")
    static let maxHeartRate = String(localized: "workout_load_max_hr", defaultValue: "Max HR", comment: "Maximum heart rate label")
    static func phase(_ phase: AIService.MesocyclePhase) -> String {
        switch phase {
        case .accumulation: String(localized: "workout_load_phase_accumulation", defaultValue: "Accumulation", comment: "Mesocycle phase")
        case .intensification: String(localized: "workout_load_phase_intensification", defaultValue: "Intensification", comment: "Mesocycle phase")
        case .realization: String(localized: "workout_load_phase_realization", defaultValue: "Realization", comment: "Mesocycle phase")
        case .deload: String(localized: "workout_load_phase_deload", defaultValue: "Deload", comment: "Mesocycle phase")
        }
    }
    static func provider(_ provider: PluggableAIProvider) -> String { provider == .foundationModels ? providerOnDevice : providerLocal }
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func number(_ value: Double, digits: Int = 1) -> String { value.formatted(.number.precision(.fractionLength(digits))) }
    static func signed(_ value: Double) -> String { "\(value >= 0 ? "+" : "")\(number(value))" }
    static func duration(_ value: TimeInterval) -> String { let minutes = max(0, Int(value.rounded())) / 60; return "\(minutes / 60)h \(minutes % 60)m" }
    static func share(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

struct WorkoutLoadProgressionView: View {
    @Query(filter: #Predicate<Workout> { $0.endDate != nil }, sort: \Workout.startDate, order: .reverse) private var workouts: [Workout]
    @Environment(\.healthDataCache) private var healthDataCache
    @Environment(\.theme) private var theme
    @Environment(AppNavigation.self) private var navigation
    @State private var state: WorkoutLoadProgressionState

    init(state: WorkoutLoadProgressionState = WorkoutLoadProgressionState()) { _state = State(initialValue: state) }

    var body: some View {
        ScrollView {
            Group {
                switch state.loadState {
                case .populated:
                    if let snapshot = state.snapshot, let report = state.report { populated(snapshot: snapshot, report: report) }
                    else { stateView(.empty) }
                case .empty: stateView(.empty)
                case .loading: stateView(.loading)
                case .error: stateView(.error)
                }
            }
            .padding(Space.md)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }
        .background(theme.canvas)
        .navigationTitle(WorkoutLoadCopy.title)
        .task {
            guard !state.hasLoaded else { return }
            await state.load(cache: healthDataCache, workouts: workouts)
        }
    }

    @ViewBuilder private func stateView(_ value: DesignStateView.State) -> some View {
        switch value {
        case .empty: DesignStateView(.empty, title: WorkoutLoadCopy.emptyTitle, message: WorkoutLoadCopy.emptyMessage, actionTitle: WorkoutLoadCopy.settings) { navigation.selectedTab = .settings }.frame(maxWidth: .infinity, minHeight: 760)
        case .loading: DesignStateView(.loading, title: WorkoutLoadCopy.loadingTitle, message: WorkoutLoadCopy.loadingMessage).frame(maxWidth: .infinity, minHeight: 760)
        case .error: DesignStateView(.error, title: WorkoutLoadCopy.errorTitle, message: WorkoutLoadCopy.errorMessage, actionTitle: WorkoutLoadCopy.retry, action: state.onRetry).frame(maxWidth: .infinity, minHeight: 760)
        }
    }

    @ViewBuilder private func populated(snapshot: VitalModels.PhysiologicalSnapshot, report: AIService.HolisticFourLayerReport) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PeriodizationCard(load: snapshot.trainingLoad, report: report, provider: state.provider)
            PMCCard(load: snapshot.trainingLoad)
            ZonesCard(zones: snapshot.heart.zoneDistribution)
            AerobicCard(aerobic: snapshot.aerobic)
        }
    }
}

private struct PeriodizationCard: View {
    @Environment(\.theme) private var theme
    let load: VitalModels.TrainingLoadSnapshot
    let report: AIService.HolisticFourLayerReport
    let provider: PluggableAIProvider
    var body: some View {
        Card {
            HStack { SectionHeader(WorkoutLoadCopy.periodization, icon: "calendar.badge.clock"); Spacer(minLength: Space.xs); StatusPill(WorkoutLoadCopy.provider(provider), tone: .primary).fixedSize(horizontal: true, vertical: false) }
            HStack(spacing: Space.xs) { ForEach(AIService.MesocyclePhase.allCases, id: \.self) { phase in CardInner { Text(WorkoutLoadCopy.phase(phase)).font(TypeScale.meta).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(phase == report.l3.mesocyclePhase ? theme.accent : theme.secondaryForeground) }.layoutPriority(1) } }
            Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) {
                GridRow { metric(WorkoutLoadCopy.intensity, WorkoutLoadCopy.percent(report.l3.recommendedIntensityCap), theme.accent); metric(WorkoutLoadCopy.readiness, "\(report.l3.readinessScore)", theme.success) }
                GridRow { metric(WorkoutLoadCopy.fatigueBalance, "\(report.l3.fatigueBalanceScore)", theme.warning); pairedMetric(load: load) }
            }
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text(WorkoutLoadCopy.prescription).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground); Text(report.l2.first?.message ?? WorkoutLoadCopy.nextSession).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } }
        }
    }
    @ViewBuilder private func pairedMetric(load: VitalModels.TrainingLoadSnapshot) -> some View { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text("TRIMP / TSS").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1); HStack(spacing: Space.xs) { Text("\(Int(load.trimp.rounded()))").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(theme.chart(1)); Text("/").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground); Text("\(Int(load.tss.rounded()))").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(theme.chart(1)) } } } }
    @ViewBuilder private func metric(_ title: String, _ value: String, _ color: Color) -> some View { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1); Text(value).font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(color) } } }
}

private struct PMCCard: View {
    @Environment(\.theme) private var theme
    let load: VitalModels.TrainingLoadSnapshot
    var body: some View {
        Card {
            HStack { SectionHeader(WorkoutLoadCopy.pmc, icon: "chart.xyaxis.line"); Spacer(); StatusPill(tsbTone.label, tone: tsbTone.tone) }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { metric("CTL", load.chronicTrainingLoad, theme.chart(0)); metric("ATL", load.acuteTrainingLoad, theme.chart(1)); metric("TSB", load.trainingStressBalance, tsbTone.color) } }
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { PMCTrajectory(load: load); HStack { Text("7d Δ \(WorkoutLoadCopy.signed(load.ctlDelta7d)) · 14d Δ \(WorkoutLoadCopy.signed(load.ctlDelta14d))").font(TypeScale.num).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85); Spacer(); Text("\(load.deduplicatedWorkoutCount) sessions").font(TypeScale.meta).lineLimit(1) } } }
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { HStack { Text("ACWR").font(TypeScale.meta); Spacer(); Text(load.acuteChronicWorkloadRatio.map { WorkoutLoadCopy.number($0, digits: 2) } ?? "—").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1); StatusPill(acwrTone.label, tone: acwrTone.tone) }; GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(theme.warning.opacity(0.18)); Capsule().fill(theme.success.opacity(0.24)).frame(width: proxy.size.width * 0.52).offset(x: proxy.size.width * 0.24); Circle().fill(acwrTone.color).frame(width: 12, height: 12).offset(x: proxy.size.width * CGFloat(min(max((load.acuteChronicWorkloadRatio ?? 0.9) / 2.0, 0), 1)) - 6) } }.frame(height: 12) } }
        }
    }
    @ViewBuilder private func metric(_ title: String, _ value: Double, _ color: Color) -> some View { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.meta); Text(WorkoutLoadCopy.number(value)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(color) } } }
    private var tsbTone: (label: String, tone: PillTone, color: Color) { if load.trainingStressBalance < -25 { return (WorkoutLoadCopy.overreaching, .danger, theme.danger) }; if load.trainingStressBalance < -10 { return (WorkoutLoadCopy.fatigue, .warning, theme.warning) }; return (WorkoutLoadCopy.optimal, .success, theme.success) }
    private var acwrTone: (label: String, tone: PillTone, color: Color) { let value = load.acuteChronicWorkloadRatio ?? 0; if value > 1.5 { return (WorkoutLoadCopy.overreaching, .danger, theme.danger) }; if value < 0.8 || value > 1.3 { return (WorkoutLoadCopy.caution, .warning, theme.warning) }; return (WorkoutLoadCopy.sweetSpot, .success, theme.success) }
}

private struct PMCTrajectory: View {
    @Environment(\.theme) private var theme
    let load: VitalModels.TrainingLoadSnapshot
    var body: some View {
        GeometryReader { proxy in
            let points = load.recentTrajectory
            let maxValue = max(points.map(\.chronicTrainingLoad).max() ?? 1, points.map(\.acuteTrainingLoad).max() ?? 1)
            let minValue = min(points.map(\.trainingStressBalance).min() ?? 0, 0)
            ZStack {
                Path { path in
                    for (index, point) in points.enumerated() { let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1)); let y = proxy.size.height * (1 - CGFloat(point.chronicTrainingLoad / max(maxValue, 1))); index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y)) }
                }.stroke(theme.chart(0), lineWidth: 2)
                Path { path in
                    for (index, point) in points.enumerated() { let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1)); let y = proxy.size.height * (1 - CGFloat(point.acuteTrainingLoad / max(maxValue, 1))); index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y)) }
                }.stroke(theme.chart(1), lineWidth: 2)
                HStack(alignment: .bottom, spacing: 2) { ForEach(Array(points.enumerated()), id: \.offset) { _, point in Rectangle().fill(point.trainingStressBalance >= 0 ? theme.success.opacity(0.32) : theme.warning.opacity(0.32)).frame(maxWidth: .infinity, minHeight: 2, maxHeight: proxy.size.height * CGFloat(min(abs(point.trainingStressBalance) / max(abs(minValue), 1), 1))) } }.frame(maxHeight: .infinity, alignment: .bottom)
            }
        }.frame(height: 94)
    }
}

private struct ZonesCard: View {
    @Environment(\.theme) private var theme
    let zones: VitalModels.HeartRateZoneDistribution
    var body: some View {
        Card {
            HStack { SectionHeader(WorkoutLoadCopy.zones, icon: "heart.text.square.fill"); Spacer(); StatusPill("\(WorkoutLoadCopy.share(lowShare)) / \(WorkoutLoadCopy.share(highShare))", tone: .primary) }
            CardInner { VStack(alignment: .leading, spacing: Space.sm) { GeometryReader { proxy in HStack(spacing: 2) { ForEach(Array(VitalModels.HeartRateZone.allCases.enumerated()), id: \.element) { index, zone in Rectangle().fill(theme.chart(index)).frame(width: max(2, proxy.size.width * CGFloat(zones.duration(in: zone) / max(zones.totalDuration, 1)))) } }.clipShape(Capsule()) }.frame(height: 14); ForEach(VitalModels.HeartRateZone.allCases, id: \.self) { zone in ZoneRow(zone: zone, duration: zones.duration(in: zone), share: zones.duration(in: zone) / max(zones.totalDuration, 1)) } } }
            Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { CardInner { VStack(alignment: .leading) { Text(WorkoutLoadCopy.zoneBase).font(TypeScale.meta); Text(WorkoutLoadCopy.share(lowShare)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.chart(0)) } }; CardInner { VStack(alignment: .leading) { Text(WorkoutLoadCopy.zoneHigh).font(TypeScale.meta); Text(WorkoutLoadCopy.share(highShare)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.chart(4)) } } } }
            Text("\(WorkoutLoadCopy.maxHeartRate) \(zones.resolvedMaximumHeartRateBPM.map { Int($0.rounded()).description } ?? "—") bpm").font(TypeScale.meta).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.secondaryForeground)
        }
    }
    private var lowShare: Double { (zones.zone1Duration + zones.zone2Duration) / max(zones.totalDuration, 1) }
    private var highShare: Double { (zones.zone4Duration + zones.zone5Duration) / max(zones.totalDuration, 1) }
}

private struct ZoneRow: View {
    @Environment(\.theme) private var theme
    let zone: VitalModels.HeartRateZone
    let duration: TimeInterval
    let share: Double
    var body: some View { let index = VitalModels.HeartRateZone.allCases.firstIndex(of: zone) ?? 0; return HStack(spacing: Space.xs) { Text("Z\(index + 1)").font(TypeScale.meta).frame(width: 24, alignment: .leading); GeometryReader { proxy in Capsule().fill(theme.chart(index).opacity(0.3)).overlay(alignment: .leading) { Capsule().fill(theme.chart(index)).frame(width: proxy.size.width * share) } }.frame(height: 8); Text(WorkoutLoadCopy.duration(duration)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).frame(width: 54, alignment: .trailing); Text(WorkoutLoadCopy.share(share)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).frame(width: 38, alignment: .trailing) } }
}

private struct AerobicCard: View {
    @Environment(\.theme) private var theme
    let aerobic: VitalModels.AerobicEfficiencySnapshot
    var body: some View { Card { HStack { SectionHeader(WorkoutLoadCopy.aerobic, icon: "lungs.fill"); Spacer(); StatusPill((aerobic.aerobicDecouplingPercentage ?? 0) <= 5 ? WorkoutLoadCopy.coupled : WorkoutLoadCopy.drift, tone: (aerobic.aerobicDecouplingPercentage ?? 0) <= 5 ? .success : .warning) }; Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text("EF").font(TypeScale.meta); Text(aerobic.efficiencyFactor.map { WorkoutLoadCopy.number($0, digits: 3) } ?? "—").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85); Text("(km/h)/bpm").font(TypeScale.meta).lineLimit(1); Text("Pa:Hr \(WorkoutLoadCopy.number(aerobic.aerobicDecouplingPercentage ?? 0))%").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.success) } }; CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text("VO2max").font(TypeScale.meta); Text(aerobic.vo2Max.map { WorkoutLoadCopy.number($0) } ?? "—").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85); Text("mL/(kg·min)").font(TypeScale.meta).lineLimit(1); Text("Δ \(WorkoutLoadCopy.signed(aerobic.vo2MaxTrend ?? 0)) · \(aerobic.sampleCount) \(WorkoutLoadCopy.sampleCount)").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.success) } } } } } }
}

#Preview("Workout Load · Light") { NavigationStack { WorkoutLoadProgressionView(state: .preview()) }.designTheme(seed: .teal, neutral: .slate) }
#Preview("Workout Load · Dark") { NavigationStack { WorkoutLoadProgressionView(state: .preview()) }.preferredColorScheme(.dark).designTheme(seed: .teal, neutral: .slate) }
