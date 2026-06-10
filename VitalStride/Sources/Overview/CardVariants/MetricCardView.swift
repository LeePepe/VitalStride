import AIService
import SwiftUI

// MARK: - Small Metric

struct MetricSmallCardView: View {
    let insight: OverviewInsight

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 6) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(insight.content)
                    .font(.title2.bold().monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(insight.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "\(insight.title), \(insight.content)",
                    comment: "Metric card accessibility: title and value"
                )
            )
        }
        .onAppear {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

// MARK: - Medium Metric

struct MetricMediumCardView: View {
    let insight: OverviewInsight

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let icon = insight.iconName {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(insight.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(.title.bold().monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let suggestion = insight.suggestion, !suggestion.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                        Text(suggestion)
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(metricAccessibilityLabel)
        }
        .onAppear {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }

    private var metricAccessibilityLabel: String {
        var label = "\(insight.title), \(insight.content)"
        if let suggestion = insight.suggestion, !suggestion.isEmpty {
            label += ", \(suggestion)"
        }
        return label
    }
}

#Preview("Metric Small") {
    MetricSmallCardView(insight: OverviewInsight(
        key: "steps", cardType: "metric", cardSize: "small",
        title: "Steps", content: "8,543", iconName: "figure.walk"
    ))
    .frame(width: 160)
    .padding()
}

#Preview("Metric Medium") {
    MetricMediumCardView(insight: OverviewInsight(
        key: "steps", cardType: "metric", cardSize: "medium",
        title: "Steps", content: "8,543",
        suggestion: "+12% vs last week", iconName: "figure.walk"
    ))
    .frame(width: 200)
    .padding()
}
