// swiftlint:disable no_hardcoded_chinese
import SwiftUI
import SwiftData
import VitalModels

struct ActiveWorkoutFocusStageView: View {
    @Bindable var workout: Workout
    @Binding var focusedSetID: PersistentIdentifier?
    @Binding var selectedExerciseID: PersistentIdentifier?
    @Bindable var restTimer: RestTimerController
    let weightUnit: WeightUnit
    let heartRateText: String
    let onAddExercise: () -> Void
    let onAddSet: () -> Void
    let onSubstitute: () -> Void
    let onReplace: () -> Void
    let onOutline: () -> Void
    let onFinish: () -> Void

    private var focusStep: FocusStep? {
        WorkoutDualModeEngine.syncCursor(
            selectedExerciseID: selectedExerciseID,
            selectedSetID: focusedSetID,
            in: workout
        )
    }

    var body: some View {
        let step = focusStep
        let stage = restTimer.phase == .resting ? FocusStageMode.restRecovery : (step == nil ? .allCompleted : .activeSet)
        let atmosphere = FocusAtmosphereTheme.resolve(muscleGroup: step?.exercise.exercise?.muscleGroup, stageMode: stage)
        VStack(spacing: 12) {
            exerciseRail
            if let step {
                FocusHeroCard(step: step, atmosphere: atmosphere, weightUnit: weightUnit, heartRateText: heartRateText, restTimer: restTimer) { focusedSetID = $0 }
            } else {
                ContentUnavailableView(String(localized: "active_workout.focus.completed", defaultValue: "全部动作已完成", comment: "All workout sets completed"), systemImage: "checkmark.circle.fill")
                Button(String(localized: "active_workout.finish", defaultValue: "完成训练", comment: "Finish workout"), action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 180, minHeight: 56)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [atmosphere.primaryTint.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Button(action: onAddSet) { Label(String(localized: "active_workout.add_set", defaultValue: "加一组", comment: "Add set"), systemImage: "plus") }
                Button(action: onSubstitute) { Label(String(localized: "active_workout.ai_substitute", defaultValue: "AI 平替", comment: "AI substitute"), systemImage: "sparkles") }
                Button(action: onReplace) { Label(String(localized: "active_workout.replace", defaultValue: "换动作", comment: "Replace exercise"), systemImage: "arrow.triangle.2.circlepath") }
                Button(action: onOutline) { Label(String(localized: "active_workout.outline", defaultValue: "动作大纲", comment: "Exercise outline"), systemImage: "list.bullet") }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 48)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var exerciseRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkoutDualModeEngine.orderedExercises(in: workout)) { exercise in
                    Button {
                        selectedExerciseID = exercise.persistentModelID
                        focusedSetID = nil
                    } label: {
                        Label(exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise"), systemImage: (exercise.sets ?? []).allSatisfy(\.isCompleted) ? "checkmark.circle.fill" : "circle")
                            .lineLimit(1)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(exercise.persistentModelID == selectedExerciseID ? .accentColor : .secondary)
                }
                Button(action: onAddExercise) { Label(String(localized: "添加动作", comment: "Add exercise"), systemImage: "plus") }
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct FocusHeroCard: View {
    @Environment(\.modelContext) private var modelContext
    let step: FocusStep
    let atmosphere: FocusAtmosphereTheme
    let weightUnit: WeightUnit
    let heartRateText: String
    @Bindable var restTimer: RestTimerController
    let onFocus: (PersistentIdentifier?) -> Void

    private var workout: Workout? { step.exercise.workout }
    private var previousSet: ExerciseSet? {
        guard let workout else { return nil }
        return PreviousSetLookup.previousMainSet(
            currentWorkout: workout,
            exercise: step.exercise.exercise,
            mainSetIndex: step.mainSetNumber,
            in: modelContext
        )
    }

    var body: some View {
        Group {
            if restTimer.phase == .resting {
                restStage
            } else {
                activeStage
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(atmosphere.primaryTint.opacity(0.4), lineWidth: 1.5))
    }

    private var activeStage: some View {
        VStack(spacing: 14) {
            HStack {
                navigationButton(systemName: "chevron.left") { move(-1) }
                Spacer()
                Text(step.set.setType.isSubSet ? "↳" : String(localized: "第 \(step.mainSetNumber + 1) 组", comment: "Current set number"))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                navigationButton(systemName: "chevron.right") { move(1) }
            }
            Text(step.exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise"))
                .font(.title2.weight(.bold))
            Text(step.exercise.exercise?.muscleGroup.localizedName ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let previousSet {
                    let prevDisplay = WorkoutDualModeEngine.displayWeight(previousSet.weight, unit: weightUnit)
                    Button {
                        WorkoutDualModeEngine.applyPreviousSet(previousSet, to: step.set)
                    } label: {
                        Text(String(localized: "上次", comment: "Previous set") + ": \(prevDisplay.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue) × \(previousSet.reps)")
                    }
                    .frame(minHeight: 44)
                    .buttonStyle(.bordered)
                }
                if let workout, let advice = WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: step.exercise, in: workout, using: modelContext) {
                    let adviceDisplay = WorkoutDualModeEngine.displayWeight(advice.suggestedWeight, unit: weightUnit)
                    Button { WorkoutDualModeEngine.applyProgressionAdvice(advice, to: step.set) } label: {
                        Text("✨ \(String(localized: "建议", comment: "Progression advice")): \(adviceDisplay.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue) × \(advice.suggestedReps)")
                    }
                    .frame(minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .tint(atmosphere.primaryTint)
                }
            }
            if step.set.isUnilateral {
                HStack(spacing: 8) {
                    unilateralCard(title: "L", value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit), field: .weight)
                    unilateralCard(title: "R", value: WorkoutDualModeEngine.displayWeight(step.set.weightRight ?? step.set.weight, unit: weightUnit), field: .weightRight)
                }
            } else {
                HStack(spacing: 12) {
                    StepperCard(title: String(localized: "重量", comment: "Weight"), value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit), suffix: weightUnit.rawValue, deltaLabel: weightUnit == .lb ? "5" : "2.5") { adjust(.weight, -1) } increment: { adjust(.weight, 1) }
                    StepperCard(title: String(localized: "次数", comment: "Reps"), value: Double(step.set.reps), suffix: "", deltaLabel: "1") { adjust(.reps, -1) } increment: { adjust(.reps, 1) }
                }
            }
            HStack(spacing: 6) {
                attributeButton(step.set.setType == .warmup ? String(localized: "热身", comment: "Warmup") : String(localized: "正式", comment: "Working")) {
                    step.set.setType = step.set.setType == .warmup ? .working : .warmup
                }
                attributeButton(step.set.isUnilateral ? String(localized: "单侧", comment: "Unilateral") : String(localized: "双侧", comment: "Bilateral")) {
                    SetRow.toggleExerciseWeightMode(from: step.set)
                }
                attributeButton(String(localized: "+ 追递减组", comment: "Add drop set")) { insertSubSet(.dropSet) }
                attributeButton(String(localized: "+ 金字塔组", comment: "Add pyramid set")) { insertSubSet(.pyramid) }
            }
            Button {
                step.set.isCompleted = true
                restTimer.startRest(duration: step.set.restDuration ?? step.set.setType.defaultRestDuration)
            } label: {
                Label(String(localized: "完成第 \(step.mainSetNumber + 1) 组", comment: "Complete current set") + " (\(Int(step.set.restDuration ?? step.set.setType.defaultRestDuration))s)", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(atmosphere.primaryTint)
        }
    }

    private var restStage: some View {
        VStack(spacing: 14) {
            Label(String(localized: "组间休息恢复", comment: "Rest recovery stage"), systemImage: "figure.mind.and.body")
                .font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let total = max(1, restTimer.restTotalDuration ?? 1)
                let remaining = max(0, Int((restTimer.restEndDate ?? context.date).timeIntervalSince(context.date)))
                let progress = min(1, max(0, Double(remaining) / total))
                ZStack {
                    Circle().stroke(atmosphere.secondaryTint.opacity(0.2), lineWidth: 12)
                    Circle().trim(from: 0, to: progress).stroke(atmosphere.secondaryTint, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.largeTitle.weight(.bold).monospacedDigit())
                        Text("♥ \(heartRateText)").font(.subheadline.monospacedDigit())
                    }
                }
                .frame(width: 180, height: 180)
            }
            HStack(spacing: 8) {
                restButton("−15s") { restTimer.adjustRest(by: -15) }
                restButton(String(localized: "跳过休息 ⏭", comment: "Skip rest")) { skipRest() }
                restButton("+15s") { restTimer.adjustRest(by: 15) }
            }
            if let next = nextIncompleteStep {
                let nextDisplayWeight = WorkoutDualModeEngine.displayWeight(next.set.weight, unit: weightUnit)
                VStack(spacing: 8) {
                    Text(String(localized: "下一组预告", comment: "Up next") + ": \(next.exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise")) · \(nextDisplayWeight.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue) × \(next.set.reps)")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        Button(String(localized: "+ 插入递减子组", comment: "Insert drop set")) { insertSubSet(.dropSet) }
                            .frame(minHeight: 44)
                        Button(String(localized: "↩ 撤回本组", comment: "Undo completion")) { undoCompletion() }
                            .frame(minHeight: 44)
                    }
                }
                .padding(12)
                .background(atmosphere.secondaryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var nextIncompleteStep: FocusStep? {
        guard let workout else { return nil }
        return WorkoutDualModeEngine.nextIncompleteStep(after: step.set.persistentModelID, in: workout)
    }

    private func move(_ direction: Int) {
        guard let workout else { return }
        let target = direction < 0
            ? WorkoutDualModeEngine.stepBackward(from: step.set.persistentModelID, in: workout)
            : WorkoutDualModeEngine.stepForward(from: step.set.persistentModelID, in: workout)
        onFocus(target?.set.persistentModelID)
    }

    private func adjust(_ field: FocusSetStepper.Field, _ direction: Int) {
        FocusSetStepper.adjust(field, by: direction, unit: weightUnit, set: step.set)
    }

    private func unilateralCard(title: String, value: Double, field: FocusSetStepper.Field) -> some View {
        StepperCard(title: title + " " + String(localized: "重量", comment: "Weight"), value: value, suffix: weightUnit.rawValue, deltaLabel: weightUnit == .lb ? "5" : "2.5") { adjust(field, -1) } increment: { adjust(field, 1) }
    }

    private func attributeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).frame(minHeight: 44).buttonStyle(.bordered)
    }

    private func navigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemName).frame(width: 44, height: 44) }
    }

    private func restButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).frame(minWidth: 72, minHeight: 48).buttonStyle(.bordered)
    }

    private func insertSubSet(_ type: SetType) {
        let workoutExercise = step.exercise
        _ = WorkoutDualModeEngine.insertSubSet(after: step.set, type: type, in: workoutExercise, using: modelContext)
    }

    private func skipRest() {
        restTimer.skipRest()
        onFocus(nextIncompleteStep?.set.persistentModelID)
    }

    private func undoCompletion() {
        step.set.isCompleted = false
        restTimer.skipRest()
        onFocus(step.set.persistentModelID)
    }
}

private struct StepperCard: View {
    let title: String
    let value: Double
    let suffix: String
    var deltaLabel = "2.5"
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.caption)
            Text(value.formatted(.number.precision(.fractionLength(0...2))) + (suffix.isEmpty ? "" : " \(suffix)"))
                .font(.title.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            HStack {
                Button("−\(deltaLabel)", action: decrement).frame(minWidth: 44, minHeight: 44)
                Button("+\(deltaLabel)", action: increment).frame(minWidth: 44, minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ActiveWorkoutFocusStagePreview: View {
    let resting: Bool

    var body: some View {
        // swiftlint:disable:next force_try
        let container = try! ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(nameEn: "Bench Press", nameZh: "杠铃卧推", muscleGroup: .chest, equipment: .barbell)
        let set1 = ExerciseSet(order: 0, weight: 60, reps: 10, setType: .working, isCompleted: resting)
        let set2 = ExerciseSet(order: 1, weight: 65, reps: 8, setType: .working)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [workoutExercise])
        workoutExercise.workout = workout
        set1.workoutExercise = workoutExercise
        set2.workoutExercise = workoutExercise
        context.insert(exercise)
        context.insert(workout)
        context.insert(workoutExercise)
        context.insert(set1)
        context.insert(set2)
        let timer = RestTimerController()
        if resting {
            timer.startRest(duration: 120)
        }
        return ActiveWorkoutFocusStageView(
            workout: workout,
            focusedSetID: .constant(set1.persistentModelID),
            selectedExerciseID: .constant(workoutExercise.persistentModelID),
            restTimer: timer,
            weightUnit: .kg,
            heartRateText: "138",
            onAddExercise: {},
            onAddSet: {},
            onSubstitute: {},
            onReplace: {},
            onOutline: {},
            onFinish: {}
        )
        .modelContainer(container)
    }
}

#Preview("Focus Stage - Active Set") {
    ActiveWorkoutFocusStagePreview(resting: false)
}

#Preview("Focus Stage - Rest Countdown") {
    ActiveWorkoutFocusStagePreview(resting: true)
}
