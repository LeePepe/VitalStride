// swiftlint:disable no_hardcoded_chinese
import AIService
import DesignKit
import HealthKitService
import SwiftUI
import VitalModels

@MainActor
@Observable
final class HolisticDashboardState {
    enum LoadState: Equatable {
        case loading
        case populated
        case empty
        case error
    }

    private(set) var loadState: LoadState = .loading
    private(set) var report: AIService.HolisticFourLayerReport?
    private(set) var provider: PluggableAIProvider = .deterministicFallback
    private let configuration: UserAIModelConfiguration

    init(configuration: UserAIModelConfiguration = UserAIModelConfiguration(provider: .deterministicFallback)) {
        self.configuration = configuration
        self.provider = configuration.provider
    }

    func load(
        cache: HealthDataCache,
        workouts: [Workout],
        forceRefresh: Bool = false,
        generatedAt: Date = Date()
    ) async {
        loadState = .loading
        report = nil
        let interval = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -30, to: generatedAt) ?? generatedAt,
            end: generatedAt
        )
        var points: [HealthDataPoint] = []
        let requestedTypes: Set<HealthSampleType> = [
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .sleepAnalysis, .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .appleStandTime, .flightsClimbed, .distanceWalkingRunning, .vo2Max
        ]
        for type in requestedTypes {
            let result = forceRefresh
                ? try? await cache.refresh(type, in: interval)
                : try? await cache.data(for: type, in: interval)
            points.append(contentsOf: result ?? [])
        }
        let healthWorkouts = (try? await cache.workoutData(in: interval)) ?? []
        let strengthWorkouts = workouts.compactMap(\.strengthSummaryInput)
        let calculator = HealthMetricsCalculator()
        guard let vitalSnapshot = calculator.physiologicalSnapshot(
            from: points,
            workouts: healthWorkouts,
            strengthWorkouts: strengthWorkouts,
            generatedAt: generatedAt
        ), let snapshot = bridge(vitalSnapshot) else {
            loadState = .empty
            return
        }

        let provider = configuration.makeProvider()
        let engine = FourLayerAdviceEngine(provider: provider)
        report = await engine.generate(snapshot: snapshot, model: configuration.modelID)
        loadState = .populated
    }

    static func preview() -> HolisticDashboardState {
        let state = HolisticDashboardState()
        state.report = AIService.HolisticFourLayerReport(
            l1: [],
            l2: [
                .init(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling", message: "Sleep supports controlled load."),
                .init(primaryDomain: .neat, secondaryDomain: .heart, relationship: "stepsBodyCoupling", message: "Movement supports circulation.")
            ],
            l3: .init(readinessScore: 82, autonomicScore: 84, sleepRestorationScore: 79, fatigueBalanceScore: 83, mesocyclePhase: .intensification, recommendedIntensityCap: 0.85),
            l4: .init(northStarScore: 86, directive: "Recovery and movement support controlled training today.", prioritizedActions: ["Keep the planned session at a controlled effort.", "Protect a consistent sleep opportunity tonight.", "Use easy movement breaks between focused work blocks."])
        )
        state.provider = .deterministicFallback
        state.loadState = .populated
        return state
    }

    private func bridge(_ snapshot: VitalModels.PhysiologicalSnapshot) -> AIService.PhysiologicalSnapshot? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return try? JSONDecoder().decode(AIService.PhysiologicalSnapshot.self, from: data)
    }
}

struct HolisticDashboardSection: View {
    @Environment(\.theme) private var theme
    @Environment(AppNavigation.self) private var navigation
    let state: HolisticDashboardState

    var body: some View {
        switch state.loadState {
        case .loading:
            EmptyView()
        case .empty:
            DesignStateView(
                .empty,
                title: L4Copy.emptyTitle,
                message: L4Copy.emptyMessage,
                actionTitle: L4Copy.settingsAction
            ) { navigation.selectedTab = .settings }
        case .error:
            DesignStateView(
                .error,
                title: L4Copy.errorTitle,
                message: L4Copy.errorMessage,
                actionTitle: L4Copy.retryAction
            ) {}
        case .populated:
            if let report = state.report {
                VStack(alignment: .leading, spacing: Space.lg) {
                    L4NorthStarHeroCard(report: report)
                    L3ReadinessGateCard(report: report)
                    CoreActionDirectivesCard(report: report, provider: state.provider)
                    QuickDrillDownSection()
                }
            }
        }
    }
}

private struct L4NorthStarHeroCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(L4Copy.northStar, icon: "scope")
                    Text(L4Copy.score(report.l4.northStarScore))
                        .font(TypeScale.metricXXL)
                        .monospacedDigit()
                        .layoutPriority(1)
                    Text(report.l4.directive)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                RingGauge(value: Double(report.l4.northStarScore) / 100, size: 88, stroke: 8, color: theme.accent)
            }
            HStack(spacing: Space.xs) {
                StatusPill(L4Copy.phase(report.l3.mesocyclePhase), tone: .primary)
                StatusPill(L4Copy.provider(.deterministicFallback), tone: .neutral)
            }
        }
    }
}

private struct L3ReadinessGateCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    SectionHeader(L4Copy.readiness, icon: "heart.text.square")
                    Text(L4Copy.score(report.l3.readinessScore))
                        .font(TypeScale.metricXL)
                        .monospacedDigit()
                        .layoutPriority(1)
                    StatusPill(L4Copy.gate(report.l3.readinessScore), tone: tone)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text(L4Copy.intensityCap).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                    Text(L4Copy.percent(report.l3.recommendedIntensityCap))
                        .font(TypeScale.num.weight(.semibold))
                        .monospacedDigit()
                        .layoutPriority(1)
                    ProgressView(value: report.l3.recommendedIntensityCap)
                        .tint(theme.warning)
                        .frame(width: 104)
                }
            }
            HStack(spacing: Space.sm) {
                ReadinessPillar(title: L4Copy.autonomic, value: report.l3.autonomicScore, color: theme.chart(0))
                ReadinessPillar(title: L4Copy.sleep, value: report.l3.sleepRestorationScore, color: theme.chart(1))
                ReadinessPillar(title: L4Copy.fatigue, value: report.l3.fatigueBalanceScore, color: theme.chart(2))
            }
        }
    }

    private var tone: PillTone {
        switch HolisticDashboardLogic.gate(for: report.l3.readinessScore) {
        case .prime: .success
        case .moderate: .warning
        case .recovery: .danger
        }
    }
}

private struct ReadinessPillar: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(TypeScale.meta).lineLimit(1).layoutPriority(1)
            Text("\(value)")
                .font(TypeScale.num.weight(.semibold))
                .monospacedDigit()
                .layoutPriority(1)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoreActionDirectivesCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport
    let provider: PluggableAIProvider

    var body: some View {
        Card {
            HStack {
                SectionHeader(L4Copy.actions, icon: "checkmark.seal.fill")
                Spacer()
                AIProvenanceBadge(provider: provider)
            }
            ForEach(Array(report.l4.prioritizedActions.enumerated()), id: \.offset) { index, action in
                CardInner {
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text("\(index + 1)")
                            .font(TypeScale.num.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 24, height: 24)
                            .background(theme.accentSubtle, in: Circle())
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(action).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                            if let coupling = report.l2[safe: index] {
                                StatusPill(L4Copy.coupling(coupling.relationship), tone: .neutral)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AIProvenanceBadge: View {
    let provider: PluggableAIProvider
    var body: some View { StatusPill(L4Copy.provider(provider), tone: .primary) }
}

private struct QuickDrillDownSection: View {
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(L4Copy.drillDown, icon: "arrow.forward")
            HStack(spacing: Space.sm) {
                DrillDownEntry(title: L4Copy.heartSleep, icon: "heart.text.square") { navigation.selectedTab = .data }
                DrillDownEntry(title: L4Copy.workoutLoad, icon: "figure.strengthtraining.traditional") { navigation.selectedTab = .workout }
                DrillDownEntry(title: L4Copy.stepsAI, icon: "brain") { navigation.selectedTab = .settings }
            }
        }
    }
}

private struct DrillDownEntry: View {
    @Environment(\.theme) private var theme
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Image(systemName: icon).foregroundStyle(theme.accent).accessibilityHidden(true)
                Text(title).font(TypeScale.meta).lineLimit(2).layoutPriority(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .padding(Space.sm)
            .background(theme.inner, in: RoundedRectangle(cornerRadius: Radius.inner))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner).stroke(theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Space.minTapTarget)
    }
}

enum HolisticReadinessGate: Equatable {
    case prime
    case moderate
    case recovery
}

enum HolisticDashboardLogic {
    static func gate(for score: Int) -> HolisticReadinessGate {
        switch score {
        case 75...: .prime
        case 50..<75: .moderate
        default: .recovery
        }
    }

    static func intensityPercent(_ cap: Double) -> Int { Int((min(max(cap, 0), 1) * 100).rounded()) }

    static func providerLabel(_ provider: PluggableAIProvider) -> String {
        switch provider {
        case .foundationModels: "On-device AI"
        case .customOpenAICompatible: "Custom API"
        case .jevGateway: "Jev Gateway"
        case .deterministicFallback: "Deterministic fallback"
        }
    }
}

private enum L4Copy {
    static let northStar = String(localized: "L4 Holistic North Star", defaultValue: "L4 Holistic North Star")
    static let readiness = String(localized: "Today's Body Readiness", defaultValue: "Today's Body Readiness")
    static let intensityCap = String(localized: "Recommended intensity cap", defaultValue: "Recommended intensity cap")
    static let autonomic = String(localized: "Autonomic", defaultValue: "Autonomic")
    static let sleep = String(localized: "Sleep restoration", defaultValue: "Sleep restoration")
    static let fatigue = String(localized: "Fatigue balance", defaultValue: "Fatigue balance")
    static let actions = String(localized: "Core action directives", defaultValue: "Core action directives")
    static let drillDown = String(localized: "Quick drill-down", defaultValue: "Quick drill-down")
    static let heartSleep = String(localized: "Heart & Sleep", defaultValue: "Heart & Sleep")
    static let workoutLoad = String(localized: "Workout Load & Progression", defaultValue: "Workout Load & Progression")
    static let stepsAI = String(localized: "Steps / NEAT & AI", defaultValue: "Steps / NEAT & AI")
    static let emptyTitle = String(localized: "holistic_empty_title", defaultValue: "Build your baseline")
    static let emptyMessage = String(localized: "holistic_empty_message", defaultValue: "Authorize health data or complete a workout to unlock your first synthesis.")
    static let settingsAction = String(localized: "holistic_settings_action", defaultValue: "Open Health Settings")
    static let errorTitle = String(localized: "holistic_error_title", defaultValue: "Dashboard unavailable")
    static let errorMessage = String(localized: "holistic_error_message", defaultValue: "Your local data is safe. Retry when the data source is available.")
    static let retryAction = String(localized: "holistic_retry_action", defaultValue: "Retry")

    static func score(_ value: Int) -> String { "\(value)" }
    static func percent(_ value: Double) -> String { "\(HolisticDashboardLogic.intensityPercent(value))%" }
    static func phase(_ phase: AIService.MesocyclePhase) -> String {
        switch phase {
        case .accumulation: String(localized: "Accumulation", defaultValue: "Accumulation")
        case .intensification: String(localized: "Intensification", defaultValue: "Intensification")
        case .realization: String(localized: "Realization", defaultValue: "Realization")
        case .deload: String(localized: "Deload", defaultValue: "Deload")
        }
    }
    static func gate(_ score: Int) -> String {
        switch score {
        case 75...: String(localized: "Prime", defaultValue: "Prime")
        case 50..<75: String(localized: "Moderate", defaultValue: "Moderate")
        default: String(localized: "Recovery", defaultValue: "Recovery")
        }
    }
    static func provider(_ provider: PluggableAIProvider) -> String {
        switch provider {
        case .foundationModels: String(localized: "On-device AI", defaultValue: "On-device AI")
        case .customOpenAICompatible: String(localized: "Custom API", defaultValue: "Custom API")
        case .jevGateway: String(localized: "Jev Gateway", defaultValue: "Jev Gateway")
        case .deterministicFallback: String(localized: "Deterministic fallback", defaultValue: "Deterministic fallback")
        }
    }
    static func coupling(_ relationship: String) -> String {
        relationship == "sleepTrainingCoupling"
            ? String(localized: "Sleep × Load", defaultValue: "Sleep × Load")
            : String(localized: "NEAT × Heart", defaultValue: "NEAT × Heart")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview("Holistic dashboard · Light") {
    HolisticDashboardSection(state: .preview())
        .padding()
        .designThemePreview(seed: .teal, neutral: .slate)
        .environment(AppNavigation())
}

#Preview("Holistic dashboard · Dark") {
    HolisticDashboardSection(state: .preview())
        .padding()
        .designThemePreview(seed: .teal, neutral: .slate)
        .preferredColorScheme(.dark)
        .environment(AppNavigation())
}
