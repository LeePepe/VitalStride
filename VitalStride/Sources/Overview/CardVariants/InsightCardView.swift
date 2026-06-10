import AIService
import SwiftUI

// MARK: - Medium Insight

struct InsightMediumCardView: View {
    let insight: OverviewInsight

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text(insight.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "AI Insight: \(insight.title), \(insight.content)",
                    comment: "Insight card accessibility label"
                )
            )
        }
        .onAppear {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

// MARK: - Wide Insight

struct InsightWideCardView: View {
    let insight: OverviewInsight

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                    Text(insight.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(.callout)
                    .foregroundStyle(.primary)

                if let suggestion = insight.suggestion, !suggestion.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(insightAccessibilityLabel)
        }
        .onAppear {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }

    private var insightAccessibilityLabel: String {
        var label = String(
            localized: "AI Insight: \(insight.title), \(insight.content)",
            comment: "Insight card accessibility label"
        )
        if let suggestion = insight.suggestion, !suggestion.isEmpty {
            label += String(
                localized: ", Suggestion: \(suggestion)",
                comment: "Insight card suggestion accessibility"
            )
        }
        return label
    }
}

#Preview("Insight Medium") {
    InsightMediumCardView(insight: OverviewInsight(
        key: "recovery", cardType: "insight", cardSize: "medium",
        title: "Recovery", content: "You've trained legs 3 days in a row. Consider resting today."
    ))
    .frame(width: 200)
    .padding()
}

#Preview("Insight Wide") {
    InsightWideCardView(insight: OverviewInsight(
        key: "recovery", cardType: "insight", cardSize: "wide",
        title: "Recovery Advice",
        content: "Your training volume increased 20% this week compared to last week.",
        suggestion: "Consider a deload next week to prevent overtraining."
    ))
    .padding()
}
