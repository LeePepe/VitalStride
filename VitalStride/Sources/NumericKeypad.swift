import SwiftUI

enum NumericKeypadMode: Sendable {
    case decimal
    case integer
}

enum NumericKeypadKey: Equatable, Sendable {
    case digit(Int)
    case decimal
    case delete

    var label: String {
        switch self {
        case .digit(let n): "\(n)"
        case .decimal: "."
        case .delete: "⌫"
        }
    }

    var a11yLabel: String {
        switch self {
        case .digit(let n): "\(n)"
        case .decimal: "小数点"
        case .delete: "删除"
        }
    }
}

enum NumericKeypadInputHandler {
    static func handleKeyPress(
        _ key: NumericKeypadKey,
        currentText: String,
        mode: NumericKeypadMode
    ) -> String {
        switch key {
        case .digit(let n):
            return currentText + "\(n)"
        case .decimal:
            guard mode == .decimal, !currentText.contains(".") else {
                return currentText
            }
            return currentText + "."
        case .delete:
            guard !currentText.isEmpty else { return currentText }
            return String(currentText.dropLast())
        }
    }
}

#if canImport(UIKit)
import UIKit

struct NumericKeypad: View {
    let mode: NumericKeypadMode
    let onKeyPress: @MainActor (NumericKeypadKey) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private static let feedbackGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(1...9, id: \.self) { digit in
                    keyButton(.digit(digit))
                }
                decimalKeySlot
                keyButton(.digit(0))
                keyButton(.delete)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var decimalKeySlot: some View {
        switch mode {
        case .decimal:
            keyButton(.decimal)
        case .integer:
            Color.clear
                .frame(minHeight: 48)
                .accessibilityHidden(true)
        }
    }

    private func keyButton(_ key: NumericKeypadKey) -> some View {
        Button {
            Self.feedbackGenerator.impactOccurred()
            onKeyPress(key)
        } label: {
            Text(key.label)
                .font(.title2)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(keyBackground(key))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.a11yLabel)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private func keyBackground(_ key: NumericKeypadKey) -> Color {
        switch key {
        case .delete: Color(uiColor: .systemGray4)
        default: Color(uiColor: .systemBackground)
        }
    }
}
#endif
