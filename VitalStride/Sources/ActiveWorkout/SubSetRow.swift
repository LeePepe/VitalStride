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
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let isLast: Bool
    let parentSetNumber: Int
    let exercise: Exercise?
    let recentWeightKg: Double?
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void

    @State private var weightText = ""
    @State private var weightRightText = ""
    @State private var repsText = ""
    @State private var focusedField: SetField?
    @State private var inputWeightUnit: WeightUnit = .kg

    var body: some View {
        HStack(spacing: 4) {
            Text("↳")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            Button(action: toggleCompleted) {
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(exerciseSet.isCompleted ? theme.success : theme.neutrals.text2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "递减组完成状态", comment: "Drop-set completion"))
            .accessibilityHint(String(localized: "双击切换完成状态", comment: "Toggle completion"))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    inputField(text: $weightText, field: .weight, label: exerciseSet.isUnilateral ? "L" : String(localized: "workout.row.total_prefix", defaultValue: "Total", comment: "Bilateral total weight prefix"))
                    if exerciseSet.isUnilateral {
                        inputField(text: $weightRightText, field: .weightRight, label: "R")
                    }
                    inputField(text: $repsText, field: .reps, label: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
                }
                Text(String(
                    format: String(localized: "active_workout.drop_set.label", defaultValue: "↳ %lld.%lld Drop set", comment: "Drop-set child label"),
                    Int64(parentSetNumber),
                    Int64(exerciseSet.order)
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.neutrals.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "关闭递减组", comment: "Delete drop-set row"))
            .accessibilityHint(String(localized: "删除此递减组", comment: "Delete drop-set hint"))
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "删除", comment: "Delete sub-set menu item"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .accessibilityLabel(String(localized: "递减组更多操作", comment: "Drop-set more actions"))
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accent.opacity(0.45))
                .frame(width: 2)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .background {
            Button(action: toggleCompleted) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
        }
        .onAppear { refreshInputText() }
        .onChange(of: exerciseSet.weight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.weightRight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.reps) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: weightUnit) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.isUnilateral) { _, _ in refreshInputText() }
    }

    private func inputField(text: Binding<String>, field: SetField, label: String) -> some View {
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
            placeholder: field == .reps ? String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit") : weightUnit.rawValue,
            text: editingText,
            keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad,
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
        return HStack(spacing: 2) {
            if isSide {
                Text(label)
                    .font(.caption2.weight(isTotal ? .semibold : .bold))
                    .foregroundStyle(isTotal ? theme.neutrals.text3 : theme.accent)
                    .fixedSize()
            }
            WorkoutSetInput(input, theme: theme)
                .frame(width: ActiveWorkoutHitTarget.side, height: 44)
            if field.isWeightField {
                Text(weightUnit.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.neutrals.text3)
            } else {
                Text(String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.neutrals.text3)
            }
        }
        .padding(.horizontal, 2)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focusedField == field {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accent, lineWidth: 1.5)
            }
        }
        .accessibilityLabel(field == .reps ? String(localized: "递减组次数", comment: "Drop-set reps") : String(localized: "递减组重量", comment: "Drop-set weight"))
        .accessibilityHint(String(localized: "输入数值", comment: "Enter drop-set value"))
        #else
        return TextField("", text: editingText)
            .frame(width: field.isWeightField ? 58 : 48, height: 44)
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
