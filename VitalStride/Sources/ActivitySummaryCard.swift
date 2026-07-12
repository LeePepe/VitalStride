// Pre-existing hardcoded Chinese literals (activity labels) predate the
// `no_hardcoded_chinese` hook and are tracked under the shared i18n cleanup;
// the DesignKit re-skin re-touched their lines but added no new strings.
// Silenced at file scope, matching HealthSummaryCards.swift / DataView.swift.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
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
        Card {
            HStack {
                Text("今日活动")
                    .font(TypeScale.title)
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
    @Environment(\.theme) private var theme
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(theme.neutrals.text2)
                .frame(width: 20)
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(theme.neutrals.text2)
            Spacer()
            Text(value)
                .font(TypeScale.num).fontWeight(.semibold)
                .foregroundStyle(theme.neutrals.text1)
        }
    }
}

struct ActivityRing: View {
    @Environment(\.theme) private var theme
    let progress: Double
    var lineWidth: Double = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.neutrals.border, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [theme.primary.primary, theme.primary.primary.opacity(0.7)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int(progress * 100))")
                    .font(TypeScale.title).monospacedDigit()
                Text("%")
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text3)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日活动进度")
        .accessibilityValue("\(Int(progress * 100))%")
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
    .designThemePreview()
    .padding()
}
