import AIService
import SwiftUI

// MARK: - Wide Summary (horizontal metrics)

struct SummaryWideCardView: View {
    let insight: OverviewInsight

    private var entries: [SummaryEntry] {
        CardContentParser.parseSummaryEntries(insight.content)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text(insight.title)
                    .font(.headline)
                    .lineLimit(1)

                if entries.isEmpty {
                    emptyContent
                } else {
                    horizontalMetrics
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryAccessibilityLabel)
        }
        .onAppear { recordTelemetry() }
    }

    private var horizontalMetrics: some View {
        HStack(spacing: 0) {
            ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                VStack(spacing: 4) {
                    Text(entry.value)
                        .font(.title3.bold().monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if index < min(entries.count, 4) - 1 {
                    Divider()
                        .frame(height: 30)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var summaryAccessibilityLabel: String {
        let entryDescriptions = entries.prefix(4).map { "\($0.key), \($0.value)" }
        return "\(insight.title), \(entryDescriptions.joined(separator: "; "))"
    }

    private func recordTelemetry() {
        guard let size = insight.parsedCardSize, let type = insight.parsedCardType else { return }
        if entries.isEmpty {
            CardTelemetry.recordRenderFailed(size: size, type: type)
        } else {
            CardTelemetry.recordRendered(size: size, type: type)
        }
    }
}

// MARK: - Large Summary (grid layout)

struct SummaryLargeCardView: View {
    let insight: OverviewInsight

    private var entries: [SummaryEntry] {
        CardContentParser.parseSummaryEntries(insight.content)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text(insight.title)
                    .font(.headline)
                    .lineLimit(1)

                if entries.isEmpty {
                    emptyContent
                } else {
                    gridMetrics
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryAccessibilityLabel)
        }
        .onAppear { recordTelemetry() }
    }

    private var gridMetrics: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.value)
                        .font(.title3.bold().monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var summaryAccessibilityLabel: String {
        let entryDescriptions = entries.map { "\($0.key), \($0.value)" }
        return "\(insight.title), \(entryDescriptions.joined(separator: "; "))"
    }

    private func recordTelemetry() {
        guard let size = insight.parsedCardSize, let type = insight.parsedCardType else { return }
        if entries.isEmpty {
            CardTelemetry.recordRenderFailed(size: size, type: type)
        } else {
            CardTelemetry.recordRendered(size: size, type: type)
        }
    }
}

#Preview("Summary Wide") {
    SummaryWideCardView(insight: OverviewInsight(
        key: "weekly_summary", cardType: "summary", cardSize: "wide",
        title: "This Week",
        content: "{\"Steps\":\"52.3K\",\"Calories\":\"3,200\",\"Sleep\":\"7h 20m\"}"
    ))
    .padding()
}

#Preview("Summary Large") {
    SummaryLargeCardView(insight: OverviewInsight(
        key: "weekly_summary", cardType: "summary", cardSize: "large",
        title: "Weekly Overview",
        content: "{\"Steps\":\"52.3K\",\"Calories\":\"3,200\",\"Sleep\":\"7h 20m\",\"Workouts\":\"5\",\"Active Min\":\"320\",\"Distance\":\"38 km\"}"
    ))
    .padding()
}
