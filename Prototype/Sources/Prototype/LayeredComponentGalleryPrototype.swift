// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

public enum LayeredComponentLayer: Int, CaseIterable, Identifiable, Sendable {
    case l1 = 1
    case l2 = 2
    case l3 = 3
    case l4 = 4

    public var id: Int { rawValue }
    public var slug: String {
        switch self {
        case .l1: "vs-l1-atomic-domain-cards"
        case .l2: "vs-l2-cross-domain-coupling-cards"
        case .l3: "vs-l3-readiness-periodization-cards"
        case .l4: "vs-l4-north-star-directive-cards"
        }
    }
}

public struct LayeredComponentGalleryPreviewData: Sendable, Equatable {
    public let state: VitalStridePreviewDataState
    public let layer: LayeredComponentLayer
    public let variant: Int
    public let domainMetrics: [[String]]
    public let couplingMessages: [String]
    public let readiness: [String]
    public let actions: [String]

    public init(layer: LayeredComponentLayer, variant: Int, state: VitalStridePreviewDataState) {
        self.layer = layer
        self.variant = min(max(variant, 1), 10)
        self.state = state
        self.domainMetrics = [
            ["HRV 68 ms", "HRV 7d 65 ms", "RHR Δ −3 bpm", "HRR 1m −32 bpm", "HRR 2m −49 bpm"],
            ["Deep + REM 47%", "Sleep debt 1.4 h", "Efficiency 92%"],
            ["TSB +6.3", "ACWR 0.90", "Zone 4–5 17%"],
            ["VO2max 51.4", "Trend +1.8", "EF 0.086", "Pa:Hr 3.4%"],
            ["NEAT 7,680 steps", "Uniformity 79%", "Active hours 11 h"]
        ]
        self.couplingMessages = [
            "Sleep × training load · Deep+REM 47% & debt 1.4h support a controlled 85% cap session.",
            "Daily NEAT × body recovery · 7,680 non-workout steps support circulation without CNS strain."
        ]
        self.readiness = ["Readiness 84", "Autonomic 86", "Sleep restoration 81", "Fatigue balance 83", "Intensification", "Cap 85%"]
        self.actions = [
            "Keep the planned session controlled within the 85% intensity cap.",
            "Protect a consistent 8h sleep opportunity to trim 1.4h debt.",
            "Use easy NEAT movement breaks across 11+ active hours."
        ]
    }
}

private enum L1FixtureTone: Sendable {
    case primary, success, warning

    var pillTone: PillTone {
        switch self {
        case .primary: .primary
        case .success: .success
        case .warning: .warning
        }
    }
}

private struct L1DomainFixture: Identifiable, Sendable {
    let id: Int
    let title: String
    let cnTitle: String
    let icon: String
    let heroValue: String
    let heroLabel: String
    let secondaryA: (String, String)
    let secondaryB: (String, String)
    let tertiary: (String, String)
    let verdict: String
    let interpretation: String
    let fixtureTone: L1FixtureTone
    let ratio: Double
    let deviation: Double // -1.0 ... 1.0
    let deviationText: String
    let sparkline: [Double]

    var tone: PillTone { fixtureTone.pillTone }
}

private let canonicalL1Domains: [L1DomainFixture] = [
    L1DomainFixture(
        id: 0,
        title: "Heart Autonomic",
        cnTitle: "心率自主神经基元",
        icon: "waveform.path.ecg",
        heroValue: "68 ms",
        heroLabel: "HRV SDNN (60d 54–72)",
        secondaryA: ("7d Avg", "65 ms"),
        secondaryB: ("RHR Δ", "−3 bpm"),
        tertiary: ("HRR 1m/2m", "−32 / −49"),
        verdict: "走廊内稳态",
        interpretation: "Parasympathetic tone sits comfortably inside the 60-day personal corridor.",
        fixtureTone: .success,
        ratio: 0.78,
        deviation: 0.36,
        deviationText: "+3 ms vs 7d",
        sparkline: [61, 63, 62, 65, 64, 66, 68]
    ),
    L1DomainFixture(
        id: 1,
        title: "Sleep Recovery",
        cnTitle: "睡眠恢复基元",
        icon: "bed.double.fill",
        heroValue: "47%",
        heroLabel: "Deep + REM Share",
        secondaryA: ("7d Debt", "1.4 h"),
        secondaryB: ("Efficiency", "92%"),
        tertiary: ("Total", "7h 24m"),
        verdict: "轻度睡眠债",
        interpretation: "Restorative stages are solid at 47%, with a mild 1.4h 7-day cumulative debt.",
        fixtureTone: .warning,
        ratio: 0.92,
        deviation: -0.22,
        deviationText: "Debt −1.4 h",
        sparkline: [43, 45, 44, 48, 46, 45, 47]
    ),
    L1DomainFixture(
        id: 2,
        title: "Training Load",
        cnTitle: "训练负荷基元",
        icon: "figure.strengthtraining.traditional",
        heroValue: "+6.3",
        heroLabel: "TSB Form (CTL−ATL)",
        secondaryA: ("ACWR", "0.90"),
        secondaryB: ("Zone 4–5", "17%"),
        tertiary: ("CTL / ATL", "64.7 / 58.4"),
        verdict: "负荷甜区",
        interpretation: "Acute-to-chronic ratio 0.90 stays in the 0.80–1.30 sweet spot with positive form.",
        fixtureTone: .success,
        ratio: 0.64,
        deviation: 0.42,
        deviationText: "ACWR 0.90",
        sparkline: [1.8, 3.1, 2.4, 4.0, 5.2, 5.8, 6.3]
    ),
    L1DomainFixture(
        id: 3,
        title: "Aerobic Capacity",
        cnTitle: "有氧能力基元",
        icon: "lungs.fill",
        heroValue: "51.4",
        heroLabel: "VO2max mL/kg·min",
        secondaryA: ("Trend Δ", "+1.8"),
        secondaryB: ("EF", "0.086"),
        tertiary: ("Pa:Hr", "3.4%"),
        verdict: "有氧耦合稳固",
        interpretation: "Aerobic decoupling 3.4% stays well below the 5.0% drift ceiling.",
        fixtureTone: .primary,
        ratio: 0.84,
        deviation: 0.48,
        deviationText: "Pa:Hr 3.4%",
        sparkline: [49.6, 50.0, 50.2, 50.6, 50.9, 51.1, 51.4]
    ),
    L1DomainFixture(
        id: 4,
        title: "Daily NEAT",
        cnTitle: "日常 NEAT 基元",
        icon: "figure.walk.motion",
        heroValue: "7,680",
        heroLabel: "Non-Workout Steps",
        secondaryA: ("Uniformity", "79%"),
        secondaryB: ("Active Hrs", "11 h"),
        tertiary: ("Excluded", "1,740 steps"),
        verdict: "节律均匀活跃",
        interpretation: "11 active non-workout hours sustain daytime circulation without adding fatigue.",
        fixtureTone: .success,
        ratio: 0.79,
        deviation: 0.30,
        deviationText: "79% cadence",
        sparkline: [6800, 7100, 7420, 6950, 7510, 7390, 7680]
    )
]

public struct LayeredComponentCandidateView: View {
    public let data: LayeredComponentGalleryPreviewData
    @Environment(\.theme) private var theme

    public init(data: LayeredComponentGalleryPreviewData) {
        self.data = data
    }

    public var body: some View {
        if data.state == .populated {
            VStack(alignment: .leading, spacing: Space.sm) {
                candidateHeader
                switch data.layer {
                case .l1: l1Content
                case .l2: l2Content
                case .l3: l3Content
                case .l4: l4Content
                }
            }
            .padding(Space.md)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .topLeading)
        } else {
            LayerGalleryStateCard(state: data.state)
                .padding(Space.md)
        }
    }

    private var candidateHeader: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            SectionHeader(variantArchetypeTitle, icon: layerIcon)
            Spacer(minLength: Space.xs)
            StatusPill(String(format: "L%d-V%02d", data.layer.rawValue, data.variant), tone: .primary)
        }
    }

    // MARK: - Layer 1 (10 Distinct Topologies)

    @ViewBuilder private var l1Content: some View {
        switch data.variant {
        case 1: l1V01CorridorGaugeBentoStack
        case 2: l1V02EditorialClinicalLedger
        case 3: l1V03CompactBiometricMosaic
        case 4: l1V04ThresholdDeviationDivergingBars
        case 5: l1V05TriPillarsCapsuleDeck
        case 6: l1V06SevenDayMicroSparklineCards
        case 7: l1V07VerdictFirstCoachingCards
        case 8: l1V08SplitRingProportionInstrument
        case 9: l1V09CalmSanctuaryMinimalistStack
        default: l1V10ProSportsScienceTelemetryMatrix
        }
    }

    // L1-V01: Corridor & Gauge Bento Stack
    private var l1V01CorridorGaugeBentoStack: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    v01BentoCell(canonicalL1Domains[0])
                    v01BentoCell(canonicalL1Domains[1])
                }
                GridRow {
                    v01BentoCell(canonicalL1Domains[2])
                    v01BentoCell(canonicalL1Domains[3])
                }
            }
            let neat = canonicalL1Domains[4]
            Card {
                HStack {
                    SectionHeader(neat.cnTitle, icon: neat.icon)
                    Spacer()
                    Text(neat.heroValue).font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                    StatusPill(neat.verdict, tone: neat.tone)
                }
                CorridorCapsuleBar(progress: neat.ratio, color: theme.chart(4))
                HStack {
                    Text("\(neat.secondaryA.0) \(neat.secondaryA.1) · \(neat.secondaryB.0) \(neat.secondaryB.1) · \(neat.tertiary.0) \(neat.tertiary.1)")
                        .font(TypeScale.meta.monospacedDigit())
                        .foregroundStyle(theme.secondaryForeground)
                        .lineLimit(1)
                    Spacer()
                }
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }
        }
    }

    private func v01BentoCell(_ dom: L1DomainFixture) -> some View {
        Card {
            HStack {
                Image(systemName: dom.icon).font(.caption.bold()).foregroundStyle(theme.chart(dom.id))
                Text(dom.cnTitle).font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(dom.heroValue).font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                Spacer()
                StatusPill(dom.verdict, tone: dom.tone)
            }
            CorridorCapsuleBar(progress: dom.ratio, color: theme.chart(dom.id))
            Text("\(dom.secondaryA.0) \(dom.secondaryA.1) · \(dom.secondaryB.1)")
                .font(TypeScale.meta.monospacedDigit())
                .foregroundStyle(theme.secondaryForeground)
                .lineLimit(1)
        }
    }

    // L1-V02: Editorial Clinical Metric Ledger (Zero progress bars or rings; vertical rule split)
    private var l1V02EditorialClinicalLedger: some View {
        Card {
            SectionHeader("Clinical Dual-Column Ledger · 社论临床双栏账本", icon: "list.bullet.clipboard")
            ForEach(canonicalL1Domains) { dom in
                HStack(alignment: .center, spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dom.title.uppercased())
                            .font(TypeScale.meta.weight(.bold))
                            .foregroundStyle(theme.secondaryForeground)
                            .lineLimit(1)
                        Text(dom.heroValue)
                            .font(TypeScale.display)
                            .foregroundStyle(theme.foreground)
                            .numLock()
                    }
                    .frame(width: 104, alignment: .leading)

                    Rectangle()
                        .fill(theme.border)
                        .frame(width: 1, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(dom.secondaryA.0) \(dom.secondaryA.1)")
                                .font(TypeScale.num.weight(.semibold))
                                .numLock()
                            Spacer()
                            StatusPill(dom.verdict, tone: dom.tone)
                        }
                        HStack {
                            Text("\(dom.secondaryB.0) \(dom.secondaryB.1)")
                                .font(TypeScale.meta.monospacedDigit())
                                .foregroundStyle(theme.secondaryForeground)
                                .lineLimit(1)
                            Spacer()
                            Text(dom.tertiary.1)
                                .font(TypeScale.meta.monospacedDigit())
                                .foregroundStyle(theme.tertiaryForeground)
                                .lineLimit(1)
                        }
                    }
                }
                if dom.id < 4 {
                    Divider()
                }
            }
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // L1-V03: Compact 2×2 + 1 Biometric Mosaic
    private var l1V03CompactBiometricMosaic: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    mosaicTile(canonicalL1Domains[0])
                    mosaicTile(canonicalL1Domains[1])
                }
                GridRow {
                    mosaicTile(canonicalL1Domains[2])
                    mosaicTile(canonicalL1Domains[3])
                }
            }
            Card {
                let neat = canonicalL1Domains[4]
                HStack(alignment: .center, spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionHeader(neat.title, icon: neat.icon)
                        Text(neat.heroValue).font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                        Text("\(neat.secondaryA.1) · \(neat.secondaryB.1)").font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                    }
                    Spacer()
                    Sparkline(data: neat.sparkline, color: theme.chart(4))
                        .frame(width: 76, height: 24)
                    StatusPill(neat.verdict, tone: neat.tone)
                }
                PreviewDetailAction(label: "7 日汇总趋势 ↗")
            }
        }
    }

    private func mosaicTile(_ dom: L1DomainFixture) -> some View {
        Card {
            HStack {
                Image(systemName: dom.icon).font(.caption.bold()).foregroundStyle(theme.chart(dom.id))
                Text(dom.title).font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
            }
            Text(dom.heroValue)
                .font(TypeScale.display)
                .foregroundStyle(theme.foreground)
                .numLock()
            Sparkline(data: dom.sparkline, color: theme.chart(dom.id))
                .frame(height: 20)
            HStack {
                Text(dom.secondaryA.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                Spacer()
                StatusPill(dom.verdict, tone: dom.tone)
            }
        }
    }

    // L1-V04: Threshold Deviation Diverging Bars
    private var l1V04ThresholdDeviationDivergingBars: some View {
        Card {
            SectionHeader("L1 Baseline Deviation Scale · 基线偏离双向刻度", icon: "slider.horizontal.below.rectangle")
            ForEach(canonicalL1Domains) { dom in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label(dom.cnTitle, systemImage: dom.icon)
                            .font(TypeScale.meta.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(dom.deviationText)
                            .font(TypeScale.num.weight(.bold))
                            .foregroundStyle(dom.deviation >= 0 ? theme.success : theme.warning)
                            .numLock()
                        StatusPill(dom.verdict, tone: dom.tone)
                    }
                    DivergingTrackBar(deviation: dom.deviation, positiveColor: theme.success, negativeColor: theme.warning)
                    HStack {
                        Text("Now \(dom.heroValue)").font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground)
                        Spacer()
                        Text("\(dom.secondaryA.0) \(dom.secondaryA.1) · \(dom.secondaryB.0) \(dom.secondaryB.1)")
                            .font(TypeScale.meta.monospacedDigit())
                            .foregroundStyle(theme.tertiaryForeground)
                            .lineLimit(1)
                    }
                }
                if dom.id < 4 {
                    Divider()
                }
            }
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    // L1-V05: Tri-Pillars Per Domain Capsule Deck
    private var l1V05TriPillarsCapsuleDeck: some View {
        Card {
            SectionHeader("Tri-Pillars Capsule Deck · 三联胶囊指标甲板", icon: "rectangle.grid.3x2.fill")
            ForEach(canonicalL1Domains) { dom in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.xxs) {
                        Circle()
                            .fill(dom.tone == .warning ? theme.warning : theme.success)
                            .frame(width: 7, height: 7)
                        Text(dom.cnTitle).font(TypeScale.meta.weight(.bold)).lineLimit(1)
                        Spacer()
                        Text(dom.verdict).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                    }
                    Grid(horizontalSpacing: Space.xxs, verticalSpacing: 2) {
                        GridRow {
                            miniCapsulePill(dom.heroValue, highlight: true)
                            miniCapsulePill("\(dom.secondaryA.0) \(dom.secondaryA.1)", highlight: false)
                            miniCapsulePill("\(dom.secondaryB.0) \(dom.secondaryB.1)", highlight: false)
                        }
                    }
                }
            }
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    private func miniCapsulePill(_ text: String, highlight: Bool) -> some View {
        Text(text)
            .font(TypeScale.meta.monospacedDigit().weight(highlight ? .bold : .medium))
            .foregroundStyle(highlight ? theme.accent : theme.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(highlight ? theme.accentSubtle : theme.inner, in: Capsule())
    }

    // L1-V06: 7-Day Micro-Sparkline Strip Cards
    private var l1V06SevenDayMicroSparklineCards: some View {
        Card {
            SectionHeader("7-Day Micro-Sparkline Strips · 七日微折线基元卡", icon: "waveform.path.ecg")
            ForEach(canonicalL1Domains) { dom in
                CardInner {
                    HStack(alignment: .center, spacing: Space.xs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dom.title).font(TypeScale.meta.weight(.bold)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(dom.heroValue).font(TypeScale.num.weight(.bold)).foregroundStyle(theme.chart(dom.id)).numLock()
                                Text("(\(dom.deviationText))").font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Sparkline(data: dom.sparkline, color: theme.chart(dom.id))
                            .frame(width: 56, height: 22)
                        StatusPill(dom.verdict, tone: dom.tone)
                    }
                }
            }
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // L1-V07: Verdict-First Coaching Evidence Cards
    private var l1V07VerdictFirstCoachingCards: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    verdictFirstTile(canonicalL1Domains[0])
                    verdictFirstTile(canonicalL1Domains[1])
                }
                GridRow {
                    verdictFirstTile(canonicalL1Domains[2])
                    verdictFirstTile(canonicalL1Domains[3])
                }
            }
            let neat = canonicalL1Domains[4]
            Card {
                HStack {
                    StatusPill(neat.verdict, tone: neat.tone)
                    Text(neat.interpretation).font(TypeScale.meta).foregroundStyle(theme.foreground).lineLimit(1)
                }
                HStack {
                    Text("\(neat.cnTitle): \(neat.heroValue)").font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                    Spacer()
                    Text("\(neat.secondaryA.0) \(neat.secondaryA.1) · \(neat.secondaryB.0) \(neat.secondaryB.1)")
                        .font(TypeScale.meta.monospacedDigit())
                        .foregroundStyle(theme.secondaryForeground)
                }
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }
        }
    }

    private func verdictFirstTile(_ dom: L1DomainFixture) -> some View {
        Card {
            StatusPill(dom.verdict, tone: dom.tone)
            Text(dom.interpretation)
                .font(TypeScale.meta)
                .foregroundStyle(theme.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(dom.heroValue).font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                Spacer()
                Text(dom.secondaryA.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
            }
        }
    }

    // L1-V08: Split Ring & Proportion Instrument
    private var l1V08SplitRingProportionInstrument: some View {
        Card {
            SectionHeader("Split Ring & Numeric Instrument · 微环与数值复合仪表", icon: "gauge.with.needle")
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    ringInstrumentCell(canonicalL1Domains[0])
                    ringInstrumentCell(canonicalL1Domains[1])
                }
                GridRow {
                    ringInstrumentCell(canonicalL1Domains[2])
                    ringInstrumentCell(canonicalL1Domains[3])
                }
            }
            let neat = canonicalL1Domains[4]
            CardInner {
                HStack(spacing: Space.sm) {
                    RingGauge(value: neat.ratio, size: 42, stroke: 4, color: theme.chart(4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(neat.cnTitle) · \(neat.heroValue) steps").font(TypeScale.num.weight(.bold)).numLock()
                        Text("\(neat.secondaryA.0) \(neat.secondaryA.1) · \(neat.secondaryB.0) \(neat.secondaryB.1)").font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground)
                    }
                    Spacer()
                    StatusPill(neat.verdict, tone: neat.tone)
                }
            }
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    private func ringInstrumentCell(_ dom: L1DomainFixture) -> some View {
        CardInner {
            HStack(spacing: Space.xs) {
                RingGauge(value: dom.ratio, size: 42, stroke: 4, color: theme.chart(dom.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(dom.title).font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                    Text(dom.heroValue).font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                    Text(dom.secondaryA.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                }
            }
        }
    }

    // L1-V09: Calm Sanctuary Minimalist Domain Stack
    private var l1V09CalmSanctuaryMinimalistStack: some View {
        Card {
            SectionHeader("Calm Sanctuary Minimalist Stack · 极简呼吸感基元栈", icon: "leaf.fill")
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(canonicalL1Domains) { dom in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(dom.heroValue)
                            .font(TypeScale.display)
                            .foregroundStyle(theme.foreground)
                            .numLock()
                            .frame(width: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dom.cnTitle).font(TypeScale.meta.weight(.semibold)).foregroundStyle(theme.foreground)
                            Text("\(dom.secondaryA.0) \(dom.secondaryA.1) · \(dom.secondaryB.0) \(dom.secondaryB.1)")
                                .font(TypeScale.meta.monospacedDigit())
                                .foregroundStyle(theme.secondaryForeground)
                                .lineLimit(1)
                        }
                        Spacer()
                        StatusPill(dom.verdict, tone: dom.tone)
                    }
                }
            }
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    // L1-V10: Pro Sports-Science 10-Metric Telemetry Matrix
    private var l1V10ProSportsScienceTelemetryMatrix: some View {
        Card {
            HStack {
                SectionHeader("L1 10-Metric Telemetry Console · 十指标遥测矩阵", icon: "tablecells")
                Spacer()
                StatusPill("5 DOMAINS × 10 METRICS", tone: .primary)
            }
            Grid(alignment: .leading, horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    Text("DOMAIN").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("PRIMARY").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("SECONDARY").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("STATUS").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                }
                Divider()
                ForEach(canonicalL1Domains) { dom in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dom.title).font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                            Text(dom.tertiary.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.tertiaryForeground).lineLimit(1)
                        }
                        Text(dom.heroValue)
                            .font(TypeScale.num.weight(.bold))
                            .foregroundStyle(theme.chart(dom.id))
                            .numLock()
                        Text("\(dom.secondaryA.1) / \(dom.secondaryB.1)")
                            .font(TypeScale.num)
                            .foregroundStyle(theme.secondaryForeground)
                            .numLock()
                        StatusPill(dom.verdict, tone: dom.tone)
                    }
                    Divider()
                }
            }
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // MARK: - Layer 2 (10 Distinct Topologies)

    @ViewBuilder private var l2Content: some View {
        switch data.variant {
        case 1: l2V01DualBridgeCouplingDeck
        case 2: l2V02RiskAlertGuardrailManifesto
        case 3: l2V03TwoByTwoInteractionMatrix
        case 4: l2V04SynergyBalanceScaleMeter
        case 5: l2V05ChronologicalBioCascade
        case 6: l2V06DualSparklineCoVarianceStudio
        case 7: l2V07PrescriptionFirstClipboard
        case 8: l2V08SplitGimbalCouplingDials
        case 9: l2V09MinimalistNarrativeDuo
        default: l2V10ProPhysiologyDiagnosticsTable
        }
    }

    // L2-V01: Dual-Bridge Cause & Effect Coupling Deck
    private var l2V01DualBridgeCouplingDeck: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            couplingBridgeCard(
                title: "sleepTrainingCoupling · 睡眠×训练负荷",
                severity: "Watch 轻度张力",
                tone: .warning,
                leftDomain: ("Sleep 81", "Deep+REM 47% · Debt 1.4h"),
                rightDomain: ("Load TSB +6.3", "ACWR 0.90 · Cap 85%"),
                message: data.couplingMessages[0]
            )
            couplingBridgeCard(
                title: "stepsBodyCoupling · 日常NEAT×身体恢复",
                severity: "Normal 协同稳态",
                tone: .success,
                leftDomain: ("NEAT 7,680", "Uniformity 79% · 11h"),
                rightDomain: ("Autonomic 86", "RHR −3 bpm · Burden 20%"),
                message: data.couplingMessages[1]
            )
        }
    }

    private func couplingBridgeCard(
        title: String,
        severity: String,
        tone: PillTone,
        leftDomain: (String, String),
        rightDomain: (String, String),
        message: String
    ) -> some View {
        Card {
            HStack {
                SectionHeader(title, icon: "arrow.triangle.2.circlepath")
                Spacer()
                StatusPill(severity, tone: tone)
            }
            HStack(spacing: Space.xs) {
                CardInner {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leftDomain.0).font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                        Text(leftDomain.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                    }
                }
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                CardInner {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rightDomain.0).font(TypeScale.num.weight(.bold)).foregroundStyle(theme.success).numLock()
                        Text(rightDomain.1).font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                    }
                }
            }
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(theme.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    // L2-V02: Risk Alert & Guardrail Manifesto
    private var l2V02RiskAlertGuardrailManifesto: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Card {
                CardInner {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GUARDRAIL 01 · 睡眠债限制高神经负荷")
                                .font(TypeScale.meta.weight(.bold))
                                .foregroundStyle(theme.warning)
                            Text("Cap session at 85%; avoid max-effort CNS lifts while 7d debt is 1.4h.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.xxs) {
                    GridRow {
                        CompactMetricCell(label: "Sleep Score", value: "81 pts")
                        CompactMetricCell(label: "ACWR Sweet Spot", value: "0.90")
                    }
                    GridRow {
                        CompactMetricCell(label: "Deep+REM", value: "47%")
                        CompactMetricCell(label: "Ceiling Cap", value: "85%")
                    }
                }
                PreviewDetailAction(label: "7 日汇总趋势 ↗")
            }

            Card {
                CardInner {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(theme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GUARDRAIL 02 · NEAT 微动促进副交感恢复")
                                .font(TypeScale.meta.weight(.bold))
                                .foregroundStyle(theme.success)
                            Text("7,680 non-workout steps at 20% energy burden accelerate vagal rebound.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.xxs) {
                    GridRow {
                        CompactMetricCell(label: "NEAT Steps", value: "7,680")
                        CompactMetricCell(label: "Autonomic", value: "86 pts")
                    }
                }
                PreviewDetailAction(label: "7 日汇总趋势 ↗")
            }
        }
    }

    // L2-V03: 2×2 Cross-Domain Interaction Matrix
    private var l2V03TwoByTwoInteractionMatrix: some View {
        Card {
            HStack {
                SectionHeader("2×2 Cross-Domain Coupling Matrix · 跨域交互矩阵", icon: "square.grid.2x2.fill")
                Spacer()
                StatusPill("L2 MATRIX", tone: .primary)
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    CardInner {
                        VStack(alignment: .leading, spacing: 4) {
                            StatusPill("Sleep × Load", tone: .warning)
                            Text("81 × 85% Cap").font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                            Text("Deep+REM 47% offsets ATL 58.4; keep Z4–5 <= 17%.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    CardInner {
                        VStack(alignment: .leading, spacing: 4) {
                            StatusPill("Sleep × NEAT", tone: .success)
                            Text("1.4h × 11h").font(TypeScale.display).foregroundStyle(theme.chart(1)).numLock()
                            Text("Daytime cadence stabilizes circadian sleep pressure.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                GridRow {
                    CardInner {
                        VStack(alignment: .leading, spacing: 4) {
                            StatusPill("Autonomic × Load", tone: .success)
                            Text("68ms × +6.3").font(TypeScale.display).foregroundStyle(theme.success).numLock()
                            Text("HRV in 60d corridor + positive TSB supports progression.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    CardInner {
                        VStack(alignment: .leading, spacing: 4) {
                            StatusPill("NEAT × Body", tone: .primary)
                            Text("7,680 × −3bpm").font(TypeScale.display).foregroundStyle(theme.chart(3)).numLock()
                            Text("79% hourly uniformity keeps non-exercise burden at 20%.")
                                .font(TypeScale.meta)
                                .foregroundStyle(theme.secondaryForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    // L2-V04: Synergy Balance Scale & Tension Meter
    private var l2V04SynergyBalanceScaleMeter: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            balanceScaleCard(
                title: "Sleep Supply vs Training Demand · 睡眠供给与训练张力天平",
                supplyLabel: "Supply: Sleep 81",
                demandLabel: "Demand: ATL 58.4",
                balanceRatio: 0.58,
                verdict: "Supply > Demand (+22.6)",
                tone: .success,
                note: data.couplingMessages[0]
            )
            balanceScaleCard(
                title: "Autonomic Reserve vs NEAT Burden · 自主神经储备与日常代谢负荷",
                supplyLabel: "Supply: Autonomic 86",
                demandLabel: "Demand: Burden 20%",
                balanceRatio: 0.76,
                verdict: "Optimal Circulation Reserve",
                tone: .primary,
                note: data.couplingMessages[1]
            )
        }
    }

    private func balanceScaleCard(
        title: String,
        supplyLabel: String,
        demandLabel: String,
        balanceRatio: Double,
        verdict: String,
        tone: PillTone,
        note: String
    ) -> some View {
        Card {
            SectionHeader(title, icon: "scalemass.fill")
            HStack {
                Text(supplyLabel).font(TypeScale.num.weight(.semibold)).foregroundStyle(theme.success).numLock()
                Spacer()
                StatusPill(verdict, tone: tone)
                Spacer()
                Text(demandLabel).font(TypeScale.num.weight(.semibold)).foregroundStyle(theme.warning).numLock()
            }
            CorridorCapsuleBar(progress: balanceRatio, color: theme.accent)
            Text(note).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // L2-V05: Chronological Bio-Cascade Coupling
    private var l2V05ChronologicalBioCascade: some View {
        Card {
            HStack {
                SectionHeader("24h Chronological Bio-Cascade · 昼夜时序生理传导链", icon: "clock.arrow.2.circlepath")
                Spacer()
                StatusPill("4-STAGE CASCADE", tone: .primary)
            }
            cascadeStep(step: "01 · 夜间睡眠修复", metric: "Deep+REM 47% · Debt 1.4h", detail: "Restores parasympathetic baseline overnight.", color: theme.chart(0))
            cascadeStep(step: "02 · 晨间自主神经门控", metric: "HRV 68 ms · RHR −3 bpm", detail: "Confirms CNS readiness within 60-day corridor.", color: theme.chart(1))
            cascadeStep(step: "03 · 主课训练负荷上限", metric: "Cap 85% · ACWR 0.90", detail: "Executes intensification block without overreaching.", color: theme.chart(2))
            cascadeStep(step: "04 · 日间 NEAT 循环恢复", metric: "7,680 steps · 79% uniform", detail: "Flushes metabolites across 11 active non-workout hours.", color: theme.chart(3))
            PreviewDetailAction(label: "在健康中查看明细 ↗")
        }
    }

    private func cascadeStep(step: String, metric: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(spacing: 2) {
                Circle().fill(color).frame(width: 10, height: 10)
                Rectangle().fill(theme.border).frame(width: 2, height: 34)
            }
            CardInner {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step).font(TypeScale.meta.weight(.bold)).foregroundStyle(color)
                        Spacer()
                        Text(metric).font(TypeScale.num.weight(.semibold)).numLock()
                    }
                    Text(detail).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                }
            }
        }
    }

    // L2-V06: Dual-Sparkline Co-Variance Studio
    private var l2V06DualSparklineCoVarianceStudio: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Card {
                HStack {
                    SectionHeader("Co-Variance A · 7d Sleep vs Training Load", icon: "chart.xyaxis.line")
                    Spacer()
                    StatusPill("r = +0.74 Coupled", tone: .success)
                }
                CardInner {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text("7d Deep+REM %").font(TypeScale.meta).foregroundStyle(theme.chart(0))
                            Spacer()
                            Text("47% today").font(TypeScale.num.weight(.semibold)).numLock()
                        }
                        Sparkline(data: [42, 45, 44, 48, 46, 45, 47], color: theme.chart(0)).frame(height: 26)
                        HStack {
                            Text("7d Acute Load (ATL)").font(TypeScale.meta).foregroundStyle(theme.chart(2))
                            Spacer()
                            Text("58.4 · Cap 85%").font(TypeScale.num.weight(.semibold)).numLock()
                        }
                        Sparkline(data: [54, 56, 55, 60, 59, 57, 58.4], color: theme.chart(2)).frame(height: 26)
                    }
                }
                Text(data.couplingMessages[0]).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                PreviewDetailAction(label: "7 日汇总趋势 ↗")
            }

            Card {
                HStack {
                    SectionHeader("Co-Variance B · 7d NEAT vs Autonomic HRV", icon: "waveform.path.ecg")
                    Spacer()
                    StatusPill("r = +0.68 Coupled", tone: .primary)
                }
                CardInner {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text("7d Non-Workout Steps").font(TypeScale.meta).foregroundStyle(theme.chart(3))
                            Spacer()
                            Text("7,680 steps").font(TypeScale.num.weight(.semibold)).numLock()
                        }
                        Sparkline(data: [6800, 7100, 7420, 6950, 7510, 7390, 7680], color: theme.chart(3)).frame(height: 26)
                        HStack {
                            Text("7d HRV SDNN").font(TypeScale.meta).foregroundStyle(theme.success)
                            Spacer()
                            Text("68 ms (7d 65 ms)").font(TypeScale.num.weight(.semibold)).numLock()
                        }
                        Sparkline(data: [61, 63, 62, 65, 64, 66, 68], color: theme.success).frame(height: 26)
                    }
                }
                PreviewDetailAction(label: "7 日汇总趋势 ↗")
            }
        }
    }

    // L2-V07: Prescription-First Coupling Clipboard
    private var l2V07PrescriptionFirstClipboard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Card {
                StatusPill("PRESCRIPTION 01 · SLEEP × LOAD", tone: .warning)
                Text("Hold today's main sets ≤ 85% ceiling and bank +30 min lights-out tonight.")
                    .font(TypeScale.title)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xxs) {
                    StatusPill("Deep+REM 47%", tone: .primary)
                    StatusPill("Debt 1.4h", tone: .warning)
                    StatusPill("ACWR 0.90", tone: .success)
                }
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }

            Card {
                StatusPill("PRESCRIPTION 02 · NEAT × RECOVERY", tone: .success)
                Text("Maintain 5-minute walking micro-breaks every hour to preserve −3 bpm RHR advantage.")
                    .font(TypeScale.title)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xxs) {
                    StatusPill("NEAT 7,680", tone: .success)
                    StatusPill("Uniformity 79%", tone: .primary)
                    StatusPill("Burden 20%", tone: .neutral)
                }
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }
        }
    }

    // L2-V08: Split Gimbal Coupling Dials
    private var l2V08SplitGimbalCouplingDials: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            gimbalCouplingCard(
                title: "Gimbal A · Sleep × Fatigue Rotor",
                leftLabel: "Sleep 81",
                leftRatio: 0.81,
                leftColor: theme.chart(1),
                rightLabel: "Fatigue 83",
                rightRatio: 0.83,
                rightColor: theme.chart(2),
                centerBadge: "85% CAP",
                subtitle: data.couplingMessages[0]
            )
            gimbalCouplingCard(
                title: "Gimbal B · NEAT × Autonomic Rotor",
                leftLabel: "NEAT 79%",
                leftRatio: 0.79,
                leftColor: theme.chart(3),
                rightLabel: "CNS 86",
                rightRatio: 0.86,
                rightColor: theme.success,
                centerBadge: "SYNERGY",
                subtitle: data.couplingMessages[1]
            )
        }
    }

    private func gimbalCouplingCard(
        title: String,
        leftLabel: String,
        leftRatio: Double,
        leftColor: Color,
        rightLabel: String,
        rightRatio: Double,
        rightColor: Color,
        centerBadge: String,
        subtitle: String
    ) -> some View {
        Card {
            SectionHeader(title, icon: "dial.medium.fill")
            CardInner {
                HStack {
                    VStack(spacing: 4) {
                        RingGauge(value: leftRatio, size: 50, stroke: 5, color: leftColor)
                        Text(leftLabel).font(TypeScale.meta.monospacedDigit()).numLock()
                    }
                    Spacer()
                    StatusPill(centerBadge, tone: .primary)
                    Spacer()
                    VStack(spacing: 4) {
                        RingGauge(value: rightRatio, size: 50, stroke: 5, color: rightColor)
                        Text(rightLabel).font(TypeScale.meta.monospacedDigit()).numLock()
                    }
                }
            }
            Text(subtitle).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // L2-V09: Minimalist Narrative Coupling Duo
    private var l2V09MinimalistNarrativeDuo: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Card {
                HStack(spacing: Space.xs) {
                    Image(systemName: "bed.double.fill").foregroundStyle(theme.accent)
                    Image(systemName: "plus").font(.caption2).foregroundStyle(theme.tertiaryForeground)
                    Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(theme.success)
                    Text("睡眠 × 训练负荷叙事").font(TypeScale.title)
                    Spacer()
                    StatusPill("Watch", tone: .warning)
                }
                Text(data.couplingMessages[0])
                    .font(TypeScale.body)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Sleep 81 · Deep+REM 47% · Debt 1.4h · TSB +6.3 · ACWR 0.90 · Cap 85%")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.secondaryForeground)
                    .lineLimit(1)
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }

            Card {
                HStack(spacing: Space.xs) {
                    Image(systemName: "figure.walk.motion").foregroundStyle(theme.chart(3))
                    Image(systemName: "plus").font(.caption2).foregroundStyle(theme.tertiaryForeground)
                    Image(systemName: "heart.fill").foregroundStyle(theme.success)
                    Text("日常 NEAT × 神经恢复叙事").font(TypeScale.title)
                    Spacer()
                    StatusPill("Normal", tone: .success)
                }
                Text(data.couplingMessages[1])
                    .font(TypeScale.body)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("NEAT 7,680 steps · Uniformity 79% · Active 11h · HRV 68ms · RHR −3bpm")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.secondaryForeground)
                    .lineLimit(1)
                PreviewDetailAction(label: "在健康中查看明细 ↗")
            }
        }
    }

    // L2-V10: Pro Physiology Coupling Diagnostics Table
    private var l2V10ProPhysiologyDiagnosticsTable: some View {
        Card {
            HStack {
                SectionHeader("L2 Coupling Diagnostics Console · 专业耦合诊断表", icon: "tablecells.badge.ellipsis")
                Spacer()
                StatusPill("DIAGNOSTICS v10", tone: .primary)
            }
            Grid(alignment: .leading, horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    Text("VECTOR").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("INPUT A").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("INPUT B").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("IMPACT").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                }
                Divider()
                GridRow {
                    Text("sleepTraining").font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                    Text("Sleep 81 / 47%").font(TypeScale.num).numLock()
                    Text("ACWR 0.90").font(TypeScale.num).numLock()
                    StatusPill("Cap 85%", tone: .warning)
                }
                Divider()
                GridRow {
                    Text("stepsBody").font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                    Text("NEAT 7,680").font(TypeScale.num).numLock()
                    Text("HRV 68 ms").font(TypeScale.num).numLock()
                    StatusPill("Rebound +", tone: .success)
                }
                Divider()
                GridRow {
                    Text("aerobicLoad").font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                    Text("VO2 51.4").font(TypeScale.num).numLock()
                    Text("Pa:Hr 3.4%").font(TypeScale.num).numLock()
                    StatusPill("Coupled", tone: .primary)
                }
                Divider()
                GridRow {
                    Text("debtCeiling").font(TypeScale.meta.weight(.semibold)).lineLimit(1)
                    Text("Debt 1.4 h").font(TypeScale.num).numLock()
                    Text("TSB +6.3").font(TypeScale.num).numLock()
                    StatusPill("Guardrail", tone: .warning)
                }
            }
            CardInner {
                Text("Synthesis: Both primary L2 couplings permit controlled intensification (85% cap) with zero raw sample noise.")
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PreviewDetailAction(label: "7 日汇总趋势 ↗")
        }
    }

    // MARK: - Layer 3 (10 Distinct Topologies)

    @ViewBuilder private var l3Content: some View {
        switch data.variant {
        case 1: l3V01ReadinessGateMesocycleCommand
        case 2: l3V02DualRotorReadinessCeilingCockpit
        case 3: l3V03EditorialPeriodizationLedger
        case 4: l3V04FourBlockMesocycleWaterfall
        case 5: l3V05TrafficLightPreWorkoutGate
        case 6: l3V06TriPillarLimitingFactorInspector
        case 7: l3V07AsymmetricBentoReadinessGrid
        case 8: l3V08IntensityCeilingFirstGate
        case 9: l3V09CalmRecoverySanctuaryDial
        default: l3V10ProPeriodizationTelemetryConsole
        }
    }

    // L3-V01: Readiness Gate & 4-Phase Mesocycle Command Card
    private var l3V01ReadinessGateMesocycleCommand: some View {
        Card {
            HStack {
                SectionHeader("今日身体准备度与周期 · L3", icon: "bolt.heart.fill")
                Spacer()
                StatusPill("Prime 最佳窗口", tone: .success)
            }
            MesocyclePhaseRibbon(activeIndex: 1)
            CardInner {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("READINESS SCORE").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Text("84").font(TypeScale.metricXL).foregroundStyle(theme.success).numLock()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("RECOMMENDED INTENSITY CAP").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Text("85%").font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                        CorridorCapsuleBar(progress: 0.85, color: theme.accent)
                            .frame(width: 120)
                    }
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    pillarMiniCard("自主神经", score: 86, color: theme.chart(0))
                    pillarMiniCard("睡眠修复", score: 81, color: theme.chart(1))
                    pillarMiniCard("疲劳平衡", score: 83, color: theme.chart(2))
                }
            }
        }
    }

    private func pillarMiniCard(_ title: String, score: Int, color: Color) -> some View {
        CardInner {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1)
                Text("\(score)").font(TypeScale.display).foregroundStyle(color).numLock()
                CorridorCapsuleBar(progress: Double(score) / 100.0, color: color)
            }
        }
    }

    // L3-V02: Dual-Rotor Readiness × Intensity Ceiling Cockpit
    private var l3V02DualRotorReadinessCeilingCockpit: some View {
        Card {
            HStack {
                SectionHeader("Dual-Rotor Cockpit · 双环准备度座舱", icon: "gauge.with.dots.needle.67percent")
                Spacer()
                StatusPill("强化期 · Intensification", tone: .primary)
            }
            CardInner {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        RingGauge(value: 0.84, size: 72, stroke: 7, color: theme.success)
                        Text("Readiness 84").font(TypeScale.num.weight(.bold)).numLock()
                    }
                    Spacer()
                    Rectangle().fill(theme.border).frame(width: 1, height: 76)
                    Spacer()
                    VStack(spacing: 6) {
                        RingGauge(value: 0.85, size: 72, stroke: 7, color: theme.accent)
                        Text("Intensity Cap 85%").font(TypeScale.num.weight(.bold)).numLock()
                    }
                    Spacer()
                }
            }
            MesocyclePhaseRibbon(activeIndex: 1)
            VStack(spacing: Space.xxs) {
                pillarHorizontalRow("Autonomic 自主神经", score: 86, color: theme.chart(0))
                pillarHorizontalRow("Sleep 睡眠修复", score: 81, color: theme.chart(1))
                pillarHorizontalRow("Fatigue 疲劳平衡", score: 83, color: theme.chart(2))
            }
        }
    }

    private func pillarHorizontalRow(_ label: String, score: Int, color: Color) -> some View {
        HStack(spacing: Space.sm) {
            Text(label).font(TypeScale.meta).frame(width: 128, alignment: .leading).lineLimit(1)
            CorridorCapsuleBar(progress: Double(score) / 100.0, color: color)
            Text("\(score)").font(TypeScale.num.weight(.bold)).foregroundStyle(color).numLock()
        }
    }

    // L3-V03: Editorial Periodization & Readiness Ledger
    private var l3V03EditorialPeriodizationLedger: some View {
        Card {
            SectionHeader("Editorial Periodization Ledger · 周期与准备度账本", icon: "text.book.closed.fill")
            HStack(alignment: .center, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("84")
                        .font(TypeScale.metricXXL)
                        .foregroundStyle(theme.success)
                        .numLock()
                    Text("READINESS / 100")
                        .font(TypeScale.meta.weight(.bold))
                        .foregroundStyle(theme.secondaryForeground)
                    StatusPill("Prime Gate", tone: .success)
                }
                .frame(width: 116, alignment: .leading)

                Rectangle().fill(theme.border).frame(width: 1, height: 128)

                VStack(alignment: .leading, spacing: Space.xs) {
                    ledgerKV("当前周期 Phase", "强化期 · Intensification")
                    Divider()
                    ledgerKV("推荐上限 Ceiling", "85% Load Cap")
                    Divider()
                    ledgerKV("三支柱 Pillars", "86 / 81 / 83")
                    Divider()
                    ledgerKV("门控状态 Gate", "Prime (≥75)")
                }
            }
        }
    }

    private func ledgerKV(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1)
            Spacer()
            Text(v).font(TypeScale.num.weight(.semibold)).foregroundStyle(theme.foreground).numLock()
        }
    }

    // L3-V04: 4-Block Mesocycle Stepper & Pillar Waterfall
    private var l3V04FourBlockMesocycleWaterfall: some View {
        Card {
            SectionHeader("4-Block Mesocycle Waterfall · 四阶中周期阶梯流", icon: "chart.bar.doc.horizontal")
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    mesocycleTile("B1 积累", sub: "Volume", active: false)
                    mesocycleTile("B2 强化", sub: "Cap 85%", active: true)
                    mesocycleTile("B3 巅峰", sub: "Peak", active: false)
                    mesocycleTile("B4 减载", sub: "Deload", active: false)
                }
            }
            CardInner {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Active Block: Intensification · 强化期").font(TypeScale.title)
                        Spacer()
                        Text("Readiness 84").font(TypeScale.num.weight(.bold)).foregroundStyle(theme.success).numLock()
                    }
                    pillarHorizontalRow("Step 1 · Autonomic CNS", score: 86, color: theme.chart(0))
                    pillarHorizontalRow("Step 2 · Fatigue Balance", score: 83, color: theme.chart(2))
                    pillarHorizontalRow("Step 3 · Sleep Restoration", score: 81, color: theme.chart(1))
                }
            }
        }
    }

    private func mesocycleTile(_ title: String, sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(TypeScale.meta.weight(.bold)).foregroundStyle(active ? theme.onInteractiveAccent : theme.foreground).lineLimit(1)
            Text(sub).font(TypeScale.meta.monospacedDigit()).foregroundStyle(active ? theme.onInteractiveAccent.opacity(0.85) : theme.secondaryForeground).lineLimit(1)
        }
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? theme.interactiveAccent : theme.inner, in: RoundedRectangle(cornerRadius: Radius.inner))
    }

    // L3-V05: Traffic-Light Pre-Workout Gate Deck
    private var l3V05TrafficLightPreWorkoutGate: some View {
        Card {
            CardInner {
                HStack(spacing: Space.sm) {
                    Circle().fill(theme.success).frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GREEN GATE · PRIME 最佳训练窗口 (Readiness 84)")
                            .font(TypeScale.meta.weight(.bold))
                            .foregroundStyle(theme.success)
                        Text("All 3 physiological pillars exceed the 75pt Prime threshold.")
                            .font(TypeScale.meta)
                            .foregroundStyle(theme.secondaryForeground)
                    }
                    Spacer()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Calibrated Intensity Ceiling Track").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                    Spacer()
                    Text("85% MAX").font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                }
                CorridorCapsuleBar(progress: 0.85, color: theme.accent)
            }
            HStack(alignment: .bottom, spacing: Space.sm) {
                verticalPillarMeter("Autonomic", score: 86, color: theme.chart(0))
                verticalPillarMeter("Sleep", score: 81, color: theme.chart(1))
                verticalPillarMeter("Fatigue", score: 83, color: theme.chart(2))
            }
        }
    }

    private func verticalPillarMeter(_ label: String, score: Int, color: Color) -> some View {
        CardInner {
            VStack(spacing: 6) {
                Text("\(score)").font(TypeScale.num.weight(.bold)).foregroundStyle(color).numLock()
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(theme.border).frame(width: 14)
                        Capsule()
                            .fill(color)
                            .frame(width: 14, height: max(8, geo.size.height * CGFloat(score) / 100.0))
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 56)
                Text(label).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1)
            }
        }
    }

    // L3-V06: Tri-Pillar Limiting-Factor Inspector
    private var l3V06TriPillarLimitingFactorInspector: some View {
        Card {
            HStack {
                SectionHeader("Limiting-Factor Inspector · 三支柱短板诊断", icon: "magnifyingglass.circle.fill")
                Spacer()
                StatusPill("Bottleneck: Sleep 81", tone: .warning)
            }
            CardInner {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Limiting Pillar: 睡眠修复 81 pts").font(TypeScale.title).foregroundStyle(theme.warning)
                        Spacer()
                        Text("Cap → 85%").font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                    }
                    Text("Autonomic (86) and Fatigue Balance (83) support 90%+, but 1.4h 7d sleep debt trims today's cap to 85%.")
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: Space.xs) {
                pillarHorizontalRow("★ Sleep (Limiting)", score: 81, color: theme.warning)
                pillarHorizontalRow("Fatigue Balance", score: 83, color: theme.chart(2))
                pillarHorizontalRow("Autonomic CNS", score: 86, color: theme.success)
            }
            HStack {
                StatusPill("Prime Threshold ≥ 75", tone: .neutral)
                Spacer()
                StatusPill("Readiness 84 · Intensification", tone: .primary)
            }
        }
    }

    // L3-V07: Asymmetric Bento Readiness & Cycle Grid
    private var l3V07AsymmetricBentoReadinessGrid: some View {
        Card {
            SectionHeader("Asymmetric Bento Readiness · 不对称准备度矩阵", icon: "rectangle.split.2x1.fill")
            HStack(alignment: .top, spacing: Space.sm) {
                CardInner {
                    VStack(alignment: .center, spacing: Space.xs) {
                        RingGauge(value: 0.84, size: 78, stroke: 7, color: theme.success)
                        Text("84").font(TypeScale.metricXL).foregroundStyle(theme.success).numLock()
                        Text("Readiness").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        StatusPill("强化期", tone: .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 138)

                VStack(alignment: .leading, spacing: Space.xs) {
                    CardInner {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Intensity Cap").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                                Text("85%").font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                            }
                            Spacer()
                            StatusPill("Prime", tone: .success)
                        }
                    }
                    CompactMetricCell(label: "Autonomic 自主神经", value: "86 pts")
                    CompactMetricCell(label: "Sleep 睡眠修复", value: "81 pts")
                    CompactMetricCell(label: "Fatigue 疲劳平衡", value: "83 pts")
                }
            }
        }
    }

    // L3-V08: Intensity Ceiling First Prescription Gate
    private var l3V08IntensityCeilingFirstGate: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S RECOMMENDED INTENSITY CEILING")
                        .font(TypeScale.meta.weight(.bold))
                        .foregroundStyle(theme.secondaryForeground)
                    Text("85%")
                        .font(TypeScale.metricXXL)
                        .foregroundStyle(theme.accent)
                        .numLock()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill("强化期 · Intensification", tone: .primary)
                    StatusPill("Prime Gate · 84", tone: .success)
                }
            }
            CorridorCapsuleBar(progress: 0.85, color: theme.accent)
            Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
                GridRow {
                    CompactMetricCell(label: "Readiness", value: "84")
                    CompactMetricCell(label: "Autonomic", value: "86")
                    CompactMetricCell(label: "Sleep", value: "81")
                    CompactMetricCell(label: "Fatigue", value: "83")
                }
            }
        }
    }

    // L3-V09: Calm Recovery Sanctuary Readiness Dial
    private var l3V09CalmRecoverySanctuaryDial: some View {
        Card {
            VStack(alignment: .center, spacing: Space.md) {
                HStack {
                    StatusPill("强化期 · Intensification", tone: .primary)
                    Spacer()
                    StatusPill("Cap 85%", tone: .success)
                }
                RingGauge(value: 0.84, size: 92, stroke: 8, color: theme.success)
                Text("Readiness 84 · Prime Window")
                    .font(TypeScale.title)
                    .foregroundStyle(theme.foreground)
                Divider()
                Text("自主神经 86  ·  睡眠修复 81  ·  疲劳平衡 83")
                    .font(TypeScale.num)
                    .foregroundStyle(theme.secondaryForeground)
                    .numLock()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // L3-V10: Pro Periodization Telemetry Console
    private var l3V10ProPeriodizationTelemetryConsole: some View {
        Card {
            HStack {
                SectionHeader("L3 Periodization Telemetry · 六维周期遥测台", icon: "cpu.fill")
                Spacer()
                StatusPill("TELEMETRY v10", tone: .primary)
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    CompactMetricCell(label: "READINESS", value: "84 / 100")
                    CompactMetricCell(label: "INTENSITY CAP", value: "85%")
                    CompactMetricCell(label: "MESOCYCLE", value: "Intens.")
                }
                GridRow {
                    CompactMetricCell(label: "AUTONOMIC", value: "86 pts")
                    CompactMetricCell(label: "SLEEP REST.", value: "81 pts")
                    CompactMetricCell(label: "FATIGUE BAL.", value: "83 pts")
                }
            }
            CardInner {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRACEABILITY · CONTRIBUTING L1/L2 SIGNALS").font(TypeScale.meta.weight(.bold)).foregroundStyle(theme.tertiaryForeground)
                    Text("• HRV 68ms in 60d corridor (+3ms vs 7d)  • ACWR 0.90 sweet spot  • Sleep debt 1.4h")
                        .font(TypeScale.meta.monospacedDigit())
                        .foregroundStyle(theme.secondaryForeground)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Layer 4 (10 Distinct Topologies)

    @ViewBuilder private var l4Content: some View {
        switch data.variant {
        case 1: l4V01NorthStarCoHeroNumberedDeck
        case 2: l4V02EditorialExecutiveMorningBriefing
        case 3: l4V03ActionFirstPrescriptiveCoach
        case 4: l4V04AsymmetricBentoNorthStarChecklist
        case 5: l4V05CausalSynthesisThreeColumnStrip
        case 6: l4V06HorizonArcTrajectoryStudio
        case 7: l4V07AIProvenanceDeterministicBriefing
        case 8: l4V08PriorityWeightedActionPyramid
        case 9: l4V09UltraCleanZenSanctuaryNorthStar
        default: l4V10HighDensityCommandBriefingConsole
        }
    }

    // L4-V01: North Star Co-Hero & Numbered Action Deck
    private var l4V01NorthStarCoHeroNumberedDeck: some View {
        Card {
            HStack {
                SectionHeader("L4 总体健康北极星与今日指令", icon: "scope")
                Spacer()
                StatusPill("On-device AI", tone: .primary)
            }
            CardInner {
                HStack(alignment: .center, spacing: Space.md) {
                    RingGauge(value: 0.86, size: 68, stroke: 6, color: theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Text("86").font(TypeScale.metricXL).foregroundStyle(theme.accent).numLock()
                            Text("North Star").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        }
                        Text("Recovery and movement support controlled training today.")
                            .font(TypeScale.body.weight(.semibold))
                            .foregroundStyle(theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            numberedActionList(domainBadges: ["训练执行", "睡眠保护", "节律微动"])
        }
    }

    private func numberedActionList(domainBadges: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(data.actions.enumerated()), id: \.offset) { index, action in
                CardInner {
                    HStack(alignment: .center, spacing: Space.sm) {
                        Text("\(index + 1)")
                            .font(TypeScale.num.weight(.bold))
                            .numLock()
                            .frame(width: 24, height: 24)
                            .background(theme.accentSubtle, in: Circle())
                        Text(action)
                            .font(TypeScale.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if index < domainBadges.count {
                            StatusPill(domainBadges[index], tone: .neutral)
                        }
                    }
                }
            }
        }
    }

    // L4-V02: Editorial Executive Morning Briefing
    private var l4V02EditorialExecutiveMorningBriefing: some View {
        Card {
            HStack {
                SectionHeader("MORNING EXECUTIVE BRIEFING · 社论晨间简报", icon: "newspaper.fill")
                Spacer()
                StatusPill("Deterministic + AI", tone: .neutral)
            }
            HStack(alignment: .center, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("86")
                        .font(TypeScale.metricXXL)
                        .foregroundStyle(theme.foreground)
                        .numLock()
                    Text("/ 100 NORTH STAR")
                        .font(TypeScale.meta.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
                Rectangle().fill(theme.border).frame(width: 1, height: 76)
                Text("Recovery and movement support controlled training today.")
                    .font(TypeScale.title)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ForEach(Array(data.actions.enumerated()), id: \.offset) { index, action in
                HStack(alignment: .top, spacing: Space.sm) {
                    Text(String(format: "0%d", index + 1))
                        .font(TypeScale.num.weight(.bold))
                        .foregroundStyle(theme.accent)
                        .numLock()
                    Text(action)
                        .font(TypeScale.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if index < data.actions.count - 1 {
                    Divider()
                }
            }
        }
    }

    // L4-V03: Action-First Prescriptive Coach Hero
    private var l4V03ActionFirstPrescriptiveCoach: some View {
        Card {
            StatusPill("TODAY'S DIRECTIVE · 行动指令置顶", tone: .primary)
            Text("Recovery and movement support controlled training today.")
                .font(TypeScale.title)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            numberedActionList(domainBadges: ["Cap 85%", "Debt 1.4h", "NEAT 11h"])
            CardInner {
                HStack(spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("L4 North Star").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Text("86 / 100").font(TypeScale.display).foregroundStyle(theme.accent).numLock()
                    }
                    Spacer()
                    Sparkline(data: [78, 80, 79, 82, 84, 85, 86], color: theme.accent)
                        .frame(width: 96, height: 28)
                    StatusPill("On-device AI", tone: .success)
                }
            }
        }
    }

    // L4-V04: Asymmetric Bento North Star & Checklist
    private var l4V04AsymmetricBentoNorthStarChecklist: some View {
        Card {
            SectionHeader("Asymmetric Bento North Star · 北极星行动舱", icon: "sidebar.left")
            HStack(alignment: .top, spacing: Space.sm) {
                CardInner {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        RingGauge(value: 0.86, size: 64, stroke: 6, color: theme.accent)
                        Text("86").font(TypeScale.metricXL).foregroundStyle(theme.accent).numLock()
                        Sparkline(data: [76, 79, 81, 80, 83, 85, 86], color: theme.accent)
                            .frame(height: 24)
                        StatusPill("On-device AI", tone: .primary)
                    }
                }
                .frame(width: 132)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Recovery and movement support controlled training today.")
                        .font(TypeScale.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(data.actions.enumerated()), id: \.offset) { idx, action in
                        CardInner {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.success)
                                Text("P\(idx + 1): \(action)")
                                    .font(TypeScale.meta)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // L4-V05: Causal Synthesis Banner & 3-Column Action Strip
    private var l4V05CausalSynthesisThreeColumnStrip: some View {
        Card {
            CardInner {
                HStack(spacing: Space.md) {
                    Text("86").font(TypeScale.metricXL).foregroundStyle(theme.accent).numLock()
                    VStack(alignment: .leading, spacing: 2) {
                        StatusPill("L4 <- L3 <- L2 <- L1 SYNTHESIS", tone: .primary)
                        Text("Recovery and movement support controlled training today.")
                            .font(TypeScale.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    actionColumnTile(code: "P1 训练", icon: "figure.run", text: data.actions[0], color: theme.chart(0))
                    actionColumnTile(code: "P2 睡眠", icon: "bed.double.fill", text: data.actions[1], color: theme.chart(1))
                    actionColumnTile(code: "P3 节律", icon: "figure.walk", text: data.actions[2], color: theme.chart(3))
                }
            }
        }
    }

    private func actionColumnTile(code: String, icon: String, text: String, color: Color) -> some View {
        CardInner {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(code).font(TypeScale.meta.weight(.bold)).foregroundStyle(color).lineLimit(1)
                }
                Text(text)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // L4-V06: Horizon Arc & Trajectory North Star Studio
    private var l4V06HorizonArcTrajectoryStudio: some View {
        Card {
            HStack {
                SectionHeader("Horizon Trajectory Studio · 天际弧与14日轨迹", icon: "waveform.path.ecg.rectangle")
                Spacer()
                StatusPill("14d +8 pts", tone: .success)
            }
            CardInner {
                VStack(spacing: Space.xs) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("86").font(TypeScale.metricXL).foregroundStyle(theme.accent).numLock()
                        Text("North Star Horizon").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
                        Spacer()
                        Text("Cap 85% · Readiness 84").font(TypeScale.num).foregroundStyle(theme.success).numLock()
                    }
                    CorridorCapsuleBar(progress: 0.86, color: theme.accent)
                    Sparkline(data: [74, 75, 77, 76, 79, 80, 81, 80, 82, 83, 84, 84, 85, 86], color: theme.accent)
                        .frame(height: 36)
                }
            }
            Text("Recovery and movement support controlled training today.")
                .font(TypeScale.title)
                .fixedSize(horizontal: false, vertical: true)
            numberedActionList(domainBadges: ["L3 Gate", "L1 Sleep", "L1 NEAT"])
        }
    }

    // L4-V07: AI Provenance & Deterministic Audit Briefing
    private var l4V07AIProvenanceDeterministicBriefing: some View {
        Card {
            SectionHeader("4-Mode AI Provenance Briefing · 四模引擎溯源简报", icon: "cpu")
            Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
                GridRow {
                    provenanceChip("On-device AI", active: true)
                    provenanceChip("Custom API", active: false)
                    provenanceChip("Jev Gateway", active: false)
                    provenanceChip("Local Rules", active: false)
                }
            }
            CardInner {
                HStack(spacing: Space.md) {
                    Text("86").font(TypeScale.metricXL).foregroundStyle(theme.accent).numLock()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verified against L1–L3 deterministic physiological bounds")
                            .font(TypeScale.meta.weight(.semibold))
                            .foregroundStyle(theme.success)
                        Text("Recovery and movement support controlled training today.")
                            .font(TypeScale.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            numberedActionList(domainBadges: ["Verified", "Verified", "Verified"])
        }
    }

    private func provenanceChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(TypeScale.meta.weight(active ? .bold : .regular))
            .foregroundStyle(active ? theme.onInteractiveAccent : theme.secondaryForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(active ? theme.interactiveAccent : theme.inner, in: RoundedRectangle(cornerRadius: Radius.badge))
    }

    // L4-V08: Priority-Weighted Action Pyramid
    private var l4V08PriorityWeightedActionPyramid: some View {
        Card {
            HStack {
                SectionHeader("Priority Action Pyramid · 优先级金字塔北极星", icon: "triangle.fill")
                Spacer()
                StatusPill("North Star 86", tone: .primary)
            }
            CardInner {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        StatusPill("P1 PRIMARY IMPERATIVE", tone: .success)
                        Spacer()
                        Text("86 pts · 85% Cap").font(TypeScale.num.weight(.bold)).foregroundStyle(theme.accent).numLock()
                    }
                    Text(data.actions[0])
                        .font(TypeScale.title)
                        .foregroundStyle(theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Recovery and movement support controlled training today.")
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.secondaryForeground)
                }
            }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                GridRow {
                    actionColumnTile(code: "P2 SECONDARY", icon: "moon.stars.fill", text: data.actions[1], color: theme.chart(1))
                    actionColumnTile(code: "P3 TERTIARY", icon: "figure.walk.motion", text: data.actions[2], color: theme.chart(3))
                }
            }
        }
    }

    // L4-V09: Ultra-Clean Zen Sanctuary North Star
    private var l4V09UltraCleanZenSanctuaryNorthStar: some View {
        Card {
            VStack(alignment: .center, spacing: Space.md) {
                StatusPill("L4 NORTH STAR SANCTUARY", tone: .primary)
                RingGauge(value: 0.86, size: 88, stroke: 7, color: theme.accent)
                Text("Recovery and movement support controlled training today.")
                    .font(TypeScale.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(data.actions.enumerated()), id: \.offset) { idx, action in
                        HStack(alignment: .top, spacing: Space.xs) {
                            Text("•").font(TypeScale.title).foregroundStyle(theme.accent)
                            Text("\(idx + 1). \(action)")
                                .font(TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.xs)
        }
    }

    // L4-V10: High-Density Command Briefing Console
    private var l4V10HighDensityCommandBriefingConsole: some View {
        Card {
            HStack {
                SectionHeader("L4 Command Briefing Console · 指挥官北极星控制台", icon: "terminal.fill")
                Spacer()
                StatusPill("CONSOLE v10", tone: .primary)
            }
            Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
                GridRow {
                    CompactMetricCell(label: "L4 SCORE", value: "86 / 100")
                    CompactMetricCell(label: "L3 READY", value: "84 pts")
                    CompactMetricCell(label: "LOAD CAP", value: "85%")
                    CompactMetricCell(label: "ENGINE", value: "On-Device")
                }
            }
            CardInner {
                Text("DIRECTIVE: Recovery and movement support controlled training today.")
                    .font(TypeScale.meta.weight(.bold))
                    .foregroundStyle(theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                ForEach(Array(data.actions.enumerated()), id: \.offset) { idx, action in
                    GridRow {
                        Text(String(format: "ACT-0%d", idx + 1))
                            .font(TypeScale.num.weight(.bold))
                            .foregroundStyle(theme.accent)
                            .numLock()
                        Text(action)
                            .font(TypeScale.meta)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusPill(idx == 0 ? "LOAD" : (idx == 1 ? "SLEEP" : "NEAT"), tone: .neutral)
                    }
                    if idx < data.actions.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var variantArchetypeTitle: String {
        let tab: VitalStridePreviewPageTab = switch data.layer {
        case .l1: .page1HolisticDashboard
        case .l2: .page2HeartSleepCoupling
        case .l3: .page3WorkoutLoadProgression
        case .l4: .page4StepsBodySettings
        }
        let list = tab.descriptors
        let idx = min(max(data.variant - 1, 0), list.count - 1)
        return list[idx].title
    }

    private var layerIcon: String {
        switch data.layer {
        case .l1: "square.grid.2x2"
        case .l2: "arrow.triangle.2.circlepath"
        case .l3: "calendar.badge.clock"
        case .l4: "scope"
        }
    }
}

private extension View {
    func numLock() -> some View {
        self.monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .layoutPriority(1)
    }
}

private struct CompactMetricCell: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String

    var body: some View {
        CardInner {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.secondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(value)
                    .font(TypeScale.num.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                    .numLock()
            }
        }
    }
}

private struct CorridorCapsuleBar: View {
    @Environment(\.theme) private var theme
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.border)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: 8)
    }
}

private struct DivergingTrackBar: View {
    @Environment(\.theme) private var theme
    let deviation: Double // -1.0 ... 1.0
    let positiveColor: Color
    let negativeColor: Color

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            let span = min(max(deviation, -1), 1) * (geo.size.width / 2 - 4)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.border)
                Rectangle()
                    .fill(theme.tertiaryForeground)
                    .frame(width: 2, height: 10)
                    .offset(x: mid - 1)
                Capsule()
                    .fill(span >= 0 ? positiveColor : negativeColor)
                    .frame(width: max(6, abs(span)), height: 8)
                    .offset(x: span >= 0 ? mid : mid + span)
            }
        }
        .frame(height: 10)
    }
}

private struct MesocyclePhaseRibbon: View {
    @Environment(\.theme) private var theme
    let activeIndex: Int

    var body: some View {
        Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
            GridRow {
                phasePill(index: 0, title: "积累 Accum.")
                phasePill(index: 1, title: "强化 Intens.")
                phasePill(index: 2, title: "巅峰 Realiz.")
                phasePill(index: 3, title: "减载 Deload")
            }
        }
    }

    private func phasePill(index: Int, title: String) -> some View {
        let isCurrent = index == activeIndex
        return Text(title)
            .font(TypeScale.meta.weight(isCurrent ? .bold : .medium))
            .foregroundStyle(isCurrent ? theme.onInteractiveAccent : theme.secondaryForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                isCurrent ? theme.interactiveAccent : theme.inner,
                in: Capsule()
            )
    }
}

private struct PreviewDetailAction: View {
    @Environment(\.theme) private var theme
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.right.square")
            Text(label)
        }
        .font(TypeScale.meta.weight(.semibold))
        .foregroundStyle(theme.accent)
        .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
    }
}

private struct LayerGalleryStateCard: View {
    @Environment(\.theme) private var theme
    let state: VitalStridePreviewDataState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: icon).font(.title2).foregroundStyle(state == .error ? theme.danger : theme.accent)
                Text(title).font(TypeScale.title)
                Text(message).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
                if state == .empty || state == .error { DesignButton(state == .error ? "Retry" : "Open Health Settings", variant: .secondary, icon: state == .error ? "arrow.clockwise" : "gearshape") {} }
            }
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
        }
    }

    private var icon: String {
        switch state { case .populated: "square.grid.2x2"; case .empty: "tray"; case .loading: "hourglass"; case .error: "exclamationmark.triangle" }
    }
    private var title: String {
        switch state { case .populated: ""; case .empty: "Build your baseline"; case .loading: "Preparing layer"; case .error: "Layer unavailable" }
    }
    private var message: String {
        switch state { case .populated: ""; case .empty: "Authorize health data to unlock aggregate summaries."; case .loading: "Gathering aggregate evidence."; case .error: "Local data is safe. Retry when the source is available." }
    }
}
