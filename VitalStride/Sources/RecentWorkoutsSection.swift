import SwiftUI

struct RecentWorkoutsSection: View {
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近训练")
                .font(.headline)

            if workouts.isEmpty {
                Text("暂无训练记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecentWorkoutRow: View {
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
                    .foregroundStyle(.secondary)

                    if let endDate = workout.endDate {
                        let minutes = Int(endDate.timeIntervalSince(workout.startDate)) / 60
                        let hours = minutes / 60
                        let remainingMinutes = minutes % 60
                        Label(
                            hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(minutes)m",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    let exerciseCount = workout.exercises?.count ?? 0
                    if exerciseCount > 0 {
                        Label(
                            "\(exerciseCount) 个动作",
                            systemImage: "list.bullet"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func workoutTypeLabel(_ type: WorkoutType) -> String {
        switch type {
        case .strength: "力量训练"
        case .running: "跑步"
        case .cycling: "骑行"
        case .swimming: "游泳"
        case .yoga: "瑜伽"
        case .hiking: "徒步"
        case .walking: "步行"
        case .rowing: "划船"
        case .elliptical: "椭圆机"
        case .coreTraining: "核心训练"
        case .flexibility: "柔韧性"
        case .other: "其他"
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
}
