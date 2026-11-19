// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

public enum HolisticPreviewState: String, CaseIterable, Sendable {
    case populated
    case empty
    case loading
    case error
}

public enum HolisticPreviewProvider: String, CaseIterable, Sendable {
    case foundationModels
    case customOpenAICompatible
    case jevGateway
    case deterministicFallback

    public var label: String {
        switch self {
        case .foundationModels: "On-device AI"
        case .customOpenAICompatible: "Custom API"
        case .jevGateway: "Jev Gateway"
        case .deterministicFallback: "Deterministic fallback"
        }
    }
}

public struct HolisticPreviewReport: Sendable, Equatable {
    public let northStarScore: Int
    public let readinessScore: Int
    public let autonomicScore: Int
    public let sleepScore: Int
    public let fatigueScore: Int
    public let intensityCap: Double
    public let phase: String
    public let directive: String
    public let actions: [String]
    public let provider: HolisticPreviewProvider
    public let couplings: [String]

    public init(
        northStarScore: Int = 86,
        readinessScore: Int = 82,
        autonomicScore: Int = 84,
        sleepScore: Int = 79,
        fatigueScore: Int = 83,
        intensityCap: Double = 0.85,
        phase: String = "Intensification",
        directive: String = "Recovery and movement support controlled training today.",
        actions: [String] = [
            "Keep the planned session at a controlled effort.",
            "Protect a consistent sleep opportunity tonight.",
            "Use easy movement breaks between focused work blocks."
        ],
        provider: HolisticPreviewProvider = .deterministicFallback,
        couplings: [String] = ["Sleep × training load", "NEAT × heart"]
    ) {
        self.northStarScore = min(max(northStarScore, 0), 100)
        self.readinessScore = min(max(readinessScore, 0), 100)
        self.autonomicScore = min(max(autonomicScore, 0), 100)
        self.sleepScore = min(max(sleepScore, 0), 100)
        self.fatigueScore = min(max(fatigueScore, 0), 100)
        self.intensityCap = min(max(intensityCap, 0), 1)
        self.phase = phase
        self.directive = directive
        self.actions = Array(actions.prefix(3))
        self.provider = provider
        self.couplings = couplings
    }
}

public struct HolisticDashboardPreviewData: Sendable, Equatable {
    public let state: HolisticPreviewState
    public let report: HolisticPreviewReport

    public init(state: HolisticPreviewState = .populated, report: HolisticPreviewReport = .init()) {
        self.state = state
        self.report = report
    }
}

private struct PreviewStateCard: View {
    @Environment(\.theme) private var theme
    let state: HolisticPreviewState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(state == .error ? theme.danger : theme.accent)
                Text(title).font(TypeScale.title)
                Text(message)
                    .font(TypeScale.body)
                    .foregroundStyle(theme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .empty || state == .error {
                    DesignButton(state == .error ? "Retry" : "Open Health Settings", variant: .secondary, icon: state == .error ? "arrow.clockwise" : "gearshape") {}
                }
            }
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
        }
    }

    private var icon: String {
        switch state {
        case .populated: "chart.line.uptrend.xyaxis"
        case .empty: "tray"
        case .loading: "hourglass"
        case .error: "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch state {
        case .populated: "Holistic health"
        case .empty: "Build your baseline"
        case .loading: "Preparing your dashboard"
        case .error: "Dashboard unavailable"
        }
    }

    private var message: String {
        switch state {
        case .populated: ""
        case .empty: "Authorize health data or complete a workout to unlock your first synthesis."
        case .loading: "Gathering available domains."
        case .error: "Your last local view is safe. Retry when your data source is available."
        }
    }
}

private struct PreviewScore: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(TypeScale.meta).foregroundStyle(theme.secondaryForeground)
            Text("\(value)")
                .font(TypeScale.metricXL)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundStyle(accent)
        }
    }
}

private struct PreviewScoreArc: View {
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
        .frame(width: 76, height: 76)
    }
}

private struct PreviewPillRow: View {
    @Environment(\.theme) private var theme
    let report: HolisticPreviewReport

    var body: some View {
        HStack(spacing: Space.xs) {
            StatusPill(report.phase, tone: .primary)
            StatusPill(report.provider.label, tone: .neutral)
            Spacer(minLength: 0)
        }
    }
}

private struct PreviewActions: View {
    @Environment(\.theme) private var theme
    let report: HolisticPreviewReport
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Core actions", icon: "checkmark.seal.fill")
            ForEach(Array(report.actions.enumerated()), id: \.offset) { index, action in
                CardInner {
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text("\(index + 1)")
                            .font(TypeScale.num.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 24, height: 24)
                            .background(theme.accentSubtle, in: Circle())
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(action)
                                .font(compact ? TypeScale.meta : TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            if let coupling = report.couplings[safe: index] {
                                StatusPill(coupling, tone: .neutral)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PreviewDrillDowns: View {
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Quick drill-down", icon: "arrow.forward")
            HStack(spacing: Space.sm) {
                PreviewDrill(title: "Heart & Sleep", icon: "heart.text.square")
                PreviewDrill(title: "Workout Load", icon: "figure.strengthtraining.traditional")
                PreviewDrill(title: "Steps & AI", icon: "brain")
            }
        }
    }
}

private struct PreviewDrill: View {
    @Environment(\.theme) private var theme
    let title: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text(title).font(TypeScale.meta).lineLimit(2).layoutPriority(1)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(Space.sm)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: Radius.inner))
        .overlay(RoundedRectangle(cornerRadius: Radius.inner).stroke(theme.border, lineWidth: 1))
    }
}

private struct PreviewScaffold<Content: View>: View {
    let data: HolisticDashboardPreviewData
    @ViewBuilder let content: (HolisticPreviewReport) -> Content

    var body: some View {
        if data.state == .populated {
            content(data.report)
        } else {
            VStack {
                Spacer(minLength: 0)
                PreviewStateCard(state: data.state)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 820)
        }
    }
}

public struct HolisticDashboardV01View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    HStack(alignment: .center, spacing: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader("North star", icon: "scope")
                            PreviewScore(title: "L4 trajectory", value: report.northStarScore, accent: theme.accent)
                            Text(report.directive).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                        }
                        PreviewScoreArc(score: report.northStarScore, color: theme.accent)
                    }
                    PreviewPillRow(report: report)
                }
                Card {
                    HStack(alignment: .center, spacing: Space.lg) {
                        PreviewScoreArc(score: report.readinessScore, color: theme.success)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            PreviewScore(title: "Readiness", value: report.readinessScore, accent: theme.success)
                            PreviewScore(title: "Cap", value: Int((report.intensityCap * 100).rounded()), accent: theme.warning)
                        }
                    }
                    PreviewPillarRows(report: report)
                    PreviewActions(report: report, compact: true)
                }
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV02View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    SectionHeader("Executive briefing", icon: "text.alignleft")
                    Text(report.directive).font(TypeScale.title)
                    HStack {
                        PreviewScore(title: "North star", value: report.northStarScore, accent: theme.accent)
                        Spacer()
                        PreviewPillRow(report: report)
                    }
                }
                Card {
                    SectionHeader("Readiness ledger", icon: "list.number")
                    PreviewLedgerRow(title: "Today's readiness", value: report.readinessScore)
                    PreviewLedgerRow(title: "Autonomic", value: report.autonomicScore)
                    PreviewLedgerRow(title: "Sleep restoration", value: report.sleepScore)
                    PreviewLedgerRow(title: "Fatigue balance", value: report.fatigueScore)
                    PreviewLedgerRow(title: "Intensity cap", value: Int((report.intensityCap * 100).rounded()), suffix: "%")
                }
                PreviewActions(report: report, compact: true)
            }
        }
    }
}

private struct PreviewLedgerRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: Int
    var suffix = ""
    var body: some View {
        HStack {
            Text(title).font(TypeScale.body)
            Spacer()
            Text("\(value)\(suffix)").font(TypeScale.num.weight(.semibold)).monospacedDigit().layoutPriority(1)
        }
        .padding(.vertical, Space.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }
}

public struct HolisticDashboardV03View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(spacing: Space.lg) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Card {
                        SectionHeader("North star")
                        PreviewScore(title: "L4", value: report.northStarScore, accent: theme.accent)
                        Sparkline(data: [62, 70, 68, 75, 79, 83, Double(report.northStarScore)], color: theme.accent)
                    }
                    Card {
                        SectionHeader("Readiness")
                        PreviewScoreArc(score: report.readinessScore, color: theme.success)
                        StatusPill("Prime window", tone: .success)
                    }
                }
                Card {
                    PreviewPillarRows(report: report)
                }
                Card {
                    PreviewActions(report: report, compact: false)
                }
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV04View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.sm) {
                PreviewStage(title: "L4 · Holistic North Star") {
                    HStack { PreviewScore(title: "Trajectory", value: report.northStarScore, accent: theme.accent); Spacer(); Text(report.directive).font(TypeScale.body) }
                }
                PreviewStage(title: "L3 · Readiness gate") {
                    HStack { PreviewScore(title: "Today", value: report.readinessScore, accent: theme.success); Spacer(); StatusPill("Prime", tone: .success) }
                    PreviewPillRow(report: report)
                }
                PreviewStage(title: "L2 · Coupled directives") { PreviewActions(report: report, compact: true) }
                PreviewStage(title: "L1 · Source domains") { PreviewDrillDowns() }
            }
        }
    }
}

private struct PreviewStage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View { Card { SectionHeader(title); content() } }
}

public struct HolisticDashboardV05View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    HStack { StatusPill("PRIME", tone: .success); Spacer(); StatusPill(report.phase, tone: .primary) }
                    HStack { PreviewScore(title: "Today's training readiness", value: report.readinessScore, accent: theme.success); Spacer(); PreviewScore(title: "North star", value: report.northStarScore, accent: theme.accent) }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack { Text("Intensity ceiling").font(TypeScale.body); Spacer(); Text("\(Int((report.intensityCap * 100).rounded()))%").font(TypeScale.num).monospacedDigit() }
                        ProgressView(value: report.intensityCap).tint(theme.warning)
                    }
                    CardInner { PreviewPillarRows(report: report) }
                }
                PreviewActions(report: report, compact: false)
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV06View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    SectionHeader("Mesocycle horizon", icon: "calendar")
                    HStack(spacing: 0) {
                        ForEach(["Accumulation", "Intensification", "Realization", "Deload"], id: \.self) { phase in
                            VStack(spacing: Space.xs) {
                                Circle().fill(phase == report.phase ? theme.accent : theme.border.opacity(0.25)).frame(width: 14, height: 14)
                                Text(phase)
                                    .font(TypeScale.meta)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity)
                            }
                            if phase != "Deload" { Rectangle().fill(theme.border.opacity(0.25)).frame(maxWidth: .infinity).frame(height: 1) }
                        }
                    }
                    HStack { PreviewScore(title: "North star", value: report.northStarScore, accent: theme.accent); Spacer(); PreviewScore(title: "Readiness", value: report.readinessScore, accent: theme.success) }
                }
                Card { PreviewPillarRows(report: report) }
                PreviewActions(report: report, compact: true)
            }
        }
    }
}

private struct PreviewPillarRows: View {
    let report: HolisticPreviewReport
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            PreviewPillar(title: "Autonomic", value: report.autonomicScore)
            PreviewPillar(title: "Sleep restoration", value: report.sleepScore)
            PreviewPillar(title: "Fatigue balance", value: report.fatigueScore)
        }
    }
}

private struct PreviewPillar: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: Int
    var body: some View {
        HStack {
            Text(title).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("\(value)").font(TypeScale.display).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.accent)
            ProgressView(value: Double(value), total: 100).tint(theme.accent).frame(width: 90)
        }
    }
}

public struct HolisticDashboardV07View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    SectionHeader("Today's core directives", icon: "checkmark.seal.fill")
                    HStack { Text(report.directive).font(TypeScale.title); Spacer(); StatusPill(report.provider.label, tone: .primary) }
                    PreviewActions(report: report, compact: false)
                }
                Card {
                    HStack { PreviewScore(title: "North star", value: report.northStarScore, accent: theme.accent); Spacer(); PreviewScore(title: "Readiness", value: report.readinessScore, accent: theme.success); Spacer(); PreviewScore(title: "Cap", value: Int((report.intensityCap * 100).rounded()), accent: theme.warning) }
                    PreviewPillarRows(report: report)
                }
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV08View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.lg) {
                Card {
                    HStack { PreviewScore(title: "North star", value: report.northStarScore, accent: theme.accent); Spacer(); PreviewScore(title: "Readiness", value: report.readinessScore, accent: theme.success); Spacer(); PreviewScore(title: "Cap", value: Int((report.intensityCap * 100).rounded()), accent: theme.warning) }
                    Text(report.directive).font(TypeScale.body)
                }
                Card {
                    SectionHeader("Tri-pillar balance", icon: "triangle")
                    PreviewPillarRows(report: report)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.sm) {
                    ForEach(Array(report.actions.enumerated()), id: \.offset) { index, action in
                        Card {
                            SectionHeader(report.couplings[safe: index] ?? "Core directive")
                            Text(action)
                                .font(TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        }
                    }
                }
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV09View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .center, spacing: Space.lg) {
                Card {
                    VStack(spacing: Space.sm) {
                        PreviewScoreArc(score: report.northStarScore, color: theme.accent)
                        StatusPill(report.phase, tone: .primary)
                        Text(report.directive).font(TypeScale.body).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
                Card {
                    HStack { PreviewScore(title: "Readiness", value: report.readinessScore, accent: theme.success); Spacer(); PreviewScore(title: "Cap", value: Int((report.intensityCap * 100).rounded()), accent: theme.warning); Spacer(); PreviewScore(title: "Sleep", value: report.sleepScore, accent: theme.accent) }
                    PreviewPillarRows(report: report)
                }
                PreviewActions(report: report, compact: true)
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardV10View: View {
    @Environment(\.theme) private var theme
    public let data: HolisticDashboardPreviewData
    public init(data: HolisticDashboardPreviewData = .init()) { self.data = data }
    public var body: some View {
        PreviewScaffold(data: data) { report in
            VStack(alignment: .leading, spacing: Space.sm) {
                Card {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                        PreviewScore(title: "L4", value: report.northStarScore, accent: theme.accent)
                        PreviewScore(title: "L3", value: report.readinessScore, accent: theme.success)
                        PreviewScore(title: "Cap", value: Int((report.intensityCap * 100).rounded()), accent: theme.warning)
                        VStack(alignment: .leading) { Text("Phase").font(TypeScale.meta); Text(report.phase).font(TypeScale.meta) }
                    }
                    CardInner { HStack { Text(report.directive).font(TypeScale.body); Spacer(); StatusPill(report.provider.label, tone: .primary) } }
                }
                Card {
                    PreviewPillarRows(report: report)
                    PreviewActions(report: report, compact: true)
                }
                PreviewDrillDowns()
            }
        }
    }
}

public struct HolisticDashboardPreviewHost: View {
    @State private var selectedVariant = 1
    @State private var selectedState: HolisticPreviewState = .populated
    @State private var selectedProvider: HolisticPreviewProvider = .deterministicFallback
    private let report = HolisticPreviewReport()

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    Picker("Variant", selection: $selectedVariant) {
                        ForEach(1...10, id: \.self) { Text("v\(String(format: "%02d", $0))").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: Space.minTapTarget)
                    Picker("State", selection: $selectedState) {
                        ForEach(HolisticPreviewState.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(HolisticPreviewProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    candidate
                }
                .padding(Space.md)
            }
            .navigationTitle("Holistic PreviewHost")
        }
        .designThemePreview(seed: .teal, neutral: .slate)
    }

    @ViewBuilder private var candidate: some View {
        let data = HolisticDashboardPreviewData(state: selectedState, report: HolisticPreviewReport(provider: selectedProvider))
        switch selectedVariant {
        case 1: HolisticDashboardV01View(data: data)
        case 2: HolisticDashboardV02View(data: data)
        case 3: HolisticDashboardV03View(data: data)
        case 4: HolisticDashboardV04View(data: data)
        case 5: HolisticDashboardV05View(data: data)
        case 6: HolisticDashboardV06View(data: data)
        case 7: HolisticDashboardV07View(data: data)
        case 8: HolisticDashboardV08View(data: data)
        case 9: HolisticDashboardV09View(data: data)
        default: HolisticDashboardV10View(data: data)
        }
    }
}

#Preview("Holistic PreviewHost · Light") {
    HolisticDashboardPreviewHost().preferredColorScheme(.light)
}

#Preview("Holistic PreviewHost · Dark") {
    HolisticDashboardPreviewHost().preferredColorScheme(.dark)
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
