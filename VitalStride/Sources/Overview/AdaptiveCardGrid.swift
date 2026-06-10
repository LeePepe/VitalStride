import AIService
import SwiftUI
import os

private let gridLogger = Logger(subsystem: "com.vitalstride", category: "OverviewGrid")

enum GridSegment: Sendable, Equatable {
    case gridBatch([OverviewInsight])
    case fullWidth(OverviewInsight)
}

enum GridLayoutEngine {
    static func segment(_ insights: [OverviewInsight]) -> (segments: [GridSegment], filteredCount: Int) {
        let validInsights = insights.filter(\.isValidVariant)
        let filteredCount = insights.count - validInsights.count

        var segments: [GridSegment] = []
        var currentBatch: [OverviewInsight] = []

        for insight in validInsights {
            guard let size = insight.parsedCardSize else { continue }

            switch size {
            case .small, .medium:
                currentBatch.append(insight)
            case .wide, .large:
                if !currentBatch.isEmpty {
                    segments.append(.gridBatch(currentBatch))
                    currentBatch = []
                }
                segments.append(.fullWidth(insight))
            }
        }

        if !currentBatch.isEmpty {
            segments.append(.gridBatch(currentBatch))
        }

        return (segments, filteredCount)
    }
}

private enum GridTelemetry {
    static func recordRendered(
        totalCards: Int,
        gridBatches: Int,
        wideCount: Int,
        largeCount: Int
    ) {
        gridLogger.info(
            """
            overview_grid_rendered \
            total_cards=\(totalCards, privacy: .public) \
            grid_batches=\(gridBatches, privacy: .public) \
            wide_count=\(wideCount, privacy: .public) \
            large_count=\(largeCount, privacy: .public)
            """
        )
    }

    static func recordFiltered(count: Int) {
        guard count > 0 else { return }
        gridLogger.warning("overview_grid_filtered_count count=\(count, privacy: .public)")
    }
}

struct AdaptiveCardGrid: View {
    let insights: [OverviewInsight]
    var onAction: (@Sendable () -> Void)?

    private static let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let result = GridLayoutEngine.segment(insights)

        if !result.segments.isEmpty {
            LazyVStack(spacing: 16) {
                ForEach(Array(result.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .gridBatch(batchInsights):
                        LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                            ForEach(batchInsights, id: \.key) { insight in
                                CardVariantFactory.makeCard(for: insight, onAction: onAction)
                            }
                        }
                    case let .fullWidth(insight):
                        CardVariantFactory.makeCard(for: insight, onAction: onAction)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .onAppear {
                emitTelemetry(result: result)
            }
        }
    }

    private func emitTelemetry(result: (segments: [GridSegment], filteredCount: Int)) {
        var totalCards = 0
        var gridBatches = 0
        var wideCount = 0
        var largeCount = 0

        for segment in result.segments {
            switch segment {
            case let .gridBatch(batch):
                gridBatches += 1
                totalCards += batch.count
            case let .fullWidth(insight):
                totalCards += 1
                if insight.parsedCardSize == .wide {
                    wideCount += 1
                } else {
                    largeCount += 1
                }
            }
        }

        GridTelemetry.recordRendered(
            totalCards: totalCards,
            gridBatches: gridBatches,
            wideCount: wideCount,
            largeCount: largeCount
        )
        GridTelemetry.recordFiltered(count: result.filteredCount)
    }
}

#Preview("Mixed Layout") {
    ScrollView {
        AdaptiveCardGrid(insights: [
            OverviewInsight(key: "steps", cardType: "metric", cardSize: "small", title: "Steps", content: "8,432"),
            OverviewInsight(key: "hr", cardType: "metric", cardSize: "small", title: "Heart Rate", content: "72 bpm"),
            OverviewInsight(key: "trend", cardType: "trend", cardSize: "wide", title: "Weekly Trend", content: "[]"),
            OverviewInsight(key: "sleep", cardType: "metric", cardSize: "medium", title: "Sleep", content: "7.5 hrs"),
            OverviewInsight(key: "summary", cardType: "summary", cardSize: "large", title: "Summary", content: "Good week overall"),
            OverviewInsight(key: "cal", cardType: "metric", cardSize: "small", title: "Calories", content: "2,100"),
            OverviewInsight(key: "weight", cardType: "metric", cardSize: "small", title: "Weight", content: "75 kg"),
        ])
        .padding(.horizontal, 16)
    }
}

#Preview("Empty") {
    AdaptiveCardGrid(insights: [])
}
