import AIService
import DesignKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct FourLayerSummaryDashboard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?
    let provider: PluggableAIProvider

    init(
        report: AIService.HolisticFourLayerReport,
        snapshot: AIService.PhysiologicalSnapshot? = nil,
        provider: PluggableAIProvider = .deterministicFallback
    ) {
        self.report = report
        self.snapshot = snapshot
        self.provider = provider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            L4NorthStarDirectiveCard(report: report, provider: provider)
            L3ReadinessPeriodizationCard(report: report)
            L2CrossDomainCouplingSection(report: report)
            L1AtomicDomainSummarySection(report: report, snapshot: snapshot)
        }
    }
}

private struct L4NorthStarDirectiveCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport
    let provider: PluggableAIProvider

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(FourLayerCopy.l4Title, icon: "scope")
                    Text(FourLayerCopy.score(report.l4.northStarScore))
                        .font(TypeScale.metricXXL)
                        .foregroundStyle(theme.accent)
                        .metricIntegrity()
                    Text(report.l4.directive)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusPill(FourLayerCopy.provider(provider), tone: .primary)
                }
                Spacer(minLength: Space.xs)
                RingGauge(value: Double(report.l4.northStarScore) / 100, color: theme.accent)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(FourLayerCopy.topActions)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.secondaryForeground)
                ForEach(Array(report.l4.prioritizedActions.prefix(3).enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text("\(index + 1)")
                            .font(TypeScale.num.weight(.semibold))
                            .metricIntegrity()
                            .frame(width: 24, height: 24)
                            .background(theme.accentSubtle, in: Circle())
                        Text(action)
                            .font(TypeScale.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct L3ReadinessPeriodizationCard: View {
    @Environment(\.theme) private var theme
    let report: AIService.HolisticFourLayerReport

    var body: some View {
        Card {
            HStack(alignment: .top) {
                SectionHeader(FourLayerCopy.l3Title, icon: "calendar.badge.clock")
                Spacer()
                StatusPill(FourLayerCopy.phase(report.l3.mesocyclePhase), tone: .primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(FourLayerCopy.score(report.l3.readinessScore))
                    .font(TypeScale.metricXL)
                    .foregroundStyle(readinessColor)
                    .metricIntegrity()
                Text(FourLayerCopy.readiness)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.secondaryForeground)
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xxs) {
                    Text(FourLayerCopy.intensityCap)
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.secondaryForeground)
                    Text(FourLayerCopy.percent(report.l3.recommendedIntensityCap))
                        .font(TypeScale.display)
                        .foregroundStyle(theme.accent)
                        .metricIntegrity()
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    readinessPillar(FourLayerCopy.autonomic, report.l3.autonomicScore, theme.chart(0))
                    readinessPillar(FourLayerCopy.sleep, report.l3.sleepRestorationScore, theme.chart(1))
                    readinessPillar(FourLayerCopy.fatigue, report.l3.fatigueBalanceScore, theme.chart(2))
                }
            }
        }
    }

    @ViewBuilder
    private func readinessPillar(_ title: String, _ value: Int, _ color: Color) -> some View {
        CardInner {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(TypeScale.meta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(FourLayerCopy.score(value))
                    .font(TypeScale.display)
                    .foregroundStyle(color)
                    .metricIntegrity()
                ProgressView(value: Double(value), total: 100).tint(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessColor: Color {
        switch report.l3.readinessScore {
        case 75...: theme.success
        case 50..<75: theme.warning
        default: theme.danger
        }
    }
}

private struct L2CrossDomainCouplingSection: View {
    let report: AIService.HolisticFourLayerReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(FourLayerCopy.l2Title, icon: "arrow.triangle.2.circlepath")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(["sleepTrainingCoupling", "stepsBodyCoupling"], id: \.self) { relationship in
                    L2CouplingSummaryCard(
                        insight: report.l2.first(where: { $0.relationship == relationship }),
                        relationship: relationship
                    )
                }
            }
        }
    }
}

private struct L2CouplingSummaryCard: View {
    @Environment(\.theme) private var theme
    let insight: AIService.L2CoupledInsight?
    let relationship: String

    var body: some View {
        Card {
            HStack {
                Text(FourLayerCopy.couplingTitle(relationship))
                    .font(TypeScale.title)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.xs)
                StatusPill(FourLayerCopy.severity(insight?.severity ?? .watch), tone: tone)
            }
            Text(insight?.message ?? FourLayerCopy.missingCoupling)
                .font(TypeScale.body)
                .foregroundStyle(theme.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            PlatformHealthDetailActionButton(
                title: FourLayerCopy.detailAction,
                trend: relationship == "sleepTrainingCoupling" ? [72, 69, 74, 71, 76, 75, 78] : [62, 66, 64, 69, 71, 70, 73]
            )
        }
    }

    private var tone: PillTone {
        switch insight?.severity {
        case .normal: .success
        case .watch, .warning, .none: .warning
        case .critical: .danger
        }
    }
}

private struct L1AtomicDomainSummarySection: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(FourLayerCopy.l1Title, icon: "square.grid.2x2")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.sm)], spacing: Space.sm) {
                L1HeartAutonomicCard(report: report, snapshot: snapshot)
                L1SleepRecoveryCard(report: report, snapshot: snapshot)
                L1TrainingLoadCard(report: report, snapshot: snapshot)
                L1AerobicCapacityCard(report: report, snapshot: snapshot)
                L1DailyNEATCard(report: report, snapshot: snapshot)
            }
        }
    }
}

private struct L1HeartAutonomicCard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        let heart = snapshot?.heart
        let hrv = heart?.hrvCorridor
        let rhr = heart?.restingHeartRate
        let recovery = heart?.recovery
        let values = [hrv?.currentMilliseconds ?? metric("hrvCurrent"), hrv?.sevenDayAverageMilliseconds ?? metric("hrv7d"), rhr?.currentBPM ?? metric("restingHeartRate"), recovery?.oneMinuteDropBPM ?? metric("heartRateRecovery1m"), recovery?.twoMinuteDropBPM ?? metric("heartRateRecovery2m")]
        let corridor = if let hrv { "\(FourLayerCopy.number(hrv.lowerBoundMilliseconds))–\(FourLayerCopy.number(hrv.upperBoundMilliseconds))" } else { "—" }
        return L1DomainCard(title: FourLayerCopy.heart, verdict: verdict(for: .heart), metrics: [
            .init(title: FourLayerCopy.hrv, value: FourLayerCopy.number(values[0]), unit: "ms"),
            .init(title: FourLayerCopy.hrv7d, value: FourLayerCopy.number(values[1]), unit: "ms"),
            .init(title: FourLayerCopy.hrvCorridor, value: corridor, unit: "60d ms"),
            .init(title: FourLayerCopy.rhrCurrent, value: FourLayerCopy.number(values[2]), unit: "bpm"),
            .init(title: FourLayerCopy.rhr, value: FourLayerCopy.number(rhr?.deltaFromBaselineBPM ?? metric("rhrBaselineDelta")), unit: "Δbpm"),
            .init(title: FourLayerCopy.hrr1m, value: FourLayerCopy.number(values[3]), unit: "bpm"),
            .init(title: FourLayerCopy.hrr2m, value: FourLayerCopy.number(values[4]), unit: "bpm")
        ], trend: values.compactMap { $0 })
    }

    private func metric(_ key: String) -> Double? { report.l1.first(where: { $0.metric == key })?.value }
    private func verdict(for domain: AIService.InsightDomain) -> String { FourLayerCopy.verdict(report.l1.first(where: { $0.domain == domain })?.severity ?? .watch) }
}

private struct L1SleepRecoveryCard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        let sleep = snapshot?.sleep
        let architecture = sleep?.architecture
        let total = architecture?.totalSleepDuration ?? metric("totalSleep") ?? 1
        let deepREM = total > 0 ? ((architecture?.deepDuration ?? metric("deepSleep") ?? 0) + (architecture?.remDuration ?? metric("remSleep") ?? 0)) / total : 0
        let debt = sleep?.debt.sevenDayDebt ?? metric("sleepDebt7d") ?? 0
        let efficiency = architecture?.sleepEfficiency ?? metric("sleepEfficiency") ?? 0
        return L1DomainCard(title: FourLayerCopy.sleepRecovery, verdict: verdict, metrics: [
            .init(title: FourLayerCopy.deepRem, value: FourLayerCopy.percent(deepREM), unit: ""),
            .init(title: FourLayerCopy.sleepDebt, value: FourLayerCopy.hours(debt), unit: "h"),
            .init(title: FourLayerCopy.efficiency, value: FourLayerCopy.percent(efficiency), unit: "")
        ], trend: [deepREM * 100, efficiency * 100, max(0, 100 - debt / 3600 * 20)])
    }

    private var verdict: String { FourLayerCopy.verdict(report.l1.first(where: { $0.domain == .sleep })?.severity ?? .watch) }
    private func metric(_ key: String) -> Double? { report.l1.first(where: { $0.metric == key })?.value }
}

private struct L1TrainingLoadCard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        let load = snapshot?.trainingLoad
        let zones = snapshot?.heart.zoneDistribution
        let zoneTotal = zones?.totalDuration ?? 0
        let highIntensity = zoneTotal > 0 ? ((zones?.zone4Duration ?? 0) + (zones?.zone5Duration ?? 0)) / zoneTotal : (metric("zone4") ?? 0) + (metric("zone5") ?? 0)
        let tsb = load?.trainingStressBalance ?? metric("tsb") ?? 0
        let acwr = load?.acuteChronicWorkloadRatio ?? metric("acwr") ?? 0
        return L1DomainCard(title: FourLayerCopy.trainingLoad, verdict: verdict, metrics: [
            .init(title: FourLayerCopy.tsb, value: FourLayerCopy.signed(tsb), unit: ""),
            .init(title: FourLayerCopy.acwr, value: FourLayerCopy.decimal(acwr), unit: ""),
            .init(title: FourLayerCopy.highIntensity, value: FourLayerCopy.percent(highIntensity), unit: "")
        ], trend: [tsb, acwr * 50, highIntensity * 100])
    }

    private var verdict: String { FourLayerCopy.verdict(report.l1.first(where: { $0.domain == .trainingLoad })?.severity ?? .watch) }
    private func metric(_ key: String) -> Double? { report.l1.first(where: { $0.metric == key })?.value }
}

private struct L1AerobicCapacityCard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        let aerobic = snapshot?.aerobic
        let vo2 = aerobic?.vo2Max ?? metric("vo2Max") ?? 0
        let trend = aerobic?.vo2MaxTrend ?? metric("vo2MaxTrend") ?? 0
        let efficiency = aerobic?.efficiencyFactor ?? metric("efficiencyFactor") ?? 0
        let decoupling = aerobic?.aerobicDecouplingPercentage ?? metric("aerobicDecouplingPercentage") ?? 0
        return L1DomainCard(title: FourLayerCopy.aerobic, verdict: verdict, metrics: [
            .init(title: FourLayerCopy.vo2max, value: FourLayerCopy.number(vo2), unit: "mL/kg·min"),
            .init(title: FourLayerCopy.vo2Trend, value: FourLayerCopy.signed(trend), unit: "Δ"),
            .init(title: FourLayerCopy.efficiencyFactor, value: FourLayerCopy.decimal(efficiency), unit: "EF"),
            .init(title: FourLayerCopy.decoupling, value: FourLayerCopy.percent(decoupling / 100), unit: "Pa:Hr")
        ], trend: [vo2, vo2 + trend, max(0, 100 - decoupling)])
    }

    private var verdict: String { FourLayerCopy.verdict(report.l1.first(where: { $0.domain == .aerobic })?.severity ?? .watch) }
    private func metric(_ key: String) -> Double? { report.l1.first(where: { $0.metric == key })?.value }
}

private struct L1DailyNEATCard: View {
    let report: AIService.HolisticFourLayerReport
    let snapshot: AIService.PhysiologicalSnapshot?

    var body: some View {
        let neat = snapshot?.neat
        let steps = neat?.nonWorkoutSteps ?? metric("nonWorkoutSteps") ?? 0
        let uniformity = neat?.hourlyMovementConsistency ?? metric("hourlyMovementConsistency") ?? 0
        let hours = neat?.activeNonWorkoutHourCount ?? Int(metric("activeNonWorkoutHours") ?? 0)
        return L1DomainCard(title: FourLayerCopy.neat, verdict: verdict, metrics: [
            .init(title: FourLayerCopy.nonWorkoutSteps, value: FourLayerCopy.number(steps, digits: 0), unit: "steps"),
            .init(title: FourLayerCopy.uniformity, value: FourLayerCopy.percent(uniformity), unit: ""),
            .init(title: FourLayerCopy.activeHours, value: FourLayerCopy.number(Double(hours), digits: 0), unit: "h")
        ], trend: [steps / 100, uniformity * 100, Double(hours) * 4])
    }

    private var verdict: String { FourLayerCopy.verdict(report.l1.first(where: { $0.domain == .neat })?.severity ?? .watch) }
    private func metric(_ key: String) -> Double? { report.l1.first(where: { $0.metric == key })?.value }
}

private struct L1Metric: Sendable {
    let title: String
    let value: String
    let unit: String
}

private struct L1DomainCard: View {
    let title: String
    let verdict: String
    let metrics: [L1Metric]
    let trend: [Double]

    var body: some View {
        Card {
            HStack {
                SectionHeader(title, icon: "waveform.path.ecg")
                Spacer(minLength: Space.xs)
                StatusPill(verdict, tone: .neutral)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], spacing: Space.xs) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                    CardInner {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(metric.title)
                                .font(TypeScale.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(metric.value)
                                .font(TypeScale.num)
                                .metricIntegrity()
                            if !metric.unit.isEmpty {
                                Text(metric.unit).font(TypeScale.meta).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            PlatformHealthDetailActionButton(title: FourLayerCopy.detailAction, trend: trend)
        }
    }
}

struct PlatformHealthDetailActionButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    let title: String
    let trend: [Double]
    @State private var showFallback = false
    @State private var showTrend = false

    var body: some View {
        #if os(iOS)
        Button {
            guard let url = URL(string: "x-apple-health://") else { return }
            if UIApplication.shared.canOpenURL(url) {
                openURL(url)
            } else {
                showFallback = true
            }
        } label: {
            Label(title, systemImage: "arrow.up.right.square")
                .font(TypeScale.meta.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .alert(FourLayerCopy.healthUnavailable, isPresented: $showFallback) {
            Button(FourLayerCopy.dismiss, role: .cancel) {}
        } message: {
            Text(FourLayerCopy.healthUnavailableMessage)
        }
        #else
        Button {
            showTrend = true
        } label: {
            Label(FourLayerCopy.macTrendAction, systemImage: "chart.bar.xaxis")
                .font(TypeScale.meta.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTrend) {
            Compact7DayTrendPopover(values: trend)
                .padding(Space.md)
                .frame(width: 320, height: 260)
        }
        #endif
    }
}

struct Compact7DayTrendPopover: View {
    @Environment(\.theme) private var theme
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(FourLayerCopy.trendTitle, icon: "chart.bar.xaxis")
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: Space.xxs) {
                    ForEach(Array(normalizedValues.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(theme.chart(0))
                            .frame(maxWidth: .infinity, maxHeight: max(4, proxy.size.height * value))
                    }
                }
            }
            .frame(height: 96)
            HStack(spacing: Space.sm) {
                trendStat(FourLayerCopy.average, average)
                trendStat(FourLayerCopy.minimum, minimum)
                trendStat(FourLayerCopy.maximum, maximum)
            }
        }
        .padding(Space.sm)
        .background(theme.surface)
    }

    @ViewBuilder
    private func trendStat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
            Text(FourLayerCopy.number(value))
                .font(TypeScale.num)
                .metricIntegrity()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cleanValues: [Double] {
        let cleaned = values.filter { $0.isFinite && $0 >= 0 }
        return cleaned.isEmpty ? [0] : Array(cleaned.prefix(7))
    }

    private var minimum: Double { cleanValues.min() ?? 0 }
    private var maximum: Double { cleanValues.max() ?? 0 }
    private var average: Double { cleanValues.reduce(0, +) / Double(cleanValues.count) }
    private var normalizedValues: [Double] {
        let maxValue = max(maximum, 1)
        return cleanValues.map { min(max($0 / maxValue, 0), 1) }
    }
}

private extension View {
    @ViewBuilder
    func metricIntegrity() -> some View {
        self
            .monospacedDigit()
            .lineLimit(1)
            .layoutPriority(1)
            .minimumScaleFactor(0.85)
    }
}

private enum FourLayerCopy {
    static let l1Title = String(localized: "four_layer_l1_title", defaultValue: "L1 Atomic domain summaries", comment: "L1 aggregate domain section title")
    static let l2Title = String(localized: "four_layer_l2_title", defaultValue: "L2 Cross-domain coupling", comment: "L2 aggregate coupling section title")
    static let l3Title = String(localized: "four_layer_l3_title", defaultValue: "L3 Readiness and periodization", comment: "L3 readiness section title")
    static let l4Title = String(localized: "four_layer_l4_title", defaultValue: "L4 North Star directive", comment: "L4 north star section title")
    static let topActions = String(localized: "four_layer_top_actions", defaultValue: "Top priorities", comment: "L4 action list title")
    static let readiness = String(localized: "four_layer_readiness", defaultValue: "Readiness", comment: "Readiness score label")
    static let autonomic = String(localized: "four_layer_autonomic", defaultValue: "Autonomic", comment: "Readiness pillar")
    static let sleep = String(localized: "four_layer_sleep", defaultValue: "Sleep restoration", comment: "Readiness pillar")
    static let fatigue = String(localized: "four_layer_fatigue", defaultValue: "Fatigue balance", comment: "Readiness pillar")
    static let intensityCap = String(localized: "four_layer_intensity_cap", defaultValue: "Intensity cap", comment: "Intensity cap label")
    static let heart = String(localized: "four_layer_heart", defaultValue: "Heart autonomic", comment: "L1 heart card title")
    static let sleepRecovery = String(localized: "four_layer_sleep_recovery", defaultValue: "Sleep recovery", comment: "L1 sleep card title")
    static let trainingLoad = String(localized: "four_layer_training_load", defaultValue: "Training load", comment: "L1 training card title")
    static let aerobic = String(localized: "four_layer_aerobic", defaultValue: "Aerobic capacity", comment: "L1 aerobic card title")
    static let neat = String(localized: "four_layer_neat", defaultValue: "Daily NEAT", comment: "L1 NEAT card title")
    static let hrv = String(localized: "four_layer_hrv", defaultValue: "HRV current", comment: "HRV metric")
    static let hrv7d = String(localized: "four_layer_hrv_7d", defaultValue: "HRV 7d", comment: "HRV seven-day metric")
    static let hrvCorridor = String(localized: "four_layer_hrv_corridor", defaultValue: "HRV corridor", comment: "HRV corridor metric")
    static let rhrCurrent = String(localized: "four_layer_rhr_current", defaultValue: "RHR current", comment: "Resting heart rate current")
    static let rhr = String(localized: "four_layer_rhr", defaultValue: "RHR Δ", comment: "Resting heart rate delta")
    static let hrr1m = String(localized: "four_layer_hrr_1m", defaultValue: "HRR 1m", comment: "Heart rate recovery one minute")
    static let hrr2m = String(localized: "four_layer_hrr_2m", defaultValue: "HRR 2m", comment: "Heart rate recovery two minute")
    static let deepRem = String(localized: "four_layer_deep_rem", defaultValue: "Deep + REM", comment: "Sleep stage share")
    static let sleepDebt = String(localized: "four_layer_sleep_debt", defaultValue: "Sleep debt 7d", comment: "Sleep debt metric")
    static let efficiency = String(localized: "four_layer_efficiency", defaultValue: "Efficiency", comment: "Sleep efficiency metric")
    static let tsb = String(localized: "four_layer_tsb", defaultValue: "TSB", comment: "Training stress balance")
    static let acwr = String(localized: "four_layer_acwr", defaultValue: "ACWR", comment: "Acute chronic workload ratio")
    static let highIntensity = String(localized: "four_layer_high_intensity", defaultValue: "Zone 4–5", comment: "High intensity share")
    static let vo2max = String(localized: "four_layer_vo2max", defaultValue: "VO2max", comment: "Aerobic capacity metric")
    static let vo2Trend = String(localized: "four_layer_vo2_trend", defaultValue: "VO2max trend", comment: "VO2max trajectory")
    static let efficiencyFactor = String(localized: "four_layer_ef", defaultValue: "Efficiency factor", comment: "Aerobic efficiency factor")
    static let decoupling = String(localized: "four_layer_decoupling", defaultValue: "Pa:Hr decoupling", comment: "Aerobic decoupling")
    static let nonWorkoutSteps = String(localized: "four_layer_non_workout_steps", defaultValue: "Non-workout steps", comment: "NEAT metric")
    static let uniformity = String(localized: "four_layer_uniformity", defaultValue: "Hourly uniformity", comment: "NEAT metric")
    static let activeHours = String(localized: "four_layer_active_hours", defaultValue: "Active hours", comment: "NEAT metric")
    static let detailAction = String(localized: "four_layer_health_detail", defaultValue: "View details in Apple Health ↗", comment: "Health detail deep link")
    static let macTrendAction = String(localized: "four_layer_mac_trend", defaultValue: "7-day summary trend ↗", comment: "macOS aggregate trend action")
    static let trendTitle = String(localized: "four_layer_trend_title", defaultValue: "7-day aggregate trend", comment: "macOS aggregate trend popover title")
    static let average = String(localized: "four_layer_average", defaultValue: "Avg", comment: "Trend average")
    static let minimum = String(localized: "four_layer_minimum", defaultValue: "Min", comment: "Trend minimum")
    static let maximum = String(localized: "four_layer_maximum", defaultValue: "Max", comment: "Trend maximum")
    static let healthUnavailable = String(localized: "four_layer_health_unavailable", defaultValue: "Apple Health is unavailable", comment: "Health deep link fallback title")
    static let healthUnavailableMessage = String(localized: "four_layer_health_unavailable_message", defaultValue: "Open Apple Health on a supported device to view detail.", comment: "Health deep link fallback message")
    static let dismiss = String(localized: "four_layer_dismiss", defaultValue: "Dismiss", comment: "Dismiss fallback alert")
    static let missingCoupling = String(localized: "four_layer_missing_coupling", defaultValue: "Coupling evidence is incomplete; keep the next effort conservative.", comment: "Missing coupling message")

    static func score(_ value: Int) -> String { "\(min(max(value, 0), 100))" }
    static func number(_ value: Double?, digits: Int = 0) -> String { guard let value, value.isFinite else { return "—" }; return value.formatted(.number.precision(.fractionLength(digits))) }
    static func decimal(_ value: Double?) -> String { number(value, digits: 2) }
    static func signed(_ value: Double?) -> String { guard let value, value.isFinite else { return "—" }; return value >= 0 ? "+\(number(value, digits: 1))" : number(value, digits: 1) }
    static func percent(_ value: Double) -> String { "\(Int((min(max(value, 0), 1) * 100).rounded()))%" }
    static func hours(_ seconds: Double) -> String { number(seconds / 3600, digits: 1) }
    static func phase(_ phase: AIService.MesocyclePhase) -> String {
        switch phase {
        case .accumulation: String(localized: "four_layer_phase_accumulation", defaultValue: "Accumulation", comment: "Mesocycle phase")
        case .intensification: String(localized: "four_layer_phase_intensification", defaultValue: "Intensification", comment: "Mesocycle phase")
        case .realization: String(localized: "four_layer_phase_realization", defaultValue: "Realization", comment: "Mesocycle phase")
        case .deload: String(localized: "four_layer_phase_deload", defaultValue: "Deload", comment: "Mesocycle phase")
        }
    }
    static func provider(_ provider: PluggableAIProvider) -> String {
        switch provider {
        case .foundationModels: String(localized: "four_layer_provider_foundation", defaultValue: "On-device AI", comment: "AI provider provenance")
        case .customOpenAICompatible: String(localized: "four_layer_provider_custom", defaultValue: "Custom API", comment: "AI provider provenance")
        case .jevGateway: String(localized: "four_layer_provider_jev", defaultValue: "Jev Gateway", comment: "AI provider provenance")
        case .deterministicFallback: String(localized: "four_layer_provider_fallback", defaultValue: "Deterministic fallback", comment: "AI provider provenance")
        }
    }
    static func couplingTitle(_ relationship: String) -> String { relationship == "sleepTrainingCoupling" ? String(localized: "four_layer_sleep_training", defaultValue: "Sleep × training load", comment: "L2 coupling title") : String(localized: "four_layer_steps_body", defaultValue: "Daily NEAT × body recovery", comment: "L2 coupling title") }
    static func severity(_ severity: AIService.InsightSeverity) -> String {
        switch severity {
        case .normal: String(localized: "four_layer_severity_normal", defaultValue: "Normal", comment: "L2/L1 severity")
        case .watch: String(localized: "four_layer_severity_watch", defaultValue: "Watch", comment: "L2/L1 severity")
        case .warning: String(localized: "four_layer_severity_warning", defaultValue: "Warning", comment: "L2/L1 severity")
        case .critical: String(localized: "four_layer_severity_critical", defaultValue: "Critical", comment: "L2/L1 severity")
        }
    }
    static func verdict(_ severity: AIService.InsightSeverity) -> String {
        switch severity {
        case .normal: String(localized: "four_layer_verdict_normal", defaultValue: "Stable", comment: "L1 qualitative verdict")
        case .watch: String(localized: "four_layer_verdict_watch", defaultValue: "Watch", comment: "L1 qualitative verdict")
        case .warning: String(localized: "four_layer_verdict_warning", defaultValue: "Strain", comment: "L1 qualitative verdict")
        case .critical: String(localized: "four_layer_verdict_critical", defaultValue: "Recovery priority", comment: "L1 qualitative verdict")
        }
    }
}
