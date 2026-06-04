import Charts
import SwiftUI

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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayCount = timeRange.dayCount

        var dailyMap: [Date: Int] = [:]
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                dailyMap[date] = 0
            }
        }

        let rangeStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        for workout in workouts {
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            guard workoutDay >= rangeStart, workoutDay <= today else { continue }
            let minutes: Int
            if let endDate = workout.endDate {
                minutes = max(1, Int(endDate.timeIntervalSince(workout.startDate)) / 60)
            } else {
                minutes = 0
            }
            dailyMap[workoutDay, default: 0] += minutes
        }

        return dailyMap
            .map { DailyWorkoutData(date: $0.key, totalMinutes: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var averageMinutes: Double {
        let data = chartData
        guard !data.isEmpty else { return 0 }
        let total = data.reduce(0) { $0 + $1.totalMinutes }
        return Double(total) / Double(data.count)
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
                    BarMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("时长", item.totalMinutes)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(4)
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
