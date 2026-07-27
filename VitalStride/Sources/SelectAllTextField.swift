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
    /// When true, the coordinator lazily builds a `WorkoutNumericKeyboard`
    /// and installs it as the text field's `inputView`, replacing the system
    /// numeric keyboard. The keyboard is owned by the coordinator so it
    /// survives across `updateUIView` cycles.
    var useCustomKeyboard: Bool = false
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
        if useCustomKeyboard {
            context.coordinator.installCustomKeyboardIfNeeded(on: textField)
        }
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
        if useCustomKeyboard {
            context.coordinator.installCustomKeyboardIfNeeded(on: textField)
            context.coordinator.refreshCustomKeyboardContextIfInstalled()
        }
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

    @MainActor
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

        /// Build and install the custom keyboard on first sight. The keyboard
        /// is owned here — its callbacks capture `self` weakly so latest
        /// coordinator state (bindings, exercise, setType) always wins.
        func installCustomKeyboardIfNeeded(on textField: UITextField) {
            guard installedKeyboard == nil else { return }
            let keyboard = WorkoutNumericKeyboard(
                field: field,
                setType: setType,
                exercise: exercise,
                recentWeightKg: recentWeightKg,
                onKeyPress: { [weak self, weak textField] key in
                    guard let self, let textField else { return }
                    self.handleKeyPress(key, on: textField)
                },
                onLeftAction: { [weak self] action in
                    self?.onLeftAction?(action)
                },
                onPresetReps: { [weak self] weightKg, reps in
                    self?.onPresetReps?(weightKg, reps)
                },
                onDone: { [weak textField] in
                    textField?.resignFirstResponder()
                }
            )
            installedKeyboard = keyboard
            textField.inputView = keyboard
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
            let selection = selectedUTF16Range(in: textField, textLength: current.utf16.count)
            let result = NumericKeypadInputHandler.handleKeyPress(
                key,
                currentText: current,
                selection: selection,
                mode: mode
            )
            // No-op path (e.g. decimal press with duplicate `.` and no selection):
            // avoid disturbing the text or the caret.
            if result.text == current && result.cursor == selection.upperBound {
                return
            }
            textField.text = result.text
            text.wrappedValue = result.text
            setCaret(in: textField, atUTF16Offset: result.cursor)
        }

        /// UTF-16 offset range of `textField.selectedTextRange`, or an empty
        /// range at end-of-text if there is no selection. Falls back to
        /// end-of-text on any unexpected nil so callers always get a
        /// well-defined range.
        private func selectedUTF16Range(
            in textField: UITextField,
            textLength: Int
        ) -> Range<Int> {
            guard let selectedRange = textField.selectedTextRange else {
                return textLength..<textLength
            }
            let start = textField.offset(from: textField.beginningOfDocument, to: selectedRange.start)
            let end = textField.offset(from: textField.beginningOfDocument, to: selectedRange.end)
            let lower = max(0, min(start, textLength))
            let upper = max(lower, min(end, textLength))
            return lower..<upper
        }

        /// Place the caret at a UTF-16 offset. Clamped to text bounds.
        private func setCaret(in textField: UITextField, atUTF16Offset offset: Int) {
            let length = (textField.text ?? "").utf16.count
            let clamped = max(0, min(offset, length))
            if let position = textField.position(from: textField.beginningOfDocument, offset: clamped) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
        }
    }
}
#endif
