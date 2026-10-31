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
    @Environment(\.workoutRowObservation) private var rowObservation
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false
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
    @State private var repsFocusRequestID = 0
    @State private var focusedField: SetField?
    @State private var inputWeightUnit: WeightUnit = .kg

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
        mainAxis
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
        .frame(maxWidth: .infinity, minHeight: largeMode ? 56 : 48)
        .designSurface(style: .solid, cornerRadius: 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accent.opacity(0.55))
                .frame(width: 2)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .background {
            Button(action: toggleCompleted) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
        }
        .onAppear {
            refreshInputText()
            rowObservation.modeAction(exerciseSet.persistentModelID) {
                handleLeftAction(.toggleUnilateral, field: .weight)
            }
        }
        .onChange(of: exerciseSet.weight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.weightRight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.reps) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: weightUnit) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.isUnilateral) { _, _ in refreshInputText() }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.85),
            value: exerciseSet.isCompleted
        )
    }

    private var mainAxis: some View {
        HStack(alignment: .center, spacing: 4) {
            leadingControls
            if exerciseSet.isUnilateral {
                inputsAndCaption
            } else {
                bilateralInputs
            }
            Spacer(minLength: 0)
            trailingControls
        }
        .padding(.horizontal, 0)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var leadingControls: some View {
        Button(action: toggleCompleted) {
            HStack(alignment: .center, spacing: 3) {
                Text("\(parentSetNumber).\(exerciseSet.order)")
                    .font((largeMode ? Font.caption : Font.caption2).monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(theme.accent)
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(exerciseSet.isCompleted ? theme.success : theme.neutrals.text2)
            }
        }
        .frame(minWidth: ActiveWorkoutHitTarget.side, minHeight: ActiveWorkoutHitTarget.side)
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .accessibilityLabel(String(localized: "递减组完成状态", comment: "Drop-set completion"))
        .accessibilityHint(String(localized: "双击切换完成状态", comment: "Toggle completion"))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowObservation.control(exerciseSet.persistentModelID, "completion", frame)
        }
    }

    private var trailingControls: some View {
        Button(role: .destructive, action: onDelete) {
            Image(systemName: "xmark")
        }
        .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .accessibilityLabel(String(localized: "关闭递减组", comment: "Delete drop-set row"))
        .accessibilityHint(String(localized: "删除此递减组", comment: "Delete drop-set hint"))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowObservation.control(exerciseSet.persistentModelID, "delete", frame)
        }
    }

    private var bilateralInputs: some View {
        HStack(spacing: 4) {
            inputField(text: $weightText, field: .weight,
                       label: String(localized: "workout.row.total_prefix", defaultValue: "Total", comment: "Bilateral total weight prefix"),
                       focusRequestID: $weightFocusRequestID)
            inputField(text: $repsText, field: .reps,
                       label: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"),
                       focusRequestID: $repsFocusRequestID)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var inputsAndCaption: some View {
        HStack(spacing: 4) {
            inputField(text: $weightText, field: .weight, label: "L", focusRequestID: $weightFocusRequestID)
            inputField(text: $weightRightText, field: .weightRight, label: "R", focusRequestID: $weightFocusRequestID)
            inputField(text: $repsText, field: .reps, label: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"), focusRequestID: $repsFocusRequestID)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func inputField(text: Binding<String>, field: SetField, label: String, focusRequestID: Binding<Int>) -> some View {
        // Only edits from the input write back. Model/unit refreshes update the
        // display directly, preserving stored precision after display rounding.
        let editingText = Binding<String>(
            get: { text.wrappedValue },
            set: { value in
                text.wrappedValue = value
                sync(field: field)
            }
        )
        #if canImport(UIKit) && !os(macOS)
        let isTotal = !exerciseSet.isUnilateral && field == .weight
        let isSide = field != .reps
        let input = SelectAllTextField(
            placeholder: "",
            text: editingText,
            keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad,
            font: LargeWorkoutInputFont.weightReps(large: largeMode),
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
        return HStack(alignment: .center, spacing: 2) {
            if isSide {
                WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "prefix", text: label)
                    .font(largeMode ? .footnote.weight(isTotal ? .semibold : .bold) : .caption2.weight(isTotal ? .semibold : .bold))
                    .foregroundStyle(isTotal ? theme.neutrals.text3 : theme.accent)
                    .fixedSize()
            }
            WorkoutSetInput(input, theme: theme, focusRequestID: focusRequestID.wrappedValue)
                .frame(
                    width: ActiveWorkoutHitTarget.numericInputWidth(
                        large: largeMode,
                        isWeight: field.isWeightField
                    ),
                    height: largeMode ? 42 : 36
                )
                .fixedSize(horizontal: true, vertical: false)
            if field.isWeightField {
                WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "unit", text: weightUnit.rawValue)
                    .font(largeMode ? .footnote.weight(.medium) : .caption2.weight(.medium))
                    .foregroundStyle(theme.neutrals.text3)
            } else {
                WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "unit",
                                     text: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
                    .font(largeMode ? .footnote.weight(.medium) : .caption2.weight(.medium))
                    .foregroundStyle(theme.neutrals.text3)
            }
        }
        .padding(.horizontal, 3)
        .frame(minWidth: ActiveWorkoutHitTarget.side, minHeight: ActiveWorkoutHitTarget.side)
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.inner)
                .frame(height: largeMode ? 42 : 36)
                .overlay {
                    if focusedField == field {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.accent, lineWidth: 1.5)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusRequestID.wrappedValue &+= 1
        }
        .accessibilityLabel(field == .reps ? String(localized: "递减组次数", comment: "Drop-set reps") : String(localized: "递减组重量", comment: "Drop-set weight"))
        .accessibilityHint(String(localized: "输入数值", comment: "Enter drop-set value"))
        #else
        return HStack(spacing: 2) {
            if field != .reps {
                WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "prefix", text: label)
                    .font(.caption2.weight(.semibold))
                    .fixedSize()
            }
            TextField("", text: editingText)
                .frame(
                    width: ActiveWorkoutHitTarget.numericInputWidth(
                        large: largeMode,
                        isWeight: field.isWeightField
                    ),
                    height: largeMode ? 42 : 36
                )
            WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "unit", text: field.isWeightField
                 ? weightUnit.rawValue
                 : String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
                .font(.caption2.weight(.medium))
                .allowsHitTesting(false)
        }
        #endif
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
        case .applyAISuggestion:
            break
        default:
            break
        }
    }

    private func applyPreset(weightKg: Double?, reps: Int) {
        if let weightKg {
            exerciseSet.weight = weightKg
            if exerciseSet.isUnilateral {
                exerciseSet.weightRight = weightKg
                weightRightText = format(weightUnit == .lb ? weightKg * 2.20462 : weightKg)
            }
        }
        exerciseSet.reps = reps
        refreshInputText()
    }

    private func toggleCompleted() {
        let wasCompleted = exerciseSet.isCompleted
        exerciseSet.isCompleted.toggle()
        if !wasCompleted { HapticManager.trigger(.setCompleted) }
        onToggleCompleted(wasCompleted)
    }

    private func refreshInputText(preservingFocusedField: SetField? = nil) {
        // The native field retains its edit binding across SwiftUI updates.
        // Keep the unit beside the text so that binding uses the displayed unit.
        inputWeightUnit = weightUnit
        if preservingFocusedField != .weight {
            weightText = format(weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight)
        }
        if preservingFocusedField != .weightRight {
            weightRightText = exerciseSet.isUnilateral
                ? format(weightUnit == .lb ? (exerciseSet.weightRight ?? exerciseSet.weight) * 2.20462 : (exerciseSet.weightRight ?? exerciseSet.weight))
                : ""
        }
        if preservingFocusedField != .reps {
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private func sync(field: SetField) {
        switch field {
        case .weight:
            if weightText.isEmpty {
                exerciseSet.weight = 0
            } else if let value = Double(weightText), value.isFinite, value >= 0 {
                exerciseSet.weight = inputWeightUnit == .lb ? value / 2.20462 : value
            }
        case .weightRight:
            if weightRightText.isEmpty {
                exerciseSet.weightRight = 0
            } else if let value = Double(weightRightText), value.isFinite, value >= 0 {
                exerciseSet.weightRight = inputWeightUnit == .lb ? value / 2.20462 : value
            }
        case .reps:
            if repsText.isEmpty {
                exerciseSet.reps = 0
            } else if let value = Int(repsText), value >= 0 {
                exerciseSet.reps = value
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == 0 ? "" : value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
