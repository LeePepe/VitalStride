import AIService
import SwiftUI

struct AdaptiveCardGrid: View {
    let insights: [OverviewInsight]

    private var validInsights: [OverviewInsight] {
        insights.filter(\.isValidVariant)
    }

    var body: some View {
        let rows = buildRows(from: validInsights)
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .full(let insight):
                    InsightCardView(insight: insight)
                case .pair(let left, let right):
                    HStack(spacing: 12) {
                        InsightCardView(insight: left)
                        InsightCardView(insight: right)
                    }
                case .halfLeft(let insight):
                    HStack(spacing: 12) {
                        InsightCardView(insight: insight)
                        Spacer()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func buildRows(from insights: [OverviewInsight]) -> [CardRow] {
        var rows: [CardRow] = []
        var pendingHalf: OverviewInsight?

        for insight in insights {
            let size = insight.parsedCardSize ?? .medium
            let isFullWidth = (size == .wide || size == .large)

            if isFullWidth {
                if let pending = pendingHalf {
                    rows.append(.halfLeft(pending))
                    pendingHalf = nil
                }
                rows.append(.full(insight))
            } else {
                if let pending = pendingHalf {
                    rows.append(.pair(pending, insight))
                    pendingHalf = nil
                } else {
                    pendingHalf = insight
                }
            }
        }

        if let pending = pendingHalf {
            rows.append(.halfLeft(pending))
        }

        return rows
    }
}

private enum CardRow {
    case full(OverviewInsight)
    case pair(OverviewInsight, OverviewInsight)
    case halfLeft(OverviewInsight)
}
