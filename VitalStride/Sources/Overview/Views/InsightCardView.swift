import AIService
import SwiftUI

struct InsightCardView: View {
    let insight: OverviewInsight

    private var cardSize: CardSize {
        insight.effectiveCardSize
    }

    private var cardType: CardType {
        insight.effectiveCardType
    }

    var body: some View {
        Group {
            switch cardType {
            case .metric:
                metricLayout
            case .trend:
                trendLayout
            case .insight:
                insightLayout
            case .summary:
                summaryLayout
            case .list:
                listLayout
            case .action:
                actionLayout
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Card Layouts

    private var metricLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(cardSize == .small ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(insight.content)
                .font(cardSize == .small ? .title2.bold() : .title.bold())
                .lineLimit(2)
            if let suggestion = insight.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var insightLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(.subheadline.bold())
            }
            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(cardSize == .medium ? 3 : 5)
            if let suggestion = insight.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
            }
        }
    }

    private var trendLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(.subheadline.bold())
            }
            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let suggestion = insight.suggestion {
                Spacer(minLength: 4)
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var summaryLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(.headline)
            }
            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let suggestion = insight.suggestion {
                Divider()
                Label {
                    Text(suggestion)
                        .font(.caption)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(.subheadline.bold())
            }
            Text(insight.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let suggestion = insight.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
    }

    private var actionLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                iconView
                Text(insight.title)
                    .font(cardSize == .small ? .caption.bold() : .subheadline.bold())
            }
            Text(insight.content)
                .font(cardSize == .small ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(cardSize == .small ? 2 : 4)
            if let suggestion = insight.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var iconView: some View {
        if let iconName = insight.iconName {
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundStyle(.tint)
        }
    }

    private var minHeight: CGFloat {
        switch cardSize {
        case .small: 80
        case .medium: 100
        case .wide: 80
        case .large: 140
        }
    }
}
