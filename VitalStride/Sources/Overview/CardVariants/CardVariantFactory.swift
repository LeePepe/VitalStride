import AIService
import SwiftUI

enum CardVariantFactory {
    @ViewBuilder
    static func makeCard(
        for insight: OverviewInsight,
        onAction: (@Sendable () -> Void)? = nil
    ) -> some View {
        let size = insight.parsedCardSize
        let type = insight.parsedCardType

        switch (size, type) {
        case (.small, .metric):
            MetricSmallCardView(insight: insight)
        case (.medium, .metric):
            MetricMediumCardView(insight: insight)
        case (.medium, .trend):
            TrendMediumCardView(insight: insight)
        case (.wide, .trend):
            TrendWideCardView(insight: insight)
        case (.large, .trend):
            TrendLargeCardView(insight: insight)
        case (.medium, .insight):
            InsightMediumCardView(insight: insight)
        case (.wide, .insight):
            InsightWideCardView(insight: insight)
        case (.wide, .list):
            ListWideCardView(insight: insight)
        case (.large, .list):
            ListLargeCardView(insight: insight)
        case (.wide, .summary):
            SummaryWideCardView(insight: insight)
        case (.large, .summary):
            SummaryLargeCardView(insight: insight)
        case (.small, .action):
            ActionSmallCardView(insight: insight, onTap: onAction)
        case (.wide, .action):
            ActionWideCardView(insight: insight, onTap: onAction)
        default:
            EmptyView()
                .onAppear {
                    CardTelemetry.recordRenderFailed(
                        size: insight.cardSize,
                        type: insight.cardType
                    )
                }
        }
    }
}
