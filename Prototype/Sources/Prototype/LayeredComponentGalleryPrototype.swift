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
        self.variant = variant
        self.state = state
        self.domainMetrics = [
            ["HRV 68 ms", "HRV 7d 65 ms", "RHR Δ −3 bpm", "HRR 1m −32 bpm", "HRR 2m −49 bpm"],
            ["Deep + REM 47%", "Sleep debt 1.4 h", "Efficiency 92%"],
            ["TSB +6.3", "ACWR 0.90", "Zone 4–5 17%"],
            ["VO2max 51.4", "Trend +1.8", "EF 0.086", "Pa:Hr 3.4%"],
            ["NEAT 7,680 steps", "Uniformity 79%", "Active hours 11 h"]
        ]
        self.couplingMessages = [
            "Sleep × training load · evidence supports a controlled session.",
            "Daily NEAT × body recovery · movement supports circulation without adding load."
        ]
        self.readiness = ["Readiness 84", "Autonomic 86", "Sleep restoration 81", "Fatigue balance 83", "Intensification", "Cap 85%"]
        self.actions = ["Keep the planned session controlled.", "Protect a consistent sleep opportunity.", "Use easy movement breaks between focused work blocks."]
    }
}

public struct LayeredComponentCandidateView: View {
    public let data: LayeredComponentGalleryPreviewData
    @Environment(\.theme) private var theme

    public init(data: LayeredComponentGalleryPreviewData) {
        self.data = data
    }

    public var body: some View {
        if data.state == .populated {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    candidateHeader
                    switch data.layer {
                    case .l1: l1Content
                    case .l2: l2Content
                    case .l3: l3Content
                    case .l4: l4Content
                    }
                }
                .padding(Space.md)
                .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
            }
        } else {
            LayerGalleryStateCard(state: data.state)
                .padding(Space.md)
        }
    }

    private var candidateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(layerTitle, icon: layerIcon)
            Spacer()
            StatusPill(String(format: "v%02d", data.variant), tone: .primary)
        }
    }

    @ViewBuilder private var l1Content: some View {
        let columns = data.variant.isMultiple(of: 3) ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: columns), spacing: Space.sm) {
            ForEach(Array(data.domainMetrics.enumerated()), id: \.offset) { index, metrics in
                Card {
                    HStack {
                        Text(l1Titles[index]).font(TypeScale.title)
                        Spacer()
                        StatusPill("L1", tone: index == 2 ? .warning : .success)
                    }
                    ForEach(metrics, id: \.self) { metric in
                        CardInner {
                            Text(metric)
                                .font(TypeScale.num)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .layoutPriority(1)
                        }
                    }
                    PreviewDetailAction(label: "View details in Apple Health ↗")
                }
            }
        }
    }

    @ViewBuilder private var l2Content: some View {
        ForEach(Array(data.couplingMessages.enumerated()), id: \.offset) { index, message in
            Card {
                HStack {
                    SectionHeader(index == 0 ? "sleepTrainingCoupling" : "stepsBodyCoupling", icon: "arrow.triangle.2.circlepath")
                    Spacer()
                    StatusPill(index == 0 ? "Watch" : "Normal", tone: index == 0 ? .warning : .success)
                }
                Text(message).font(TypeScale.body).foregroundStyle(theme.secondaryForeground).fixedSize(horizontal: false, vertical: true)
                PreviewDetailAction(label: "View details in Apple Health ↗")
            }
        }
    }

    @ViewBuilder private var l3Content: some View {
        Card {
            HStack {
                Text("Readiness").font(TypeScale.title)
                Spacer()
                Text("84").font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(data.readiness.prefix(4), id: \.self) { value in
                    CardInner { Text(value).font(TypeScale.num).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85).layoutPriority(1) }
                }
            }
            HStack { StatusPill("Intensification", tone: .primary); Spacer(); StatusPill("Cap 85%", tone: .success) }
        }
    }

    @ViewBuilder private var l4Content: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("North Star").font(TypeScale.title)
                    Text("86").font(TypeScale.metricXXL).monospacedDigit().lineLimit(1).layoutPriority(1).foregroundStyle(theme.accent)
                    Text("Recovery and movement support controlled training today.")
                        .font(TypeScale.body)
                        .foregroundStyle(theme.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                RingGauge(value: 0.86, color: theme.accent)
            }
            ForEach(Array(data.actions.enumerated()), id: \.offset) { index, action in
                CardInner {
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text("\(index + 1)").font(TypeScale.num).monospacedDigit().frame(width: 24, height: 24).background(theme.accentSubtle, in: Circle())
                        Text(action).font(TypeScale.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var layerTitle: String {
        switch data.layer {
        case .l1: "L1 Atomic domain cards · 5 domains / 10 curated metrics"
        case .l2: "L2 Cross-domain coupling cards"
        case .l3: "L3 Readiness and periodization card"
        case .l4: "L4 North Star directive card"
        }
    }

    private var layerIcon: String {
        switch data.layer {
        case .l1: "square.grid.2x2"
        case .l2: "arrow.triangle.2.circlepath"
        case .l3: "calendar.badge.clock"
        case .l4: "scope"
        }
    }

    private var l1Titles: [String] { ["Heart autonomic", "Sleep recovery", "Training load", "Aerobic capacity", "Daily NEAT"] }
}

private struct PreviewDetailAction: View {
    let label: String
    var body: some View {
        Text(label)
            .font(TypeScale.meta.weight(.semibold))
            .foregroundStyle(.tint)
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
