import SwiftData
import SwiftUI
import VitalModels

#if canImport(UIKit)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var workout: Workout?
    @State private var showingExercisePicker = false
    @State private var showingFinishAlert = false
    @State private var showingDiscardAlert = false
    @State private var exerciseToReplace: WorkoutExercise?
    @State private var restEndDate: Date?
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
        workout?.endDate = Date()
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
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var setType: SetType = .working
    @State private var editingSetID: PersistentIdentifier?
    @State private var editWeightText = ""
    @State private var editRepsText = ""
    @State private var editSetType: SetType = .working

    private var sortedSets: [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        Section {
            ForEach(Array(sortedSets.enumerated()), id: \.element.persistentModelID) { index, exerciseSet in
                completedSetView(index: index, exerciseSet: exerciseSet)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteSet(exerciseSet)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
            setInputRow
        } header: {
            Text(workoutExercise.exercise?.localizedName ?? "动作")
                .contextMenu {
                    Button {
                        onReplace()
                    } label: {
                        Label("替换动作", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除动作", systemImage: "trash")
                    }
                }
        }
    }

    private var setInputRow: some View {
        HStack(spacing: 8) {
            TextField(weightUnit.rawValue, text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .onChange(of: weightText) { _, newValue in
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { weightText = filtered }
                }

            TextField("次数", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .onChange(of: repsText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { repsText = filtered }
                }

            Picker("组类型", selection: $setType) {
                Text("正式").tag(SetType.working)
                Text("热身").tag(SetType.warmup)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()

            Button {
                addSet()
            } label: {
                Text("+ 添加一组")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("添加组")
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func completedSetView(index: Int, exerciseSet: ExerciseSet) -> some View {
        if editingSetID == exerciseSet.persistentModelID {
            editSetRow(index: index, exerciseSet: exerciseSet)
        } else {
            completedSetRow(index: index, exerciseSet: exerciseSet)
                .contentShape(Rectangle())
                .onTapGesture { beginEditing(exerciseSet) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("点击编辑")
        }
    }

    private func completedSetRow(index: Int, exerciseSet: ExerciseSet) -> some View {
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

    private func editSetRow(index: Int, exerciseSet: ExerciseSet) -> some View {
        HStack(spacing: 8) {
            Text("第 \(index + 1) 组")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            TextField(weightUnit.rawValue, text: $editWeightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .onChange(of: editWeightText) { _, newValue in
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { editWeightText = filtered }
                }

            TextField("次数", text: $editRepsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .onChange(of: editRepsText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { editRepsText = filtered }
                }

            Picker("组类型", selection: $editSetType) {
                Text("正式").tag(SetType.working)
                Text("热身").tag(SetType.warmup)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()

            Button {
                saveEdit(exerciseSet)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("保存修改")
            .frame(minHeight: 44)
        }
    }

    private func beginEditing(_ exerciseSet: ExerciseSet) {
        let displayW = displayWeight(exerciseSet.weight)
        editWeightText = formatWeight(displayW)
        editRepsText = "\(exerciseSet.reps)"
        editSetType = exerciseSet.setType
        editingSetID = exerciseSet.persistentModelID
    }

    private func saveEdit(_ exerciseSet: ExerciseSet) {
        let weight: Double
        if editWeightText.isEmpty {
            weight = 0
        } else {
            guard let parsed = Double(editWeightText) else { return }
            weight = parsed
        }
        let reps: Int
        if editRepsText.isEmpty {
            reps = 0
        } else {
            guard let parsed = Int(editRepsText) else { return }
            reps = parsed
        }
        guard weight.isFinite, weight >= 0, reps >= 0 else { return }
        let storageWeight = weightUnit == .lb ? weight / 2.20462 : weight
        exerciseSet.weight = storageWeight
        exerciseSet.reps = reps
        exerciseSet.setType = editSetType
        editingSetID = nil
    }

    private func deleteSet(_ exerciseSet: ExerciseSet) {
        modelContext.delete(exerciseSet)
        let remaining = sortedSets.filter { $0.persistentModelID != exerciseSet.persistentModelID }
        for (newOrder, set) in remaining.enumerated() {
            set.order = newOrder
        }
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
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    private func addSet() {
        let weight: Double
        if weightText.isEmpty {
            weight = 0
        } else {
            guard let parsed = Double(weightText) else { return }
            weight = parsed
        }
        let reps: Int
        if repsText.isEmpty {
            reps = 0
        } else {
            guard let parsed = Int(repsText) else { return }
            reps = parsed
        }
        guard weight.isFinite, weight >= 0, reps >= 0 else { return }
        let storageWeight = weightUnit == .lb ? weight / 2.20462 : weight
        let order = workoutExercise.sets?.count ?? 0
        let newSet = ExerciseSet(order: order, weight: storageWeight, reps: reps, setType: setType)
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
        repsText = ""
        onSetCompleted()
    }

    private func displayWeight(_ kgValue: Double) -> Double {
        weightUnit == .lb ? kgValue * 2.20462 : kgValue
    }
}

// MARK: - Exercise Picker

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var selectedGroup: MuscleGroup?
    let onSelect: (Exercise) -> Void

    private var filteredExercises: [Exercise] {
        var result = exercises
        if let group = selectedGroup {
            result = result.filter { $0.muscleGroup == group }
        }
        if !searchText.isEmpty {
            result = result.filter { exercise in
                exercise.nameEn.localizedCaseInsensitiveContains(searchText) ||
                exercise.nameZh.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var groupedExercises: [(MuscleGroup, [Exercise])] {
        let dict = Dictionary(grouping: filteredExercises) { $0.muscleGroup }
        return MuscleGroup.allCases.compactMap { group in
            guard let items = dict[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "动作库为空",
                        systemImage: "tray",
                        description: Text("请先导入预置动作库")
                    )
                } else if horizontalSizeClass == .regular {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .searchable(text: $searchText, prompt: "搜索动作")
            .navigationTitle("选择动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Regular Layout (iPad / wide screen)

    private var regularLayout: some View {
        HStack(spacing: 0) {
            muscleGroupSidebar
            Divider()
            exerciseCollection
        }
    }

    private var muscleGroupSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                sidebarButton(label: "全部", isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    sidebarButton(
                        label: muscleGroupName(group),
                        isSelected: selectedGroup == group
                    ) {
                        selectedGroup = group
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .frame(width: 100)
        .background(.bar)
    }

    private func sidebarButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : .clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            chipBar
            exerciseCollection
        }
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "全部", isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    chipButton(
                        label: muscleGroupName(group),
                        isSelected: selectedGroup == group
                    ) {
                        selectedGroup = group
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Exercise Collection

    @ViewBuilder
    private var exerciseCollection: some View {
        if groupedExercises.isEmpty {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if let group = selectedGroup {
                ContentUnavailableView(
                    "没有动作",
                    systemImage: "dumbbell",
                    description: Text("\(muscleGroupName(group))分类下暂无动作")
                )
            } else {
                ContentUnavailableView(
                    "没有动作",
                    systemImage: "dumbbell",
                    description: Text("暂无可用动作")
                )
            }
        } else {
            List {
                ForEach(groupedExercises, id: \.0) { group, items in
                    Section(muscleGroupName(group)) {
                        ForEach(items) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.localizedName)
                                    Text(equipmentName(exercise.equipment))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private func muscleGroupName(_ group: MuscleGroup) -> String {
    switch group {
    case .chest: "胸"
    case .back: "背"
    case .shoulders: "肩"
    case .legs: "腿"
    case .arms: "臂"
    case .core: "核心"
    case .fullBody: "全身"
    }
}

private func equipmentName(_ equipment: Equipment) -> String {
    switch equipment {
    case .barbell: "杠铃"
    case .dumbbell: "哑铃"
    case .machine: "固定器械"
    case .bodyweight: "自重"
    case .cable: "绳索"
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
