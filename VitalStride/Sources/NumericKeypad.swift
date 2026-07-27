import DesignKit
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
        case .decimal: String(localized: "numeric_keypad.decimal", defaultValue: "Decimal", comment: "Numeric keypad decimal key a11y label")
        case .delete: String(localized: "numeric_keypad.delete", defaultValue: "Delete", comment: "Numeric keypad delete key a11y label")
        }
    }
}

enum NumericKeypadInputHandler {
    /// Result of a selection-aware key press: the new text plus the caret
    /// position (UTF-16 offset in `text`) where the cursor should land.
    struct Result: Equatable, Sendable {
        var text: String
        var cursor: Int
    }

    /// Legacy append-at-end handler. Kept for callers / tests that don't yet
    /// carry a selection range. Equivalent to
    /// `handleKeyPress(_:currentText:selection:mode:)` with an empty selection
    /// pinned at the end of `currentText`.
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

    /// Selection-aware handler (MY-1341 / MY-1346).
    ///
    /// `selection` is expressed in UTF-16 offsets into `currentText` — the same
    /// unit `UITextField.selectedTextRange` reports through
    /// `textField.offset(from:to:)`. Semantics:
    ///
    /// - Non-empty selection + digit / decimal: replace the selected substring
    ///   with the inserted character; caret lands after the insertion.
    /// - Non-empty selection + delete: drop the selected substring; caret lands
    ///   at the start of what used to be the selection.
    /// - Decimal mode: decimal insert is a no-op when the *unselected* part of
    ///   the text already contains a dot (avoids duplicate `.`); integer mode
    ///   drops decimal presses entirely.
    /// - Empty selection: preserves the legacy append-at-end / backspace-from-end
    ///   behavior of `handleKeyPress(_:currentText:mode:)`; caret lands at the
    ///   end of the new text.
    static func handleKeyPress(
        _ key: NumericKeypadKey,
        currentText: String,
        selection: Range<Int>,
        mode: NumericKeypadMode
    ) -> Result {
        let length = currentText.utf16.count
        let clampedLower = max(0, min(selection.lowerBound, length))
        let clampedUpper = max(clampedLower, min(selection.upperBound, length))
        let hasSelection = clampedLower < clampedUpper

        guard hasSelection else {
            let next = handleKeyPress(key, currentText: currentText, mode: mode)
            return Result(text: next, cursor: next.utf16.count)
        }

        let (prefix, suffix) = splitByUTF16(
            currentText,
            lower: clampedLower,
            upper: clampedUpper
        )

        switch key {
        case .digit(let n):
            let replacement = "\(n)"
            let text = prefix + replacement + suffix
            let cursor = prefix.utf16.count + replacement.utf16.count
            return Result(text: text, cursor: cursor)
        case .decimal:
            guard mode == .decimal else {
                // Integer mode: swallow the press but collapse selection to end
                // of what was previously selected, matching legacy no-op feel.
                return Result(text: currentText, cursor: clampedUpper)
            }
            let remaining = prefix + suffix
            guard !remaining.contains(".") else {
                return Result(text: currentText, cursor: clampedUpper)
            }
            let replacement = "."
            let text = prefix + replacement + suffix
            let cursor = prefix.utf16.count + replacement.utf16.count
            return Result(text: text, cursor: cursor)
        case .delete:
            let text = prefix + suffix
            let cursor = prefix.utf16.count
            return Result(text: text, cursor: cursor)
        }
    }

    /// Split `text` into (prefix, suffix) around a UTF-16 offset range. Inputs
    /// to the custom keypad are ASCII digits + optional `.`, so UTF-16 offsets
    /// always align with `String.Index` boundaries; the fallback still guards
    /// against unexpected input.
    private static func splitByUTF16(
        _ text: String,
        lower: Int,
        upper: Int
    ) -> (prefix: String, suffix: String) {
        let utf16 = text.utf16
        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: lower)
        let upperUTF16 = utf16.index(utf16.startIndex, offsetBy: upper)
        guard
            let startIdx = lowerUTF16.samePosition(in: text),
            let endIdx = upperUTF16.samePosition(in: text)
        else {
            // Fallback: treat as no selection to avoid corrupting user text on
            // an unexpected non-ASCII paste.
            return (text, "")
        }
        return (String(text[text.startIndex..<startIdx]), String(text[endIdx..<text.endIndex]))
    }
}

#if canImport(UIKit)
import UIKit

struct NumericKeypad: View {
    @Environment(\.theme) private var theme
    let mode: NumericKeypadMode
    let onKeyPress: @MainActor (NumericKeypadKey) -> Void

    // Visual constants — north-star §11.
    private static let gridSpacing: CGFloat = 8
    private static let digitMinHeight: CGFloat = 52
    private static let keyRadius: CGFloat = Radius.inner // 10

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.gridSpacing) {
            ForEach(1...9, id: \.self) { digit in
                keyButton(.digit(digit))
            }
            decimalKeySlot
            keyButton(.digit(0))
            keyButton(.delete)
        }
        .background(theme.neutrals.bg)
        .accessibilityElement(children: .contain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var decimalKeySlot: some View {
        switch mode {
        case .decimal:
            keyButton(.decimal)
        case .integer:
            Color.clear
                .frame(minHeight: Self.digitMinHeight)
                .accessibilityHidden(true)
        }
    }

    private func keyButton(_ key: NumericKeypadKey) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onKeyPress(key)
        } label: {
            Text(key.label)
                .font(TypeScale.title)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(keyForeground(key))
                .frame(maxWidth: .infinity, minHeight: Self.digitMinHeight)
                .background(theme.neutrals.inner)
                .clipShape(RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.a11yLabel)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private func keyForeground(_ key: NumericKeypadKey) -> Color {
        switch key {
        // Red line (north-star §11.5): digit keys must never fade to text2/text3.
        // Delete key softens one step to text2.
        case .delete: theme.neutrals.text2
        default: theme.neutrals.text1
        }
    }
}
#endif
