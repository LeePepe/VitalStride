import SwiftData
import SwiftUI
import VitalModels

enum WorkoutStartSource {
    case blank
    case fromWorkout(Workout)
    case fromTemplate(WorkoutTemplate)
}

struct StartWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var recentWorkouts: [Workout]
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    let onStart: (WorkoutStartSource) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        onStart(.blank)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("空白训练")
                                    .font(.body)
                                Text("从零开始，逐个添加动作")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if !recentWorkouts.isEmpty {
                    Section("从历史复制") {
                        ForEach(recentWorkouts.prefix(5)) { workout in
                            Button {
                                dismiss()
                                onStart(.fromWorkout(workout))
                            } label: {
                                HistoryWorkoutRow(workout: workout)
                            }
                        }
                    }
                }

                if !templates.isEmpty {
                    Section("从模板开始") {
                        ForEach(templates) { template in
                            Button {
                                dismiss()
                                onStart(.fromTemplate(template))
                            } label: {
                                TemplateRow(template: template)
                            }
                        }
                    }
                }
            }
            .navigationTitle("开始训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryWorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.startDate, style: .date)
                .font(.body)
            let exerciseNames = (workout.exercises ?? [])
                .sorted { $0.order < $1.order }
                .compactMap { $0.exercise?.localizedName }
            if !exerciseNames.isEmpty {
                Text(exerciseNames.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
                .font(.body)
            let count = template.exercises?.count ?? 0
            Text("\(count) 个动作")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StartWorkoutView { _ in }
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
