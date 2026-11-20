import DesignKit
import SwiftUI

public enum StepsBodySettingsPreviewState: String, CaseIterable, Sendable {
    case populated, empty, loading, error
}

public enum StepsBodyPreviewProvider: String, CaseIterable, Sendable {
    case foundationModels, customOpenAICompatible, jevGateway, deterministicFallback

    public var label: String {
        switch self {
        case .foundationModels: "On-device AI"
        case .customOpenAICompatible: "Custom API"
        case .jevGateway: "Jev Gateway"
        case .deterministicFallback: "Offline rules"
        }
    }
}

public struct StepsBodySettingsPreviewData: Sendable, Equatable {
    public struct WeightPoint: Sendable, Equatable { public let raw: Double; public let average: Double; public init(raw: Double, average: Double) { self.raw = raw; self.average = average } }
    public let state: StepsBodySettingsPreviewState
    public let provider: StepsBodyPreviewProvider
    public let dailySteps: Double
    public let nonWorkoutSteps: Double
    public let workoutStepsExcluded: Double
    public let hourlyNonWorkoutDistribution: [Int: Double]
    public let activeNonWorkoutHourCount: Int
    public let hourlyMovementConsistency: Double
    public let standDurationHours: Double
    public let flightsClimbed: Double
    public let nonExerciseActiveEnergy: Double
    public let workoutActiveEnergyExcluded: Double
    public let basalEnergy: Double
    public let burdenRatio: Double
    public let latestWeightKg: Double
    public let weightChange7dKg: Double
    public let weightPoints: [WeightPoint]
    public let bodyFatPercentage: Double?
    public let leanBodyMassKg: Double?
    public let bmi: Double?
    public let readinessScore: Int
    public let autonomicScore: Int
    public let fatigueBalanceScore: Int
    public let couplingNarrative: String
    public let allowsUnauthenticatedGateway: Bool

    public init(state: StepsBodySettingsPreviewState = .populated, provider: StepsBodyPreviewProvider = .foundationModels) {
        self.state = state
        self.provider = provider
        self.dailySteps = 9_420
        self.nonWorkoutSteps = 7_680
        self.workoutStepsExcluded = 1_740
        self.hourlyNonWorkoutDistribution = Dictionary(uniqueKeysWithValues: (0..<24).map { hour in
            let peak = max(0.08, sin(Double(hour) * .pi / 12) + 1.15)
            return (hour, peak * (hour.isMultiple(of: 5) ? 1.25 : 0.72))
        })
        self.activeNonWorkoutHourCount = 11
        self.hourlyMovementConsistency = 0.79
        self.standDurationHours = 9.4
        self.flightsClimbed = 8
        self.nonExerciseActiveEnergy = 340
        self.workoutActiveEnergyExcluded = 410
        self.basalEnergy = 1_680
        self.burdenRatio = 0.20
        self.latestWeightKg = 73.4
        self.weightChange7dKg = -0.6
        let raw = [74.0, 73.9, 73.8, 73.7, 73.6, 73.5, 73.4]
        self.weightPoints = raw.enumerated().map { index, value in
            let values = raw.prefix(index + 1)
            return WeightPoint(raw: value, average: values.reduce(0, +) / Double(values.count))
        }
        self.bodyFatPercentage = 15.8
        self.leanBodyMassKg = 61.8
        self.bmi = 22.4
        self.readinessScore = 84
        self.autonomicScore = 86
        self.fatigueBalanceScore = 83
        self.couplingNarrative = "Steady non-workout movement supports peripheral circulation and active recovery without adding central nervous system fatigue. Expenditure is observed independently from intake."
        self.allowsUnauthenticatedGateway = provider == .jevGateway
    }
}

private func compact(_ value: Double, digits: Int = 0) -> String { value.formatted(.number.precision(.fractionLength(digits))) }
private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

private struct PrototypeState: View {
    @Environment(\.theme) private var theme
    let state: StepsBodySettingsPreviewState
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: icon).font(.title2).foregroundStyle(state == .error ? theme.danger : theme.accent).accessibilityHidden(true)
                Text(title).font(TypeScale.title)
                Text(message).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
                if state == .empty || state == .error { DesignButton(state == .error ? "Retry" : "Open Health Settings", variant: .secondary) {} }
            }
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
        }
    }
    private var icon: String { switch state { case .empty: "tray"; case .loading: "hourglass"; case .error: "exclamationmark.triangle"; case .populated: "figure.walk" } }
    private var title: String { switch state { case .empty: "Build your recovery baseline"; case .loading: "Preparing recovery detail"; case .error: "Recovery detail unavailable"; case .populated: "" } }
    private var message: String { switch state { case .empty: "Health data is not available for this view."; case .loading: "Gathering recent movement and body evidence."; case .error: "Local data is safe. Retry when the source is available."; case .populated: "" } }
}

private struct PrototypeShell<Content: View>: View {
    let data: StepsBodySettingsPreviewData
    @ViewBuilder let content: (StepsBodySettingsPreviewData) -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if data.state == .populated { content(data) } else { PrototypeState(state: data.state) }
            }.padding(Space.md).frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }.background(.clear)
    }
}

private struct MiniMetric: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground).lineLimit(1).minimumScaleFactor(0.85)
            Text(value).font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CadenceBars: View {
    @Environment(\.theme) private var theme
    let data: StepsBodySettingsPreviewData
    var body: some View {
        GeometryReader { proxy in
            let maxValue = data.hourlyNonWorkoutDistribution.values.max() ?? 1
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    Capsule().fill(theme.chart(hour % 4)).frame(maxWidth: .infinity, maxHeight: proxy.size.height * CGFloat((data.hourlyNonWorkoutDistribution[hour] ?? 0) / maxValue))
                }
            }
        }.frame(height: 52)
    }
}

private struct WeightTrend: View {
    @Environment(\.theme) private var theme
    let data: StepsBodySettingsPreviewData
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Sparkline(data: data.weightPoints.map(\.raw), color: theme.chart(0))
            Sparkline(data: data.weightPoints.map(\.average), color: theme.success)
            HStack { Text("raw").font(TypeScale.meta); Spacer(); Text("7d average").font(TypeScale.meta).foregroundStyle(theme.success) }
        }
    }
}

private struct ProviderTiles: View {
    @Environment(\.theme) private var theme
    let data: StepsBodySettingsPreviewData
    var body: some View {
        Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
            GridRow { provider("On-device", .foundationModels); provider("Custom API", .customOpenAICompatible) }
            GridRow { provider("Jev Gateway", .jevGateway); provider("Offline rules", .deterministicFallback) }
        }
    }
    private func provider(_ title: String, _ provider: StepsBodyPreviewProvider) -> some View {
        CardInner { VStack(alignment: .leading, spacing: Space.hair) { Image(systemName: icon(provider)).foregroundStyle(data.provider == provider ? theme.accent : theme.secondaryForeground); Text(title).font(TypeScale.meta).lineLimit(1).minimumScaleFactor(0.8); Text(data.provider == provider ? "Active" : "Ready").font(TypeScale.meta).foregroundStyle(data.provider == provider ? theme.accent : theme.secondaryForeground) } }
    }
    private func icon(_ provider: StepsBodyPreviewProvider) -> String { switch provider { case .foundationModels: "apple.intelligence"; case .customOpenAICompatible: "network"; case .jevGateway: "arrow.triangle.branch"; case .deterministicFallback: "lock.shield" } }
}

private func standardBody(_ item: StepsBodySettingsPreviewData) -> some View {
    Group {
        Card {
            HStack { SectionHeader("Steps × Body Recovery · L2", icon: "figure.walk.motion"); Spacer(); StatusPill(item.provider.label, tone: .primary) }
            CardInner { HStack { MiniMetric(title: "Pure NEAT", value: compact(item.nonWorkoutSteps)); Spacer(); MiniMetric(title: "Readiness", value: "\(item.readinessScore)") } }
            HStack { StatusPill("Autonomic \(item.autonomicScore)", tone: .success); StatusPill("Fatigue \(item.fatigueBalanceScore)", tone: .warning) }
            Text(item.couplingNarrative).font(TypeScale.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Card {
            SectionHeader("Daily NEAT · L1", icon: "flame.fill")
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { MiniMetric(title: "Total steps", value: compact(item.dailySteps)); MiniMetric(title: "Active hours", value: "\(item.activeNonWorkoutHourCount)h"); MiniMetric(title: "Consistency", value: percent(item.hourlyMovementConsistency)) } }
            CardInner { VStack(alignment: .leading, spacing: Space.xs) { CadenceBars(data: item); HStack { Text("00h"); Spacer(); Text("06h"); Spacer(); Text("12h"); Spacer(); Text("18h"); Spacer(); Text("23h") }.font(TypeScale.meta) } }
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { MiniMetric(title: "NEAT energy", value: "\(compact(item.nonExerciseActiveEnergy)) kcal"); MiniMetric(title: "Basal energy", value: "\(compact(item.basalEnergy)) kcal") } }
        }
        Card {
            HStack { SectionHeader("Body mass · L1", icon: "scalemass.fill"); Spacer(); StatusPill("−0.6 kg", tone: .success) }
            HStack { MiniMetric(title: "Latest", value: "\(compact(item.latestWeightKg, digits: 1)) kg"); Spacer(); MiniMetric(title: "7d average", value: "73.6 kg") }
            WeightTrend(data: item)
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { MiniMetric(title: "Body fat", value: "15.8%"); MiniMetric(title: "Lean mass", value: "61.8 kg"); MiniMetric(title: "BMI", value: "22.4") } }
            Text("Observed expenditure and body-mass trends do not infer caloric balance without intake data.").font(TypeScale.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Card { HStack { SectionHeader("AI routing", icon: "cpu.fill"); Spacer(); StatusPill("Ready", tone: .success) }; ProviderTiles(data: item); CardInner { VStack(alignment: .leading, spacing: Space.hair) { Text("Fallback chain").font(TypeScale.meta); Text("On-device → Custom API → Offline rules").font(TypeScale.body).lineLimit(1).minimumScaleFactor(0.75) } } }
    }
}

public struct StepsBodySettingsV01View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in standardBody(item) } } }
public struct StepsBodySettingsV02View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Recovery ledger", icon: "list.bullet.clipboard"); HStack(alignment: .bottom) { Text(compact(item.nonWorkoutSteps)).font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75); Spacer(); Text("\(item.readinessScore)").font(TypeScale.metricXL).monospacedDigit().lineLimit(1) }; Text(item.couplingNarrative).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; Card { ForEach([("Steps / total", "\(compact(item.nonWorkoutSteps)) / \(compact(item.dailySteps))"), ("Energy / basal", "340 / 1,680 kcal"), ("Movement rhythm", "79% · 11h"), ("Weight / trend", "73.4 kg · −0.6 kg")], id: \.0) { row in HStack { Text(row.0).font(TypeScale.body); Spacer(); Text(row.1).font(TypeScale.num).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }; Divider() } }; Card { SectionHeader("Provider routing ledger", icon: "point.3.connected.trianglepath.dotted"); ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV03View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Grid(horizontalSpacing: Space.gap, verticalSpacing: Space.gap) { GridRow { Card { SectionHeader("Coupling hero", icon: "sparkles"); MiniMetric(title: "NEAT / readiness", value: "7,680 / 84"); StatusPill("79% consistent", tone: .success); Text(item.couplingNarrative).font(TypeScale.meta).fixedSize(horizontal: false, vertical: true) }.gridCellColumns(2) }; GridRow { Card { MiniMetric(title: "Steps split", value: "7,680 / 1,740"); Text("340 kcal NEAT").font(TypeScale.meta) }; Card { SectionHeader("Cadence"); CadenceBars(data: item); Text("11 active hours").font(TypeScale.meta) } }; GridRow { Card { MiniMetric(title: "Weight", value: "73.4 kg"); WeightTrend(data: item) }; Card { MiniMetric(title: "Composition", value: "15.8% / 22.4"); Text("Observed only").font(TypeScale.meta) } }; GridRow { Card { ProviderTiles(data: item) }.gridCellColumns(2) } } } } }
public struct StepsBodySettingsV04View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in ForEach(Array([("Input", "24h movement cadence"), ("Coupling", "NEAT 340 kcal / basal 1,680 kcal"), ("Trend", "7-day weight average 73.6 kg"), ("Routing", "Primary → optional fallback → offline")].enumerated()), id: \.offset) { index, stage in HStack(alignment: .top, spacing: Space.sm) { VStack { Image(systemName: ["chart.bar.xaxis", "arrow.triangle.merge", "chart.line.uptrend.xyaxis", "cpu"][index]).foregroundStyle(.secondary); Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1) }.frame(width: 24); Card { SectionHeader("Stage \(index + 1)"); Text(stage.0).font(TypeScale.title); Text(stage.1).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) } } }; Card { ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV05View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { HStack { CardInner { RingGauge(value: item.hourlyMovementConsistency, size: 72); Text("Cadence").font(TypeScale.meta) }; CardInner { RingGauge(value: Double(item.readinessScore) / 100, size: 72); Text("Readiness").font(TypeScale.meta) } }; Text(item.couplingNarrative).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; Card { HStack { MiniMetric(title: "NEAT", value: "340 kcal"); MiniMetric(title: "Basal", value: "1,680 kcal"); MiniMetric(title: "Weight", value: "73.4 kg") }; WeightTrend(data: item) }; Card { SectionHeader("Four-mode engine", icon: "switch.2"); ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV06View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Telemetry canvas", icon: "waveform.path.ecg"); CadenceBars(data: item); HStack { MiniMetric(title: "NEAT", value: "7,680"); MiniMetric(title: "Consistency", value: "79%") } }; Card { SectionHeader("Energy burden", icon: "chart.bar.xaxis"); HStack { MiniMetric(title: "NEAT / basal", value: "20%"); MiniMetric(title: "Recovery", value: "84") }; Text(item.couplingNarrative).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; Card { SectionHeader("Weight envelope", icon: "chart.xyaxis.line"); WeightTrend(data: item); HStack { MiniMetric(title: "Body fat", value: "15.8%"); MiniMetric(title: "Lean mass", value: "61.8 kg"); MiniMetric(title: "BMI", value: "22.4") } }; Card { SectionHeader("AI inspector dock", icon: "slider.horizontal.3"); ProviderTiles(data: item); Text("Keychain credential · masked").font(TypeScale.meta) } } } }
public struct StepsBodySettingsV07View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Active recovery prescription", icon: "clipboard.fill"); Text("84").font(TypeScale.metricXL).monospacedDigit().lineLimit(1); Text("7,680 NEAT steps · 20% burden ratio").font(TypeScale.title).lineLimit(1).minimumScaleFactor(0.75); Text(item.couplingNarrative).font(TypeScale.body).fixedSize(horizontal: false, vertical: true) }; Card { SectionHeader("Evidence pillar 1", icon: "flame.fill"); CadenceBars(data: item); HStack { MiniMetric(title: "Active hours", value: "11h"); MiniMetric(title: "Standing", value: "9.4h"); MiniMetric(title: "Flights", value: "8") } }; Card { SectionHeader("Evidence pillar 2", icon: "scalemass.fill"); HStack { MiniMetric(title: "Weight", value: "73.4 kg"); MiniMetric(title: "Trend", value: "−0.6 kg") }; WeightTrend(data: item) }; Card { SectionHeader("Evidence pillar 3", icon: "cpu.fill"); ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV08View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Physiological × AI matrix", icon: "square.grid.2x2"); Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { CardInner { MiniMetric(title: "NEAT vector", value: "7,680") }; CardInner { MiniMetric(title: "Energy vector", value: "20%") } }; GridRow { CardInner { MiniMetric(title: "Body vector", value: "73.4 kg") }; CardInner { MiniMetric(title: "AI vector", value: "84") } }; GridRow { CardInner { Text(item.couplingNarrative).font(TypeScale.meta).fixedSize(horizontal: false, vertical: true) }.gridCellColumns(2) } } }; Card { CadenceBars(data: item); WeightTrend(data: item) }; Card { ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV09View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { VStack(alignment: .center, spacing: Space.sm) { SectionHeader("Active recovery sanctuary", icon: "leaf.fill"); RingGauge(value: item.hourlyMovementConsistency, size: 88, stroke: 7); Text("79%").font(TypeScale.metricXL).monospacedDigit().lineLimit(1); Text("7,680 NEAT steps · readiness 84").font(TypeScale.title).lineLimit(1).minimumScaleFactor(0.75); Text(item.couplingNarrative).font(TypeScale.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true); StatusPill(item.provider.label, tone: .primary) }.frame(maxWidth: .infinity) }; Card { HStack { MiniMetric(title: "NEAT", value: "340 kcal"); MiniMetric(title: "Standing", value: "9.4h"); MiniMetric(title: "Weight", value: "73.4 kg") }; WeightTrend(data: item) }; Card { ProviderTiles(data: item) } } } }
public struct StepsBodySettingsV10View: View { public let data: StepsBodySettingsPreviewData; public init(data: StepsBodySettingsPreviewData = .init()) { self.data = data }; public var body: some View { PrototypeShell(data: data) { item in Card { SectionHeader("Biometric routing workbench", icon: "waveform.path.ecg.rectangle"); Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) { GridRow { MiniMetric(title: "Pure NEAT", value: "7,680"); MiniMetric(title: "Movement", value: "79%") }; GridRow { MiniMetric(title: "NEAT energy", value: "340"); MiniMetric(title: "Body mass", value: "73.4") }; GridRow { MiniMetric(title: "Readiness", value: "84"); MiniMetric(title: "Burden", value: "20%") } }; CardInner { Text(item.couplingNarrative).font(TypeScale.meta).fixedSize(horizontal: false, vertical: true) } }; Card { CadenceBars(data: item); WeightTrend(data: item); HStack { MiniMetric(title: "Body fat", value: "15.8%"); MiniMetric(title: "Lean mass", value: "61.8 kg"); MiniMetric(title: "BMI", value: "22.4") } }; Card { SectionHeader("Provider configuration", icon: "key.fill"); ProviderTiles(data: item); Text("baseURL · modelID · keychainService · local auth toggle").font(TypeScale.meta).lineLimit(1).minimumScaleFactor(0.75) } } } }

public struct StepsBodySettingsPreviewHost: View {
    @State private var variant = 1
    @State private var previewState: StepsBodySettingsPreviewState = .populated
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            Picker("Candidate", selection: $variant) { ForEach(1...10, id: \.self) { Text("v\($0)").tag($0) } }.pickerStyle(.segmented).padding(Space.sm)
            Picker("State", selection: $previewState) { ForEach(StepsBodySettingsPreviewState.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, Space.sm)
            selectedView
        }.designThemePreview(seed: .teal, neutral: .slate)
    }
    @ViewBuilder private var selectedView: some View {
        let data = StepsBodySettingsPreviewData(state: previewState)
        switch variant {
        case 1: StepsBodySettingsV01View(data: data)
        case 2: StepsBodySettingsV02View(data: data)
        case 3: StepsBodySettingsV03View(data: data)
        case 4: StepsBodySettingsV04View(data: data)
        case 5: StepsBodySettingsV05View(data: data)
        case 6: StepsBodySettingsV06View(data: data)
        case 7: StepsBodySettingsV07View(data: data)
        case 8: StepsBodySettingsV08View(data: data)
        case 9: StepsBodySettingsV09View(data: data)
        default: StepsBodySettingsV10View(data: data)
        }
    }
}

#Preview("Steps Body Settings · Light") { StepsBodySettingsPreviewHost() }
#Preview("Steps Body Settings · Dark") { StepsBodySettingsPreviewHost().preferredColorScheme(.dark) }
