import Foundation
import HealthKitService
import SwiftUI

struct DataAISummaryCard: View {
    let state: DataAISummaryState

    var body: some View {
        switch state.phase {
        case .idle, .failed:
            EmptyView()
        case .loading:
            loadingView
        case .done:
            doneView
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                    .accessibilityAddTraits(.updatesFrequently)
                Text(String(localized: "正在分析…", comment: "AI summary loading text"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(localized: "正在生成 AI 健康汇总", comment: "AI summary loading a11y")
            )
        } header: {
            cardHeader
        }
    }

    // MARK: - Done

    private var doneView: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(state.results, id: \.sampleType) { result in
                    trendRow(result: result)
                }

                if let suggestion = state.focusSuggestion, !suggestion.isEmpty {
                    suggestionRow(suggestion: suggestion)
                }

                footerRow
            }
            .padding(.vertical, 4)
        } header: {
            cardHeader
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        Label(
            String(localized: "AI 健康速览", comment: "AI summary card title"),
            systemImage: "sparkles"
        )
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Trend Row

    private func trendRow(result: DataAISummaryState.TypeResult) -> some View {
        HStack(spacing: 8) {
            Text(trendIcon(result.trend))
                .font(.body)
                .foregroundStyle(trendColor(result.trend))
                .frame(width: 20, alignment: .center)
                .accessibilityHidden(true)

            Text(result.sampleType.localizedName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .layoutPriority(1)

            Text(truncatedSummary(result.summary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                localized: "\(result.sampleType.localizedName)，\(trendDescription(result.trend))，\(result.summary)",
                comment: "AI summary row a11y"
            )
        )
    }

    // MARK: - Suggestion Row

    private func suggestionRow(suggestion: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "建议", comment: "Suggestion prefix"))
                    .font(.caption.weight(.medium))
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footerRow: some View {
        Group {
            if let generatedAt = state.earliestGeneratedAt {
                Text(
                    String(
                        localized: "上次更新 \(generatedAt, format: .relative(presentation: .named))",
                        comment: "Last updated timestamp"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(
                    String(
                        localized: "上次更新 \(generatedAt, format: .relative(presentation: .named))",
                        comment: "Last updated timestamp a11y"
                    )
                )
            }
        }
    }

    // MARK: - Trend Helpers

    private func trendIcon(_ trend: String) -> String {
        switch trend {
        case "rising": "↗"
        case "falling": "↘"
        case "stable": "→"
        default: "—"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "rising": .green
        case "falling": .red
        case "stable": .blue
        default: .secondary
        }
    }

    private func trendDescription(_ trend: String) -> String {
        switch trend {
        case "rising": String(localized: "上升趋势", comment: "Rising trend a11y")
        case "falling": String(localized: "下降趋势", comment: "Falling trend a11y")
        case "stable": String(localized: "稳定", comment: "Stable trend a11y")
        default: String(localized: "数据不足", comment: "Insufficient trend a11y")
        }
    }

    private func truncatedSummary(_ summary: String) -> String {
        if summary.count <= 20 { return summary }
        return String(summary.prefix(20)) + "…"
    }
}
