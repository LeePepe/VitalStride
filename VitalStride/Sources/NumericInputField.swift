import SwiftUI

#if canImport(UIKit)
import UIKit

struct NumericInputField: UIViewRepresentable {
    @Binding var text: String
    let mode: NumericKeypadMode
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, mode: mode)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.textAlignment = .center
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = context.coordinator
        textField.text = text
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        context.coordinator.configureInputView(for: textField)

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        if textField.placeholder != placeholder {
            textField.placeholder = placeholder
        }
        context.coordinator.textBinding = $text
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var textBinding: Binding<String>
        let mode: NumericKeypadMode
        private var hostingController: UIHostingController<NumericKeypad>?

        init(text: Binding<String>, mode: NumericKeypadMode) {
            self.textBinding = text
            self.mode = mode
        }

        func configureInputView(for textField: UITextField) {
            let keypad = NumericKeypad(mode: mode) { [weak self, weak textField] key in
                guard let self, let textField else { return }
                let current = textField.text ?? ""
                let updated = NumericKeypadInputHandler.handleKeyPress(
                    key, currentText: current, mode: self.mode
                )
                textField.text = updated
                self.textBinding.wrappedValue = updated
            }
            let hc = UIHostingController(rootView: keypad)
            hc.view.autoresizingMask = [.flexibleWidth]
            hc.view.frame = CGRect(x: 0, y: 0, width: 0, height: 260)
            hc.view.backgroundColor = .systemGroupedBackground
            textField.inputView = hc.view
            self.hostingController = hc
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = textField.text ?? ""

            if string.isEmpty {
                guard let swiftRange = Range(range, in: current) else { return false }
                let updated = current.replacingCharacters(in: swiftRange, with: "")
                textField.text = updated
                textBinding.wrappedValue = updated
                return false
            }

            var result = current
            for char in string {
                if let digit = char.wholeNumberValue {
                    result = NumericKeypadInputHandler.handleKeyPress(
                        .digit(digit), currentText: result, mode: mode
                    )
                } else if char == "." {
                    result = NumericKeypadInputHandler.handleKeyPress(
                        .decimal, currentText: result, mode: mode
                    )
                }
            }
            textField.text = result
            textBinding.wrappedValue = result
            return false
        }
    }
}
#endif
