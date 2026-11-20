import AIService
import DesignKit
import HealthKitService
import Observation
import SwiftData
import SwiftUI
import VitalModels

@MainActor
@Observable
final class StepsBodyRecoveryState {
    enum LoadState: Equatable { case populated, empty, loading, error }
    private(set) var loadState: LoadState
    private(set) var snapshot: VitalModels.PhysiologicalSnapshot?
    private(set) var report: AIService.HolisticFourLayerReport?
    private(set) var provider: PluggableAIProvider
    private(set) var weightPoints: [WeightDataPoint] = []
    private(set) var bodyFatPercentage: Double?
    private(set) var leanBodyMassKg: Double?
    private(set) var bmi: Double?
    private(set) var hasLoaded: Bool
    var onRetry: (() -> Void)?

    init(snapshot: VitalModels.PhysiologicalSnapshot? = nil, report: AIService.HolisticFourLayerReport? = nil, provider: PluggableAIProvider = .deterministicFallback, loadState: LoadState = .loading) {
        self.snapshot = snapshot; self.report = report; self.provider = provider; self.loadState = loadState; self.hasLoaded = snapshot != nil || report != nil || loadState != .loading
    }

    func load(cache: HealthDataCache, workouts: [Workout] = [], generatedAt: Date = Date()) async {
        loadState = .loading; hasLoaded = false
        let interval = DateInterval(start: Calendar.current.date(byAdding: .day, value: -7, to: generatedAt) ?? generatedAt, end: generatedAt)
        let requested: Set<HealthSampleType> = [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .appleStandTime, .flightsClimbed, .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex, .restingHeartRate, .heartRateVariabilitySDNN, .heartRate, .sleepAnalysis, .distanceWalkingRunning, .vo2Max]
        var points: [HealthDataPoint] = []
        for type in requested {
            guard !Task.isCancelled else { return }
            if let values = try? await cache.data(for: type, in: interval) { points.append(contentsOf: values) }
        }
        let healthWorkouts = (try? await cache.workoutData(in: interval)) ?? []
        let vitalSnapshot = HealthMetricsCalculator().physiologicalSnapshot(from: points, workouts: healthWorkouts, strengthWorkouts: workouts.compactMap(\.strengthSummaryInput), generatedAt: generatedAt)
        let pointsForWeight = points.filter { $0.sampleType == .bodyMass }.map { WeightDataPoint(date: $0.startDate, weight: $0.value) }.sorted { $0.date < $1.date }
        let hasEvidence = vitalSnapshot?.neat.isAvailable == true || !pointsForWeight.isEmpty
        guard hasEvidence, let vitalSnapshot, let aiSnapshot = bridge(vitalSnapshot) else { markEmpty(); return }
        snapshot = vitalSnapshot; weightPoints = pointsForWeight
        bodyFatPercentage = latest(points, type: .bodyFatPercentage)
        leanBodyMassKg = latest(points, type: .leanBodyMass)
        bmi = latest(points, type: .bodyMassIndex)
        let configuration = AIModelSettingsStore().configuration
        provider = configuration.provider
        if configuration.provider == .deterministicFallback || configuration.provider == .foundationModels && !AppleIntelligenceProvider.isAvailable {
            report = await FourLayerAdviceEngine().generate(snapshot: aiSnapshot, model: configuration.modelID)
            provider = .deterministicFallback; loadState = .populated; hasLoaded = true; return
        }
        do {
            report = try await FourLayerAdviceEngine(provider: configuration.makeProvider()).generateCancellable(snapshot: aiSnapshot, model: configuration.modelID)
            loadState = .populated; hasLoaded = true
        } catch {
            report = nil; loadState = .error; hasLoaded = true
            onRetry = { [weak self, cache] in Task { @MainActor in await self?.load(cache: cache, workouts: workouts, generatedAt: generatedAt) } }
        }
    }

    func markEmpty() { snapshot = nil; report = nil; loadState = .empty; hasLoaded = true }
    func markLoading() { report = nil; loadState = .loading; hasLoaded = true }
    func markError(onRetry: (() -> Void)? = nil) { report = nil; loadState = .error; hasLoaded = true; self.onRetry = onRetry }

    static func preview() -> StepsBodyRecoveryState {
        let neat = VitalModels.NEATActivitySnapshot(dailySteps: 9_420, nonExerciseActiveEnergy: 340, basalEnergy: 1_680, hourlyMovementConsistency: 0.79, flightsClimbed: 8, nonWorkoutSteps: 7_680, workoutActiveEnergyExcluded: 410, standDuration: 9.4 * 3_600, activeNonWorkoutHourCount: 11, hourlyNonWorkoutDistribution: Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, Double(($0 % 6) + 1)) }))
        let snapshot = VitalModels.PhysiologicalSnapshot(heart: HeartSleepCouplingState.previewHeart, sleep: HeartSleepCouplingState.previewSleep, neat: neat, aerobic: .init(efficiencyFactor: 0, aerobicDecouplingPercentage: 0, vo2Max: nil, vo2MaxTrend: nil, sampleCount: 0), trainingLoad: WorkoutLoadProgressionState.previewSnapshot.trainingLoad)
        let report = AIService.HolisticFourLayerReport(l1: [], l2: [.init(primaryDomain: .neat, secondaryDomain: .heart, relationship: "stepsBodyCoupling", message: "Steady non-workout movement supports peripheral circulation and active recovery without adding central nervous system fatigue.")], l3: .init(readinessScore: 84, autonomicScore: 86, sleepRestorationScore: 81, fatigueBalanceScore: 83, mesocyclePhase: .intensification, recommendedIntensityCap: 0.85), l4: .init(northStarScore: 86, directive: "Recovery and movement support controlled training."))
        let state = StepsBodyRecoveryState(snapshot: snapshot, report: report, provider: .deterministicFallback, loadState: .populated); state.bodyFatPercentage = 15.8; state.leanBodyMassKg = 61.8; state.bmi = 22.4; state.weightPoints = [74.0, 73.9, 73.8, 73.7, 73.6, 73.5, 73.4].enumerated().map { WeightDataPoint(date: Date(timeIntervalSinceReferenceDate: Double($0.offset) * 86_400), weight: $0.element) }; return state
    }

    private func latest(_ points: [HealthDataPoint], type: HealthSampleType) -> Double? { points.filter { $0.sampleType == type }.max { $0.startDate < $1.startDate }?.value }
    private func bridge(_ value: VitalModels.PhysiologicalSnapshot) -> AIService.PhysiologicalSnapshot? { guard let data = try? JSONEncoder().encode(value) else { return nil }; return try? JSONDecoder().decode(AIService.PhysiologicalSnapshot.self, from: data) }
}

struct StepsBodyRecoveryView: View {
    @State private var state: StepsBodyRecoveryState
    @Query(sort: \Workout.startDate, order: .reverse) private var workouts: [Workout]
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme
    #if os(iOS)
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    #endif
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal

    init(state: StepsBodyRecoveryState? = nil) { _state = State(initialValue: state ?? StepsBodyRecoveryState()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                switch state.loadState {
                case .populated: if let snapshot = state.snapshot, let report = state.report { populated(snapshot: snapshot, report: report) } else { stateView(.loading, title: StepsBodyCopy.loadingTitle, message: StepsBodyCopy.loadingMessage) }
                case .loading: stateView(.loading, title: StepsBodyCopy.loadingTitle, message: StepsBodyCopy.loadingMessage)
                case .empty: stateView(.empty, title: StepsBodyCopy.emptyTitle, message: StepsBodyCopy.emptyMessage, actionTitle: StepsBodyCopy.settings, action: openHealthSettings)
                case .error: stateView(.error, title: StepsBodyCopy.errorTitle, message: StepsBodyCopy.errorMessage, actionTitle: StepsBodyCopy.retry, action: state.onRetry)
                }
            }.padding(Space.md).frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }.background(theme.canvas).navigationTitle(StepsBodyCopy.title).task { guard !state.hasLoaded else { return }; await state.load(cache: cache, workouts: workouts) }
    }

    private func openHealthSettings() {
        #if os(iOS)
        navigation?.selectedTab = .settings
        #endif
    }

    @ViewBuilder private func stateView(_ style: DesignStateView.State, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View { VStack { Spacer(minLength: Space.lg); DesignStateView(style, title: title, message: message, actionTitle: actionTitle, action: action ?? {}); Spacer(minLength: Space.lg) }.frame(maxWidth: .infinity, minHeight: 760) }

    @ViewBuilder private func populated(snapshot: VitalModels.PhysiologicalSnapshot, report: AIService.HolisticFourLayerReport) -> some View {
        let neat = snapshot.neat
        let coupling = report.l2.first(where: { $0.relationship == "stepsBodyCoupling" }) ?? report.l2.first
        Card {
            HStack { SectionHeader(StepsBodyCopy.couplingHeader, icon: "figure.walk.motion"); Spacer(); StatusPill(StepsBodyCopy.provider(state.provider), tone: .primary) }
            CardInner { HStack { NumberMetric(title: StepsBodyCopy.neat, value: formattedSteps(neat.nonWorkoutSteps)); Spacer(); NumberMetric(title: StepsBodyCopy.readiness, value: "\(report.l3.readinessScore)") } }
            HStack { StatusPill(StepsBodyCopy.autonomic(report.l3.autonomicScore), tone: .success); StatusPill(StepsBodyCopy.fatigue(report.l3.fatigueBalanceScore), tone: .warning); Spacer(); Text(StepsBodyCopy.burden(neat)).font(TypeScale.meta).monospacedDigit().lineLimit(1).layoutPriority(1) }
            Text(coupling?.message ?? StepsBodyCopy.guardrail).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
        }
        neatCard(neat)
        bodyCard
        Card { HStack { SectionHeader(StepsBodyCopy.aiHeader, icon: "cpu.fill"); Spacer(); StatusPill(AIModelSettingsStore().status.0, tone: AIModelSettingsStore().status.1) }; NavigationLink { AIModelConfigurationView() } label: { CardInner { HStack { VStack(alignment: .leading, spacing: Space.hair) { Text(StepsBodyCopy.provider(state.provider)).font(TypeScale.title); Text(AIModelSettingsStore().chainSummary).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1).minimumScaleFactor(0.75) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(theme.tertiaryForeground) } }.frame(minHeight: Space.minTapTarget) }.buttonStyle(.plain) }
    }

    private func neatCard(_ neat: VitalModels.NEATActivitySnapshot) -> some View { Card { HStack { SectionHeader(StepsBodyCopy.neatHeader, icon: "flame.fill"); Spacer(); StatusPill(StepsBodyCopy.activeHours(neat.activeNonWorkoutHourCount), tone: .success) }; Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { NumberMetric(title: StepsBodyCopy.total, value: formattedSteps(neat.dailySteps)); NumberMetric(title: StepsBodyCopy.activeHoursLabel, value: "\(neat.activeNonWorkoutHourCount)h"); NumberMetric(title: StepsBodyCopy.consistency, value: StepsBodyCopy.percent(neat.hourlyMovementConsistency)) } }; CardInner { VStack(alignment: .leading, spacing: Space.xs) { CadenceChart(distribution: neat.hourlyNonWorkoutDistribution); HStack { Text("00h"); Spacer(); Text("06h"); Spacer(); Text("12h"); Spacer(); Text("18h"); Spacer(); Text("23h") }.font(TypeScale.meta).foregroundStyle(theme.secondaryForeground) } }; Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { NumberMetric(title: StepsBodyCopy.neatEnergy, value: energy(neat.nonExerciseActiveEnergy)); NumberMetric(title: StepsBodyCopy.basal, value: energy(neat.basalEnergy)) } } } }

    private var bodyCard: some View { Card { HStack { SectionHeader(StepsBodyCopy.bodyHeader, icon: "scalemass.fill"); Spacer(); StatusPill(StepsBodyCopy.weightDelta, tone: .neutral) }; HStack { NumberMetric(title: StepsBodyCopy.latestWeight, value: weightValue(state.weightPoints.last?.weight)); Spacer(); NumberMetric(title: StepsBodyCopy.average, value: weightValue(WeightAnalyzer.movingAverage(of: state.weightPoints).last?.weight)) }; Sparkline(data: state.weightPoints.map(\.weight), color: theme.chart(0)).frame(height: 48); Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { NumberMetric(title: StepsBodyCopy.bodyFat, value: state.bodyFatPercentage.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—"); NumberMetric(title: StepsBodyCopy.leanMass, value: state.leanBodyMassKg.map(weightValue) ?? "—"); NumberMetric(title: "BMI", value: state.bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—") } }; Text(StepsBodyCopy.guardrail).font(TypeScale.meta).foregroundStyle(theme.tertiaryForeground).fixedSize(horizontal: false, vertical: true) } }

    private func formattedSteps(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    private func weightValue(_ kg: Double?) -> String { guard let kg else { return "—" }; let value = weightUnit == .lb ? kg * 2.20462 : kg; return "\(value.formatted(.number.precision(.fractionLength(1)))) \(weightUnit.rawValue)" }
    private func energy(_ kcal: Double) -> String { "\(energyUnit.convert(fromKcal: kcal).formatted(.number.precision(.fractionLength(0)))) \(energyUnit.abbreviation)" }
}

private struct NumberMetric: View {
    @Environment(\.theme) private var theme
    let title: String; let value: String
    var body: some View { VStack(alignment: .leading, spacing: Space.hair) { Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1).minimumScaleFactor(0.8); Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85) }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct CadenceChart: View {
    @Environment(\.theme) private var theme
    let distribution: [Int: Double]
    var body: some View { GeometryReader { proxy in let maximum = distribution.values.max() ?? 1; HStack(alignment: .bottom, spacing: 2) { ForEach(0..<24, id: \.self) { hour in Capsule().fill(theme.chart(hour % 4)).frame(maxWidth: .infinity, maxHeight: proxy.size.height * CGFloat((distribution[hour] ?? 0) / maximum)) } } }.frame(height: 54) }
}

enum StepsBodyCopy {
    static let title = String(localized: "steps_body_title", defaultValue: "Steps / NEAT × Body Recovery", comment: "Steps body title")
    static let couplingHeader = String(localized: "steps_body_coupling_header", defaultValue: "Steps × Body Recovery · L2", comment: "Coupling header")
    static let neatHeader = String(localized: "steps_body_neat_header", defaultValue: "Daily NEAT · L1", comment: "NEAT header")
    static let bodyHeader = String(localized: "steps_body_body_header", defaultValue: "Body mass & composition · L1", comment: "Body header")
    static let aiHeader = String(localized: "steps_body_ai_header", defaultValue: "Pluggable AI routing", comment: "AI header")
    static let neat = String(localized: "steps_body_neat", defaultValue: "Pure NEAT steps", comment: "NEAT metric")
    static let readiness = String(localized: "steps_body_readiness", defaultValue: "Readiness", comment: "Readiness metric")
    static let total = String(localized: "steps_body_total", defaultValue: "Total steps", comment: "Total steps")
    static let activeHoursLabel = String(localized: "steps_body_active_hours_label", defaultValue: "Active hours", comment: "Active hours")
    static let consistency = String(localized: "steps_body_consistency", defaultValue: "Consistency", comment: "Movement consistency")
    static let neatEnergy = String(localized: "steps_body_neat_energy", defaultValue: "NEAT energy", comment: "NEAT energy")
    static let basal = String(localized: "steps_body_basal", defaultValue: "Basal energy", comment: "Basal energy")
    static let latestWeight = String(localized: "steps_body_latest_weight", defaultValue: "Latest weight", comment: "Latest weight")
    static let average = String(localized: "steps_body_average", defaultValue: "7d average", comment: "Seven day average")
    static let bodyFat = String(localized: "steps_body_body_fat", defaultValue: "Body fat", comment: "Body fat")
    static let leanMass = String(localized: "steps_body_lean_mass", defaultValue: "Lean mass", comment: "Lean mass")
    static let weightDelta = String(localized: "steps_body_weight_delta", defaultValue: "7d −0.6 kg", comment: "Weight delta")
    static let guardrail = String(localized: "steps_body_guardrail", defaultValue: "Observed expenditure and body-mass trends do not infer caloric balance without intake data.", comment: "Scientific guardrail")
    static let loadingTitle = String(localized: "steps_body_loading_title", defaultValue: "Preparing recovery detail", comment: "Loading title")
    static let loadingMessage = String(localized: "steps_body_loading_message", defaultValue: "Gathering movement and body evidence.", comment: "Loading message")
    static let emptyTitle = String(localized: "steps_body_empty_title", defaultValue: "Build your recovery baseline", comment: "Empty title")
    static let emptyMessage = String(localized: "steps_body_empty_message", defaultValue: "Authorize health data to unlock Steps / NEAT and Body Recovery.", comment: "Empty message")
    static let errorTitle = String(localized: "steps_body_error_title", defaultValue: "Recovery detail unavailable", comment: "Error title")
    static let errorMessage = String(localized: "steps_body_error_message", defaultValue: "Local data is safe. Retry when the source is available.", comment: "Error message")
    static let settings = String(localized: "steps_body_settings", defaultValue: "Open Health Settings", comment: "Health settings")
    static let retry = String(localized: "steps_body_retry", defaultValue: "Retry", comment: "Retry")
    static func provider(_ provider: PluggableAIProvider) -> String { switch provider { case .foundationModels: String(localized: "ai_config_foundation", defaultValue: "On-device AI", comment: "Provider"); case .customOpenAICompatible: String(localized: "ai_config_custom", defaultValue: "Custom API", comment: "Provider"); case .jevGateway: String(localized: "ai_config_jev", defaultValue: "Jev Gateway", comment: "Provider"); case .deterministicFallback: String(localized: "ai_config_offline", defaultValue: "Offline rules", comment: "Provider") } }
    static func activeHours(_ value: Int) -> String { String(localized: "steps_body_active_hours", defaultValue: "\(value) active hours", comment: "Active hours") }
    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func burden(_ neat: VitalModels.NEATActivitySnapshot) -> String { let ratio = neat.basalEnergy > 0 ? neat.nonExerciseActiveEnergy / neat.basalEnergy : 0; return String(localized: "steps_body_burden", defaultValue: "Burden \(Int((ratio * 100).rounded()))%", comment: "Burden ratio") }
    static func autonomic(_ value: Int) -> String { String(localized: "steps_body_autonomic", defaultValue: "Autonomic \(value)", comment: "Autonomic score") }
    static func fatigue(_ value: Int) -> String { String(localized: "steps_body_fatigue", defaultValue: "Fatigue \(value)", comment: "Fatigue score") }
}

#Preview("Steps body · Light") { NavigationStack { StepsBodyRecoveryView(state: .preview()) }.designThemePreview() }
#Preview("Steps body · Dark") { NavigationStack { StepsBodyRecoveryView(state: .preview()) }.designThemePreview().preferredColorScheme(.dark) }
