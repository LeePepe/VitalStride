// swiftlint:disable no_hardcoded_chinese
// Set Row (Always Editable).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). MY-1073 wires each weight
// / reps input to the shared custom `WorkoutNumericKeyboard` and consolidates
// the previous Menu function items (pyramid / drop-set / unilateral toggle)
// into the keyboard's left column.

import DesignKit
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif


struct WorkoutRowDescriptor: View {
    let text: String
    init(row: AnyHashable, field: SetField, kind: String, text: String) { self.text = text }
    var body: some View { Text(text).fixedSize() }
}

/// MY-1013: shared 44pt hit-target size for compact SetRow / SubSetRow
/// controls. Kept as a single source of truth so the SetRow completion
/// button, SetRow ellipsis Menu trigger, and SubSetRow completion button
/// cannot drift below Constitution P1-H (>=44pt tappable + accessibility
/// target) independently. Held here (SetRow.swift) rather than in a new
/// file so the fix stays inside the two files authorized for MY-1013.
enum ActiveWorkoutHitTarget {
    /// Rendered hit-region side length (pt). Constitution P1-H requires
    /// >= 44pt on iOS; VoiceOver rotor also uses rendered geometry.
    static let side: CGFloat = 44

    static func numericInputWidth(large: Bool, isWeight: Bool) -> CGFloat {
        if large {
            return isWeight ? 36 : 32
        }
        return isWeight ? 28 : 24
    }
}

/// Numeric inputs retain a real 44pt interactive height in compact mode.
/// Large Mode supplies its own larger field floor.
private struct NormalModeHitTargetPadding: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .frame(minHeight: ActiveWorkoutHitTarget.side)
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}

#if canImport(UIKit) && !os(macOS)
/// The shared coordinator keeps selection-aware editing and the custom keyboard
/// bridge. This row-owned host adds explicit sizing and Strata input colors, so
/// UIKit's intrinsic size cannot paint over the adjacent L/R label or reps box.
struct WorkoutSetInput: UIViewRepresentable {
    let input: SelectAllTextField
    let theme: Theme
    var focusRequestID: Int = 0

    init(_ input: SelectAllTextField, theme: Theme, focusRequestID: Int = 0) {
        self.input = input
        self.theme = theme
        self.focusRequestID = focusRequestID
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        let inputCoordinator: SelectAllTextField.Coordinator
        var lastFocusRequestID = 0

        init(inputCoordinator: SelectAllTextField.Coordinator) {
            self.inputCoordinator = inputCoordinator
        }

        @objc func textChanged(_ textField: UITextField) {
            inputCoordinator.textChanged(textField)
        }

        func attach(textField: UITextField) {
            inputCoordinator.attach(textField: textField)
        }

        func update(
            field: SetField,
            setType: SetType,
            exercise: Exercise?,
            recentWeightKg: Double?,
            suggestedWeightKg: Double?,
            suggestedReps: Int?,
            onLeftAction: ((LeftKeyAction) -> Void)?,
            onPresetReps: ((Double?, Int) -> Void)?,
            onFocusChange: ((SetField?) -> Void)?
        ) {
            inputCoordinator.update(
                field: field, setType: setType, exercise: exercise,
                recentWeightKg: recentWeightKg, suggestedWeightKg: suggestedWeightKg,
                suggestedReps: suggestedReps, onLeftAction: onLeftAction,
                onPresetReps: onPresetReps, onFocusChange: onFocusChange
            )
        }

        func installCustomKeyboardIfNeeded(on textField: UITextField) {
            inputCoordinator.installCustomKeyboardIfNeeded(on: textField)
        }

        func refreshCustomKeyboardContextIfInstalled() {
            inputCoordinator.refreshCustomKeyboardContextIfInstalled()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            inputCoordinator.textFieldDidBeginEditing(textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            inputCoordinator.textFieldDidEndEditing(textField)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(inputCoordinator: input.makeCoordinator())
    }

    func makeUIView(context: Context) -> UITextField {
        let view = UITextField()
        view.delegate = context.coordinator
        view.borderStyle = .none
        view.textAlignment = .center
        view.adjustsFontForContentSizeCategory = true
        view.adjustsFontSizeToFitWidth = true
        view.minimumFontSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addTarget(context.coordinator,
                       action: #selector(SelectAllTextField.Coordinator.textChanged(_:)), for: .editingChanged)
        context.coordinator.attach(textField: view)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: UITextField, context: Context) {
        if focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if !view.isFirstResponder {
                view.becomeFirstResponder()
            }
        }
        if view.text != input.text { view.text = input.text }
        view.placeholder = ""
        if input.placeholder.isEmpty {
            view.attributedPlaceholder = nil
        } else {
            view.attributedPlaceholder = NSAttributedString(
                string: input.placeholder,
                attributes: [
                    .foregroundColor: UIColor(Color.accentColor.opacity(0.72))
                ]
            )
        }
        view.font = input.font
        view.textColor = UIColor(Color.primary)
        view.tintColor = UIColor(Color.accentColor)
        view.keyboardType = input.keyboardType
        context.coordinator.update(
            field: input.field, setType: input.setType, exercise: input.exercise,
            recentWeightKg: input.recentWeightKg,
            suggestedWeightKg: input.suggestedWeightKg,
            suggestedReps: input.suggestedReps,
            onLeftAction: input.onLeftAction,
            onPresetReps: input.onPresetReps,
            onFocusChange: input.onFocusChange
        )
        context.coordinator.installCustomKeyboardIfNeeded(on: view)
        context.coordinator.refreshCustomKeyboardContextIfInstalled()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 60, height: max(44, input.font.lineHeight + 12))
    }
}
#endif

struct SetRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    let index: Int
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let canDelete: Bool
    let exercise: Exercise?
    let recentWeightKg: Double?
    let previousSet: ExerciseSet?
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    let onAddSubSet: (_ type: SetType) -> Void
    let onCopyToNext: () -> Void
    @State private var weightText = ""
    @State private var rightWeightText = ""
    @State private var repsText = ""
    @State private var focusID = 0

    init(index: Int, exerciseSet: ExerciseSet, weightUnit: WeightUnit, canDelete: Bool, exercise: Exercise?, recentWeightKg: Double?, previousSet: ExerciseSet? = nil, onToggleCompleted: @escaping (_ wasCompleted: Bool) -> Void, onDelete: @escaping () -> Void, onAddSubSet: @escaping (_ type: SetType) -> Void, onCopyToNext: @escaping () -> Void) {
        self.index = index; self.exerciseSet = exerciseSet; self.weightUnit = weightUnit; self.canDelete = canDelete
        self.exercise = exercise; self.recentWeightKg = recentWeightKg; self.previousSet = previousSet
        self.onToggleCompleted = onToggleCompleted; self.onDelete = onDelete; self.onAddSubSet = onAddSubSet; self.onCopyToNext = onCopyToNext
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { exerciseSet.setType = exerciseSet.setType == .warmup ? .working : .warmup } label: { badge }
                .buttonStyle(.plain).frame(width: 44, alignment: .leading)
            previousColumn.frame(maxWidth: .infinity, alignment: .leading)
            weightColumn.frame(width: 88)
            repsColumn.frame(width: 68)
            Button(action: toggleCompleted) { Image(systemName: exerciseSet.isCompleted ? "checkmark" : "checkmark").font(.headline.weight(.bold)).foregroundStyle(exerciseSet.isCompleted ? .white : .secondary).frame(width: 30, height: 30).background(exerciseSet.isCompleted ? Color.green : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous)) }.buttonStyle(.plain).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 48)
        .background(exerciseSet.isCompleted ? Color.green.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .contextMenu { Button(String(localized: "切换正式/热身组", comment: "Toggle set type")) { exerciseSet.setType = exerciseSet.setType == .warmup ? .working : .warmup }; Button(String(localized: "切换单侧/双侧", comment: "Toggle unilateral")) { Self.toggleExerciseWeightMode(from: exerciseSet) }; Button(String(localized: "+ 递减组", comment: "Add drop set")) { onAddSubSet(.dropSet) }; Button(String(localized: "+ 金字塔组", comment: "Add pyramid set")) { onAddSubSet(.pyramid) }; Button(String(localized: "复制到下一组", comment: "Copy to next set")) { onCopyToNext() }; if canDelete { Button(String(localized: "删除本组", comment: "Delete set"), role: .destructive, action: onDelete) } }
        .onAppear { refresh() }.onChange(of: exerciseSet.weight) { _, _ in refresh() }.onChange(of: exerciseSet.reps) { _, _ in refresh() }
    }

    private var badge: some View { Text(exerciseSet.setType == .warmup ? "W" : "\(index + 1)").font(.caption.weight(.bold)).foregroundStyle(exerciseSet.setType == .warmup ? .orange : .accentColor).frame(width: 32, height: 28).background((exerciseSet.setType == .warmup ? Color.orange : Color.accentColor).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous)) }
    private var previousColumn: some View {
        Group { if let previousSet { Button { apply(previousSet) } label: { VStack(alignment: .leading, spacing: 2) { Text("\(display(previousSet.weight)) × \(previousSet.reps)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary); if let advice = smartAdvice { Text("↑\(display(advice.suggestedWeight))×\(advice.suggestedReps)").font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(Color.accentColor) } } }.buttonStyle(.plain) } else { Text("—").font(.subheadline).foregroundStyle(.tertiary) } }
    }
    private var weightColumn: some View { Group { if exerciseSet.isUnilateral { HStack(spacing: 4) { field(.weight, text: $weightText, label: "L", width: 42); field(.weightRight, text: $rightWeightText, label: "R", width: 42) } } else { field(.weight, text: $weightText, label: nil, width: 88) } } }
    private var repsColumn: some View { field(.reps, text: $repsText, label: nil, width: 68) }
    @ViewBuilder private func field(_ field: SetField, text: Binding<String>, label: String?, width: CGFloat) -> some View {
        #if canImport(UIKit) && !os(macOS)
        let input = SelectAllTextField(placeholder: "", text: text, keyboardType: field.isDecimalEnabled ? .decimalPad : .numberPad, font: .systemFont(ofSize: 17, weight: .semibold), useCustomKeyboard: true, field: field, exercise: exercise, setType: exerciseSet.setType, recentWeightKg: recentWeightKg, onLeftAction: { action in handle(action, field: field) }, onPresetReps: { weight, reps in if let weight { exerciseSet.weight = weight }; exerciseSet.reps = reps }, onFocusChange: nil)
        WorkoutSetInput(input, theme: theme, focusRequestID: focusID).frame(width: width - (label == nil ? 0 : 12), height: 38).overlay(alignment: .leading) { if let label { Text(label).font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor).padding(.leading, 3) } }
        #else
        TextField("", text: text).multilineTextAlignment(.center).frame(width: width, height: 38)
        #endif
    }
    private var smartAdvice: ProgressionAdvice? { guard let owner = exerciseSet.workoutExercise, let workout = owner.workout else { return nil }; return WorkoutDualModeEngine.computeExerciseProgressionAdvice(for: owner, in: workout, using: modelContext) }
    private func apply(_ source: ExerciseSet) { exerciseSet.weight = source.weight; exerciseSet.reps = source.reps; if exerciseSet.isUnilateral { exerciseSet.weightRight = source.weightRight ?? source.weight }; refresh() }
    private func handle(_ action: LeftKeyAction, field: SetField) { switch action { case .toggleUnilateral: Self.toggleExerciseWeightMode(from: exerciseSet); case .copyToNext: onCopyToNext(); case .addDropSet: onAddSubSet(.dropSet); case .addPyramidSet: onAddSubSet(.pyramid); case .addSet: if let owner = exerciseSet.workoutExercise { _ = ActiveExerciseSection.insertAppendedMainSet(in: owner, using: modelContext) }; default: break } }
    private func toggleCompleted() { let was = exerciseSet.isCompleted; exerciseSet.isCompleted.toggle(); onToggleCompleted(was) }
    private func refresh() { weightText = display(WorkoutDualModeEngine.displayWeight(exerciseSet.weight, unit: weightUnit)); rightWeightText = exerciseSet.weightRight.map { display(WorkoutDualModeEngine.displayWeight($0, unit: weightUnit)) } ?? ""; repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)" }
    private func display(_ value: Double) -> String { value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...1))) }
    static func toggleExerciseWeightMode(from set: ExerciseSet) { let unilateral = !set.isUnilateral; for row in set.workoutExercise?.sets ?? [set] { row.isUnilateral = unilateral; if unilateral, row.weightRight == nil { row.weightRight = row.weight } } }
}
