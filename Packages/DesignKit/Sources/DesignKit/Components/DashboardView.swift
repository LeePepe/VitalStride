import SwiftUI

/// Demo dashboard proving the design language: independent KPI cards in a grid,
/// data-viz next to numbers, colored pills, ≥3 type levels. Lives in DesignKit
/// so it's reusable in previews and the snapshot pipeline.
public struct DashboardView: View {
    @Environment(\.theme) private var theme
    private let trend: [Double] = [12, 18, 15, 24, 21, 30, 28, 36]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Overview")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                    Card {
                        Metric(value: "$48,250", label: "Balance", delta: ("12.4%", true))
                        Sparkline(data: trend, color: theme.chart(0))
                    }
                    Card {
                        Metric(value: "1,284", label: "Active users", delta: ("3.1%", true))
                        Sparkline(data: trend.reversed(), color: theme.chart(2))
                    }
                    Card {
                        Metric(value: "$3,910", label: "Spend", delta: ("1.8%", false))
                        Sparkline(data: [8, 14, 10, 20, 16, 12, 18, 9], color: theme.chart(4))
                    }
                    Card {
                        HStack {
                            Metric(value: "72%", label: "Savings goal")
                            Spacer()
                            RingGauge(value: 0.72)
                        }
                    }
                }

                Card {
                    SectionHeader("Recent activity")
                    ForEach(activity, id: \.title) { row in
                        CardInner {
                            StatusPill(row.tone.label, tone: row.tone.pill)
                            Text(row.title).font(TypeScale.body)
                            Spacer()
                            Text(row.value).font(TypeScale.num)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: Space.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(theme.neutrals.bg)
    }

    private struct Row { let title: String; let value: String; let tone: Tone }
    private enum Tone {
        case success, primary, danger, warning
        var label: String {
            switch self {
            case .success: return "success"
            case .primary: return "primary"
            case .danger: return "danger"
            case .warning: return "warning"
            }
        }
        var pill: PillTone {
            switch self {
            case .success: return .success
            case .primary: return .primary
            case .danger: return .danger
            case .warning: return .warning
            }
        }
    }
    private var activity: [Row] {
        [
            Row(title: "Payment received", value: "+$1,200", tone: .success),
            Row(title: "Subscription renewed", value: "-$29", tone: .primary),
            Row(title: "Card declined", value: "$0", tone: .danger),
            Row(title: "Review pending", value: "—", tone: .warning)
        ]
    }
}

#Preview("Dashboard") {
    DashboardView()
        .designTheme(seed: .blue, neutral: .slate)
        .frame(width: 720, height: 640)
}
