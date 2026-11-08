// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

enum ActiveWorkoutHitTarget {
    static let side: CGFloat = 44
}

#if canImport(UIKit) && !os(macOS)
struct WorkoutSetInput: UIViewRepresentable {
    let input: SelectAllTextField
    let theme: Theme
    var focusRequestID: Int = 0
    var textColor: UIColor = UIColor(Color.primary)

    init(
        _ input: SelectAllTextField,
        theme: Theme,
        focusRequestID: Int = 0,
        textColor: UIColor = UIColor(Color.primary)
    ) {
        self.input = input
        self.theme = theme
        self.focusRequestID = focusRequestID
        self.textColor = textColor
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
        view.addTarget(
            context.coordinator,
            action: #selector(SelectAllTextField.Coordinator.textChanged(_:)),
            for: .editingChanged
        )
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
                    .foregroundColor: UIColor.tertiaryLabel
                ]
            )
        }
        view.font = input.font
        view.textColor = textColor
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
        CGSize(width: proposal.width ?? 60, height: proposal.height ?? max(38, input.font.lineHeight + 8))
    }
}
#endif

struct SetRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var weightRightText = ""
    @State private var repsText = ""
    @State private var weightFocusRequestID = 0
    @State private var weightRightFocusRequestID = 0
    @State private var repsFocusRequestID = 0
    @State private var focusedField: SetField?

    init(
        index: Int,
        exerciseSet: ExerciseSet,
        weightUnit: WeightUnit,
        canDelete: Bool,
        exercise: Exercise?,
        recentWeightKg: Double?,
        previousSet: ExerciseSet? = nil,
        onToggleCompleted: @escaping (_ wasCompleted: Bool) -> Void,
        onDelete: @escaping () -> Void,
        onAddSubSet: @escaping (_ type: SetType) -> Void,
        onCopyToNext: @escaping () -> Void
    ) {
        self.index = index
        self.exerciseSet = exerciseSet
        self.weightUnit = weightUnit
        self.canDelete = canDelete
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.previousSet = previousSet
        self.onToggleCompleted = onToggleCompleted
        self.onDelete = onDelete
        self.onAddSubSet = onAddSubSet
        self.onCopyToNext = onCopyToNext
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: toggleSetType) {
                setBadge
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(
                exerciseSet.setType == .warmup
                    ? String(localized: "热身组", comment: "Warmup set")
                    : String(localized: "第 \(index + 1) 组", comment: "Working set number")
            )

            previousColumn
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            weightColumn
                .frame(width: 88, alignment: .center)

            repsColumn
                .frame(width: 68, alignment: .center)

            completionButton
                .frame(width: 44, height: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(exerciseSet.isCompleted ? Color.green.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .sensoryFeedback(.success, trigger: exerciseSet.isCompleted)
        .contextMenu {
            Button(String(localized: "切换正式/热身组", comment: "Toggle working or warmup set")) {
                toggleSetType()
            }
            Button(String(localized: "切换单侧/双侧", comment: "Toggle unilateral or bilateral weight")) {
                Self.toggleExerciseWeightMode(from: exerciseSet)
                refreshInputText()
            }
            Button(String(localized: "+ 递减组", comment: "Add drop set")) {
                onAddSubSet(.dropSet)
            }
            Button(String(localized: "+ 金字塔组", comment: "Add pyramid set")) {
                onAddSubSet(.pyramid)
            }
            Button(String(localized: "复制到下一组", comment: "Copy set to next")) {
                onCopyToNext()
            }
            if canDelete {
                Divider()
                Button(String(localized: "删除本组", comment: "Delete this set"), role: .destructive, action: onDelete)
            }
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

    private var setBadge: some View {
        let isWarmup = exerciseSet.setType == .warmup
        let title = isWarmup ? "W" : "\(index + 1)"
        let fg: Color = isWarmup ? .orange : .accentColor
        let bg: Color = isWarmup ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.14)
        return Text(title)
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(fg)
            .frame(width: 32, height: 28)
            .background(bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resolvedPreviousSet: ExerciseSet? {
        if let previousSet { return previousSet }
        guard let workout = exerciseSet.workoutExercise?.workout else { return nil }
        return PreviousSetLookup.previousMainSet(
            currentWorkout: workout,
            exercise: exercise,
            mainSetIndex: index,
            in: modelContext
        )
    }

    private var resolvedAdvice: ProgressionAdvice? {
        guard !exerciseSet.isCompleted, !exerciseSet.setType.isSubSet,
              let owner = exerciseSet.workoutExercise,
              let workout = owner.workout else { return nil }
        return WorkoutDualModeEngine.computeExerciseProgressionAdvice(
            for: owner,
            in: workout,
            using: modelContext
        )
    }

    @ViewBuilder
    private var previousColumn: some View {
        let prev = resolvedPreviousSet
        let advice = resolvedAdvice
        if let prev {
            let prevWeight = formatDisplay(WorkoutDualModeEngine.displayWeight(prev.weight, unit: weightUnit))
            Button {
                #if canImport(UIKit) && !os(macOS)
                HapticManager.trigger(.setCompleted)
                #endif
                if let advice {
                    WorkoutDualModeEngine.applyProgressionAdvice(advice, to: exerciseSet)
                } else {
                    WorkoutDualModeEngine.applyPreviousSet(prev, to: exerciseSet)
                }
                refreshInputText()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(prevWeight) × \(prev.reps)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let advice {
                        let advWeight = formatDisplay(WorkoutDualModeEngine.displayWeight(advice.suggestedWeight, unit: weightUnit))
                        Text("↑\(advWeight)×\(advice.suggestedReps)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var weightColumn: some View {
        let advice = resolvedAdvice
        if exerciseSet.isUnilateral {
            HStack(spacing: 4) {
                numericInputSlot(
                    binding: $weightText,
                    field: .weight,
                    width: 42,
                    placeholder: "L",
                    suggestion: advice,
                    focusRequestID: $weightFocusRequestID,
                    a11yLabel: String(localized: "第 \(index + 1) 组左侧重量", comment: "Left weight")
                )
                numericInputSlot(
                    binding: $weightRightText,
                    field: .weightRight,
                    width: 42,
                    placeholder: "R",
                    suggestion: advice,
                    focusRequestID: $weightRightFocusRequestID,
                    a11yLabel: String(localized: "第 \(index + 1) 组右侧重量", comment: "Right weight")
                )
            }
        } else {
            let placeholder = advice.map { formatDisplay(WorkoutDualModeEngine.displayWeight($0.suggestedWeight, unit: weightUnit)) } ?? "0"
            numericInputSlot(
                binding: $weightText,
                field: .weight,
                width: 88,
                placeholder: placeholder,
                suggestion: advice,
                focusRequestID: $weightFocusRequestID,
                a11yLabel: String(localized: "第 \(index + 1) 组重量", comment: "Set weight")
            )
        }
    }

    private var repsColumn: some View {
        let advice = resolvedAdvice
        let placeholder = advice.map { "\($0.suggestedReps)" } ?? "0"
        return numericInputSlot(
            binding: $repsText,
            field: .reps,
            width: 68,
            placeholder: placeholder,
            suggestion: advice,
            focusRequestID: $repsFocusRequestID,
            a11yLabel: String(localized: "第 \(index + 1) 组次数", comment: "Set reps")
        )
    }

    @ViewBuilder
    private func numericInputSlot(
        binding: Binding<String>,
        field: SetField,
        width: CGFloat,
        placeholder: String,
        suggestion: ProgressionAdvice?,
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
            suggestedWeightKg: suggestion?.suggestedWeight,
            suggestedReps: suggestion?.suggestedReps,
            onLeftAction: { action in handleLeftAction(action, field: field) },
            onPresetReps: { weightKg, reps in handlePresetReps(weightKg: weightKg, reps: reps) },
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
            .frame(width: width, height: 38)
            .background(Color(uiColor: .tertiarySystemFill), in: slotShape)
            .overlay {
                slotShape.strokeBorder(
                    isFocused ? Color.accentColor : Color.clear,
                    lineWidth: 1.5
                )
            }
            .frame(width: width, height: 44)
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
            .frame(width: width, height: 38)
            .background(workoutTertiaryFill, in: slotShape)
            .frame(width: width, height: 44)
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
            String(
                localized: "第 \(index + 1) 组，\(exerciseSet.isCompleted ? String(localized: "已完成", comment: "Completed") : String(localized: "未完成", comment: "Incomplete"))",
                comment: "Set completion button a11y label"
            )
        )
    }

    private func toggleSetType() {
        exerciseSet.setType = exerciseSet.setType == .warmup ? .working : .warmup
    }

    private func toggleCompleted() {
        let wasCompleted = exerciseSet.isCompleted
        exerciseSet.isCompleted.toggle()
        if !wasCompleted {
            HapticManager.trigger(.setCompleted)
        }
        onToggleCompleted(wasCompleted)
    }

    private func handleLeftAction(_ action: LeftKeyAction, field: SetField) {
        switch action {
        case .addDropSet:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onAddSubSet(.dropSet)
        case .addPyramidSet:
            onAddSubSet(.pyramid)
        case .toggleUnilateral:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.setCompleted)
            #endif
            Self.toggleExerciseWeightMode(from: exerciseSet)
            refreshInputText()
        case .setWarmup:
            toggleSetType()
        case .addSet:
            if let owner = exerciseSet.workoutExercise {
                _ = ActiveExerciseSection.insertAppendedMainSet(in: owner, using: modelContext)
            }
        case .toggleWeightUnit:
            let next: WeightUnit = weightUnit == .kg ? .lb : .kg
            UserDefaults.standard.set(next.rawValue, forKey: "weightUnit")
        case .copyToNext:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onCopyToNext()
        case .applyAISuggestion:
            if let advice = resolvedAdvice {
                WorkoutDualModeEngine.applyProgressionAdvice(advice, to: exerciseSet)
                refreshInputText()
            }
        case .decreaseWeightFive:
            adjustWeight(by: -5, field: field)
        case .decreaseWeightTwoPointFive:
            adjustWeight(by: -2.5, field: field)
        case .increaseWeightTwoPointFive:
            adjustWeight(by: 2.5, field: field)
        case .increaseWeightFive:
            adjustWeight(by: 5, field: field)
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

    private func handlePresetReps(weightKg: Double?, reps: Int) {
        if let weightKg {
            exerciseSet.weight = weightKg
            if exerciseSet.isUnilateral {
                exerciseSet.weightRight = weightKg
            }
        }
        exerciseSet.reps = reps
        refreshInputText()
    }

    static func toggleExerciseWeightMode(from targetSet: ExerciseSet) {
        let unilateral = !targetSet.isUnilateral
        for row in targetSet.workoutExercise?.sets ?? [targetSet] {
            row.isUnilateral = unilateral
            if unilateral, row.weightRight == nil {
                row.weightRight = row.weight
            }
        }
    }

    private func refreshInputText(preservingFocusedField: SetField? = nil) {
        if preservingFocusedField != .weight {
            weightText = formatWeight(WorkoutDualModeEngine.displayWeight(exerciseSet.weight, unit: weightUnit))
        }
        if preservingFocusedField != .weightRight {
            let right = exerciseSet.weightRight ?? exerciseSet.weight
            weightRightText = exerciseSet.isUnilateral
                ? formatWeight(WorkoutDualModeEngine.displayWeight(right, unit: weightUnit))
                : ""
        }
        if preservingFocusedField != .reps {
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    private func syncWeightToModel() {
        let current = WorkoutDualModeEngine.displayWeight(exerciseSet.weight, unit: weightUnit)
        guard weightText != formatWeight(current) else { return }
        if weightText.isEmpty {
            exerciseSet.weight = 0
            return
        }
        guard let parsed = Double(weightText), parsed.isFinite, parsed >= 0 else { return }
        exerciseSet.weight = weightUnit == .lb ? parsed / 2.20462 : parsed
    }

    private func syncWeightRightToModel() {
        let current = exerciseSet.weightRight ?? exerciseSet.weight
        guard weightRightText != formatWeight(WorkoutDualModeEngine.displayWeight(current, unit: weightUnit)) else { return }
        if weightRightText.isEmpty {
            exerciseSet.weightRight = nil
            return
        }
        guard let parsed = Double(weightRightText), parsed.isFinite, parsed >= 0 else { return }
        exerciseSet.weightRight = weightUnit == .lb ? parsed / 2.20462 : parsed
    }

    private func syncRepsToModel() {
        if repsText.isEmpty {
            exerciseSet.reps = 0
            return
        }
        guard let parsed = Int(repsText), parsed >= 0 else { return }
        exerciseSet.reps = parsed
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
        value == 0 ? "" : formatDisplay(value)
    }

    private func formatDisplay(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
