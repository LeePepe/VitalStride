import AIService
import Charts
import SwiftUI

// MARK: - Medium Trend (mini chart, no axis labels)

struct TrendMediumCardView: View {
    let insight: OverviewInsight

    private var dataPoints: [TrendDataPoint] {
        CardContentParser.parseTrendData(insight.content)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(insight.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if dataPoints.isEmpty {
                    noDataView
                } else {
                    miniChart
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "\(insight.title), trend chart",
                    comment: "Trend card accessibility label"
                )
            )
        }
        .onAppear { recordTelemetry() }
    }

    private var miniChart: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value(String(localized: "Date", comment: "Chart axis"), point.date),
                y: .value(String(localized: "Value", comment: "Chart axis"), point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 50)
    }

    @ViewBuilder
    private var noDataView: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(height: 50)
    }

    private func recordTelemetry() {
        if dataPoints.isEmpty {
            CardTelemetry.recordRenderFailed(size: insight.cardSize, type: insight.cardType)
        } else {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

// MARK: - Wide Trend (chart with axis labels)

struct TrendWideCardView: View {
    let insight: OverviewInsight

    private var dataPoints: [TrendDataPoint] {
        CardContentParser.parseTrendData(insight.content)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(insight.title)
                    .font(.headline)
                    .lineLimit(1)

                if dataPoints.isEmpty {
                    noDataPlaceholder
                } else {
                    labeledChart
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "\(insight.title), trend chart",
                    comment: "Trend card accessibility label"
                )
            )
        }
        .onAppear { recordTelemetry() }
    }

    private var labeledChart: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value(String(localized: "Date", comment: "Chart axis"), point.date),
                y: .value(String(localized: "Value", comment: "Chart axis"), point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)
            .symbol(Circle().strokeBorder(lineWidth: 1.5))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .frame(height: 120)
    }

    @ViewBuilder
    private var noDataPlaceholder: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(height: 120)
    }

    private func recordTelemetry() {
        if dataPoints.isEmpty {
            CardTelemetry.recordRenderFailed(size: insight.cardSize, type: insight.cardType)
        } else {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

// MARK: - Large Trend (full interactive chart)

struct TrendLargeCardView: View {
    let insight: OverviewInsight
    @State private var selectedPoint: String?

    private var dataPoints: [TrendDataPoint] {
        CardContentParser.parseTrendData(insight.content)
    }

    private var averageValue: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.reduce(0.0) { $0 + $1.value } / Double(dataPoints.count)
    }

    var body: some View {
        OverviewCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(insight.title)
                        .font(.headline)
                    Spacer()
                    if let suggestion = insight.suggestion, !suggestion.isEmpty {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if dataPoints.isEmpty {
                    noDataPlaceholder
                } else {
                    fullChart
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "\(insight.title), interactive trend chart",
                    comment: "Large trend card accessibility label"
                )
            )
        }
        .onAppear { recordTelemetry() }
    }

    private var fullChart: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value(String(localized: "Date", comment: "Chart axis"), point.date),
                y: .value(String(localized: "Value", comment: "Chart axis"), point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)
            .symbol(Circle().strokeBorder(lineWidth: 1.5))

            if averageValue > 0 {
                RuleMark(y: .value(
                    String(localized: "Average", comment: "Chart average line"),
                    averageValue
                ))
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                AxisGridLine()
            }
        }
        .chartXSelection(value: $selectedPoint)
        .frame(height: 200)
    }

    @ViewBuilder
    private var noDataPlaceholder: some View {
        Text(String(localized: "no_data", defaultValue: "No data"))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(height: 200)
    }

    private func recordTelemetry() {
        if dataPoints.isEmpty {
            CardTelemetry.recordRenderFailed(size: insight.cardSize, type: insight.cardType)
        } else {
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

#Preview("Trend Medium") {
    TrendMediumCardView(insight: OverviewInsight(
        key: "steps_trend", cardType: "trend", cardSize: "medium",
        title: "Steps Trend",
        content: "[{\"date\":\"Mon\",\"value\":6000},{\"date\":\"Tue\",\"value\":8000},{\"date\":\"Wed\",\"value\":7500},{\"date\":\"Thu\",\"value\":9000},{\"date\":\"Fri\",\"value\":8500}]"
    ))
    .frame(width: 200)
    .padding()
}

#Preview("Trend Wide") {
    TrendWideCardView(insight: OverviewInsight(
        key: "steps_trend", cardType: "trend", cardSize: "wide",
        title: "Steps Trend",
        content: "[{\"date\":\"Mon\",\"value\":6000},{\"date\":\"Tue\",\"value\":8000},{\"date\":\"Wed\",\"value\":7500},{\"date\":\"Thu\",\"value\":9000},{\"date\":\"Fri\",\"value\":8500}]"
    ))
    .padding()
}

#Preview("Trend Large") {
    TrendLargeCardView(insight: OverviewInsight(
        key: "steps_trend", cardType: "trend", cardSize: "large",
        title: "Weekly Steps",
        content: "[{\"date\":\"Mon\",\"value\":6000},{\"date\":\"Tue\",\"value\":8000},{\"date\":\"Wed\",\"value\":7500},{\"date\":\"Thu\",\"value\":9000},{\"date\":\"Fri\",\"value\":8500},{\"date\":\"Sat\",\"value\":12000},{\"date\":\"Sun\",\"value\":4000}]",
        suggestion: "Avg: 7,857 steps/day"
    ))
    .padding()
}
