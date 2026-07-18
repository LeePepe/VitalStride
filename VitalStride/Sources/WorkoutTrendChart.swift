// MY-1090 precedent: pre-existing `no_hardcoded_chinese` literals (chart
// title, picker labels, axis/series keys) predate the `--strict` SwiftLint
// hook and stay silenced at file scope until the shared i18n cleanup. No
// semantic change from this pragma.
// swiftlint:disable no_hardcoded_chinese
import Charts
import DesignKit
import SwiftUI
import VitalModels

enum TrendTimeRange: String, CaseIterable {
    case week = "week"
    case month = "month"

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        }
    }

    /// Localized label shown in the picker.
    var displayName: String {
        switch self {
        case .week: String(localized: "周", comment: "Time range picker: week")
        case .month: String(localized: "月", comment: "Time range picker: month")
        }
    }
}

struct DailyWorkoutData: Identifiable {
    let id: Date
    let date: Date
    let totalMinutes: Int

    init(date: Date, totalMinutes: Int) {
        self.id = date
        self.date = date
        self.totalMinutes = totalMinutes
    }
}

struct WorkoutTrendChart: View {
    @Environment(\.theme) private var theme
    let workouts: [Workout]
    @State private var timeRange: TrendTimeRange = .week

    private var chartData: [DailyWorkoutData] {
        WorkoutAggregator.computeDailyTrendData(from: workouts, dayCount: timeRange.dayCount)
    }

    private var averageMinutes: Double {
        WorkoutAggregator.computeAverage(from: chartData)
    }

    var body: some View {
        Card {
            HStack {
                Text(String(localized: "训练趋势", comment: ""))
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text1)
                Spacer()
                Picker(String(localized: "时间范围", comment: ""), selection: $timeRange) {
                    ForEach(TrendTimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            Chart {
                ForEach(chartData) { item in
                    LineMark(
                        x: .value(String(localized: "日期", comment: ""), item.date, unit: .day),
                        y: .value(String(localized: "时长", comment: ""), item.totalMinutes)
                    )
                    .foregroundStyle(theme.chart(0))
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle().strokeBorder(lineWidth: 1.5))
                }

                if averageMinutes > 0 {
                    RuleMark(y: .value(String(localized: "均值", comment: ""), averageMinutes))
                        .foregroundStyle(theme.warning)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(localized: "均值 \(Int(averageMinutes))m", comment: "Average minutes annotation on trend chart"))
                                .font(.caption2)
                                .foregroundStyle(theme.warning)
                        }
                }
            }
            .chartXAxis {
                if timeRange == .week {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        AxisGridLine()
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        AxisGridLine()
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text("\(minutes)m")
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
    }
}

#Preview {
    WorkoutTrendChart(workouts: [])
        .padding()
        .designThemePreview()
}
