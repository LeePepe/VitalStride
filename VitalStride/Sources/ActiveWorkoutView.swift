import HealthKitService
import os
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveWorkout")

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.healthKitService) private var healthKitService
    #endif
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
    @State private var showingFinishAlert = false
    @State private var showingDiscardAlert = false
    @State private var exerciseToReplace: WorkoutExercise?
    @State private var restTimer = RestTimerController()
    @State private var currentHeartRate: Double?
    @State private var heartRateReceivedAt: Date?
    #if !os(macOS)
    @State private var sessionManager: (any WorkoutSessionManaging)?
    #endif
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    @State private var startTime = Date()
    let source: WorkoutStartSource

    init(source: WorkoutStartSource = .blank) {
        self.source = source
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    workoutTimer
                    exerciseList
                }
                .snackbar(
                    isPresented: restSnackbarPresented,
                    mode: restTimer.phase == .completed ? .autoDismiss(duration: 2) : .persistent
                ) {
                    restSnackbarContent
                }
                addExerciseButton
                    .padding(.bottom, restTimer.phase != .idle ? 100 : 0)
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: restTimer.phase != .idle)
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
                ExercisePickerView { exercises in
                    for exercise in exercises {
                        addExercise(exercise)
                    }
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
            .task(id: restTimer.restEndDate) {
                await restTimer.handleTimerTask()
            }
            .onChange(of: restTimer.phase) { _, newPhase in
                if newPhase == .completed {
                    HapticManager.trigger(.restCompleted)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                do {
                    try modelContext.save()
                    logger.info("Background save triggered: result=success")
                } catch {
                    logger.info("Background save triggered: result=failure, error=\(error.localizedDescription)")
                }
            }
            #if !os(macOS)
            .task { await observeHeartRate() }
            .task { await monitorHeartRateStaleness() }
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

    private var restSnackbarPresented: Binding<Bool> {
        Binding(
            get: { restTimer.phase != .idle },
            set: { newValue in
                guard !newValue else { return }
                switch restTimer.phase {
                case .resting: restTimer.skipRest()
                case .completed: restTimer.dismissCompleted()
                case .idle: break
                }
            }
        )
    }

    @ViewBuilder
    private var restSnackbarContent: some View {
        if restTimer.phase == .completed {
            Button {
                restTimer.dismissCompleted()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "休息结束", comment: "Rest completed banner text"))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "休息结束", comment: "Rest completed a11y label"))
            .accessibilityHint(String(localized: "点击关闭", comment: "Dismiss rest completed banner a11y hint"))
        } else if restTimer.phase == .resting, let restEnd = restTimer.restEndDate {
            let totalDuration = restTimer.restTotalDuration ?? 0
            let totalSeconds = max(1, Int(totalDuration))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(restEnd.timeIntervalSince(context.date)))
                let progress = 1.0 - Double(remaining) / Double(totalSeconds)
                HStack {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: progress)
                        Text("\(remaining)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(width: 32, height: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "休息中 \(remaining)s / \(totalSeconds)s", comment: "Rest timer progress a11y label"))
                    Spacer()
                    restAdjustButtons
                }
            }
        }
    }

    private var restAdjustButtons: some View {
        HStack(spacing: 8) {
            Button("-10s") {
                restTimer.adjustRest(by: -10)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "缩短十秒", comment: "Subtract 10 seconds a11y label"))
            Button("+10s") {
                restTimer.adjustRest(by: 10)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "延长十秒", comment: "Add 10 seconds a11y label"))
            Button(String(localized: "跳过", comment: "Skip rest button label")) {
                restTimer.skipRest()
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel(String(localized: "跳过休息", comment: "Skip rest a11y label"))
        }
        .buttonStyle(.plain)
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
                            restTimer.startRest()
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
            HapticManager.trigger(.exerciseAdded)
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
            guard dataPoint.startDate.timeIntervalSinceNow > -120 else { continue }
            currentHeartRate = dataPoint.value
            heartRateReceivedAt = Date()
        }
    }

    private func monitorHeartRateStaleness() async {
        let freshnessLimit: TimeInterval = 120
        let checkInterval: Duration = .seconds(10)
        while !Task.isCancelled {
            try? await Task.sleep(for: checkInterval)
            if let receivedAt = heartRateReceivedAt,
               receivedAt.timeIntervalSinceNow < -freshnessLimit {
                currentHeartRate = nil
                heartRateReceivedAt = nil
            }
        }
    }
    #endif

    private func setupWorkout() {
        guard workout == nil else { return }

        switch source {
        case .resume(let existingWorkout):
            workout = existingWorkout
            startTime = existingWorkout.startDate
            let exerciseCount = existingWorkout.exercises?.count ?? 0
            let setCount = existingWorkout.exercises?
                .reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0
            logger.info("Workout resumed: exerciseCount=\(exerciseCount), setCount=\(setCount)")
        default:
            let newWorkout = Workout(type: .strength, startDate: startTime)
            modelContext.insert(newWorkout)

            switch source {
            case .blank:
                break
            case .fromWorkout(let sourceWorkout):
                WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: modelContext)
            case .fromTemplate(let template):
                WorkoutCopier.setupFromTemplate(template, into: newWorkout, using: modelContext)
            case .resume:
                break
            }

            workout = newWorkout
        }

        #if !os(macOS)
        let manager = healthKitService.makeWorkoutSessionManager()
        sessionManager = manager
        Task { await manager.startSession() }
        #endif
    }

    private func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises?.count ?? 0
        let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
        workoutExercise.workout = workout
        modelContext.insert(workoutExercise)

        let defaultSet = ExerciseSet(order: 0, weight: 0, reps: 0, setType: .working)
        defaultSet.workoutExercise = workoutExercise
        modelContext.insert(defaultSet)
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
        restTimer.cancelRestForWorkoutEnd()
        workout.finish()
        HapticManager.trigger(.workoutFinished)
        try? modelContext.save()
        #if !os(macOS)
        if let manager = sessionManager {
            Task {
                let healthKitUUID = await manager.endSession(save: true)
                if let healthKitUUID {
                    workout.healthKitUUID = healthKitUUID
                    try? modelContext.save()
                }
                dismiss()
            }
            return
        }
        #endif
        dismiss()
    }

    private func discardWorkout() {
        restTimer.cancelRestForWorkoutEnd()
        #if !os(macOS)
        if let manager = sessionManager {
            Task { await manager.endSession(save: false) }
        }
        #endif
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
                if exerciseSet.setType.isSubSet {
                    SubSetRow(
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        isLast: isLastSubSet(at: index),
                        parentSetNumber: parentSetNumber(for: index),
                        onToggleCompleted: { wasCompleted in
                            if !wasCompleted { onSetCompleted() }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if sortedSets.count > 1 {
                            Button(role: .destructive) {
                                deleteSet(exerciseSet)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    SetRow(
                        index: mainSetNumber(upTo: index),
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        onToggleCompleted: { wasCompleted in
                            if !wasCompleted { onSetCompleted() }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if sortedSets.count > 1 {
                            Button(role: .destructive) {
                                deleteSet(exerciseSet)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if exerciseSet.setType == .working {
                            Button {
                                addSubSet(after: exerciseSet, type: .dropSet)
                            } label: {
                                Label("添加递减组", systemImage: "arrow.down.right")
                            }
                            Button {
                                addSubSet(after: exerciseSet, type: .pyramid)
                            } label: {
                                Label("添加递增组", systemImage: "arrow.up.right")
                            }
                        }
                    }
                }
            }
            addSetButton
        } header: {
            HStack {
                Text(workoutExercise.exercise?.localizedName ?? "动作")
                    .contextMenu {
                        Button {
                            onReplace()
                        } label: {
                            Label(String(localized: "替换动作", comment: "Replace exercise context menu item"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "删除动作", comment: "Delete exercise context menu item"), systemImage: "trash")
                        }
                    }
                    .accessibilityHint(String(localized: "长按可替换或删除动作", comment: "Exercise section header context menu a11y hint"))
                Spacer()
                Menu {
                    Button {
                        onReplace()
                    } label: {
                        Label(String(localized: "替换动作", comment: "Replace exercise menu item"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "删除动作", comment: "Delete exercise menu item"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "动作操作菜单", comment: "Exercise action menu a11y label"))
            }
            .confirmationDialog(
                String(localized: "删除动作？", comment: "Delete exercise confirmation title"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "删除", comment: "Delete confirmation button"), role: .destructive) { onDelete() }
                Button(String(localized: "取消", comment: "Cancel confirmation button"), role: .cancel) {}
            } message: {
                Text(String(localized: "该动作及所有已录入的组数据将被删除", comment: "Delete exercise confirmation message"))
            }
        }
    }

    private func mainSetNumber(upTo index: Int) -> Int {
        let sets = sortedSets
        var count = 0
        for i in 0..<index {
            if !sets[i].setType.isSubSet { count += 1 }
        }
        return count
    }

    private func parentSetNumber(for index: Int) -> Int {
        let sets = sortedSets
        var lastMainNumber = 0
        for i in 0..<index {
            if !sets[i].setType.isSubSet { lastMainNumber += 1 }
        }
        return lastMainNumber
    }

    private func isLastSubSet(at index: Int) -> Bool {
        let sets = sortedSets
        if index + 1 >= sets.count { return true }
        return !sets[index + 1].setType.isSubSet
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
        let lastMainSet = sortedSets.last(where: { !$0.setType.isSubSet })
        let order = workoutExercise.sets?.count ?? 0
        let newSet = ExerciseSet(
            order: order,
            weight: lastMainSet?.weight ?? 0,
            reps: lastMainSet?.reps ?? 0,
            setType: lastMainSet?.setType ?? .working,
            isUnilateral: lastMainSet?.isUnilateral ?? false
        )
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
    }

    private func addSubSet(after parentSet: ExerciseSet, type: SetType) {
        let sets = sortedSets
        let parentIndex = sets.firstIndex(where: { $0.persistentModelID == parentSet.persistentModelID }) ?? 0

        var insertIndex = parentIndex + 1
        while insertIndex < sets.count && sets[insertIndex].setType.isSubSet {
            insertIndex += 1
        }

        let adjustedWeight: Double
        if type == .dropSet {
            adjustedWeight = parentSet.weight * 0.85
        } else {
            adjustedWeight = parentSet.weight * 1.15
        }

        for i in insertIndex..<sets.count {
            sets[i].order = sets[i].order + 1
        }

        let newSet = ExerciseSet(
            order: insertIndex,
            weight: adjustedWeight,
            reps: parentSet.reps,
            setType: type
        )
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
    }

    private func deleteSet(_ exerciseSet: ExerciseSet) {
        WorkoutSetManager.deleteSet(exerciseSet, from: workoutExercise, using: modelContext)
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

            SelectAllTextField(
                placeholder: weightUnit.rawValue,
                text: $weightText,
                keyboardType: .decimalPad
            )
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

            SelectAllTextField(
                placeholder: "次数",
                text: $repsText,
                keyboardType: .numberPad
            )
                .frame(width: 60)
                .accessibilityLabel("第 \(index + 1) 组次数")
                .accessibilityHint("输入次数")
                .onChange(of: repsText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { repsText = filtered }
                    syncRepsToModel()
                }

            Menu {
                Picker(selection: Binding(
                    get: { exerciseSet.setType },
                    set: { exerciseSet.setType = $0 }
                )) {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                } label: {
                    Text(String(localized: "组类型", comment: "Set type picker label in menu"))
                }
                Divider()
                Toggle(
                    String(localized: "单侧重量", comment: "Unilateral weight toggle in set menu"),
                    isOn: Binding(
                        get: { exerciseSet.isUnilateral },
                        set: { exerciseSet.isUnilateral = $0 }
                    )
                )
            } label: {
                HStack(spacing: 2) {
                    Text(exerciseSet.setType.displayName)
                    if exerciseSet.isUnilateral {
                        Text("·")
                        Text(String(localized: "左/右", comment: "Each side weight mode label"))
                    }
                }
                .font(.caption)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "第 \(index + 1) 组设置", comment: "Set configuration menu a11y label"))
            .accessibilityValue(
                exerciseSet.isUnilateral
                    ? "\(exerciseSet.setType.displayName)，\(String(localized: "单侧重量", comment: "Unilateral weight a11y value"))"
                    : "\(exerciseSet.setType.displayName)，\(String(localized: "总重量", comment: "Total weight a11y value"))"
            )

            Spacer()

            completionButton
        }
        .onAppear {
            let displayW = weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight
            weightText = formatWeight(displayW)
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private var completionButton: some View {
        Button {
            let wasCompleted = exerciseSet.isCompleted
            exerciseSet.isCompleted = !wasCompleted
            if !wasCompleted {
                HapticManager.trigger(.setCompleted)
            }
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

// MARK: - Sub-Set Row (Compact, Indented with Tree Lines)

private struct SubSetRow: View {
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let isLast: Bool
    let parentSetNumber: Int
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void

    @State private var weightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            treeLine
                .accessibilityHidden(true)

            SelectAllTextField(
                placeholder: weightUnit.rawValue,
                text: $weightText,
                keyboardType: .decimalPad,
                font: .preferredFont(forTextStyle: .footnote)
            )
                .frame(width: 62)
                .accessibilityLabel("第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组重量")
                .accessibilityHint("输入重量数值")
                .onChange(of: weightText) { _, newValue in
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { weightText = filtered }
                    syncWeightToModel()
                }

            Text("×")
                .font(.footnote)
                .foregroundStyle(.secondary)

            SelectAllTextField(
                placeholder: "次数",
                text: $repsText,
                keyboardType: .numberPad,
                font: .preferredFont(forTextStyle: .footnote)
            )
                .frame(width: 52)
                .accessibilityLabel("第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组次数")
                .accessibilityHint("输入次数")
                .onChange(of: repsText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { repsText = filtered }
                    syncRepsToModel()
                }

            Text(exerciseSet.setType.displayName)
                .font(.caption)
                .foregroundStyle(exerciseSet.setType.labelColor)
                .accessibilityLabel(exerciseSet.setType.displayName)

            Spacer()

            Button {
                let wasCompleted = exerciseSet.isCompleted
                exerciseSet.isCompleted = !wasCompleted
                if !wasCompleted {
                    HapticManager.trigger(.setCompleted)
                }
                onToggleCompleted(wasCompleted)
            } label: {
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(exerciseSet.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组，\(exerciseSet.isCompleted ? "已完成" : "未完成")")
            .accessibilityHint("双击切换完成状态")
        }
        .padding(.vertical, -2)
        .onAppear {
            let displayW = weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight
            weightText = formatWeight(displayW)
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private var treeLine: some View {
        HStack(spacing: 2) {
            Text(isLast ? "└─" : "├─")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(width: 28, alignment: .leading)
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

// MARK: - SetType Color Extension

extension SetType {
    var labelColor: Color {
        switch self {
        case .working: .primary
        case .warmup: .orange
        case .dropSet: .blue
        case .pyramid: .purple
        }
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
