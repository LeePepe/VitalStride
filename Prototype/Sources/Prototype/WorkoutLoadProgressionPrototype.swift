import DesignKit
import SwiftUI

public enum WorkoutLoadProgressionPreviewState: String, CaseIterable, Sendable {
    case populated, empty, loading, error
}

public enum WorkoutLoadProgressionPreviewProvider: String, CaseIterable, Sendable {
    case onDevice, localRules
    var label: String { self == .onDevice ? "On-device AI" : "Local rules" }
}

public enum WorkoutLoadProgressionPhase: String, CaseIterable, Sendable {
    case accumulation, intensification, realization, deload
    var shortLabel: String { ["Accum.", "Intens.", "Realiz.", "Deload"][Self.allCases.firstIndex(of: self) ?? 0] }
}

public struct WorkoutLoadProgressionPreviewData: Sendable, Equatable {
    public struct DailyPoint: Sendable, Equatable { public let ctl: Double; public let atl: Double; public let tsb: Double; public init(ctl: Double, atl: Double, tsb: Double) { self.ctl = ctl; self.atl = atl; self.tsb = tsb } }
    public let state: WorkoutLoadProgressionPreviewState
    public let provider: WorkoutLoadProgressionPreviewProvider
    public let phase: WorkoutLoadProgressionPhase
    public let ctl: Double
    public let atl: Double
    public let tsb: Double
    public let acwr: Double
    public let trimp: Int
    public let tss: Int
    public let zones: [Int]
    public let ef: Double
    public let decoupling: Double
    public let vo2: Double
    public let vo2Trend: Double
    public let readiness: Int
    public let fatigue: Int
    public let points: [DailyPoint]

    public init(state: WorkoutLoadProgressionPreviewState = .populated, provider: WorkoutLoadProgressionPreviewProvider = .localRules) {
        self.state = state; self.provider = provider; self.phase = .intensification
        self.ctl = 64.7; self.atl = 58.4; self.tsb = 6.3; self.acwr = 0.90
        self.trimp = 312; self.tss = 268; self.zones = [36, 108, 22, 26, 8]
        self.ef = 0.086; self.decoupling = 3.4; self.vo2 = 51.4; self.vo2Trend = 1.8
        self.readiness = 84; self.fatigue = 83
        self.points = (0..<14).map { index in DailyPoint(ctl: 58 + Double(index) * 0.5, atl: 54 + Double(index % 5), tsb: 4 + Double(index % 4)) }
    }
}

private func number(_ value: Double, digits: Int = 1) -> String { value.formatted(.number.precision(.fractionLength(digits))) }
private func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
private func duration(_ minutes: Int) -> String { "\(minutes / 60)h \(minutes % 60)m" }

private struct PrototypeStateView: View {
    @Environment(\.theme) private var theme
    let state: WorkoutLoadProgressionPreviewState
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: icon).font(.title2).foregroundStyle(state == .error ? theme.danger : theme.accent).accessibilityHidden(true)
                Text(title).font(TypeScale.title)
                Text(message).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
                if state == .empty || state == .error { DesignButton(state == .error ? "Retry" : "Open Health Settings", variant: .secondary, action: {}) }
            }.frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
        }
    }
    private var icon: String { switch state { case .empty: "tray"; case .loading: "hourglass"; case .error: "exclamationmark.triangle"; case .populated: "chart.xyaxis.line" } }
    private var title: String { switch state { case .empty: "Build your load baseline"; case .loading: "Preparing load detail"; case .error: "Load detail unavailable"; case .populated: "" } }
    private var message: String { switch state { case .empty: "Complete a workout to unlock load and progression evidence."; case .loading: "Gathering recent training evidence."; case .error: "Your local data is safe. Retry when the source is available."; case .populated: "" } }
}

private struct PrototypeShell<Content: View>: View {
    let data: WorkoutLoadProgressionPreviewData
    @ViewBuilder let content: (WorkoutLoadProgressionPreviewData) -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if data.state == .populated { content(data) } else { PrototypeStateView(state: data.state) }
            }.padding(Space.md).frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }.background(.clear)
    }
}

private struct PhaseTrack: View {
    @Environment(\.theme) private var theme
    let data: WorkoutLoadProgressionPreviewData
    var body: some View { LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible(), spacing: Space.xs)], spacing: Space.xs) { ForEach(WorkoutLoadProgressionPhase.allCases, id: \.self) { phase in CardInner { Text(phase.shortLabel).font(TypeScale.meta).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(phase == data.phase ? theme.accent : theme.secondaryForeground) } } } }
}

private struct LoadMetrics: View {
    @Environment(\.theme) private var theme
    let data: WorkoutLoadProgressionPreviewData
    var body: some View { Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { tile("CTL", number(data.ctl), theme.chart(0)); tile("ATL", number(data.atl), theme.chart(1)); tile("TSB", "+\(number(data.tsb))", theme.success) } } }
    @ViewBuilder private func tile(_ title: String, _ value: String, _ color: Color) -> some View { CardInner { VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.meta); Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85).foregroundStyle(color) } } }
}

private struct ZoneBars: View {
    @Environment(\.theme) private var theme
    let data: WorkoutLoadProgressionPreviewData
    var body: some View { VStack(alignment: .leading, spacing: Space.xs) { SectionHeader("Zone 1–5 distribution", icon: "heart.text.square.fill"); GeometryReader { proxy in HStack(spacing: 2) { ForEach(Array(data.zones.enumerated()), id: \.offset) { index, minutes in Rectangle().fill(theme.chart(index)).frame(width: max(2, proxy.size.width * CGFloat(minutes) / CGFloat(data.zones.reduce(0, +)))) } }.clipShape(Capsule()) }.frame(height: 14); ForEach(Array(data.zones.enumerated()), id: \.offset) { index, minutes in HStack { Text("Z\(index + 1)").font(TypeScale.meta).frame(width: 24, alignment: .leading); GeometryReader { proxy in Capsule().fill(theme.chart(index).opacity(0.28)).overlay(alignment: .leading) { Capsule().fill(theme.chart(index)).frame(width: proxy.size.width * CGFloat(minutes) / CGFloat(data.zones.reduce(0, +))) } }.frame(height: 8); Text(duration(minutes)).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1); Text(pct(Double(minutes) / Double(data.zones.reduce(0, +)))).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1) } } } }
}

private struct Trajectory: View {
    @Environment(\.theme) private var theme
    let data: WorkoutLoadProgressionPreviewData
    var body: some View { GeometryReader { proxy in Path { path in for (index, point) in data.points.enumerated() { let x = proxy.size.width * CGFloat(index) / 13; let y = proxy.size.height * CGFloat(1 - (point.ctl - 56) / 16); index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y)) } }.stroke(theme.chart(0), lineWidth: 2); Path { path in for (index, point) in data.points.enumerated() { let x = proxy.size.width * CGFloat(index) / 13; let y = proxy.size.height * CGFloat(1 - (point.atl - 52) / 16); index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y)) } }.stroke(theme.chart(1), lineWidth: 2) }.frame(height: 82) }
}

private struct SummaryHeader: View {
    @Environment(\.theme) private var theme
    let data: WorkoutLoadProgressionPreviewData
    var body: some View { HStack { SectionHeader("Fitness periodization · L3", icon: "calendar.badge.clock"); Spacer(); StatusPill(data.provider.label, tone: .primary) }; Text("85%").font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.accent); Text("Recommended intensity ceiling").font(TypeScale.meta).foregroundStyle(theme.secondaryForeground); HStack { StatusPill("Readiness \(data.readiness)", tone: .success); StatusPill("Fatigue \(data.fatigue)", tone: .warning) } }
}

public struct WorkoutLoadProgressionV01View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SummaryHeader(data: item); PhaseTrack(data: item) }; Card { SectionHeader("PMC horizon", icon: "chart.xyaxis.line"); LoadMetrics(data: item); CardInner { Trajectory(data: item) }; StatusPill("ACWR \(number(item.acwr, digits: 2)) · Sweet spot", tone: .success) }; Card { ZoneBars(data: item) }; Card { SectionHeader("Aerobic efficiency", icon: "lungs.fill"); HStack { Metric(value: number(item.ef, digits: 3), label: "EF"); Spacer(); Metric(value: number(item.vo2), label: "VO2max", delta: ("+\(number(item.vo2Trend))", true)) } } } } }

public struct WorkoutLoadProgressionV02View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("PERIODIZATION MANIFESTO", icon: "waveform.path.ecg"); HStack(alignment: .bottom) { Text("+\(number(item.tsb))").font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1); Spacer(); VStack(alignment: .trailing) { Text("85%").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); Text("ceiling").font(TypeScale.meta) } }; Text("TSB training form · ACWR \(number(item.acwr, digits: 2))").font(TypeScale.body) }; Card { SectionHeader("Clinical load ledger"); ledger("CTL 42d fitness", number(item.ctl), "+3.1 / +5.8"); ledger("ATL 7d fatigue", number(item.atl), "−4.2"); ledger("TRIMP / TSS", "\(item.trimp) / \(item.tss)", "hybrid stress"); ledger("Deduplicated sessions", "9", "clean history") }; Card { ZoneBars(data: item) }; Card { ledger("EF pace / heart", number(item.ef, digits: 3), "(km/h)/bpm"); ledger("Pa:Hr durability", "\(number(item.decoupling))%", "coupled"); ledger("VO2max", number(item.vo2), "+\(number(item.vo2Trend))") } } } }
    @ViewBuilder private func ledger(_ title: String, _ value: String, _ detail: String) -> some View { HStack { Text(title).font(TypeScale.body); Spacer(); VStack(alignment: .trailing) { Text(value).font(TypeScale.num).monospacedDigit().lineLimit(1).layoutPriority(1); Text(detail).font(TypeScale.meta) } }.padding(.vertical, Space.xs); Divider() }

public struct WorkoutLoadProgressionV03View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { Card { SummaryHeader(data: item) }.gridCellColumns(2) }; GridRow { Card { Metric(value: number(item.ctl), label: "CTL · ATL \(number(item.atl))"); Trajectory(data: item) }; Card { Metric(value: number(item.acwr, digits: 2), label: "ACWR · TSB +\(number(item.tsb))"); StatusPill("Sweet spot", tone: .success); Text("TRIMP \(item.trimp) · TSS \(item.tss)").font(TypeScale.meta).monospacedDigit().lineLimit(1) } }; GridRow { Card { ZoneBars(data: item) }.gridCellColumns(2) }; GridRow { Card { Metric(value: number(item.ef, digits: 3), label: "EF") }; Card { Metric(value: number(item.vo2), label: "VO2max") } } } } } }

public struct WorkoutLoadProgressionV04View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in TimelineStep(icon: "arrow.up.right", title: "Accumulation") { CardInner { Text("Base volume builds the CTL horizon · \(number(item.ctl))").font(TypeScale.body) } }; TimelineStep(icon: "bolt.fill", title: "Intensification") { Card { SummaryHeader(data: item); CardInner { Text("Progress within the 85% ceiling.").font(TypeScale.body) } } }; TimelineStep(icon: "target", title: "Realization") { CardInner { HStack { Metric(value: number(item.acwr, digits: 2), label: "ACWR"); Spacer(); Metric(value: "+\(number(item.tsb))", label: "TSB") } } }; TimelineStep(icon: "arrow.down.right", title: "Deload") { CardInner { Text("Recovery window protects the next block.").font(TypeScale.body) } }; Card { ZoneBars(data: item) } } } }
private struct TimelineStep<Content: View>: View { @Environment(\.theme) private var theme; let icon: String; let title: String; @ViewBuilder let content: () -> Content; var body: some View { HStack(alignment: .top, spacing: Space.sm) { VStack { Image(systemName: icon).foregroundStyle(theme.accent); Rectangle().fill(theme.border).frame(width: 1) }.frame(width: 24); VStack(alignment: .leading, spacing: Space.xs) { Text(title).font(TypeScale.title); content() } } } }

public struct WorkoutLoadProgressionV05View: View { @Environment(\.theme) private var theme; public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { HStack { CardInner { RingGauge(value: Double(item.readiness) / 100, color: theme.success); Text("Readiness").font(TypeScale.meta) }; CardInner { RingGauge(value: Double(item.fatigue) / 100, color: theme.warning); Text("Balance").font(TypeScale.meta) } }; SummaryHeader(data: item) }; Card { SectionHeader("Dual rotor", icon: "arrow.triangle.2.circlepath"); HStack { Metric(value: number(item.acwr, digits: 2), label: "ACWR"); Spacer(); Metric(value: "\(item.trimp)", label: "TRIMP"); Spacer(); Metric(value: "\(item.tss)", label: "TSS") }; Trajectory(data: item) }; Card { ZoneBars(data: item) }; Card { Metric(value: number(item.vo2), label: "VO2max", delta: ("+\(number(item.vo2Trend))", true)) } } } }

public struct WorkoutLoadProgressionV06View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Multi-curve chart studio", icon: "chart.xyaxis.line"); Trajectory(data: item); LoadMetrics(data: item); Text("CTL fitness · ATL fatigue · TSB form").font(TypeScale.meta) }; Card { SectionHeader("Zone spectrum", icon: "chart.bar.fill"); ZoneBars(data: item) }; Card { SectionHeader("Efficiency curve", icon: "speedometer"); HStack { Metric(value: number(item.ef, digits: 3), label: "EF"); Spacer(); Metric(value: "\(number(item.decoupling))%", label: "Pa:Hr"); Spacer(); Metric(value: number(item.vo2), label: "VO2max") } }; Card { SummaryHeader(data: item) } } } }

public struct WorkoutLoadProgressionV07View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SummaryHeader(data: item); Divider(); Text("Coach guardrails").font(TypeScale.title); HStack { StatusPill("CNS controlled", tone: .success); StatusPill("Zone 2 recovery", tone: .neutral) } }; Card { SectionHeader("Evidence pillar 1", icon: "figure.strengthtraining.traditional"); LoadMetrics(data: item); Text("TRIMP \(item.trimp) · TSS \(item.tss)").font(TypeScale.num).monospacedDigit().lineLimit(1) }; Card { SectionHeader("Evidence pillar 2", icon: "heart.fill"); ZoneBars(data: item) }; Card { SectionHeader("Evidence pillar 3", icon: "lungs.fill"); Metric(value: number(item.vo2), label: "VO2max", delta: ("+\(number(item.vo2Trend))", true)) } } } }

public struct WorkoutLoadProgressionV08View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Hybrid load matrix", icon: "square.grid.2x2"); Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { CardInner { Text("Cardio\nTRIMP \(item.trimp)").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; CardInner { Text("Strength\nTSS \(item.tss)").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } }; GridRow { CardInner { Text("Fitness\nCTL \(number(item.ctl))").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; CardInner { Text("Form\nTSB +\(number(item.tsb))").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } } }; StatusPill("ACWR \(number(item.acwr, digits: 2))", tone: .success) }; Card { ZoneBars(data: item) }; Card { HStack { Metric(value: number(item.ef, digits: 3), label: "EF"); Spacer(); Metric(value: number(item.vo2), label: "VO2max") } }; Card { SummaryHeader(data: item) } } } }

public struct WorkoutLoadProgressionV09View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { VStack(alignment: .center, spacing: Space.lg) { SectionHeader("Minimal adaptation focus", icon: "leaf.fill"); RingGauge(value: 0.85, size: 112, stroke: 8); Text("85%").font(TypeScale.metricXL).monospacedDigit().lineLimit(1).layoutPriority(1); Text("Controlled progression window").font(TypeScale.title); StatusPill(item.provider.label, tone: .primary) }.frame(maxWidth: .infinity) }; Card { HStack { Metric(value: "\(item.readiness)", label: "Ready"); Spacer(); Metric(value: number(item.acwr, digits: 2), label: "ACWR"); Spacer(); Metric(value: "+\(number(item.tsb))", label: "Form") } }; Card { ZoneBars(data: item) }; Card { HStack { Metric(value: number(item.ef, digits: 3), label: "EF"); Spacer(); Metric(value: number(item.vo2), label: "VO2max") } } } } }

public struct WorkoutLoadProgressionV10View: View { public let data: WorkoutLoadProgressionPreviewData; public init(data: WorkoutLoadProgressionPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Performance telemetry lab", icon: "waveform.path.ecg.rectangle"); Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) { GridRow { TelemetryCell(title: "CTL", value: number(item.ctl)); TelemetryCell(title: "ATL", value: number(item.atl)) }; GridRow { TelemetryCell(title: "ACWR", value: number(item.acwr, digits: 2)); TelemetryCell(title: "TSB", value: "+\(number(item.tsb))") }; GridRow { TelemetryCell(title: "EF", value: number(item.ef, digits: 3)); TelemetryCell(title: "VO2max", value: number(item.vo2)) } }; SummaryHeader(data: item) }; Card { ZoneBars(data: item) }; Card { SectionHeader("Prescription", icon: "checkmark.seal.fill"); Text("Keep the session controlled, then protect recovery before the next block.").font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } } } }
private struct TelemetryCell: View { let title: String; let value: String; var body: some View { CardInner { VStack(alignment: .leading) { Text(title).font(TypeScale.meta); Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.85) } } } }

public struct WorkoutLoadProgressionPreviewHost: View {
    @State private var variant = 1
    @State private var state: WorkoutLoadProgressionPreviewState = .populated
    public init() {}
    public var body: some View { VStack(spacing: 0) { Picker("Candidate", selection: $variant) { ForEach(1...10, id: \.self) { Text("v\($0)").tag($0) } }.pickerStyle(.segmented).padding(Space.sm); Picker("State", selection: $state) { ForEach(WorkoutLoadProgressionPreviewState.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, Space.sm); selectedView }.designThemePreview(seed: .teal, neutral: .slate) }
    @ViewBuilder private var selectedView: some View { let data = WorkoutLoadProgressionPreviewData(state: state); switch variant { case 1: WorkoutLoadProgressionV01View(data: data); case 2: WorkoutLoadProgressionV02View(data: data); case 3: WorkoutLoadProgressionV03View(data: data); case 4: WorkoutLoadProgressionV04View(data: data); case 5: WorkoutLoadProgressionV05View(data: data); case 6: WorkoutLoadProgressionV06View(data: data); case 7: WorkoutLoadProgressionV07View(data: data); case 8: WorkoutLoadProgressionV08View(data: data); case 9: WorkoutLoadProgressionV09View(data: data); default: WorkoutLoadProgressionV10View(data: data) } }
}

#Preview("Workout Load Host") { WorkoutLoadProgressionPreviewHost() }
