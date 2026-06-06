import Charts
import SwiftUI
import VitalModels

enum TrendTimeRange: String, CaseIterable {
    case week = "周"
    case month = "月"

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
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
    let workouts: [Workout]
    @State private var timeRange: TrendTimeRange = .week

    private var chartData: [DailyWorkoutData] {
        WorkoutAggregator.computeDailyTrendData(from: workouts, dayCount: timeRange.dayCount)
    }

    private var averageMinutes: Double {
        WorkoutAggregator.computeAverage(from: chartData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练趋势")
                    .font(.headline)
                Spacer()
                Picker("时间范围", selection: $timeRange) {
                    ForEach(TrendTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            Chart {
                ForEach(chartData) { item in
                    LineMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("时长", item.totalMinutes)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    .symbol(Circle().strokeBorder(lineWidth: 1.5))
                }

                if averageMinutes > 0 {
                    RuleMark(y: .value("均值", averageMinutes))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("均值 \(Int(averageMinutes))m")
                                .font(.caption2)
                                .foregroundStyle(.orange)
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
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    WorkoutTrendChart(workouts: [])
        .padding()
}
