import DesignKit
import SwiftUI

public enum HeartSleepCouplingPreviewState: String, CaseIterable, Sendable {
    case populated, empty, loading, error
}

public enum HeartSleepPreviewProvider: String, CaseIterable, Sendable {
    case foundationModels, customOpenAICompatible, jevGateway, deterministicFallback

    public var label: String {
        switch self {
        case .foundationModels: "On-device AI"
        case .customOpenAICompatible: "Custom API"
        case .jevGateway: "Jev Gateway"
        case .deterministicFallback: "Local rules"
        }
    }
}

public enum HeartSleepSeverity: String, CaseIterable, Sendable {
    case normal, watch, warning, critical

    var label: String {
        switch self {
        case .normal: "Within corridor"
        case .watch: "Watch load"
        case .warning: "Moderate strain"
        case .critical: "High strain"
        }
    }

    var tone: PillTone {
        switch self {
        case .normal: .success
        case .watch, .warning: .warning
        case .critical: .danger
        }
    }
}

public enum HeartSleepPhase: String, CaseIterable, Sendable {
    case accumulation, intensification, realization, deload

    var label: String { rawValue.capitalized }
}

public struct HeartSleepHRV: Sendable, Equatable {
    public let current: Double
    public let sevenDayAverage: Double
    public let baseline: Double
    public let lowerBound: Double
    public let upperBound: Double
    public let isWithinCorridor: Bool

    public init(current: Double = 68, sevenDayAverage: Double = 65, baseline: Double = 63, lowerBound: Double = 54, upperBound: Double = 72) {
        self.current = current
        self.sevenDayAverage = sevenDayAverage
        self.baseline = baseline
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.isWithinCorridor = (lowerBound...upperBound).contains(current) && (lowerBound...upperBound).contains(sevenDayAverage)
    }
}

public struct HeartSleepRHR: Sendable, Equatable {
    public let currentBPM: Double
    public let sevenDayAverageBPM: Double
    public let sixtyDayBaselineBPM: Double
    public var delta: Double { currentBPM - sixtyDayBaselineBPM }

    public init(currentBPM: Double = 52, sevenDayAverageBPM: Double = 53, sixtyDayBaselineBPM: Double = 55) {
        self.currentBPM = currentBPM
        self.sevenDayAverageBPM = sevenDayAverageBPM
        self.sixtyDayBaselineBPM = sixtyDayBaselineBPM
    }
}

public struct HeartSleepHRR: Sendable, Equatable {
    public let peakBaselineBPM: Double
    public let oneMinuteBPM: Double
    public let twoMinuteBPM: Double
    public var oneMinuteDrop: Double { peakBaselineBPM - oneMinuteBPM }
    public var twoMinuteDrop: Double { peakBaselineBPM - twoMinuteBPM }

    public init(peakBaselineBPM: Double = 164, oneMinuteBPM: Double = 132, twoMinuteBPM: Double = 115) {
        self.peakBaselineBPM = peakBaselineBPM
        self.oneMinuteBPM = oneMinuteBPM
        self.twoMinuteBPM = twoMinuteBPM
    }
}

public struct HeartSleepZones: Sendable, Equatable {
    public let durations: [TimeInterval]
    public init(durations: [TimeInterval] = [12 * 60, 28 * 60, 42 * 60, 18 * 60, 6 * 60]) {
        self.durations = durations.map { max(0, $0) }.prefix(5).map { $0 } + Array(repeating: 0, count: max(0, 5 - durations.count))
    }
    public var total: TimeInterval { durations.reduce(0, +) }
    public func ratio(at index: Int) -> Double { guard total > 0, durations.indices.contains(index) else { return 0 }; return durations[index] / total }
}

public struct HeartSleepArchitecture: Sendable, Equatable {
    public let deep: TimeInterval
    public let rem: TimeInterval
    public let core: TimeInterval
    public let awake: TimeInterval
    public let totalSleep: TimeInterval
    public let inBed: TimeInterval
    public let sleepEfficiency: Double

    public init(deep: TimeInterval = 1.8 * 3600, rem: TimeInterval = 1.9 * 3600, core: TimeInterval = 3.7 * 3600, awake: TimeInterval = 20 * 60, inBed: TimeInterval = 8.0 * 3600) {
        self.deep = deep; self.rem = rem; self.core = core; self.awake = awake; self.totalSleep = deep + rem + core; self.inBed = inBed
        self.sleepEfficiency = inBed > 0 ? (deep + rem + core) / inBed : 0
    }
    public func ratio(_ duration: TimeInterval) -> Double { totalSleep > 0 ? duration / totalSleep : 0 }
}

public struct HeartSleepDebt: Sendable, Equatable {
    public let sevenDay: TimeInterval
    public let fourteenDay: TimeInterval
    public let targetSleep: TimeInterval
    public let observedNightCount7d: Int
    public let observedNightCount14d: Int

    public init(sevenDay: TimeInterval = 1.4 * 3600, fourteenDay: TimeInterval = 2.6 * 3600, targetSleep: TimeInterval = 8 * 3600, observedNightCount7d: Int = 7, observedNightCount14d: Int = 14) {
        self.sevenDay = sevenDay; self.fourteenDay = fourteenDay; self.targetSleep = targetSleep; self.observedNightCount7d = observedNightCount7d; self.observedNightCount14d = observedNightCount14d
    }
}

public struct HeartSleepCoupling: Sendable, Equatable {
    public let message: String
    public let severity: HeartSleepSeverity
    public let autonomicScore: Int
    public let sleepRestorationScore: Int
    public let readinessScore: Int
    public let recommendedIntensityCap: Double
    public let mesocyclePhase: HeartSleepPhase
    public let provider: HeartSleepPreviewProvider

    public init(message: String = "Deep and REM restoration support a controlled strength session. Keep high-CNS work below today's ceiling and finish with easy aerobic recovery.", severity: HeartSleepSeverity = .normal, autonomicScore: Int = 86, sleepRestorationScore: Int = 81, readinessScore: Int = 84, recommendedIntensityCap: Double = 0.85, mesocyclePhase: HeartSleepPhase = .intensification, provider: HeartSleepPreviewProvider = .deterministicFallback) {
        self.message = message; self.severity = severity; self.autonomicScore = autonomicScore; self.sleepRestorationScore = sleepRestorationScore; self.readinessScore = readinessScore; self.recommendedIntensityCap = min(max(recommendedIntensityCap, 0), 1); self.mesocyclePhase = mesocyclePhase; self.provider = provider
    }
}

public struct HeartSleepCouplingPreviewData: Sendable, Equatable {
    public let state: HeartSleepCouplingPreviewState
    public let hrv: HeartSleepHRV
    public let rhr: HeartSleepRHR
    public let hrr: HeartSleepHRR
    public let zones: HeartSleepZones
    public let architecture: HeartSleepArchitecture
    public let debt: HeartSleepDebt
    public let coupling: HeartSleepCoupling

    public init(state: HeartSleepCouplingPreviewState = .populated, coupling: HeartSleepCoupling = .init()) {
        self.state = state; self.hrv = .init(); self.rhr = .init(); self.hrr = .init(); self.zones = .init(); self.architecture = .init(); self.debt = .init(); self.coupling = coupling
    }
}

private func durationText(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds.rounded()) / 60
    return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
}

private struct PreviewScoreArc: View {
    @Environment(\.theme) private var theme
    let score: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(theme.neutrals.border, lineWidth: 8)
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
        .frame(width: 76, height: 76)
    }
}

private struct PreviewStateView: View {
    @Environment(\.theme) private var theme
    let state: HeartSleepCouplingPreviewState
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
    private var icon: String { switch state { case .empty: "tray"; case .loading: "hourglass"; case .error: "exclamationmark.triangle"; case .populated: "heart.text.square" } }
    private var title: String { switch state { case .empty: "Build your baseline"; case .loading: "Preparing detail"; case .error: "Detail unavailable"; case .populated: "" } }
    private var message: String { switch state { case .empty: "Authorize health data to unlock heart and sleep evidence."; case .loading: "Gathering recent domains."; case .error: "Your local data is safe. Retry when the source is available."; case .populated: "" } }
}

private struct CouplingHeader: View {
    @Environment(\.theme) private var theme
    let data: HeartSleepCouplingPreviewData
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack { SectionHeader("Sleep × training coupling", icon: "bolt.heart.fill"); Spacer(minLength: Space.xs); StatusPill(data.coupling.provider.label, tone: .primary) }
            Text("\(Int((data.coupling.recommendedIntensityCap * 100).rounded()))%")
                .font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1)
            Text("Recommended intensity ceiling").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    StatusPill(data.coupling.severity.label, tone: data.coupling.severity.tone)
                        .fixedSize(horizontal: true, vertical: false)
                    StatusPill(data.coupling.mesocyclePhase.label, tone: .primary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                StatusPill("Readiness \(data.coupling.readinessScore)", tone: .neutral)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(data.coupling.message).font(TypeScale.body).fixedSize(horizontal: false, vertical: true).foregroundStyle(theme.secondaryForeground)
        }
    }
}

private struct HeartEvidence: View {
    @Environment(\.theme) private var theme
    let data: HeartSleepCouplingPreviewData
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("L1 autonomic evidence", icon: "waveform.path.ecg")
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { HStack { Text("HRV SDNN").font(TypeScale.title); Spacer(); StatusPill(data.hrv.isWithinCorridor ? "Within corridor" : "Outside corridor", tone: data.hrv.isWithinCorridor ? .success : .warning) }; Text("\(Int(data.hrv.current.rounded())) ms").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); Text("7d \(Int(data.hrv.sevenDayAverage.rounded())) · 60d \(Int(data.hrv.lowerBound.rounded()))–\(Int(data.hrv.upperBound.rounded())) ms").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.secondaryForeground) } }
            HStack(spacing: Space.sm) {
                CardInner { VStack(alignment: .leading) { Text("RHR").font(TypeScale.meta); Text("\(Int(data.rhr.currentBPM.rounded())) bpm").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1); Text("Δ \(Int(data.rhr.delta.rounded()))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.success) } }
                CardInner { VStack(alignment: .leading) { Text("HRR").font(TypeScale.meta); Text("-\(Int(data.hrr.oneMinuteDrop.rounded())) bpm").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1); Text("2m -\(Int(data.hrr.twoMinuteDrop.rounded()))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.secondaryForeground) } }
            }
        }
    }
}

private struct SleepEvidence: View {
    @Environment(\.theme) private var theme
    let data: HeartSleepCouplingPreviewData
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("L1 sleep architecture & debt", icon: "bed.double.fill")
            CardInner { VStack(alignment: .leading, spacing: Space.sm) { HStack { Text(durationText(data.architecture.totalSleep)).font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); Spacer(); Text("\(Int((data.architecture.sleepEfficiency * 100).rounded()))% efficient").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }; StageBar(data: data); HStack(spacing: Space.xs) { Text("Deep \(durationText(data.architecture.deep))"); Text("REM \(durationText(data.architecture.rem))"); Text("Core \(durationText(data.architecture.core))") }.font(TypeScale.meta).foregroundStyle(theme.secondaryForeground) } }
            HStack(spacing: Space.sm) { CardInner { VStack(alignment: .leading) { Text("7d debt").font(TypeScale.meta); Text(durationText(data.debt.sevenDay)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1); Text("\(data.debt.observedNightCount7d)/7 nights").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } }; CardInner { VStack(alignment: .leading) { Text("14d debt").font(TypeScale.meta); Text(durationText(data.debt.fourteenDay)).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1); Text("\(data.debt.observedNightCount14d)/14 nights").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } } }
        }
    }
}

private struct StageBar: View {
    @Environment(\.theme) private var theme
    let data: HeartSleepCouplingPreviewData
    var body: some View { GeometryReader { proxy in HStack(spacing: 2) { Rectangle().fill(theme.chart(3)).frame(width: proxy.size.width * data.architecture.ratio(data.architecture.deep)); Rectangle().fill(theme.chart(2)).frame(width: proxy.size.width * data.architecture.ratio(data.architecture.rem)); Rectangle().fill(theme.chart(0)).frame(width: proxy.size.width * data.architecture.ratio(data.architecture.core)); Rectangle().fill(theme.secondaryForeground).frame(width: max(2, proxy.size.width * data.architecture.ratio(data.architecture.awake))) } }.frame(height: 12).clipShape(Capsule()) }
}

private struct ZoneBar: View {
    @Environment(\.theme) private var theme
    let zones: HeartSleepZones
    var body: some View { VStack(alignment: .leading, spacing: Space.xs) { SectionHeader("Heart rate zones", icon: "chart.bar.xaxis"); GeometryReader { proxy in HStack(spacing: 2) { ForEach(0..<5, id: \.self) { index in Rectangle().fill(theme.chart(index + 4)).frame(width: max(2, proxy.size.width * zones.ratio(at: index))) } }.clipShape(Capsule()) }.frame(height: 12); HStack { ForEach(0..<5, id: \.self) { index in Text("Z\(index + 1)").font(TypeScale.meta).frame(maxWidth: .infinity) } } } }
}

private struct CandidateScaffold<Content: View>: View {
    let data: HeartSleepCouplingPreviewData
    @ViewBuilder let content: (HeartSleepCouplingPreviewData) -> Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: Space.md) { if data.state == .populated { content(data) } else { PreviewStateView(state: data.state) } }.padding(Space.md).frame(maxWidth: Space.contentMaxWidth, alignment: .leading) }.background(.clear) }
}

public struct HeartSleepCouplingV01View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { CouplingHeader(data: item) }; HeartEvidence(data: item); SleepEvidence(data: item); Card { ZoneBar(zones: item.zones) } } } }
public struct HeartSleepCouplingV02View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { HStack(alignment: .bottom) { VStack(alignment: .leading) { SectionHeader("Morning prescription", icon: "sunrise.fill"); Text("\(Int(item.coupling.recommendedIntensityCap * 100))%").font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1); Text("load ceiling").font(TypeScale.meta) }; Spacer(); StatusPill(item.coupling.mesocyclePhase.label, tone: .primary) }; Text(item.coupling.message).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; Card { AutonomicLedgerRows(data: item) }; Card { SleepLedgerRows(data: item) } } } }
private struct AutonomicLedgerRows: View { let data: HeartSleepCouplingPreviewData; var body: some View { VStack(alignment: .leading, spacing: Space.sm) { SectionHeader("Autonomic clinical ledger"); HStack { Text("HRV SDNN"); Spacer(); Text("\(Int(data.hrv.current)) ms · \(Int(data.hrv.lowerBound))–\(Int(data.hrv.upperBound)) ms").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }; Divider(); HStack { Text("Resting HR"); Spacer(); Text("\(Int(data.rhr.currentBPM)) bpm · Δ \(Int(data.rhr.delta.rounded()))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }; Divider(); HStack { Text("Post-workout HRR"); Spacer(); Text("1m -\(Int(data.hrr.oneMinuteDrop)) · 2m -\(Int(data.hrr.twoMinuteDrop)) bpm").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } }.font(TypeScale.body) } }
private struct SleepLedgerRows: View { let data: HeartSleepCouplingPreviewData; var body: some View { VStack(alignment: .leading, spacing: Space.sm) { SectionHeader("Sleep restoration ledger"); HStack { Text("Total sleep / efficiency"); Spacer(); Text("\(durationText(data.architecture.totalSleep)) · \(Int(data.architecture.sleepEfficiency * 100))%").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }; Divider(); HStack { Text("Deep / REM"); Spacer(); Text("\(durationText(data.architecture.deep)) · \(durationText(data.architecture.rem))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) }; Divider(); HStack { Text("Sleep debt (7d / 14d)"); Spacer(); Text("\(durationText(data.debt.sevenDay)) · \(durationText(data.debt.fourteenDay))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } }.font(TypeScale.body) } }
public struct HeartSleepCouplingV03View: View {
    @Environment(\.theme) private var theme
    public let data: HeartSleepCouplingPreviewData
    public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }
    public var body: some View {
        CandidateScaffold(data: data) { item in
            Card { CouplingHeader(data: item) }
            Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) {
                GridRow { V03HRVTile(data: item, color: theme.chart(1)); V03RecoveryTile(data: item, color: theme.chart(3)) }
                GridRow { V03SleepTile(data: item, color: theme.chart(3)); V03DebtTile(data: item, color: theme.chart(2)) }
                GridRow { Card { ZoneBar(zones: item.zones) }.gridCellColumns(2) }
            }
        }
    }
}

private struct V03HRVTile: View {
    let data: HeartSleepCouplingPreviewData
    let color: Color
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("HRV corridor").font(TypeScale.meta).lineLimit(1)
                Text("\(Int(data.hrv.current.rounded())) ms").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1)
                Sparkline(data: [58, 61, 63, 60, 65, 66, data.hrv.current], color: color)
                Text("\(Int(data.hrv.lowerBound.rounded()))–\(Int(data.hrv.upperBound.rounded())) ms").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1)
            }
        }
    }
}

private struct V03RecoveryTile: View {
    let data: HeartSleepCouplingPreviewData
    let color: Color
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("RHR").font(TypeScale.meta).lineLimit(1)
                Text("\(Int(data.rhr.currentBPM.rounded())) bpm").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1)
                Divider()
                Text("HRR 1m").font(TypeScale.meta).lineLimit(1)
                Text("-\(Int(data.hrr.oneMinuteDrop.rounded())) bpm").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(color)
            }
        }
    }
}

private struct V03SleepTile: View {
    let data: HeartSleepCouplingPreviewData
    let color: Color
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Sleep efficiency").font(TypeScale.meta).lineLimit(1)
                RingGauge(value: data.architecture.sleepEfficiency, color: color)
                Text(durationText(data.architecture.totalSleep)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1)
            }
        }
    }
}

private struct V03DebtTile: View {
    let data: HeartSleepCouplingPreviewData
    let color: Color
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Sleep debt").font(TypeScale.meta).lineLimit(1)
                Text("7d \(durationText(data.debt.sevenDay))").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(color)
                Text("14d \(durationText(data.debt.fourteenDay))").font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1)
                Text("Target \(durationText(data.debt.targetSleep))").font(TypeScale.meta).monospacedDigit().lineLimit(1).layoutPriority(1)
            }
        }
    }
}
public struct HeartSleepCouplingV04View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in TimelineStage(icon: "moon.fill", title: "Last night") { SleepEvidence(data: item) }; TimelineStage(icon: "waveform.path.ecg", title: "Morning autonomic readout") { HeartEvidence(data: item) }; TimelineStage(icon: "bolt.fill", title: "Today's training window") { Card { CouplingHeader(data: item) } } } } }
private struct TimelineStage<Content: View>: View { @Environment(\.theme) private var theme; let icon: String; let title: String; @ViewBuilder let content: () -> Content; var body: some View { HStack(alignment: .top, spacing: Space.sm) { VStack { Image(systemName: icon).foregroundStyle(theme.accent); Rectangle().fill(theme.border).frame(width: 1) }.frame(width: 24); VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.title); content() } } } }
public struct HeartSleepCouplingV05View: View { @Environment(\.theme) private var theme; public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { HStack { CardInner { VStack { PreviewScoreArc(score: item.coupling.autonomicScore, color: theme.chart(1)); Text("Autonomic \(item.coupling.autonomicScore)").font(TypeScale.meta) } }; CardInner { VStack { PreviewScoreArc(score: item.coupling.sleepRestorationScore, color: theme.chart(3)); Text("Sleep \(item.coupling.sleepRestorationScore)").font(TypeScale.meta) } } }; CouplingHeader(data: item) }; Card { HeartEvidence(data: item); ZoneBar(zones: item.zones) }; Card { SleepEvidence(data: item) } } } }
public struct HeartSleepCouplingV06View: View { @Environment(\.theme) private var theme; public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { SectionHeader("Corridor chart studio", icon: "chart.xyaxis.line"); Sparkline(data: [58, 61, 63, 60, 65, 66, item.hrv.current], color: theme.chart(1)); HeartEvidence(data: item) }; Card { SectionHeader("Seven-night architecture", icon: "chart.bar.fill"); HStack(alignment: .bottom, spacing: Space.xs) { ForEach(0..<7, id: \.self) { day in VStack { Capsule().fill(theme.chart(3).opacity(0.7)).frame(height: CGFloat(20 + day * 5)); Text("\(day + 1)").font(TypeScale.meta) } .frame(maxWidth: .infinity) } }; SleepEvidence(data: item) }; Card { CouplingHeader(data: item) } } } }
public struct HeartSleepCouplingV07View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { CouplingHeader(data: item); Divider(); Text("Guardrails").font(TypeScale.title); HStack { StatusPill("CNS controlled", tone: .success); StatusPill("Zone 2 recovery", tone: .neutral) } }; Card { SectionHeader("Evidence pillar 1", icon: "heart.fill"); HeartEvidence(data: item) }; Card { SectionHeader("Evidence pillar 2", icon: "bed.double.fill"); SleepEvidence(data: item) } } } }
public struct HeartSleepCouplingV08View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { SectionHeader("Coupling matrix", icon: "square.grid.2x2"); Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { CardInner { Text("Autonomic\n\(Int(item.hrv.current)) ms · score \(item.coupling.autonomicScore)").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; CardInner { Text("Sleep\n\(durationText(item.architecture.totalSleep)) · score \(item.coupling.sleepRestorationScore)").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } }; GridRow { CardInner { CouplingHeader(data: item) }.gridCellColumns(2) } } }; Card { HeartEvidence(data: item); ZoneBar(zones: item.zones) }; Card { SleepEvidence(data: item) } } } }
public struct HeartSleepCouplingV09View: View { @Environment(\.theme) private var theme; public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { VStack(alignment: .center, spacing: Space.lg) { SectionHeader("Calm recovery check-in", icon: "leaf.fill"); RingGauge(value: item.coupling.recommendedIntensityCap, size: 96, stroke: 7, color: theme.accent); Text("Train below ceiling").font(TypeScale.title); Text(item.coupling.message).font(TypeScale.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true); StatusPill(item.coupling.provider.label, tone: .primary) }.frame(maxWidth: .infinity) }; Card { HStack { Metric(value: "\(Int(item.hrv.current)) ms", label: "HRV"); Spacer(); Metric(value: "\(Int(item.rhr.currentBPM)) bpm", label: "RHR"); Spacer(); Metric(value: "-\(Int(item.hrr.oneMinuteDrop)) bpm", label: "HRR") } }; Card { SleepEvidence(data: item) } } } }
public struct HeartSleepCouplingV10View: View { public let data: HeartSleepCouplingPreviewData; public init(data: HeartSleepCouplingPreviewData = .init()) { self.data = data }; public var body: some View { CandidateScaffold(data: data) { item in Card { SectionHeader("Sports science console", icon: "waveform.path.ecg.rectangle"); Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) { GridRow { TelemetryCell(title: "HRV", value: "\(Int(item.hrv.current)) ms"); TelemetryCell(title: "RHR", value: "\(Int(item.rhr.currentBPM)) bpm") }; GridRow { TelemetryCell(title: "Sleep", value: durationText(item.architecture.totalSleep)); TelemetryCell(title: "Debt", value: durationText(item.debt.sevenDay)) } }; CouplingHeader(data: item) }; Card { HeartEvidence(data: item); ZoneBar(zones: item.zones) }; Card { SleepEvidence(data: item) } } } }
private struct TelemetryCell: View { let title: String; let value: String; var body: some View { CardInner { VStack(alignment: .leading) { Text(title).font(TypeScale.meta); Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1) } } } }

public struct HeartSleepCouplingPreviewHost: View {
    @State private var variant = 1
    @State private var state: HeartSleepCouplingPreviewState = .populated
    public init() {}
    public var body: some View { VStack(spacing: 0) { Picker("Candidate", selection: $variant) { ForEach(1...10, id: \.self) { Text("v\($0, format: .number.precision(.integerLength(2)))").tag($0) } }.pickerStyle(.segmented).padding(Space.sm); Picker("State", selection: $state) { ForEach(HeartSleepCouplingPreviewState.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, Space.sm); selectedView(state: state) }.designThemePreview(seed: .teal, neutral: .slate) }
    @ViewBuilder private func selectedView(state: HeartSleepCouplingPreviewState) -> some View { let data = HeartSleepCouplingPreviewData(state: state); switch variant { case 1: HeartSleepCouplingV01View(data: data); case 2: HeartSleepCouplingV02View(data: data); case 3: HeartSleepCouplingV03View(data: data); case 4: HeartSleepCouplingV04View(data: data); case 5: HeartSleepCouplingV05View(data: data); case 6: HeartSleepCouplingV06View(data: data); case 7: HeartSleepCouplingV07View(data: data); case 8: HeartSleepCouplingV08View(data: data); case 9: HeartSleepCouplingV09View(data: data); default: HeartSleepCouplingV10View(data: data) } }
}

#Preview("Heart Sleep Coupling Host") { HeartSleepCouplingPreviewHost() }
#Preview("Heart Sleep Coupling Dark") { HeartSleepCouplingV01View().preferredColorScheme(.dark).designThemePreview(seed: .teal, neutral: .slate) }
