import HealthKitService
import SwiftData
import SwiftUI
import VitalModels

#if canImport(UIKit)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    #if !os(macOS)
    @Environment(\.healthKitService) private var healthKitService
    #endif
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
    @State private var showingFinishAlert = false
    @State private var showingDiscardAlert = false
    @State private var exerciseToReplace: WorkoutExercise?
    @State private var restEndDate: Date?
    @State private var currentHeartRate: Double?
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    private let startTime = Date()
    let source: WorkoutStartSource

    init(source: WorkoutStartSource = .blank) {
        self.source = source
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    workoutTimer
                    restTimerBanner
                    exerciseList
                }
                addExerciseButton
            }
            .navigationTitle("训练中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("放弃", role: .destructive) {
                        showingDiscardAlert = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("结束训练") {
                        showingFinishAlert = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                }
            }
            .sheet(item: $exerciseToReplace) { workoutExercise in
                ExercisePickerView { newExercise in
                    workoutExercise.exercise = newExercise
                }
            }
            .alert("完成训练？", isPresented: $showingFinishAlert) {
                Button("完成") { finishWorkout() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("训练将被保存到历史记录")
            }
            .alert("放弃训练？", isPresented: $showingDiscardAlert) {
                Button("放弃", role: .destructive) { discardWorkout() }
                Button("继续训练", role: .cancel) {}
            } message: {
                Text("训练数据将不会保存")
            }
            .onAppear { setupWorkout() }
            .task(id: restEndDate) {
                guard let restEnd = restEndDate else { return }
                let remaining = restEnd.timeIntervalSinceNow
                guard remaining > 0 else {
                    restEndDate = nil
                    return
                }
                try? await Task.sleep(for: .seconds(remaining))
                restEndDate = nil
            }
            #if !os(macOS)
            .task { await observeHeartRate() }
            #endif
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var workoutTimer: some View {
        TimelineView(.periodic(from: startTime, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(startTime)
            let totalSeconds = Int(elapsed)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            let timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            let exerciseCount = workout?.exercises?.count ?? 0
            let setCount = workout?.exercises?
                .reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
            let volumeKg = totalVolumeKg
            let displayVolume = weightUnit == .lb ? volumeKg * 2.20462 : volumeKg
            let volumeText = Int(displayVolume).formatted()
            let summaryText = "\(exerciseCount) 动作 · \(setCount) 组 · \(volumeText) \(weightUnit.rawValue)"
            ViewThatFits(in: .horizontal) {
                HStack {
                    timerLabel
                    Text(timeString)
                        .font(.title3.monospacedDigit())
                    #if !os(macOS)
                    heartRateLabel
                    #endif
                    Spacer()
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        timerLabel
                        Text(timeString)
                            .font(.title3.monospacedDigit())
                        #if !os(macOS)
                        heartRateLabel
                        #endif
                        Spacer()
                    }
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var timerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
            Text("训练时长")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    #if !os(macOS)
    private var heartRateLabel: some View {
        let bpmText = HeartRateFormatter.displayText(currentHeartRate)
        let unitText = String(localized: "次/分", comment: "Heart rate unit bpm")
        return HStack(spacing: 2) {
            Image(systemName: "heart.fill")
            Text(bpmText)
                .monospacedDigit()
            Text(unitText)
        }
        .font(.subheadline)
        .foregroundStyle(.pink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "心率", comment: "Heart rate a11y label"))
        .accessibilityValue(HeartRateFormatter.accessibilityText(currentHeartRate))
    }
    #endif

    @ViewBuilder
    private var restTimerBanner: some View {
        if let restEnd = restEndDate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(restEnd.timeIntervalSince(context.date)))
                if remaining > 0 {
                    HStack {
                        Image(systemName: "bed.double.fill")
                        Text("休息中 \(remaining)s")
                            .monospacedDigit()
                        Spacer()
                        Button("跳过") {
                            restEndDate = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.1))
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        let exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        if exercises.isEmpty {
            ContentUnavailableView(
                "添加第一个动作",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("点击下方按钮选择训练动作")
            )
        } else {
            List {
                ForEach(exercises) { workoutExercise in
                    ActiveExerciseSection(
                        workoutExercise: workoutExercise,
                        onSetCompleted: {
                            restEndDate = Date().addingTimeInterval(90)
                        },
                        onReplace: {
                            exerciseToReplace = workoutExercise
                        },
                        onDelete: {
                            deleteExercise(workoutExercise)
                        }
                    )
                }
                .onMove { source, destination in
                    moveExercises(from: source, to: destination)
                }
                Section {} footer: { Color.clear.frame(height: 72) }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var addExerciseButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showingExercisePicker = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(FABButtonStyle())
        .accessibilityLabel("添加动作")
        .padding()
    }

    private var totalVolumeKg: Double {
        (workout?.exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    // MARK: - Actions

    #if !os(macOS)
    private func observeHeartRate() async {
        for await dataPoint in healthKitService.observeHeartRate() {
            currentHeartRate = dataPoint.value
        }
    }
    #endif

    private func setupWorkout() {
        guard workout == nil else { return }
        let newWorkout = Workout(type: .strength, startDate: startTime)
        modelContext.insert(newWorkout)

        switch source {
        case .blank:
            break
        case .fromWorkout(let sourceWorkout):
            let sourceExercises = (sourceWorkout.exercises ?? []).sorted { $0.order < $1.order }
            for (index, srcExercise) in sourceExercises.enumerated() {
                let workoutExercise = WorkoutExercise(order: index, exercise: srcExercise.exercise)
                workoutExercise.workout = newWorkout
                modelContext.insert(workoutExercise)
                let srcSets = (srcExercise.sets ?? []).sorted { $0.order < $1.order }
                for (setIndex, srcSet) in srcSets.enumerated() {
                    let newSet = ExerciseSet(
                        order: setIndex,
                        weight: srcSet.weight,
                        reps: srcSet.reps,
                        setType: srcSet.setType
                    )
                    newSet.workoutExercise = workoutExercise
                    modelContext.insert(newSet)
                }
            }
        case .fromTemplate(let template):
            let templateExercises = (template.exercises ?? []).sorted { $0.order < $1.order }
            for (index, templateExercise) in templateExercises.enumerated() {
                let workoutExercise = WorkoutExercise(order: index, exercise: templateExercise.exercise)
                workoutExercise.workout = newWorkout
                modelContext.insert(workoutExercise)
            }
        }

        workout = newWorkout
    }

    private func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises?.count ?? 0
        let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
        workoutExercise.workout = workout
        modelContext.insert(workoutExercise)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var exercises = (workout?.exercises ?? []).sorted { $0.order < $1.order }
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
    }

    private func deleteExercise(_ workoutExercise: WorkoutExercise) {
        modelContext.delete(workoutExercise)
        let remaining = (workout?.exercises ?? [])
            .filter { $0.persistentModelID != workoutExercise.persistentModelID }
            .sorted { $0.order < $1.order }
        for (index, exercise) in remaining.enumerated() {
            exercise.order = index
        }
    }

    private func finishWorkout() {
        guard let workout else { return }
        workout.finish()
        try? modelContext.save()
        dismiss()
    }

    private func discardWorkout() {
        if let workout {
            modelContext.delete(workout)
            try? modelContext.save()
        }
        dismiss()
    }
}

// MARK: - Active Exercise Section

private struct ActiveExerciseSection: View {
    let workoutExercise: WorkoutExercise
    let onSetCompleted: () -> Void
    let onReplace: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @State private var showingDeleteConfirmation = false

    private var sortedSets: [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        Section {
            ForEach(Array(sortedSets.enumerated()), id: \.element.persistentModelID) { index, exerciseSet in
                SetRow(
                    index: index,
                    exerciseSet: exerciseSet,
                    weightUnit: weightUnit,
                    onToggleCompleted: { wasCompleted in
                        if !wasCompleted {
                            onSetCompleted()
                        }
                    }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteSet(exerciseSet)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            addSetButton
        } header: {
            Text(workoutExercise.exercise?.localizedName ?? "动作")
                .contextMenu {
                    Button {
                        onReplace()
                    } label: {
                        Label("替换动作", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("删除动作", systemImage: "trash")
                    }
                }
                .accessibilityHint("长按可替换或删除动作")
                .confirmationDialog(
                    "删除动作？",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("删除", role: .destructive) { onDelete() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("该动作及所有已录入的组数据将被删除")
                }
        }
    }

    private var addSetButton: some View {
        Button {
            addSet()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("添加一组")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("添加一组")
        .accessibilityHint("在列表末尾插入新的一组")
    }

    private func addSet() {
        let lastSet = sortedSets.last
        let order = workoutExercise.sets?.count ?? 0
        let newSet = ExerciseSet(
            order: order,
            weight: lastSet?.weight ?? 0,
            reps: lastSet?.reps ?? 0,
            setType: lastSet?.setType ?? .working
        )
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
    }

    private func deleteSet(_ exerciseSet: ExerciseSet) {
        modelContext.delete(exerciseSet)
        let remaining = sortedSets.filter { $0.persistentModelID != exerciseSet.persistentModelID }
        for (newOrder, set) in remaining.enumerated() {
            set.order = newOrder
        }
    }
}

// MARK: - Set Row (Always Editable)

private struct SetRow: View {
    let index: Int
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            TextField(weightUnit.rawValue, text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .accessibilityLabel("第 \(index + 1) 组重量")
                .accessibilityHint("输入重量数值")
                .onChange(of: weightText) { _, newValue in
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { weightText = filtered }
                    syncWeightToModel()
                }

            Text("×")
                .foregroundStyle(.secondary)

            TextField("次数", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .accessibilityLabel("第 \(index + 1) 组次数")
                .accessibilityHint("输入次数")
                .onChange(of: repsText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { repsText = filtered }
                    syncRepsToModel()
                }

            Picker(selection: Binding(
                get: { exerciseSet.setType },
                set: { exerciseSet.setType = $0 }
            )) {
                Text(SetType.working.displayName).tag(SetType.working)
                Text(SetType.warmup.displayName).tag(SetType.warmup)
            } label: {
                Text("第 \(index + 1) 组类型")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("第 \(index + 1) 组类型")
            .accessibilityHint("选择组类型")

            Spacer()

            Button {
                let wasCompleted = exerciseSet.isCompleted
                exerciseSet.isCompleted = !wasCompleted
                onToggleCompleted(wasCompleted)
            } label: {
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(exerciseSet.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("第 \(index + 1) 组，\(exerciseSet.isCompleted ? "已完成" : "未完成")")
            .accessibilityHint("双击切换完成状态")
        }
        .onAppear {
            let displayW = weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight
            weightText = formatWeight(displayW)
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private func syncWeightToModel() {
        let weight: Double
        if weightText.isEmpty {
            weight = 0
        } else {
            guard let parsed = Double(weightText) else { return }
            weight = parsed
        }
        guard weight.isFinite, weight >= 0 else { return }
        exerciseSet.weight = weightUnit == .lb ? weight / 2.20462 : weight
    }

    private func syncRepsToModel() {
        let reps: Int
        if repsText.isEmpty {
            reps = 0
        } else {
            guard let parsed = Int(repsText) else { return }
            reps = parsed
        }
        guard reps >= 0 else { return }
        exerciseSet.reps = reps
    }

    private func filterDecimalInput(_ text: String) -> String {
        var result = ""
        var hasDecimalPoint = false
        for char in text {
            if char.isNumber {
                result.append(char)
            } else if char == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                result.append(char)
            }
        }
        return result
    }

    private func formatWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? (value == 0 ? "" : String(Int(value)))
            : String(format: "%.1f", value)
    }
}

// MARK: - Heart Rate Formatter

enum HeartRateFormatter {
    static func displayText(_ heartRate: Double?) -> String {
        guard let heartRate else { return "--" }
        return "\(Int(heartRate))"
    }

    static func accessibilityText(_ heartRate: Double?) -> String {
        guard let heartRate else {
            return String(localized: "无数据", comment: "No data a11y value")
        }
        let bpm = Int(heartRate)
        return String(localized: "\(bpm) 次每分钟", comment: "Heart rate a11y value with full unit")
    }
}

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ActiveWorkoutView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
