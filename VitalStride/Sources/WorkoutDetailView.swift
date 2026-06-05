import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutDetail")

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @State private var showingDeleteAlert = false

    private var sortedExercises: [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section("概要") {
                LabeledContent("日期") {
                    Text(workout.startDate, style: .date)
                }
                if let endDate = workout.endDate {
                    LabeledContent("时长") {
                        let totalSeconds = Int(endDate.timeIntervalSince(workout.startDate))
                        let hours = totalSeconds / 3600
                        let minutes = (totalSeconds % 3600) / 60
                        Text(hours > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(minutes) 分钟")
                    }
                }
                LabeledContent("动作数") {
                    Text("\(sortedExercises.count)")
                }
                let totalSets = sortedExercises
                    .reduce(0) { $0 + ($1.sets?.count ?? 0) }
                LabeledContent("总组数") {
                    Text("\(totalSets)")
                }
                if let calories = workout.totalCalories {
                    LabeledContent("消耗热量") {
                        Text("\(Int(calories)) kcal")
                    }
                }
            }

            ForEach(sortedExercises) { workoutExercise in
                let sets = workoutExercise.sets ?? []
                Section(workoutExercise.exercise?.localizedName ?? "动作") {
                    if sets.isEmpty {
                        Text("无记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, exerciseSet in
                            HStack {
                                Text("第 \(index + 1) 组")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text("\(displayWeight(exerciseSet.weight), specifier: "%.1f") \(weightUnit.rawValue)")
                                Text("×")
                                    .foregroundStyle(.secondary)
                                Text("\(exerciseSet.reps) 次")
                                Spacer()
                                if exerciseSet.setType == .warmup {
                                    Text("热身")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        let workingSets = sets.filter { $0.setType == .working }
                        if !workingSets.isEmpty {
                            let totalVolume = workingSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                            HStack {
                                Text("总训练量")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(displayWeight(totalVolume), specifier: "%.0f") \(weightUnit.rawValue)")
                                    .font(.footnote.bold())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("训练详情")
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label(
                        String(localized: "删除训练", comment: "Delete workout toolbar button"),
                        systemImage: "trash"
                    )
                }
                .accessibilityLabel(String(localized: "删除训练", comment: "Delete workout a11y"))
            }
        }
        .alert(
            String(localized: "确认删除", comment: "Delete confirmation alert title"),
            isPresented: $showingDeleteAlert
        ) {
            Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {}
            Button(String(localized: "删除", comment: "Delete confirm button"), role: .destructive) {
                deleteWorkout()
            }
        } message: {
            Text(String(localized: "确定删除这次训练？", comment: "Delete confirmation message"))
        }
    }

    private func displayWeight(_ kgValue: Double) -> Double {
        weightUnit == .lb ? kgValue * 2.20462 : kgValue
    }

    private func deleteWorkout() {
        logger.info("Deleting workout from detail source=\(workout.source.rawValue, privacy: .public)")
        modelContext.delete(workout)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(
            workout: {
                let w = Workout(
                    type: .strength,
                    startDate: Date().addingTimeInterval(-3600),
                    endDate: Date()
                )
                return w
            }()
        )
    }
    .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
