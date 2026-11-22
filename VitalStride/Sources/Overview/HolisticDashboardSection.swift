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
    private(set) var snapshot: AIService.PhysiologicalSnapshot?
    private(set) var provider: PluggableAIProvider
    private(set) var isRefreshing: Bool = false
    private let configuration: UserAIModelConfiguration

    init(configuration: UserAIModelConfiguration? = nil) {
        let resolved = configuration ?? Self.resolveConfiguration()
        self.configuration = resolved
        self.provider = resolved.provider
    }

    static func resolveConfiguration(
        defaults: UserDefaults = .standard,
        keychain: KeychainHelper = KeychainHelper()
    ) -> UserAIModelConfiguration {
        if let data = defaults.data(forKey: "userAIModelConfiguration"),
           let stored = try? JSONDecoder().decode(UserAIModelConfiguration.self, from: data) {
            return stored
        }
        if AIModelSettingsStore.isFoundationModelsAvailable {
            return UserAIModelConfiguration(provider: .foundationModels)
        }
        let apiKeyService = "\(KeychainHelper.defaultServicePrefix).apikey"
        if AIModelSettingsStore.hasSecretCached(for: apiKeyService, keychain: keychain) {
            return UserAIModelConfiguration(
                provider: .customOpenAICompatible,
                baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4"),
                modelID: "glm-4-flash",
                keychainService: apiKeyService
            )
        }
        return UserAIModelConfiguration(provider: .deterministicFallback)
    }

    func load(
        cache: HealthDataCache,
        workouts: [Workout],
        forceRefresh: Bool = false,
        generatedAt: Date = Date()
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if report == nil {
            loadState = .loading
        }
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
            guard !Task.isCancelled else { return }
            let result = forceRefresh
                ? try? await cache.refresh(type, in: interval)
                : try? await cache.data(for: type, in: interval)
            points.append(contentsOf: result ?? [])
        }
        let healthWorkouts = (try? await cache.workoutData(in: interval)) ?? []
        let strengthWorkouts = workouts.compactMap(\.strengthSummaryInput)
        guard let snapshot = await Self.synthesizeSnapshotOffMainActor(
            points: points,
            workouts: healthWorkouts,
            strengthWorkouts: strengthWorkouts,
            generatedAt: generatedAt
        ) else {
            report = nil
            self.snapshot = nil
            loadState = .empty
            return
        }

        self.snapshot = snapshot
        guard isProviderAvailable else {
            report = await FourLayerAdviceEngine().generate(snapshot: snapshot, model: configuration.modelID)
            provider = .deterministicFallback
            loadState = .populated
            return
        }
        let provider = configuration.makeProvider()
        let engine = FourLayerAdviceEngine(provider: provider)
        if configuration.provider == .deterministicFallback {
            report = await engine.generate(snapshot: snapshot, model: configuration.modelID)
            self.provider = .deterministicFallback
        } else {
            do {
                report = try await engine.generateCancellable(snapshot: snapshot, model: configuration.modelID)
                self.provider = configuration.provider
            } catch {
                report = await FourLayerAdviceEngine().generate(snapshot: snapshot, model: configuration.modelID)
                self.provider = .deterministicFallback
                loadState = .error
                return
            }
        }
        loadState = .populated
    }

    nonisolated private static func synthesizeSnapshotOffMainActor(
        points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord],
        strengthWorkouts: [VitalModels.StrengthWorkoutSummaryInput],
        generatedAt: Date
    ) async -> AIService.PhysiologicalSnapshot? {
        let calculator = HealthMetricsCalculator()
        guard let vitalSnapshot = calculator.physiologicalSnapshot(
            from: points,
            workouts: workouts,
            strengthWorkouts: strengthWorkouts,
            generatedAt: generatedAt
        ),
        let data = try? JSONEncoder().encode(vitalSnapshot) else {
            return nil
        }
        return try? JSONDecoder().decode(AIService.PhysiologicalSnapshot.self, from: data)
    }

    func markError() {
        report = nil
        snapshot = nil
        loadState = .error
    }

    func markEmpty() {
        report = nil
        snapshot = nil
        loadState = .empty
    }

    func markLoading() {
        report = nil
        snapshot = nil
        loadState = .loading
    }

    static func preview() -> HolisticDashboardState {
        let state = HolisticDashboardState()
        state.snapshot = nil
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

    private var isProviderAvailable: Bool {
        switch configuration.provider {
        case .foundationModels:
            return AIModelSettingsStore.isFoundationModelsAvailable
        case .deterministicFallback:
            return true
        case .customOpenAICompatible, .jevGateway:
            guard let baseURL = configuration.baseURL,
                  ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""),
                  baseURL.host != nil,
                  let modelID = configuration.modelID,
                  !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if configuration.provider == .jevGateway, configuration.allowsUnauthenticatedGateway { return true }
            guard let service = configuration.keychainService else { return false }
            return AIModelSettingsStore.hasSecretCached(for: service)
        }
    }
}

struct HolisticDashboardSection: View {
    @Environment(AppNavigation.self) private var navigation
    let state: HolisticDashboardState
    var onRetry: (() -> Void)? = nil

    var body: some View {
        switch state.loadState {
        case .loading:
            centeredState(.loading, title: L4Copy.loadingTitle, message: L4Copy.loadingMessage)
        case .empty:
            centeredState(.empty, title: L4Copy.emptyTitle, message: L4Copy.emptyMessage, actionTitle: L4Copy.settingsAction) {
                navigation.selectedTab = .settings
            }
        case .error:
            centeredState(.error, title: L4Copy.errorTitle, message: L4Copy.errorMessage, actionTitle: L4Copy.retryAction, action: onRetry)
        case .populated:
            if let report = state.report {
                FourLayerSummaryDashboard(
                    report: report,
                    snapshot: state.snapshot,
                    provider: state.provider
                )
                QuickDrillDownSection()
            }
        }
    }

    @ViewBuilder
    private func centeredState(
        _ style: DesignStateView.State,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack {
            Spacer(minLength: Space.lg)
            DesignStateView(style, title: title, message: message, actionTitle: actionTitle, action: action ?? {})
            Spacer(minLength: Space.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 780)
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
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(report.l4.directive)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                ScoreArcView(score: report.l4.northStarScore, color: theme.accent)
            }
            StatusPill(L4Copy.phase(report.l3.mesocyclePhase), tone: .primary)
        }
    }
}

private struct ScoreArcView: View {
    @Environment(\.theme) private var theme
    let score: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(theme.border, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(min(max(score, 0), 100))")
                .font(TypeScale.display)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(width: 88, height: 88)
        .accessibilityLabel(L4Copy.score(score))
    }
}

private struct L3ReadinessGateCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport

    var body: some View {
        Card {
            SectionHeader(L4Copy.readiness, icon: "heart.text.square")
            CardInner {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(L4Copy.readinessScore).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Text(L4Copy.score(report.l3.readinessScore))
                            .font(TypeScale.metricXL)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                        StatusPill(L4Copy.gate(report.l3.readinessScore), tone: tone)
                    }
                    Spacer(minLength: Space.sm)
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Text(L4Copy.intensityCap).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Text(L4Copy.percent(report.l3.recommendedIntensityCap))
                            .font(TypeScale.display)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                        ProgressView(value: min(max(report.l3.recommendedIntensityCap, 0), 1))
                            .tint(theme.warning)
                            .frame(width: 104)
                    }
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    ReadinessPillar(title: L4Copy.autonomic, value: report.l3.autonomicScore, color: theme.chart(0))
                    ReadinessPillar(title: L4Copy.sleep, value: report.l3.sleepRestorationScore, color: theme.chart(1))
                    ReadinessPillar(title: L4Copy.fatigue, value: report.l3.fatigueBalanceScore, color: theme.chart(2))
                }
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
    @Environment(\.theme) private var theme
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        CardInner {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(TypeScale.meta).lineLimit(1).minimumScaleFactor(0.85).layoutPriority(1)
                Text("\(value)")
                    .font(TypeScale.display)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
                    .foregroundStyle(color)
                ProgressView(value: Double(value), total: 100).tint(color)
            }
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
                            Text(action)
                                .font(TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            if let coupling = report.l2[safe: index] {
                                StatusPill(L4Copy.coupling(coupling.relationship), tone: .neutral)
                            }
                        }
                    }
                }
            }
            CardInner {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(L4Copy.couplingSummary).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                    ForEach(report.l2.prefix(2), id: \.relationship) { coupling in
                        HStack(alignment: .top, spacing: Space.xs) {
                            StatusPill(L4Copy.coupling(coupling.relationship), tone: .neutral)
                            Text(coupling.message)
                                .font(TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
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
            DrillDownEntry(title: L4Copy.heartSleep, subtitle: L4Copy.heartSleepSubtitle, icon: "heart.text.square") { navigation.selectedTab = .data }
            DrillDownEntry(title: L4Copy.workoutLoad, subtitle: L4Copy.workoutLoadSubtitle, icon: "figure.strengthtraining.traditional") { navigation.selectedTab = .workout; navigation.showWorkoutLoadProgression = true }
            DrillDownEntry(title: L4Copy.stepsAI, subtitle: L4Copy.stepsAISubtitle, icon: "brain") { navigation.selectedTab = .settings; navigation.showStepsBodySettings = true }
        }
    }
}

private struct DrillDownEntry: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: icon).foregroundStyle(theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(TypeScale.title).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.tertiaryForeground)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
            .padding(.horizontal, Space.sm)
            .background(theme.inner, in: RoundedRectangle(cornerRadius: Radius.inner))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner).stroke(theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

enum L4Copy {
    static let northStar = String(localized: "holistic_north_star", defaultValue: "L4 Holistic North Star")
    static let readiness = String(localized: "holistic_readiness", defaultValue: "Today's Body Readiness")
    static let readinessScore = String(localized: "holistic_readiness_score", defaultValue: "Readiness score")
    static let intensityCap = String(localized: "holistic_intensity_cap", defaultValue: "Recommended intensity cap")
    static let autonomic = String(localized: "holistic_autonomic", defaultValue: "Autonomic")
    static let sleep = String(localized: "holistic_sleep_restoration", defaultValue: "Sleep restoration")
    static let fatigue = String(localized: "holistic_fatigue_balance", defaultValue: "Fatigue balance")
    static let actions = String(localized: "holistic_core_actions", defaultValue: "Core action directives")
    static let couplingSummary = String(localized: "holistic_coupling_summary", defaultValue: "L2 coupling summary")
    static let drillDown = String(localized: "holistic_quick_drill_down", defaultValue: "Quick drill-down")
    static let heartSleep = String(localized: "holistic_heart_sleep", defaultValue: "Heart & Sleep")
    static let heartSleepSubtitle = String(localized: "holistic_heart_sleep_subtitle", defaultValue: "HRV corridor · resting heart rate · sleep debt")
    static let workoutLoad = String(localized: "holistic_workout_load", defaultValue: "Workout Load & Progression")
    static let workoutLoadSubtitle = String(localized: "holistic_workout_load_subtitle", defaultValue: "ATL / CTL / TSB · mesocycle progress")
    static let stepsAI = String(localized: "holistic_steps_ai", defaultValue: "Steps / NEAT & AI")
    static let stepsAISubtitle = String(localized: "holistic_steps_ai_subtitle", defaultValue: "NEAT steps · active AI provider")
    static let loadingTitle = String(localized: "holistic_loading_title", defaultValue: "Preparing your dashboard")
    static let loadingMessage = String(localized: "holistic_loading_message", defaultValue: "Gathering available domains.")
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
        case .accumulation: String(localized: "holistic_phase_accumulation", defaultValue: "Accumulation")
        case .intensification: String(localized: "holistic_phase_intensification", defaultValue: "Intensification")
        case .realization: String(localized: "holistic_phase_realization", defaultValue: "Realization")
        case .deload: String(localized: "holistic_phase_deload", defaultValue: "Deload")
        }
    }
    static func gate(_ score: Int) -> String {
        switch score {
        case 75...: String(localized: "holistic_gate_prime", defaultValue: "Prime")
        case 50..<75: String(localized: "holistic_gate_moderate", defaultValue: "Moderate")
        default: String(localized: "holistic_gate_recovery", defaultValue: "Recovery")
        }
    }
    static func provider(_ provider: PluggableAIProvider) -> String {
        switch provider {
        case .foundationModels: String(localized: "holistic_provider_foundation", defaultValue: "On-device AI")
        case .customOpenAICompatible: String(localized: "holistic_provider_custom", defaultValue: "Custom API")
        case .jevGateway: String(localized: "holistic_provider_jev", defaultValue: "Jev Gateway")
        case .deterministicFallback: String(localized: "holistic_provider_fallback", defaultValue: "Deterministic fallback")
        }
    }
    static func coupling(_ relationship: String) -> String {
        relationship == "sleepTrainingCoupling"
            ? String(localized: "holistic_coupling_sleep_load", defaultValue: "Sleep × Load")
            : String(localized: "holistic_coupling_neat_heart", defaultValue: "NEAT × Heart")
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
