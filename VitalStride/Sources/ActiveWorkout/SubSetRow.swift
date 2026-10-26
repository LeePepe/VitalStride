import DesignKit
import SwiftUI
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

struct SubSetRow: View {
    @Environment(\.theme) private var theme
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    inputField(text: $weightText, field: .weight, label: "L")
                    if exerciseSet.isUnilateral {
                        inputField(text: $weightRightText, field: .weightRight, label: "R")
                    }
                    inputField(text: $repsText, field: .reps, label: "次")
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
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "删除", comment: "Delete sub-set menu item"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
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
        .onAppear(perform: refreshInputText)
        .onChange(of: exerciseSet.weight) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.weightRight) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.reps) { _, _ in refreshInputText() }
    }

    @ViewBuilder
    private func inputField(text: Binding<String>, field: SetField, label: String) -> some View {
        #if canImport(UIKit) && !os(macOS)
        SelectAllTextField(
            placeholder: field == .reps ? String(localized: "次", comment: "Repetitions unit") : weightUnit.rawValue,
            text: text,
            keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad,
            useCustomKeyboard: true,
            field: field,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg
        )
        .frame(width: field.isWeightField ? 58 : 48, height: 44)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(theme.accent).padding(.leading, 3)
        }
        .onChange(of: text.wrappedValue) { _, _ in sync(field: field) }
        #else
        TextField("", text: text)
            .frame(width: field.isWeightField ? 58 : 48, height: 44)
            .onChange(of: text.wrappedValue) { _, _ in sync(field: field) }
        #endif
    }

    private func toggleCompleted() {
        let wasCompleted = exerciseSet.isCompleted
        exerciseSet.isCompleted.toggle()
        if !wasCompleted { HapticManager.trigger(.setCompleted) }
        onToggleCompleted(wasCompleted)
    }

    private func refreshInputText() {
        weightText = format(weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight)
        weightRightText = exerciseSet.isUnilateral
            ? format(weightUnit == .lb ? (exerciseSet.weightRight ?? exerciseSet.weight) * 2.20462 : (exerciseSet.weightRight ?? exerciseSet.weight))
            : ""
        repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
    }

    private func sync(field: SetField) {
        switch field {
        case .weight:
            if let value = Double(weightText), value.isFinite, value >= 0 {
                exerciseSet.weight = weightUnit == .lb ? value / 2.20462 : value
            }
        case .weightRight:
            if let value = Double(weightRightText), value.isFinite, value >= 0 {
                exerciseSet.weightRight = weightUnit == .lb ? value / 2.20462 : value
            }
        case .reps:
            if let value = Int(repsText), value >= 0 { exerciseSet.reps = value }
        }
    }

    private func format(_ value: Double) -> String {
        value == 0 ? "" : value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
