#if canImport(UIKit)
import SwiftUI
import UIKit
import VitalModels

struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var font: UIFont = .preferredFont(forTextStyle: .body)

    // MARK: MY-1073 — custom keyboard wiring
    /// When non-nil, the text field's `inputView` is replaced with the shared
    /// `WorkoutNumericKeyboard` UIView instead of the system numeric keyboard.
    /// The keyboard is retained by the coordinator so it survives across
    /// `updateUIView` cycles.
    var customKeyboard: WorkoutNumericKeyboard?
    /// Which set field is being edited. Passed through to the keyboard on
    /// focus so it can render the correct digit set + preset keys.
    var field: SetField = .weight
    /// Optional exercise context — required for preset weight resolution.
    var exercise: Exercise?
    /// Set type of the row being edited — controls left-column key enablement
    /// (pyramid/dropSet only available for `.working`).
    var setType: SetType = .working
    /// Most recent same-exercise weight (kg) used as preset fallback when the
    /// exercise has no seeded default for the tapped bucket.
    var recentWeightKg: Double?
    /// Called when a left-column function key fires.
    var onLeftAction: ((LeftKeyAction) -> Void)?
    /// Called when a right-column preset key fires. `weightKg` is nil when no
    /// value is available and the caller MUST preserve the existing input.
    var onPresetReps: ((Double?, Int) -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.font = font
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .roundedRect
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        context.coordinator.attach(textField: textField)
        context.coordinator.installCustomKeyboardIfNeeded(customKeyboard, on: textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        if textField.placeholder != placeholder {
            textField.placeholder = placeholder
        }
        if textField.keyboardType != keyboardType {
            textField.keyboardType = keyboardType
        }
        if textField.font != font {
            textField.font = font
        }
        context.coordinator.update(
            field: field,
            setType: setType,
            exercise: exercise,
            recentWeightKg: recentWeightKg,
            onLeftAction: onLeftAction,
            onPresetReps: onPresetReps
        )
        context.coordinator.installCustomKeyboardIfNeeded(customKeyboard, on: textField)
        context.coordinator.refreshCustomKeyboardContextIfInstalled()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            field: field,
            setType: setType,
            exercise: exercise,
            recentWeightKg: recentWeightKg,
            onLeftAction: onLeftAction,
            onPresetReps: onPresetReps
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        private var field: SetField
        private var setType: SetType
        private var exercise: Exercise?
        private var recentWeightKg: Double?
        private var onLeftAction: ((LeftKeyAction) -> Void)?
        private var onPresetReps: ((Double?, Int) -> Void)?

        private weak var textField: UITextField?
        private var installedKeyboard: WorkoutNumericKeyboard?

        init(
            text: Binding<String>,
            field: SetField,
            setType: SetType,
            exercise: Exercise?,
            recentWeightKg: Double?,
            onLeftAction: ((LeftKeyAction) -> Void)?,
            onPresetReps: ((Double?, Int) -> Void)?
        ) {
            self.text = text
            self.field = field
            self.setType = setType
            self.exercise = exercise
            self.recentWeightKg = recentWeightKg
            self.onLeftAction = onLeftAction
            self.onPresetReps = onPresetReps
        }

        @objc func textChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func attach(textField: UITextField) {
            self.textField = textField
        }

        func update(
            field: SetField,
            setType: SetType,
            exercise: Exercise?,
            recentWeightKg: Double?,
            onLeftAction: ((LeftKeyAction) -> Void)?,
            onPresetReps: ((Double?, Int) -> Void)?
        ) {
            self.field = field
            self.setType = setType
            self.exercise = exercise
            self.recentWeightKg = recentWeightKg
            self.onLeftAction = onLeftAction
            self.onPresetReps = onPresetReps
        }

        /// Install the custom keyboard as `inputView` on first sight. We only
        /// swap once — SwiftUI recreates the representable's struct on every
        /// update, but the coordinator (and thus the retained keyboard) is
        /// stable, so we install exactly once and keep the same UIView.
        func installCustomKeyboardIfNeeded(
            _ keyboard: WorkoutNumericKeyboard?,
            on textField: UITextField
        ) {
            guard let keyboard, installedKeyboard !== keyboard else { return }
            installedKeyboard = keyboard
            textField.inputView = keyboard
            // Route digit key presses into the focused text field's binding.
            keyboard.onKeyPress = { [weak self, weak textField] key in
                guard let self, let textField else { return }
                self.handleKeyPress(key, on: textField)
            }
            keyboard.onLeftActionOverride = { [weak self] action in
                self?.onLeftAction?(action)
            }
            keyboard.onPresetRepsOverride = { [weak self] weightKg, reps in
                self?.onPresetReps?(weightKg, reps)
            }
            keyboard.onDoneOverride = { [weak textField] in
                textField?.resignFirstResponder()
            }
            // Force the input view to swap in on next focus.
            if textField.isFirstResponder {
                textField.reloadInputViews()
            }
        }

        /// Re-push the current row context into the retained keyboard so the
        /// SwiftUI content view redraws with the right field / setType /
        /// exercise / recent-weight values.
        func refreshCustomKeyboardContextIfInstalled() {
            installedKeyboard?.update(
                field: field,
                setType: setType,
                exercise: exercise,
                recentWeightKg: recentWeightKg
            )
        }

        private func handleKeyPress(_ key: NumericKeypadKey, on textField: UITextField) {
            let current = textField.text ?? ""
            let mode: NumericKeypadMode = field.isDecimalEnabled ? .decimal : .integer
            let next = NumericKeypadInputHandler.handleKeyPress(key, currentText: current, mode: mode)
            guard next != current else { return }
            textField.text = next
            text.wrappedValue = next
        }
    }
}
#endif
