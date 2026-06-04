import SwiftUI

struct TodayActivitySummary: Equatable {
    let workoutCount: Int
    let totalDurationMinutes: Int
    let totalCalories: Int
}

struct ActivitySummaryCard: View {
    let summary: TodayActivitySummary
    private let dailyGoalMinutes = 60

    private var progress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(Double(summary.totalDurationMinutes) / Double(dailyGoalMinutes), 1.0)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("今日活动")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                ActivityRing(progress: progress)
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 8) {
                    StatRow(
                        icon: "figure.strengthtraining.traditional",
                        label: "训练",
                        value: "\(summary.workoutCount) 次"
                    )
                    StatRow(
                        icon: "clock",
                        label: "时长",
                        value: formatDuration(summary.totalDurationMinutes)
                    )
                    StatRow(
                        icon: "flame",
                        label: "消耗",
                        value: "\(summary.totalCalories) kcal"
                    )
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes) 分钟"
    }
}

private struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
        }
    }
}

struct ActivityRing: View {
    let progress: Double
    var lineWidth: Double = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [.green, .green.opacity(0.7)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int(progress * 100))")
                    .font(.title3.bold())
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ActivitySummaryCard(
        summary: TodayActivitySummary(
            workoutCount: 2,
            totalDurationMinutes: 45,
            totalCalories: 320
        )
    )
    .padding()
}
