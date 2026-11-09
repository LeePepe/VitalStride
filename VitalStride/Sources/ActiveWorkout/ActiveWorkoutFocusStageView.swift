// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

struct ActiveWorkoutFocusStageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        WorkoutDualModeEngine.syncCursor(
            selectedExerciseID: selectedExerciseID,
            selectedSetID: focusedSetID,
            in: workout
        )
    }

    var body: some View {
        let current = step
        let mode: FocusStageMode = current == nil ? .allCompleted : .activeSet
        let palette = FocusAtmosphereTheme.resolve(
            muscleGroup: current?.exercise.exercise?.muscleGroup,
            stageMode: mode
        )

        ZStack(alignment: .top) {
            atmosphereBackground(palette: palette)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    if let current {
                        FocusStageHeader(
                            step: current,
                            workout: workout,
                            palette: palette,
                            heartRateText: heartRateText,
                            onOutline: onOutline
                        )
                        FocusHeroCard(
                            step: current,
                            palette: palette,
                            weightUnit: weightUnit,
                            heartRateText: heartRateText,
                            restTimer: restTimer,
                            onFocus: { nextSetID in
                                focusedSetID = nextSetID
                                if let nextSetID,
                                   let nextStep = WorkoutDualModeEngine.focusSteps(in: workout).first(where: { $0.set.persistentModelID == nextSetID }) {
                                    selectedExerciseID = nextStep.exercise.persistentModelID
                                }
                            },
                            onAddSet: onAddSet
                        )
                    } else {
                        VStack(spacing: 20) {
                            ContentUnavailableView(
                                String(localized: "active_workout.focus.completed", defaultValue: "全部动作已完成", comment: "All workout sets completed"),
                                systemImage: "checkmark.circle.fill"
                            )
                            Button(action: onFinish) {
                                Text(String(localized: "active_workout.finish", defaultValue: "完成训练", comment: "Finish workout"))
                                    .font(.headline.weight(.bold))
                                    .frame(minWidth: 200, minHeight: 54)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 48)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.horizontal)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84),
            value: restTimer.phase == .resting
        )
    }

    @ViewBuilder
    private func atmosphereBackground(palette: FocusAtmosphereTheme) -> some View {
        if reduceTransparency {
            Color(uiColor: .systemGroupedBackground)
        } else {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                LinearGradient(
                    colors: [
                        palette.primaryTint.opacity(0.24),
                        palette.secondaryTint.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                RadialGradient(
                    colors: [
                        palette.secondaryTint.opacity(0.18),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 16,
                    endRadius: 320
                )
            }
        }
    }
}

private struct FocusStageHeader: View {
    let step: FocusStep
    let workout: Workout
    let palette: FocusAtmosphereTheme
    let heartRateText: String
    let onOutline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Button(action: onOutline) {
                    HStack(spacing: 4) {
                        Text(String(localized: "动作 \(step.exerciseIndex + 1) / \(workout.exercises?.count ?? 0) ▾", comment: "Exercise position and outline trigger"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground).opacity(0.85),
                        in: Capsule()
                    )
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    TimelineView(.periodic(from: workout.startDate, by: 1)) { context in
                        Text("⏱ \(elapsedText(at: context.date))")
                    }
                    Text("·")
                    Text("♥ \(heartRateText)")
                    Menu {
                        Button(String(localized: "设为热身组", comment: "Set warmup menu item")) { step.set.setType = .warmup }
                        Button(String(localized: "设为正式组", comment: "Set working menu item")) { step.set.setType = .working }
                        Button(String(localized: "+ 追加递减组", comment: "Add drop set menu item")) { }
                        Button(String(localized: "+ 追加金字塔组", comment: "Add pyramid set menu item")) { }
                        Button(String(localized: "删除当前组", comment: "Delete current set menu item"), role: .destructive) { }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(String(localized: "当前组操作菜单", comment: "Focus set actions menu"))
                }
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(step.exercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise"))
                    .font(.title.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(String(localized: "第 \(step.mainSetNumber + 1) / \(step.totalSetsInExercise) 组", comment: "Set position"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    setKindTag
                }
            }
        }
    }

    @ViewBuilder
    private var setKindTag: some View {
        if step.set.setType == .dropSet {
            Text(String(localized: "↳ 递减组", comment: "Drop set subtitle"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if step.set.setType == .pyramid {
            Text(String(localized: "↳ 金字塔组", comment: "Pyramid set subtitle"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if step.set.setType == .warmup {
            Text(String(localized: "热身组", comment: "Warmup set subtitle"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Text(String(localized: "正式组", comment: "Working set subtitle"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.primaryTint)
        }
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(workout.startDate)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

private struct FocusHeroCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: FocusStep
    let palette: FocusAtmosphereTheme
    let weightUnit: WeightUnit
    let heartRateText: String
    @Bindable var restTimer: RestTimerController
    let onFocus: (PersistentIdentifier?) -> Void
    let onAddSet: () -> Void

    private var workout: Workout? { step.exercise.workout }
    private var next: FocusStep? {
        workout.flatMap {
            WorkoutDualModeEngine.nextIncompleteStep(after: step.set.persistentModelID, in: $0)
        }
    }

    var body: some View {
        activeStage
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(palette.primaryTint.opacity(0.32), lineWidth: 1.5)
        }
    }

    private var activeStage: some View {
        VStack(spacing: 16) {
            if restTimer.phase == .resting {
                restCompanionBar
            }
            progressRail
            referenceLine

            if step.set.isUnilateral {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        FocusTactileModule(
                            title: "L · \(weightUnit.rawValue.uppercased())",
                            value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit),
                            field: .weight,
                            step: step,
                            unit: weightUnit,
                            palette: palette,
                            onAddSet: onAddSet
                        )
                        FocusTactileModule(
                            title: "R · \(weightUnit.rawValue.uppercased())",
                            value: WorkoutDualModeEngine.displayWeight(step.set.weightRight ?? step.set.weight, unit: weightUnit),
                            field: .weightRight,
                            step: step,
                            unit: weightUnit,
                            palette: palette,
                            onAddSet: onAddSet
                        )
                    }
                    FocusTactileModule(
                        title: String(localized: "次数 · REPS", comment: "Reps module header"),
                        value: Double(step.set.reps),
                        field: .reps,
                        step: step,
                        unit: weightUnit,
                        palette: palette,
                        onAddSet: onAddSet
                    )
                }
            } else {
                HStack(spacing: 12) {
                    FocusTactileModule(
                        title: String(localized: "重量 · \(weightUnit.rawValue.uppercased())", comment: "Weight module header"),
                        value: WorkoutDualModeEngine.displayWeight(step.set.weight, unit: weightUnit),
                        field: .weight,
                        step: step,
                        unit: weightUnit,
                        palette: palette,
                        onAddSet: onAddSet
                    )
                    FocusTactileModule(
                        title: String(localized: "次数 · REPS", comment: "Reps module header"),
                        value: Double(step.set.reps),
                        field: .reps,
                        step: step,
                        unit: weightUnit,
                        palette: palette,
                        onAddSet: onAddSet
                    )
                }
            }

            Button {
                let targetNext = next?.set.persistentModelID
                applyHintIfNeeded()
                step.set.isCompleted = true
                HapticManager.trigger(.setCompleted)
                restTimer.startRest(duration: step.set.restDuration ?? step.set.setType.defaultRestDuration)
                if let targetNext {
                    onFocus(targetNext)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                    Text(String(localized: "active_workout.complete_set", defaultValue: "完成本组", comment: "Complete current set"))
                        .font(.title3.weight(.bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    LinearGradient(
                        colors: [palette.primaryTint, palette.secondaryTint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: step.set.isCompleted)

            if let next {
                let nextWeight = display(WorkoutDualModeEngine.displayWeight(next.set.weight, unit: weightUnit))
                Text(String(localized: "下一组：第 \(next.mainSetNumber + 1) 组 · \(nextWeight) \(weightUnit.rawValue) × \(next.set.reps)", comment: "Up next caption"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var progressRail: some View {
        let currentWorkout = workout ?? step.exercise.workout ?? Workout(type: .strength, startDate: Date(), exercises: [])
        let exerciseSteps = WorkoutDualModeEngine.focusSteps(for: step.exercise, in: currentWorkout)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(exerciseSteps, id: \.set.persistentModelID) { item in
                    Button {
                        onFocus(item.set.persistentModelID)
                    } label: {
                        Text(item.set.isCompleted ? "✓" : (item.set.persistentModelID == step.set.persistentModelID ? "●" : "○"))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(item.set.isCompleted ? .green : (item.set.persistentModelID == step.set.persistentModelID ? palette.primaryTint : .secondary))
                            .frame(minWidth: 36, minHeight: 36)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onAddSet) {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "添加一组", comment: "Add set"))
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var restCompanionBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((restTimer.restEndDate ?? context.date).timeIntervalSince(context.date)))
            let total = max(1, Int(restTimer.restTotalDuration ?? 1))
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(String(localized: "⏱ 组间休息", comment: "Companion rest bar"))
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).monospacedDigit()
                    Text("· ♥ \(heartRateText)").monospacedDigit()
                    Spacer()
                    Button("−15s") { restTimer.adjustRest(by: -15) }
                    Button("+15s") { restTimer.adjustRest(by: 15) }
                    Button { restTimer.skipRest() } label: { Image(systemName: "xmark") }
                }
                ProgressView(value: Double(remaining), total: Double(total))
                    .tint(palette.primaryTint)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(palette.primaryTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func applyHintIfNeeded() {
        guard step.set.weight == 0 || step.set.reps == 0 else { return }
        if let workout, let previous = PreviousSetLookup.previousMainSet(currentWorkout: workout, exercise: step.exercise.exercise, mainSetIndex: step.mainSetNumber, in: modelContext) {
            if step.set.weight == 0 { step.set.weight = previous.weight }
            if step.set.isUnilateral, step.set.weightRight == nil || step.set.weightRight == 0 { step.set.weightRight = previous.weightRight ?? previous.weight }
            if step.set.reps == 0 { step.set.reps = previous.reps }
        }
        if let workout, let advice = WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: step.exercise, in: workout, using: modelContext) {
            if step.set.weight == 0 { step.set.weight = advice.suggestedWeight }
            if step.set.isUnilateral, step.set.weightRight == nil || step.set.weightRight == 0 { step.set.weightRight = step.set.weight }
            if step.set.reps == 0 { step.set.reps = advice.suggestedReps }
        }
    }

    private var referenceLine: some View {
        let previous = workout.flatMap {
            PreviousSetLookup.previousMainSet(
                currentWorkout: $0,
                exercise: step.exercise.exercise,
                mainSetIndex: step.mainSetNumber,
                in: modelContext
            )
        }
        let advice = workout.flatMap {
            WorkoutDualModeEngine.computeExerciseProgressionAdvice(
                for: step.exercise,
                in: $0,
                using: modelContext
            )
        }
        return HStack(spacing: 8) {
            if let previous {
                Button {
                    #if canImport(UIKit) && !os(macOS)
                    HapticManager.trigger(.setCompleted)
                    #endif
                    WorkoutDualModeEngine.applyPreviousSet(previous, to: step.set)
                } label: {
                    Text(String(localized: "上次 \(display(WorkoutDualModeEngine.displayWeight(previous.weight, unit: weightUnit))) \(weightUnit.rawValue) × \(previous.reps)", comment: "Previous set reference"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let advice {
                Button {
                    #if canImport(UIKit) && !os(macOS)
                    HapticManager.trigger(.setCompleted)
                    #endif
                    WorkoutDualModeEngine.applyProgressionAdvice(advice, to: step.set)
                } label: {
                    Text("· ✨ \(display(WorkoutDualModeEngine.displayWeight(advice.suggestedWeight, unit: weightUnit))) \(weightUnit.rawValue) × \(advice.suggestedReps)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(palette.primaryTint)
                }
                .buttonStyle(.plain)
            }
            if previous == nil, advice == nil {
                Text(String(localized: "准备开始本组", comment: "No previous set reference"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
    }

    private var restStage: some View {
        VStack(spacing: 18) {
            Text(String(localized: "组间休息", comment: "Rest stage"))
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.primaryTint)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let total = max(1, restTimer.restTotalDuration ?? 1)
                let remaining = max(0, Int((restTimer.restEndDate ?? context.date).timeIntervalSince(context.date)))
                let progress = min(1, max(0, Double(remaining) / total))
                ZStack {
                    Circle()
                        .stroke(palette.secondaryTint.opacity(0.18), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [palette.primaryTint, palette.secondaryTint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 6) {
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 48, weight: .heavy, design: .rounded).monospacedDigit())
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                        Text("♥ \(heartRateText)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 210, height: 210)
            }

            HStack(spacing: 10) {
                restControlButton("−15s") {
                    restTimer.adjustRest(by: -15)
                }
                restControlButton(String(localized: "跳过休息", comment: "Skip rest"), prominent: true) {
                    restTimer.skipRest()
                }
                restControlButton("+15s") {
                    restTimer.adjustRest(by: 15)
                }
            }

            if let currentStep = workout.flatMap({ WorkoutDualModeEngine.syncCursor(selectedExerciseID: step.exercise.persistentModelID, selectedSetID: step.set.persistentModelID, in: $0) }) {
                let upNextWeight = display(WorkoutDualModeEngine.displayWeight(currentStep.set.weight, unit: weightUnit))
                Text(String(localized: "下一组预告：\(upNextWeight) \(weightUnit.rawValue) × \(currentStep.set.reps)", comment: "Rest up next"))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Button {
                if let prevCompleted = workout.flatMap({ WorkoutDualModeEngine.focusSteps(in: $0).last(where: { $0.set.isCompleted }) }) {
                    prevCompleted.set.isCompleted = false
                    restTimer.skipRest()
                    onFocus(prevCompleted.set.persistentModelID)
                } else {
                    step.set.isCompleted = false
                    restTimer.skipRest()
                    onFocus(step.set.persistentModelID)
                }
            } label: {
                Label(
                    String(localized: "active_workout.undo_set", defaultValue: "撤回上一组", comment: "Undo completion"),
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func restControlButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(prominent ? Color.white : palette.primaryTint)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    prominent ? palette.primaryTint : palette.primaryTint.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func display(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

private struct FocusTactileModule: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text: String
    @State private var focusRequestID = 0
    @State private var isFocused = false
    @State private var stepTrigger = 0

    let title: String
    let value: Double
    let field: SetField
    let step: FocusStep
    let unit: WeightUnit
    let palette: FocusAtmosphereTheme
    let onAddSet: () -> Void

    init(
        title: String,
        value: Double,
        field: SetField,
        step: FocusStep,
        unit: WeightUnit,
        palette: FocusAtmosphereTheme,
        onAddSet: @escaping () -> Void
    ) {
        let initialText = value == 0
            ? ""
            : (value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value))
        _text = State(initialValue: initialText)
        self.title = title
        self.value = value
        self.field = field
        self.step = step
        self.unit = unit
        self.palette = palette
        self.onAddSet = onAddSet
    }

    private var displayHeroString: String {
        if !text.isEmpty { return text }
        return "0"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.primaryTint)

            ZStack {
                Text(displayHeroString)
                    .font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.45) : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .allowsHitTesting(false)

                #if canImport(UIKit) && !os(macOS)
                let input = SelectAllTextField(
                    placeholder: "",
                    text: $text,
                    keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad,
                    font: .systemFont(ofSize: 44, weight: .bold),
                    useCustomKeyboard: true,
                    field: field,
                    exercise: step.exercise.exercise,
                    setType: step.set.setType,
                    onLeftAction: handleLeftAction,
                    onPresetReps: { weightKg, reps in
                        if field == .reps {
                            step.set.reps = reps
                        } else if let weightKg {
                            step.set.weight = weightKg
                        }
                        syncFromModel()
                    },
                    onFocusChange: { newField in
                        isFocused = (newField == field)
                    }
                )
                WorkoutSetInput(
                    input,
                    theme: theme,
                    focusRequestID: focusRequestID,
                    textColor: .clear
                )
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusRequestID &+= 1
                }
                .onChange(of: text) { _, newValue in
                    applyEditedText(newValue)
                }
                #else
                TextField("0", text: $text)
                    .multilineTextAlignment(.center)
                    .opacity(0.02)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .onChange(of: text) { _, newValue in
                        applyEditedText(newValue)
                    }
                #endif
            }
            .frame(maxWidth: .infinity, minHeight: 68)

            HStack(spacing: 8) {
                let delta = field == .reps ? "1" : (unit == .lb ? "5" : "2.5")
                let stepField: FocusSetStepper.Field = field == .reps
                    ? .reps
                    : (field == .weightRight ? .weightRight : .weight)
                stepperButton("−\(delta)") {
                    FocusSetStepper.adjust(stepField, by: -1, unit: unit, set: step.set)
                    stepTrigger &+= 1
                    syncFromModel()
                }
                stepperButton("+\(delta)") {
                    FocusSetStepper.adjust(stepField, by: 1, unit: unit, set: step.set)
                    stepTrigger &+= 1
                    syncFromModel()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(palette.primaryTint.opacity(0.10), in: shape)
        .overlay {
            shape.strokeBorder(
                isFocused ? palette.primaryTint : palette.primaryTint.opacity(0.25),
                lineWidth: isFocused ? 2 : 1.5
            )
        }
        .sensoryFeedback(.selection, trigger: stepTrigger)
        .onChange(of: value) { _, _ in
            if !isFocused {
                syncFromModel()
            }
        }
        .onChange(of: step.set.persistentModelID) { _, _ in
            syncFromModel()
        }
    }

    private func stepperButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(palette.primaryTint)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    palette.primaryTint.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyEditedText(_ raw: String) {
        if field == .reps {
            let filtered = raw.filter(\.isNumber)
            if filtered != raw { text = filtered }
            step.set.reps = Int(filtered) ?? 0
        } else {
            let number = Double(raw) ?? 0
            let kg = unit == .lb ? number / 2.20462 : number
            if field == .weightRight {
                step.set.weightRight = max(0, kg)
            } else {
                step.set.weight = max(0, kg)
            }
        }
    }

    private func handleLeftAction(_ action: LeftKeyAction) {
        switch action {
        case .toggleUnilateral:
            SetRow.toggleExerciseWeightMode(from: step.set)
        case .setWarmup:
            step.set.setType = step.set.setType == .warmup ? .working : .warmup
        case .addDropSet:
            _ = WorkoutDualModeEngine.insertSubSet(after: step.set, type: .dropSet, in: step.exercise, using: modelContext)
        case .addPyramidSet:
            _ = WorkoutDualModeEngine.insertSubSet(after: step.set, type: .pyramid, in: step.exercise, using: modelContext)
        case .addSet:
            onAddSet()
        case .toggleWeightUnit:
            UserDefaults.standard.set((unit == .kg ? WeightUnit.lb : .kg).rawValue, forKey: "weightUnit")
        case .copyToNext:
            if let workout = step.exercise.workout,
               let next = WorkoutDualModeEngine.nextIncompleteStep(after: step.set.persistentModelID, in: workout) {
                next.set.weight = step.set.weight
                next.set.weightRight = step.set.weightRight
                next.set.reps = step.set.reps
            }
        case .applyAISuggestion:
            if let workout = step.exercise.workout,
               let advice = WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: step.exercise, in: workout, using: modelContext) {
                WorkoutDualModeEngine.applyProgressionAdvice(advice, to: step.set)
                syncFromModel()
            }
        default:
            break
        }
    }

    private func syncFromModel() {
        if field == .reps {
            text = step.set.reps == 0 ? "" : "\(step.set.reps)"
        } else {
            let kg = field == .weightRight ? (step.set.weightRight ?? step.set.weight) : step.set.weight
            let disp = WorkoutDualModeEngine.displayWeight(kg, unit: unit)
            text = disp == 0 ? "" : (disp.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(disp)) : String(format: "%.1f", disp))
        }
    }
}
