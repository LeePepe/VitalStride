import AIService
import DesignKit
import SwiftUI

// MARK: - Small Metric

struct MetricSmallCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 6) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.neutrals.text2)
                }
                Text(insight.content)
                    .font(TypeScale.display)
                    .foregroundStyle(theme.neutrals.text1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(insight.title)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
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
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
        }
    }
}

// MARK: - Medium Metric

struct MetricMediumCardView: View {
    let insight: OverviewInsight
    @Environment(\.theme) private var theme

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let icon = insight.iconName {
                        Image(systemName: icon)
                            .font(TypeScale.meta.weight(.semibold))
                            .foregroundStyle(theme.neutrals.text2)
                    }
                    Text(insight.title)
                        .font(TypeScale.meta.weight(.semibold))
                        .foregroundStyle(theme.neutrals.text2)
                        .lineLimit(1)
                }

                Text(insight.content)
                    .font(TypeScale.display)
                    .foregroundStyle(theme.neutrals.text1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let suggestion = insight.suggestion, !suggestion.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(TypeScale.meta)
                        Text(suggestion)
                            .font(TypeScale.meta)
                    }
                    .foregroundStyle(theme.success)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(metricAccessibilityLabel)
        }
        .onAppear {
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
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
    .designThemePreview()
    .frame(width: 160)
    .padding()
}

#Preview("Metric Medium") {
    MetricMediumCardView(insight: OverviewInsight(
        key: "steps", cardType: "metric", cardSize: "medium",
        title: "Steps", content: "8,543",
        suggestion: "+12% vs last week", iconName: "figure.walk"
    ))
    .designThemePreview()
    .frame(width: 200)
    .padding()
}
