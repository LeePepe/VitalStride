// MY-1090 precedent: pre-existing `no_hardcoded_chinese` literals (section
// title, empty-state text, workout-type labels) predate the `--strict`
// SwiftLint hook and stay silenced at file scope until the shared i18n
// cleanup migrates them. No semantic change from this pragma.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI
import VitalModels

struct RecentWorkoutsSection: View {
    @Environment(\.theme) private var theme
    let workouts: [Workout]

    var body: some View {
        Card {
            Text(String(localized: "最近训练", comment: ""))
                .font(TypeScale.title)
                .foregroundStyle(theme.neutrals.text1)

            if workouts.isEmpty {
                Text(String(localized: "暂无训练记录", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        RecentWorkoutRow(workout: workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RecentWorkoutRow: View {
    @Environment(\.theme) private var theme
    let workout: Workout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.startDate, style: .date)
                    .font(.subheadline.bold())

                HStack(spacing: 12) {
                    Label(
                        workoutTypeLabel(workout.type),
                        systemImage: workoutTypeIcon(workout.type)
                    )
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)

                    if let endDate = workout.endDate {
                        let minutes = Int(endDate.timeIntervalSince(workout.startDate)) / 60
                        let hours = minutes / 60
                        let remainingMinutes = minutes % 60
                        Label(
                            hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(minutes)m",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)
                    }

                    let exerciseCount = workout.exercises?.count ?? 0
                    if exerciseCount > 0 {
                        Label(
                            String(localized: "\(exerciseCount) 个动作", comment: "Exercise count label"),
                            systemImage: "list.bullet"
                        )
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(theme.neutrals.text3)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func workoutTypeLabel(_ type: WorkoutType) -> String {
        switch type {
        case .strength: String(localized: "力量训练", comment: "")
        case .running: String(localized: "跑步", comment: "")
        case .cycling: String(localized: "骑行", comment: "")
        case .swimming: String(localized: "游泳", comment: "")
        case .yoga: String(localized: "瑜伽", comment: "")
        case .hiking: String(localized: "徒步", comment: "")
        case .walking: String(localized: "步行", comment: "")
        case .rowing: String(localized: "划船", comment: "")
        case .elliptical: String(localized: "椭圆机", comment: "")
        case .coreTraining: String(localized: "核心训练", comment: "")
        case .flexibility: String(localized: "柔韧性", comment: "")
        case .other: String(localized: "其他", comment: "")
        }
    }

    private func workoutTypeIcon(_ type: WorkoutType) -> String {
        switch type {
        case .strength: "figure.strengthtraining.traditional"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .hiking: "figure.hiking"
        case .walking: "figure.walk"
        case .rowing: "figure.rowing"
        case .elliptical: "figure.elliptical"
        case .coreTraining: "figure.core.training"
        case .flexibility: "figure.flexibility"
        case .other: "figure.mixed.cardio"
        }
    }
}

#Preview {
    NavigationStack {
        RecentWorkoutsSection(workouts: [])
    }
    .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
    .designThemePreview()
}
