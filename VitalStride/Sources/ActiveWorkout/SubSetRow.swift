import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

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
    let onAddSubSet: (_ type: SetType) -> Void
    @State private var weightText = ""
    @State private var rightWeightText = ""
    @State private var repsText = ""
    @State private var focusID = 0
    init(exerciseSet: ExerciseSet, weightUnit: WeightUnit, isLast: Bool, parentSetNumber: Int, exercise: Exercise?, recentWeightKg: Double?, onToggleCompleted: @escaping (_ wasCompleted: Bool) -> Void, onDelete: @escaping () -> Void, onAddSubSet: @escaping (_ type: SetType) -> Void = { _ in }) { self.exerciseSet=exerciseSet; self.weightUnit=weightUnit; self.isLast=isLast; self.parentSetNumber=parentSetNumber; self.exercise=exercise; self.recentWeightKg=recentWeightKg; self.onToggleCompleted=onToggleCompleted; self.onDelete=onDelete; self.onAddSubSet=onAddSubSet }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) { Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.secondary); Text(exerciseSet.setType == .dropSet ? "D" : "P").font(.caption2.bold()).foregroundStyle(exerciseSet.setType == .dropSet ? .purple : .teal).frame(width: 24, height: 24).background((exerciseSet.setType == .dropSet ? Color.purple : Color.teal).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous)) }.frame(width: 44, alignment: .leading)
            Text(exerciseSet.setType == .dropSet ? String(localized: "递减 -20%", comment: "Drop set description") : String(localized: "金字塔", comment: "Pyramid description")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            weightColumn.frame(width: 88); repsColumn.frame(width: 68)
            Button { let was = exerciseSet.isCompleted; exerciseSet.isCompleted.toggle(); onToggleCompleted(was) } label: { Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(exerciseSet.isCompleted ? .white : .secondary).frame(width: 30, height: 30).background(exerciseSet.isCompleted ? Color.green : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous)) }.buttonStyle(.plain).frame(width: 44, alignment: .trailing)
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 48).background(exerciseSet.isCompleted ? Color.green.opacity(0.10) : .clear).contextMenu { Button(String(localized: "删除本组", comment: "Delete set"), role: .destructive, action: onDelete); Button(String(localized: "+ 递减组", comment: "Add drop set")) { onAddSubSet(.dropSet) }; Button(String(localized: "+ 金字塔组", comment: "Add pyramid set")) { onAddSubSet(.pyramid) } }.onAppear { refresh() }
    }
    private var weightColumn: some View { Group { if exerciseSet.isUnilateral { HStack(spacing: 4) { field(.weight, text: $weightText, width: 42); field(.weightRight, text: $rightWeightText, width: 42) } } else { field(.weight, text: $weightText, width: 88) } } }
    private var repsColumn: some View { field(.reps, text: $repsText, width: 68) }
    @ViewBuilder
    private func field(_ field: SetField, text: Binding<String>, width: CGFloat) -> some View {
        #if canImport(UIKit) && !os(macOS)
        let input = SelectAllTextField(placeholder: "", text: text, keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad, font: .systemFont(ofSize: 17, weight: .semibold), useCustomKeyboard: true, field: field, exercise: exercise, setType: exerciseSet.setType, recentWeightKg: recentWeightKg, onLeftAction: { _ in }, onPresetReps: { _, reps in exerciseSet.reps = reps }, onFocusChange: nil)
        WorkoutSetInput(input, theme: theme, focusRequestID: focusID).frame(width: width, height: 38)
        #else
        TextField("", text: text).multilineTextAlignment(.center).frame(width: width, height: 38)
        #endif
    }
    private func refresh() { weightText = show(exerciseSet.weight); rightWeightText = exerciseSet.weightRight.map(show) ?? ""; repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)" }
    private func show(_ value: Double) -> String { value == 0 ? "" : WorkoutDualModeEngine.displayWeight(value, unit: weightUnit).formatted(.number.precision(.fractionLength(0...1))) }
}
