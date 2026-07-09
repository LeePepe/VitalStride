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
    @State private var deletionController = WorkoutDeletionController()
    @State private var showingSaveTemplateAlert = false
    @State private var templateNameInput = ""
    @State private var showingSaveTemplateError = false
    @State private var showingSaveTemplateSuccess = false
    @State private var heartRateStats: WorkoutHeartRateStats?

    private var isDeleting: Bool { deletionController.isDeleting }

    private var sortedExercises: [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        content
            .navigationTitle("训练详情")
            .toolbar {
                saveTemplateToolbarItem
                deleteToolbarItem
            }
            .alert(
                String(localized: "确认删除", comment: "Delete confirmation alert title"),
                isPresented: $showingDeleteAlert
            ) {
                Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {}
                Button(String(localized: "删除", comment: "Delete confirm button"), role: .destructive) {
                    beginDelete()
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
            .alert(
                String(localized: "workout_template_name_prompt", defaultValue: "Template Name", comment: "Prompt title asking for the template name when saving a workout as a template"),
                isPresented: $showingSaveTemplateAlert
            ) {
                TextField(
                    String(localized: "workout_template_name_placeholder", defaultValue: "Template name", comment: "Placeholder text in the template name text field"),
                    text: $templateNameInput
                )
                Button(String(localized: "common_cancel", defaultValue: "Cancel", comment: "Cancel button on the save-as-template alert"), role: .cancel) {}
                Button(String(localized: "workout_template_save_confirm", defaultValue: "Save", comment: "Confirm button on the save-as-template alert")) {
                    saveAsTemplate()
                }
                .disabled(templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text(String(localized: "workout_template_name_message", defaultValue: "Give this template a name so you can reuse it later.", comment: "Body message on the save-as-template alert"))
            }
            .alert(
                String(localized: "workout_template_save_failed_title", defaultValue: "Save Failed", comment: "Alert title when saving a workout as a template fails"),
                isPresented: $showingSaveTemplateError
            ) {
                Button(String(localized: "common_ok", defaultValue: "OK", comment: "OK button on the save-as-template failure alert")) {}
            } message: {
                Text(String(localized: "workout_template_save_failed_message", defaultValue: "Unable to save this workout as a template. Please try again.", comment: "Body of the alert shown when saving a template fails"))
            }
            .alert(
                String(localized: "workout_template_saved_title", defaultValue: "Template Saved", comment: "Alert title after a workout was successfully saved as a template"),
                isPresented: $showingSaveTemplateSuccess
            ) {
                Button(String(localized: "common_ok", defaultValue: "OK", comment: "OK button on the save-as-template success alert")) {}
            } message: {
                Text(String(localized: "workout_template_saved_message", defaultValue: "You can start a new workout from this template on the Start Workout screen.", comment: "Body of the alert shown after saving a template"))
            }
            .task {
                await loadHeartRateStats()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isDeleting {
            // Once deletion begins, stop reading any property on `workout`.
            // If SwiftData detaches the backing store before dismissal, reading
            // e.g. `\Workout.type` on the stale reference traps with
            // "backing data was detached without resolving faults".
            Color.clear
                .accessibilityHidden(true)
        } else {
            detailList
        }
    }

    private var detailList: some View {
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
                    if let hrr = stats.heartRateRecovery1Min {
                        LabeledContent(String(localized: "workout_detail_hrr_1min", defaultValue: "1-min HRR", comment: "1-minute heart rate recovery (HRR) label in workout summary")) {
                            Text(String(localized: "\(hrr) bpm", comment: "Heart rate value with unit, e.g. 24 bpm"))
                        }
                        .accessibilityLabel(
                            Text(String(localized: "workout_detail_hrr_1min_a11y", defaultValue: "1-minute heart rate recovery \(hrr) beats per minute", comment: "1-minute heart rate recovery a11y"))
                        )
                    }
                    if let zones = stats.zoneDistribution, !zones.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HeartRateZoneStackedBar(zones: zones)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(zones) { zone in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(HeartRateZoneStackedBar.color(forZoneId: zone.id))
                                            .frame(width: 8, height: 8)
                                        Text(zone.localizedName)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(zone.percentage * 100))%")
                                            .font(.footnote.bold())
                                    }
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
                            oneRepMaxSection(for: workoutExercise)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(exerciseSubtotalA11yLabel(workoutExercise))
                    }
                }
            }
        }
    }

    private var deleteToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label(
                    String(localized: "删除训练", comment: "Delete workout toolbar button"),
                    systemImage: "trash"
                )
            }
            .disabled(isDeleting)
            .accessibilityLabel(String(localized: "删除训练", comment: "Delete workout a11y"))
        }
    }

    private var saveTemplateToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                templateNameInput = WorkoutTemplateBuilder.defaultTemplateName(from: workout)
                showingSaveTemplateAlert = true
            } label: {
                Label(
                    String(localized: "workout_save_as_template", defaultValue: "Save as Template", comment: "Workout detail toolbar button that saves the current workout as a reusable template"),
                    systemImage: "square.and.arrow.down.on.square"
                )
            }
            .disabled(isDeleting)
            .accessibilityLabel(String(localized: "workout_save_as_template", defaultValue: "Save as Template", comment: "Workout detail toolbar button a11y for saving current workout as a template"))
        }
    }

    @ViewBuilder
    private func oneRepMaxSection(for workoutExercise: WorkoutExercise) -> some View {
        if let oneRepMax = workoutExercise.bestEstimatedOneRepMax {
            HStack {
                Text(String(localized: "workout_detail_estimated_1rm", defaultValue: "Estimated 1RM", comment: "Per-exercise estimated one-rep max label"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(displayWeight(oneRepMax), specifier: "%.1f") \(weightUnit.rawValue)")
                    .font(.footnote.bold())
            }
            if let exerciseModel = workoutExercise.exercise {
                NavigationLink {
                    OneRepMaxTrendView(exercise: exerciseModel)
                } label: {
                    Text(String(
                        localized: "workout_detail_view_1rm_trend",
                        defaultValue: "View 1RM Trend",
                        comment: "Navigation link from workout detail exercise section to the per-exercise 1RM trend view"
                    ))
                    .font(.footnote)
                }
                .accessibilityLabel(String(
                    localized: "workout_detail_view_1rm_trend_a11y",
                    defaultValue: "View one rep max trend for this exercise",
                    comment: "A11y label for View 1RM Trend link"
                ))
            }
        }
    }

    private func exerciseSubtotalA11yLabel(_ exercise: WorkoutExercise) -> String {
        var parts: [String] = []
        parts.append(String(localized: "总组数", comment: "Per-exercise total sets a11y") + " \(exercise.totalSetsCount) " + String(localized: "组", comment: "Sets unit a11y"))
        parts.append(String(localized: "总次数", comment: "Per-exercise total reps a11y") + " \(exercise.totalRepsCount) " + String(localized: "次", comment: "Reps unit a11y"))
        if exercise.workingVolume > 0 {
            parts.append(String(localized: "总训练量", comment: "Per-exercise total volume a11y") + " \(Int(displayWeight(exercise.workingVolume))) \(weightUnit.a11yName)")
        }
        if let oneRepMax = exercise.bestEstimatedOneRepMax {
            let value = String(format: "%.1f", displayWeight(oneRepMax))
            parts.append(String(localized: "workout_detail_estimated_1rm", defaultValue: "Estimated 1RM", comment: "Per-exercise estimated one-rep max a11y") + " \(value) \(weightUnit.a11yName)")
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

    private func beginDelete() {
        guard !isDeleting else { return }
        let hkService = healthKitService
        deletionController.beginDelete(
            workout: workout,
            in: modelContext,
            healthKitDelete: { uuid in
                try await hkService.deleteWorkout(healthKitUUID: uuid)
            },
            onFinished: { dismiss() },
            onError: { _ in showingDeleteError = true }
        )
    }

    private func saveAsTemplate() {
        let name = templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try WorkoutTemplateBuilder.saveAsTemplate(from: workout, name: name, context: modelContext)
            showingSaveTemplateSuccess = true
        } catch {
            logger.error("Failed to save workout as template: \(error.localizedDescription, privacy: .private)")
            modelContext.rollback()
            showingSaveTemplateError = true
        }
    }
}

struct HeartRateZoneStackedBar: View {
    let zones: [HeartRateZone]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(zones) { zone in
                    Rectangle()
                        .fill(Self.color(forZoneId: zone.id))
                        .frame(width: max(0, geo.size.width * zone.percentage))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    static func color(forZoneId id: Int) -> Color {
        switch id {
        case 1: .gray
        case 2: .blue
        case 3: .green
        case 4: .orange
        case 5: .red
        default: .secondary
        }
    }
}

#Preview("WorkoutDetail — empty stats") {
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

private struct _HeartRateSummaryPreviewFixture {
    static let fullZones: [HeartRateZone] = [
        HeartRateZone(id: 1, localizedName: "Zone 1", range: 0...99, percentage: 0.10),
        HeartRateZone(id: 2, localizedName: "Zone 2", range: 100...119, percentage: 0.25),
        HeartRateZone(id: 3, localizedName: "Zone 3", range: 120...139, percentage: 0.35),
        HeartRateZone(id: 4, localizedName: "Zone 4", range: 140...159, percentage: 0.20),
        HeartRateZone(id: 5, localizedName: "Zone 5", range: 160...300, percentage: 0.10),
    ]

    static let singleZone: [HeartRateZone] = [
        HeartRateZone(id: 3, localizedName: "Zone 3", range: 120...139, percentage: 1.0),
    ]
}

/// Preview-only view mirroring the heart-rate/zone/HRR rows rendered inside
/// `WorkoutDetailView`. Because the production view loads stats from HealthKit
/// via `.task`, previews cannot exercise those UI states directly; this fixture
/// renders equivalent SwiftUI to visualize each `zoneDistribution` / HRR
/// combination without altering `WorkoutDetailView`'s runtime behavior.
private struct _HeartRateSummaryPreviewHost: View {
    let stats: WorkoutHeartRateStats

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Average HR") {
                    Text("\(stats.averageHeartRate) bpm")
                }
                LabeledContent("Max HR") {
                    Text("\(stats.maxHeartRate) bpm")
                }
                if let hrr = stats.heartRateRecovery1Min {
                    LabeledContent("1-min HRR") {
                        Text("\(hrr) bpm")
                    }
                }
                if let zones = stats.zoneDistribution, !zones.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HeartRateZoneStackedBar(zones: zones)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(zones) { zone in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(HeartRateZoneStackedBar.color(forZoneId: zone.id))
                                        .frame(width: 8, height: 8)
                                    Text(zone.localizedName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(zone.percentage * 100))%")
                                        .font(.footnote.bold())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("HR summary — full zones + HRR") {
    _HeartRateSummaryPreviewHost(
        stats: WorkoutHeartRateStats(
            averageHeartRate: 138,
            maxHeartRate: 172,
            zoneDistribution: _HeartRateSummaryPreviewFixture.fullZones,
            heartRateRecovery1Min: 24
        )
    )
}

#Preview("HR summary — single zone, nil HRR") {
    _HeartRateSummaryPreviewHost(
        stats: WorkoutHeartRateStats(
            averageHeartRate: 128,
            maxHeartRate: 134,
            zoneDistribution: _HeartRateSummaryPreviewFixture.singleZone,
            heartRateRecovery1Min: nil
        )
    )
}

#Preview("HR summary — nil zones + HRR") {
    _HeartRateSummaryPreviewHost(
        stats: WorkoutHeartRateStats(
            averageHeartRate: 142,
            maxHeartRate: 165,
            zoneDistribution: nil,
            heartRateRecovery1Min: 31
        )
    )
}

#Preview("Zone bar — full spread") {
    HeartRateZoneStackedBar(zones: _HeartRateSummaryPreviewFixture.fullZones)
        .padding()
}

#Preview("Zone bar — single zone") {
    HeartRateZoneStackedBar(zones: _HeartRateSummaryPreviewFixture.singleZone)
        .padding()
}

#Preview("Zone bar — no zones") {
    HeartRateZoneStackedBar(zones: [])
        .padding()
}
