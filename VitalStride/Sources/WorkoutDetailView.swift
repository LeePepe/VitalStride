import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutDetail")

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthKitService) private var healthKitService
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @State private var showingDeleteAlert = false
    @State private var showingDeleteError = false
    @State private var heartRateStats: WorkoutHeartRateStats?

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
                if workout.hasWorkingSets {
                    LabeledContent(String(localized: "总训练量", comment: "Total training volume in workout summary")) {
                        Text("\(displayWeight(workout.overallWorkingVolume), specifier: "%.0f") \(weightUnit.rawValue)")
                    }
                    .accessibilityLabel(
                        Text(verbatim: "\(String(localized: "总训练量", comment: "Total volume a11y")) \(Int(displayWeight(workout.overallWorkingVolume))) \(weightUnit.a11yName)")
                    )
                }
                if let calories = workout.totalCalories {
                    LabeledContent("消耗热量") {
                        Text("\(Int(calories)) kcal")
                    }
                }
                if let stats = heartRateStats {
                    LabeledContent(String(localized: "平均心率", comment: "Average heart rate in workout summary")) {
                        Text(String(localized: "\(stats.averageHeartRate) bpm", comment: "Heart rate value with unit, e.g. 142 bpm"))
                    }
                    .accessibilityLabel(
                        Text(String(localized: "平均心率 \(stats.averageHeartRate) 次每分钟", comment: "Average heart rate a11y"))
                    )
                    LabeledContent(String(localized: "最高心率", comment: "Max heart rate in workout summary")) {
                        Text(String(localized: "\(stats.maxHeartRate) bpm", comment: "Heart rate value with unit, e.g. 155 bpm"))
                    }
                    .accessibilityLabel(
                        Text(String(localized: "最高心率 \(stats.maxHeartRate) 次每分钟", comment: "Max heart rate a11y"))
                    )
                    if let zones = stats.zoneDistribution {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(zones) { zone in
                                HStack {
                                    Text(zone.localizedName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(zone.percentage * 100))%")
                                        .font(.footnote.bold())
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            Text(String(
                                localized: "心率区间：\(zones.map { "\($0.localizedName) \(Int($0.percentage * 100))%" }.joined(separator: "，"))",
                                comment: "Heart rate zone distribution a11y"
                            ))
                        )
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
                                if exerciseSet.isUnilateral {
                                    Text("×2")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                        .accessibilityLabel(String(localized: "单侧重量", comment: "Unilateral weight a11y label for ×2 badge in detail view"))
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(localized: "总组数", comment: "Per-exercise total sets"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(workoutExercise.totalSetsCount)")
                                    .font(.footnote.bold())
                            }
                            HStack {
                                Text(String(localized: "总次数", comment: "Per-exercise total reps"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(workoutExercise.totalRepsCount)")
                                    .font(.footnote.bold())
                            }
                            if workoutExercise.workingVolume > 0 {
                                HStack {
                                    Text(String(localized: "总训练量", comment: "Per-exercise total volume"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(displayWeight(workoutExercise.workingVolume), specifier: "%.0f") \(weightUnit.rawValue)")
                                        .font(.footnote.bold())
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(exerciseSubtotalA11yLabel(workoutExercise))
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
        .alert(
            String(localized: "删除失败", comment: "Delete failure alert title"),
            isPresented: $showingDeleteError
        ) {
            Button(String(localized: "好", comment: "OK button")) {}
        } message: {
            Text(String(localized: "无法删除训练记录，请稍后重试。", comment: "Delete failure message"))
        }
        .task {
            await loadHeartRateStats()
        }
    }

    private func exerciseSubtotalA11yLabel(_ exercise: WorkoutExercise) -> String {
        var parts: [String] = []
        parts.append(String(localized: "总组数", comment: "Per-exercise total sets a11y") + " \(exercise.totalSetsCount) " + String(localized: "组", comment: "Sets unit a11y"))
        parts.append(String(localized: "总次数", comment: "Per-exercise total reps a11y") + " \(exercise.totalRepsCount) " + String(localized: "次", comment: "Reps unit a11y"))
        if exercise.workingVolume > 0 {
            parts.append(String(localized: "总训练量", comment: "Per-exercise total volume a11y") + " \(Int(displayWeight(exercise.workingVolume))) \(weightUnit.a11yName)")
        }
        return parts.joined(separator: "，")
    }

    private func loadHeartRateStats() async {
        heartRateStats = await WorkoutHeartRateStats.load(
            startDate: workout.startDate,
            endDate: workout.endDate
        ) { dateRange in
            try await healthKitService.fetchData(for: .heartRate, dateRange: dateRange).dataPoints
        }
    }

    private func displayWeight(_ kgValue: Double) -> Double {
        weightUnit == .lb ? kgValue * 2.20462 : kgValue
    }

    private func deleteWorkout() {
        let source = workout.source
        let hkUUID = workout.healthKitUUID
        logger.info("Deleting workout from detail source=\(source.rawValue, privacy: .private)")

        Task {
            if source == .recorded, let hkUUID {
                do {
                    try await healthKitService.deleteWorkout(healthKitUUID: hkUUID)
                } catch {
                    logger.error("HealthKit delete failed uuid=\(hkUUID, privacy: .private) error=\(error.localizedDescription, privacy: .private)")
                }
            }

            modelContext.delete(workout)
            do {
                try modelContext.save()
                dismiss()
            } catch {
                logger.error("Failed to save after deleting workout: \(error.localizedDescription, privacy: .private)")
                modelContext.rollback()
                showingDeleteError = true
            }
        }
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
