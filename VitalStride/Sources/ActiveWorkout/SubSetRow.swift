// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

struct SubSetRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let isLast: Bool
    let parentSetNumber: Int
    let exercise: Exercise?
    let recentWeightKg: Double?
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    let onAddSubSet: (_ type: SetType) -> Void

    @State private var weightText = ""
    @State private var weightRightText = ""
    @State private var repsText = ""
    @State private var weightFocusRequestID = 0
    @State private var weightRightFocusRequestID = 0
    @State private var repsFocusRequestID = 0
    @State private var focusedField: SetField?

    init(
        exerciseSet: ExerciseSet,
        weightUnit: WeightUnit,
        isLast: Bool,
        parentSetNumber: Int,
        exercise: Exercise?,
        recentWeightKg: Double?,
        onToggleCompleted: @escaping (_ wasCompleted: Bool) -> Void,
        onDelete: @escaping () -> Void,
        onAddSubSet: @escaping (_ type: SetType) -> Void = { _ in }
    ) {
        self.exerciseSet = exerciseSet
        self.weightUnit = weightUnit
        self.isLast = isLast
        self.parentSetNumber = parentSetNumber
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.onToggleCompleted = onToggleCompleted
        self.onDelete = onDelete
        self.onAddSubSet = onAddSubSet
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            subSetBadge
                .frame(width: 44, height: 44, alignment: .center)

            weightColumn
                .frame(maxWidth: .infinity, alignment: .center)

            repsColumn
                .frame(width: 84, alignment: .center)

            completionButton
                .frame(width: 44, height: 44, alignment: .center)
            rowActionMenu
                .frame(width: 40, height: 44, alignment: .center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(exerciseSet.isCompleted ? Color.green.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .sensoryFeedback(.success, trigger: exerciseSet.isCompleted)
        .contextMenu {
            Button(String(localized: "切换单侧/双侧", comment: "Toggle unilateral or bilateral weight")) {
                SetRow.toggleExerciseWeightMode(from: exerciseSet)
                refreshInputText()
            }
            Button(String(localized: "+ 递减组", comment: "Add drop set")) {
                onAddSubSet(.dropSet)
            }
            Button(String(localized: "+ 金字塔组", comment: "Add pyramid set")) {
                onAddSubSet(.pyramid)
            }
            if let owner = exerciseSet.workoutExercise {
                Button(String(localized: "复制到下一组", comment: "Copy set to next")) {
                    ActiveExerciseSection.copyToNext(from: exerciseSet, in: owner, using: modelContext)
                }
            }
            Divider()
            Button(String(localized: "删除本组", comment: "Delete this sub-set"), role: .destructive, action: onDelete)
        }
        .onAppear {
            refreshInputText()
        }
        .onChange(of: weightUnit) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.weight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.weightRight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.reps) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.isUnilateral) { _, _ in refreshInputText() }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.85),
            value: exerciseSet.isCompleted
        )
    }

    private var subSetBadge: some View {
        let isDrop = exerciseSet.setType == .dropSet
        let badgeColor: Color = isDrop ? .purple : .teal
        return HStack(alignment: .center, spacing: 3) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(isDrop ? "D" : "P")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(badgeColor)
                .frame(width: 24, height: 24)
                .background(badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isDrop
                ? String(localized: "递减组", comment: "Drop set badge")
                : String(localized: "金字塔组", comment: "Pyramid set badge")
        )
    }

    private var hintWeightText: String {
        guard let owner = exerciseSet.workoutExercise, let workout = owner.workout else { return "" }
        let previous = PreviousSetLookup.previousMainSet(currentWorkout: workout, exercise: exercise, mainSetIndex: parentSetNumber, in: modelContext)
        return previous.map { format(WorkoutDualModeEngine.displayWeight($0.weight, unit: weightUnit)) } ?? ""
    }

    private var hintRepsText: String {
        guard let owner = exerciseSet.workoutExercise, let workout = owner.workout else { return "" }
        let previous = PreviousSetLookup.previousMainSet(currentWorkout: workout, exercise: exercise, mainSetIndex: parentSetNumber, in: modelContext)
        return previous.map { "\($0.reps)" } ?? ""
    }

    @ViewBuilder
    private var weightColumn: some View {
        if exerciseSet.isUnilateral {
            HStack(spacing: 6) {
                numericInputSlot(
                    binding: $weightText,
                    field: .weight,
                    width: nil,
                    placeholder: hintWeightText.isEmpty ? "L" : hintWeightText,
                    focusRequestID: $weightFocusRequestID,
                    a11yLabel: String(localized: "子组左侧重量", comment: "Sub-set left weight")
                )
                numericInputSlot(
                    binding: $weightRightText,
                    field: .weightRight,
                    width: nil,
                    placeholder: hintWeightText.isEmpty ? "R" : hintWeightText,
                    focusRequestID: $weightRightFocusRequestID,
                    a11yLabel: String(localized: "子组右侧重量", comment: "Sub-set right weight")
                )
            }
        } else {
            numericInputSlot(
                binding: $weightText,
                field: .weight,
                width: nil,
                placeholder: hintWeightText,
                focusRequestID: $weightFocusRequestID,
                a11yLabel: String(localized: "子组重量", comment: "Sub-set weight")
            )
        }
    }

    private var repsColumn: some View {
        numericInputSlot(
            binding: $repsText,
            field: .reps,
            width: 84,
            placeholder: hintRepsText,
            focusRequestID: $repsFocusRequestID,
            a11yLabel: String(localized: "子组次数", comment: "Sub-set reps")
        )
    }

    @ViewBuilder
    private func numericInputSlot(
        binding: Binding<String>,
        field: SetField,
        width: CGFloat?,
        placeholder: String,
        focusRequestID: Binding<Int>,
        a11yLabel: String
    ) -> some View {
        let isFocused = focusedField == field
        let slotShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        #if canImport(UIKit) && !os(macOS)
        let uiFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        )
        let input = SelectAllTextField(
            placeholder: placeholder,
            text: binding,
            keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad,
            font: uiFont,
            useCustomKeyboard: true,
            field: field,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg,
            onLeftAction: { action in handleLeftAction(action, field: field) },
            onPresetReps: { weightKg, reps in applyPreset(weightKg: weightKg, reps: reps) },
            onFocusChange: { newField in
                if let newField {
                    focusedField = newField
                } else if focusedField == field {
                    focusedField = nil
                    refreshInputText()
                }
            }
        )
        WorkoutSetInput(input, theme: theme, focusRequestID: focusRequestID.wrappedValue)
            .frame(maxWidth: width ?? .infinity, minHeight: 38, maxHeight: 38)
            .background(Color(uiColor: .tertiarySystemFill), in: slotShape)
            .overlay {
                slotShape.strokeBorder(
                    isFocused ? Color.accentColor : Color.clear,
                    lineWidth: 1.5
                )
            }
            .frame(maxWidth: width ?? .infinity, minHeight: 44, maxHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                focusRequestID.wrappedValue &+= 1
            }
            .accessibilityLabel(a11yLabel)
            .onChange(of: binding.wrappedValue) { _, newValue in
                if field == .reps {
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue { binding.wrappedValue = filtered }
                    syncRepsToModel()
                } else {
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { binding.wrappedValue = filtered }
                    if field == .weight {
                        syncWeightToModel()
                    } else {
                        syncWeightRightToModel()
                    }
                }
            }
        #else
        TextField(placeholder, text: binding)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit().weight(.semibold))
            .frame(maxWidth: width ?? .infinity, minHeight: 38, maxHeight: 38)
            .background(workoutTertiaryFill, in: slotShape)
            .frame(maxWidth: width ?? .infinity, minHeight: 44, maxHeight: 44)
            .accessibilityLabel(a11yLabel)
            .onChange(of: binding.wrappedValue) { _, newValue in
                if field == .reps {
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue { binding.wrappedValue = filtered }
                    syncRepsToModel()
                } else {
                    let filtered = filterDecimalInput(newValue)
                    if filtered != newValue { binding.wrappedValue = filtered }
                    if field == .weight {
                        syncWeightToModel()
                    } else {
                        syncWeightRightToModel()
                    }
                }
            }
        #endif
    }

    private var rowActionMenu: some View {
        Menu {
            Button(String(localized: "设为热身组", comment: "Set warmup menu item")) { exerciseSet.setType = .warmup }
            Button(String(localized: "设为正式组", comment: "Set working menu item")) { exerciseSet.setType = .working }
            Button(String(localized: "+ 追加递减组", comment: "Add drop set menu item")) { onAddSubSet(.dropSet) }
            Button(String(localized: "+ 追加金字塔组", comment: "Add pyramid set menu item")) { onAddSubSet(.pyramid) }
            Button(String(localized: "切换单侧 / 双侧", comment: "Toggle unilateral menu item")) {
                SetRow.toggleExerciseWeightMode(from: exerciseSet)
                refreshInputText()
            }
            Button(String(localized: "复制到下一组", comment: "Copy set menu item")) {
                if let owner = exerciseSet.workoutExercise {
                    ActiveExerciseSection.copyToNext(from: exerciseSet, in: owner, using: modelContext)
                }
            }
            Divider()
            Button(String(localized: "删除本组", comment: "Delete set menu item"), role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Color.secondary)
                .frame(width: 40, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "行操作菜单", comment: "Set row actions menu"))
    }

    private var completionButton: some View {
        Button(action: toggleCompleted) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(exerciseSet.isCompleted ? Color.green : Color(uiColor: .tertiarySystemFill))
                    .frame(width: 30, height: 30)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(exerciseSet.isCompleted ? Color.white : Color.secondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            exerciseSet.isCompleted
                ? String(localized: "子组已完成", comment: "Sub-set completed")
                : String(localized: "完成子组", comment: "Complete sub-set")
        )
    }

    private func handleLeftAction(_ action: LeftKeyAction, field: SetField) {
        switch action {
        case .toggleUnilateral:
            SetRow.toggleExerciseWeightMode(from: exerciseSet)
            refreshInputText()
        case .toggleWeightUnit:
            let next: WeightUnit = weightUnit == .kg ? .lb : .kg
            UserDefaults.standard.set(next.rawValue, forKey: "weightUnit")
        case .addSet:
            if let owner = exerciseSet.workoutExercise {
                _ = ActiveExerciseSection.insertAppendedMainSet(in: owner, using: modelContext)
            }
        case .copyToNext:
            if let owner = exerciseSet.workoutExercise {
                #if canImport(UIKit) && !os(macOS)
                HapticManager.trigger(.exerciseAdded)
                #endif
                ActiveExerciseSection.copyToNext(from: exerciseSet, in: owner, using: modelContext)
            }
        case .addDropSet:
            onAddSubSet(.dropSet)
        case .addPyramidSet:
            onAddSubSet(.pyramid)
        case .decreaseWeightFive:
            adjustWeight(by: -5, field: field)
        case .decreaseWeightTwoPointFive:
            adjustWeight(by: -2.5, field: field)
        case .increaseWeightTwoPointFive:
            adjustWeight(by: 2.5, field: field)
        case .increaseWeightFive:
            adjustWeight(by: 5, field: field)
        default:
            break
        }
    }

    private func adjustWeight(by delta: Double, field: SetField) {
        let isRight = field == .weightRight && exerciseSet.isUnilateral
        let currentKg = isRight ? (exerciseSet.weightRight ?? exerciseSet.weight) : exerciseSet.weight
        let conversion = weightUnit == .lb ? 2.20462 : 1
        let updatedDisplay = max(0, currentKg * conversion + delta)
        let updatedKg = weightUnit == .lb ? updatedDisplay / conversion : updatedDisplay
        if isRight {
            exerciseSet.weightRight = updatedKg
        } else {
            exerciseSet.weight = updatedKg
        }
        refreshInputText(preservingFocusedField: nil)
    }

    private func applyPreset(weightKg: Double?, reps: Int) {
        if let weightKg {
            exerciseSet.weight = weightKg
            if exerciseSet.isUnilateral {
                exerciseSet.weightRight = weightKg
            }
        }
        exerciseSet.reps = reps
        refreshInputText()
    }

    private func applyHintIfNeeded() {
        if exerciseSet.weight == 0, let owner = exerciseSet.workoutExercise, let workout = owner.workout,
           let previous = PreviousSetLookup.previousMainSet(currentWorkout: workout, exercise: exercise, mainSetIndex: parentSetNumber, in: modelContext) {
            exerciseSet.weight = previous.weight
            if exerciseSet.isUnilateral { exerciseSet.weightRight = previous.weightRight ?? previous.weight }
            if exerciseSet.reps == 0 { exerciseSet.reps = previous.reps }
        }
    }

    private func toggleCompleted() {
        let wasCompleted = exerciseSet.isCompleted
        if !wasCompleted { applyHintIfNeeded(); refreshInputText() }
        exerciseSet.isCompleted.toggle()
        if !wasCompleted {
            HapticManager.trigger(.setCompleted)
        }
        onToggleCompleted(wasCompleted)
    }

    private func refreshInputText(preservingFocusedField: SetField? = nil) {
        if preservingFocusedField != .weight {
            weightText = format(WorkoutDualModeEngine.displayWeight(exerciseSet.weight, unit: weightUnit))
        }
        if preservingFocusedField != .weightRight {
            let right = exerciseSet.weightRight ?? exerciseSet.weight
            weightRightText = exerciseSet.isUnilateral
                ? format(WorkoutDualModeEngine.displayWeight(right, unit: weightUnit))
                : ""
        }
        if preservingFocusedField != .reps {
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private func syncWeightToModel() {
        let current = WorkoutDualModeEngine.displayWeight(exerciseSet.weight, unit: weightUnit)
        guard weightText != format(current) else { return }
        if weightText.isEmpty {
            exerciseSet.weight = 0
            return
        }
        guard let value = Double(weightText), value.isFinite, value >= 0 else { return }
        exerciseSet.weight = weightUnit == .lb ? value / 2.20462 : value
    }

    private func syncWeightRightToModel() {
        let current = exerciseSet.weightRight ?? exerciseSet.weight
        guard weightRightText != format(WorkoutDualModeEngine.displayWeight(current, unit: weightUnit)) else { return }
        if weightRightText.isEmpty {
            exerciseSet.weightRight = nil
            return
        }
        guard let value = Double(weightRightText), value.isFinite, value >= 0 else { return }
        exerciseSet.weightRight = weightUnit == .lb ? value / 2.20462 : value
    }

    private func syncRepsToModel() {
        if repsText.isEmpty {
            exerciseSet.reps = 0
            return
        }
        guard let value = Int(repsText), value >= 0 else { return }
        exerciseSet.reps = value
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

    private func format(_ value: Double) -> String {
        value == 0 ? "" : (value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value))
    }
}
