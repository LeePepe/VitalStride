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

    private var step: FocusStep? {
        WorkoutDualModeEngine.syncCursor(selectedExerciseID: selectedExerciseID, selectedSetID: focusedSetID, in: workout)
    }

    var body: some View {
        let current = step
        let mode: FocusStageMode = restTimer.phase == .resting ? .restRecovery : (current == nil ? .allCompleted : .activeSet)
        let theme = FocusAtmosphereTheme.resolve(muscleGroup: current?.exercise.exercise?.muscleGroup, stageMode: mode)
        VStack(spacing: 10) {
            if let current {
                FocusStageHeader(step: current, workout: workout, heartRateText: heartRateText, onOutline: onOutline)
                FocusHeroCard(
                    step: current,
                    theme: theme,
                    weightUnit: weightUnit,
                    heartRateText: heartRateText,
                    restTimer: restTimer,
                    onFocus: { focusedSetID = $0 },
                    onAddSet: onAddSet
                )
            } else {
                ContentUnavailableView(String(localized: "active_workout.focus.completed", defaultValue: "全部动作已完成", comment: "All workout sets completed"), systemImage: "checkmark.circle.fill")
                Button(String(localized: "active_workout.finish", defaultValue: "完成训练", comment: "Finish workout"), action: onFinish)
                    .buttonStyle(.borderedProminent).frame(minWidth: 180, minHeight: 56)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .background(LinearGradient(colors: [theme.primaryTint.opacity(0.18), .clear], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }
}

private struct FocusStageHeader: View {
    let step: FocusStep
    let workout: Workout
    let heartRateText: String
    let onOutline: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onOutline) {
                Text(String(localized: "动作 \(step.exerciseIndex + 1) / \(workout.exercises?.count ?? 0) ▾", comment: "Exercise position and outline trigger"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }.frame(minHeight: 44)
            Text(step.exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise"))
                .font(.title2.weight(.bold))
            HStack(spacing: 10) {
                Text(String(localized: "第 \(step.mainSetNumber + 1) / \(step.totalSetsInExercise) 组", comment: "Set position"))
                if let sub = step.subSetOrdinal { Text(sub == 1 ? "↳ 递减组" : "↳ 子组") }
                TimelineView(.periodic(from: workout.startDate, by: 1)) { context in
                    Text("⏱ \(elapsedText(at: context.date))")
                }
                Text("♥ \(heartRateText)")
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(workout.startDate)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

private struct FocusHeroCard: View {
    @Environment(\.modelContext) private var modelContext
    let step: FocusStep
    let theme: FocusAtmosphereTheme
    let weightUnit: WeightUnit
    let heartRateText: String
    @Bindable var restTimer: RestTimerController
    let onFocus: (PersistentIdentifier?) -> Void
    let onAddSet: () -> Void

    private var workout: Workout? { step.exercise.workout }
    private var next: FocusStep? { workout.flatMap { WorkoutDualModeEngine.nextIncompleteStep(after: step.set.persistentModelID, in: $0) } }

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
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.primaryTint.opacity(0.4), lineWidth: 1.5))
    }

    private var activeStage: some View {
        VStack(spacing: 16) {
            referenceLine
            HStack(spacing: 10) {
                if step.set.isUnilateral {
                    FocusValueControl(title: "L", value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit), suffix: weightUnit.rawValue, field: .weight, step: step, unit: weightUnit, onAddSet: onAddSet)
                    FocusValueControl(title: "R", value: WorkoutDualModeEngine.displayWeight(step.set.weightRight ?? step.set.weight, unit: weightUnit), suffix: weightUnit.rawValue, field: .weightRight, step: step, unit: weightUnit, onAddSet: onAddSet)
                } else {
                    FocusValueControl(title: String(localized: "重量", comment: "Weight"), value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit), suffix: weightUnit.rawValue, field: .weight, step: step, unit: weightUnit, onAddSet: onAddSet)
                }
                FocusValueControl(title: String(localized: "次数", comment: "Reps"), value: Double(step.set.reps), suffix: "", field: .reps, step: step, unit: weightUnit, onAddSet: onAddSet)
            }
            Button {
                step.set.isCompleted = true
                restTimer.startRest(duration: step.set.restDuration ?? step.set.setType.defaultRestDuration)
            } label: {
                Label(String(localized: "active_workout.complete_set", defaultValue: "Complete set", comment: "Complete current set"), systemImage: "checkmark")
                    .font(.title3.weight(.bold)).frame(maxWidth: .infinity, minHeight: 56)
            }.buttonStyle(.borderedProminent).tint(theme.primaryTint)
            if let next {
                Text(String(localized: "下一组：第 \(next.mainSetNumber + 1) 组 · \(display(WorkoutDualModeEngine.displayWeight(next.set.weight, unit: weightUnit))) \(weightUnit.rawValue) × \(next.set.reps)", comment: "Up next caption"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var referenceLine: some View {
        let previous = workout.flatMap { PreviousSetLookup.previousMainSet(currentWorkout: $0, exercise: step.exercise.exercise, mainSetIndex: step.mainSetNumber, in: modelContext) }
        let advice = workout.flatMap { WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: step.exercise, in: $0, using: modelContext) }
        return HStack(spacing: 6) {
            if let previous {
                Button { WorkoutDualModeEngine.applyPreviousSet(previous, to: step.set) } label: {
                    Text(String(localized: "上次 \(display(WorkoutDualModeEngine.displayWeight(previous.weight, unit: weightUnit))) \(weightUnit.rawValue) × \(previous.reps)", comment: "Previous set reference"))
                }.buttonStyle(.plain)
            }
            if let advice {
                Button { WorkoutDualModeEngine.applyProgressionAdvice(advice, to: step.set) } label: {
                    Text("· ✨ \(display(WorkoutDualModeEngine.displayWeight(advice.suggestedWeight, unit: weightUnit))) \(weightUnit.rawValue) × \(advice.suggestedReps)")
                        .foregroundStyle(theme.primaryTint)
                }.buttonStyle(.plain)
            }
            if previous == nil, advice == nil {
                Text(String(localized: "准备开始", comment: "No previous set"))
            }
        }.font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
    }

    private var restStage: some View {
        VStack(spacing: 16) {
            Text(String(localized: "组间休息", comment: "Rest stage")).font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let total = max(1, restTimer.restTotalDuration ?? 1)
                let remaining = max(0, Int((restTimer.restEndDate ?? context.date).timeIntervalSince(context.date)))
                let progress = min(1, max(0, Double(remaining) / total))
                ZStack {
                    Circle().stroke(theme.secondaryTint.opacity(0.2), lineWidth: 12)
                    Circle().trim(from: 0, to: progress).stroke(theme.secondaryTint, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) { Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.largeTitle.weight(.bold).monospacedDigit()); Text("♥ \(heartRateText)").font(.subheadline.monospacedDigit()) }
                }.frame(width: 180, height: 180)
            }
            HStack(spacing: 8) {
                restButton("−15s") { restTimer.adjustRest(by: -15) }
                restButton(String(localized: "跳过休息", comment: "Skip rest")) { restTimer.skipRest(); onFocus(next?.set.persistentModelID) }
                restButton("+15s") { restTimer.adjustRest(by: 15) }
            }
            if let next { Text(String(localized: "下一组预告：\(display(WorkoutDualModeEngine.displayWeight(next.set.weight, unit: weightUnit))) \(weightUnit.rawValue) × \(next.set.reps)", comment: "Rest up next" )).font(.subheadline.weight(.semibold)) }
            Button { step.set.isCompleted = false; restTimer.skipRest(); onFocus(step.set.persistentModelID) } label: { Text(String(localized: "active_workout.undo_set", defaultValue: "Undo previous set", comment: "Undo completion")) }.frame(minHeight: 44)
        }
    }

    private func display(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func restButton(_ title: String, action: @escaping () -> Void) -> some View { Button(title, action: action).frame(minWidth: 76, minHeight: 48).buttonStyle(.bordered) }
}

private struct FocusValueControl: View {
    @Environment(\.modelContext) private var modelContext
    @State private var text: String
    let title: String
    let value: Double
    let suffix: String
    let field: SetField
    let step: FocusStep
    let unit: WeightUnit
    let onAddSet: () -> Void

    init(title: String, value: Double, suffix: String, field: SetField, step: FocusStep, unit: WeightUnit, onAddSet: @escaping () -> Void) {
        _text = State(initialValue: value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2))))
        self.title = title; self.value = value; self.suffix = suffix; self.field = field; self.step = step; self.unit = unit; self.onAddSet = onAddSet
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(suffix.isEmpty ? title : "\(title) \(suffix.uppercased())").font(.caption).foregroundStyle(.secondary)
            #if canImport(UIKit)
            SelectAllTextField(placeholder: "0", text: $text, keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad, font: .systemFont(ofSize: 46, weight: .bold), useCustomKeyboard: true, field: field, exercise: step.exercise.exercise, setType: step.set.setType, onLeftAction: handleLeftAction, onPresetReps: { weight, reps in if field == .reps { step.set.reps = reps } else if let weight { step.set.weight = weight }; sync() }, onFocusChange: nil)
                .frame(minHeight: 56).contentShape(Rectangle())
                .onChange(of: text) { _, newValue in
                    guard let number = Double(newValue) else { return }
                    if field == .reps {
                        step.set.reps = Int(number)
                    } else if field == .weightRight {
                        step.set.weightRight = unit == .lb ? number / 2.20462 : number
                    } else {
                        step.set.weight = unit == .lb ? number / 2.20462 : number
                    }
                }
            #else
            Text(text).font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit()).frame(minHeight: 56)
            #endif
            HStack(spacing: 6) {
                let delta = field == .reps ? "1" : (unit == .lb ? "5" : "2.5")
                let stepField: FocusSetStepper.Field = field == .reps ? .reps : (field == .weightRight ? .weightRight : .weight)
                stepButton("−\(delta)") { FocusSetStepper.adjust(stepField, by: -1, unit: unit, set: step.set); sync() }
                stepButton("+\(delta)") { FocusSetStepper.adjust(stepField, by: 1, unit: unit, set: step.set); sync() }
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: value) { _, _ in sync() }
    }

    private func handleLeftAction(_ action: LeftKeyAction) {
        switch action {
        case .toggleUnilateral: SetRow.toggleExerciseWeightMode(from: step.set)
        case .setWarmup: step.set.setType = step.set.setType == .warmup ? .working : .warmup
        case .addDropSet: _ = WorkoutDualModeEngine.insertSubSet(after: step.set, type: .dropSet, in: step.exercise, using: modelContext)
        case .addSet: onAddSet()
        case .toggleWeightUnit: UserDefaults.standard.set((unit == .kg ? WeightUnit.lb : .kg).rawValue, forKey: "weightUnit")
        case .copyToNext:
            if let workout = step.exercise.workout, let next = WorkoutDualModeEngine.nextIncompleteStep(after: step.set.persistentModelID, in: workout) {
                next.set.weight = step.set.weight; next.set.weightRight = step.set.weightRight; next.set.reps = step.set.reps
            }
        case .applyAISuggestion:
            if let workout = step.exercise.workout, let advice = WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: step.exercise, in: workout, using: modelContext) {
                WorkoutDualModeEngine.applyProgressionAdvice(advice, to: step.set); sync()
            }
        default: break
        }
    }

    private func stepButton(_ title: String, action: @escaping () -> Void) -> some View { Button(title, action: action).frame(maxWidth: .infinity, minHeight: 44).background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemFill))).buttonStyle(.plain) }
    private func sync() {
        if field == .reps {
            text = "\(step.set.reps)"
        } else {
            let kg = field == .weightRight ? (step.set.weightRight ?? step.set.weight) : step.set.weight
            text = WorkoutDualModeEngine.displayWeight(kg, unit: unit).formatted(.number.precision(.fractionLength(0...2)))
        }
    }
}
