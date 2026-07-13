import AIService
import DesignKit
import SwiftUI

// MARK: - Medium Insight

struct InsightMediumCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.primary.primary)
                    Text(insight.title)
                        .font(TypeScale.meta.weight(.semibold))
                        .foregroundStyle(theme.neutrals.text1)
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(TypeScale.body)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .foregroundStyle(theme.neutrals.text1)
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
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
        }
    }
}

// MARK: - Wide Insight

struct InsightWideCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(TypeScale.meta.weight(.semibold))
                        .foregroundStyle(theme.primary.primary)
                    Text(insight.title)
                        .font(TypeScale.title)
                        .foregroundStyle(theme.neutrals.text1)
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(TypeScale.body)
                    .lineSpacing(3)
                    .foregroundStyle(theme.neutrals.text1)

                if let suggestion = insight.suggestion, !suggestion.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(TypeScale.meta)
                            .foregroundStyle(theme.primary.primary)
                        Text(suggestion)
                            .font(TypeScale.meta.weight(.semibold))
                            .foregroundStyle(theme.neutrals.text2)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(insightAccessibilityLabel)
        }
        .onAppear {
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
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
    .designThemePreview()
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
    .designThemePreview()
    .padding()
}
