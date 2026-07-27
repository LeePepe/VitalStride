import Testing

@testable import VitalStride

@Suite("NumericKeypadInputHandler")
struct NumericKeypadInputHandlerTests {
    // MARK: - Digit append

    @Test("Appends digit to empty string")
    func appendDigitToEmpty() {
        let result = NumericKeypadInputHandler.handleKeyPress(.digit(5), currentText: "", mode: .decimal)
        #expect(result == "5")
    }

    @Test("Appends digit to existing text")
    func appendDigitToExisting() {
        let result = NumericKeypadInputHandler.handleKeyPress(.digit(3), currentText: "12", mode: .decimal)
        #expect(result == "123")
    }

    @Test("Appends zero")
    func appendZero() {
        let result = NumericKeypadInputHandler.handleKeyPress(.digit(0), currentText: "1", mode: .decimal)
        #expect(result == "10")
    }

    // MARK: - Decimal point

    @Test("Appends decimal point in decimal mode")
    func appendDecimal() {
        let result = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "12", mode: .decimal)
        #expect(result == "12.")
    }

    @Test("Prevents duplicate decimal point")
    func preventDuplicateDecimal() {
        let result = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "12.5", mode: .decimal)
        #expect(result == "12.5")
    }

    @Test("Decimal point on empty string")
    func decimalOnEmpty() {
        let result = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "", mode: .decimal)
        #expect(result == ".")
    }

    // MARK: - Integer mode

    @Test("Blocks decimal point in integer mode")
    func integerModeBlocksDecimal() {
        let result = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "12", mode: .integer)
        #expect(result == "12")
    }

    @Test("Digits work in integer mode")
    func integerModeAllowsDigits() {
        let result = NumericKeypadInputHandler.handleKeyPress(.digit(7), currentText: "3", mode: .integer)
        #expect(result == "37")
    }

    // MARK: - Delete

    @Test("Deletes last character")
    func deleteLast() {
        let result = NumericKeypadInputHandler.handleKeyPress(.delete, currentText: "123", mode: .decimal)
        #expect(result == "12")
    }

    @Test("Delete on empty string is no-op")
    func deleteOnEmpty() {
        let result = NumericKeypadInputHandler.handleKeyPress(.delete, currentText: "", mode: .decimal)
        #expect(result == "")
    }

    @Test("Delete removes decimal point")
    func deleteDecimalPoint() {
        let result = NumericKeypadInputHandler.handleKeyPress(.delete, currentText: "12.", mode: .decimal)
        #expect(result == "12")
    }

    @Test("Can add decimal after deleting previous decimal")
    func addDecimalAfterDelete() {
        let afterDelete = NumericKeypadInputHandler.handleKeyPress(.delete, currentText: "1.5", mode: .decimal)
        #expect(afterDelete == "1.")
        let afterDeleteAgain = NumericKeypadInputHandler.handleKeyPress(.delete, currentText: afterDelete, mode: .decimal)
        #expect(afterDeleteAgain == "1")
        let withNewDecimal = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: afterDeleteAgain, mode: .decimal)
        #expect(withNewDecimal == "1.")
    }

    // MARK: - Sequences

    @Test("Full weight entry sequence: 72.5")
    func weightEntrySequence() {
        var text = ""
        text = NumericKeypadInputHandler.handleKeyPress(.digit(7), currentText: text, mode: .decimal)
        text = NumericKeypadInputHandler.handleKeyPress(.digit(2), currentText: text, mode: .decimal)
        text = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: text, mode: .decimal)
        text = NumericKeypadInputHandler.handleKeyPress(.digit(5), currentText: text, mode: .decimal)
        #expect(text == "72.5")
    }

    @Test("Full reps entry sequence: 12")
    func repsEntrySequence() {
        var text = ""
        text = NumericKeypadInputHandler.handleKeyPress(.digit(1), currentText: text, mode: .integer)
        text = NumericKeypadInputHandler.handleKeyPress(.digit(2), currentText: text, mode: .integer)
        #expect(text == "12")
    }
}

// MARK: - Selection-aware handler (MY-1341 / MY-1346)

@Suite("NumericKeypadInputHandler (selection-aware)")
struct NumericKeypadInputHandlerSelectionTests {
    // Regression: MY-1341 repro. Text `60`, full selection, digit `8` => `8`.
    @Test("Repro: 60 fully selected + digit 8 replaces to 8")
    func fullSelectionReplacedByDigit() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(8),
            currentText: "60",
            selection: 0..<2,
            mode: .decimal
        )
        #expect(result.text == "8")
        #expect(result.cursor == 1)
    }

    @Test("Full selection + digit in integer mode replaces")
    func fullSelectionIntegerModeReplace() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(5),
            currentText: "12",
            selection: 0..<2,
            mode: .integer
        )
        #expect(result.text == "5")
        #expect(result.cursor == 1)
    }

    @Test("Full selection + decimal in decimal mode replaces")
    func fullSelectionDecimalReplace() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: "60",
            selection: 0..<2,
            mode: .decimal
        )
        #expect(result.text == ".")
        #expect(result.cursor == 1)
    }

    @Test("Full selection + decimal in integer mode is no-op, caret collapses")
    func fullSelectionDecimalIntegerNoOp() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: "60",
            selection: 0..<2,
            mode: .integer
        )
        #expect(result.text == "60")
        #expect(result.cursor == 2)
    }

    @Test("Full selection + delete clears text")
    func fullSelectionDeleteClears() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .delete,
            currentText: "72.5",
            selection: 0..<4,
            mode: .decimal
        )
        #expect(result.text == "")
        #expect(result.cursor == 0)
    }

    @Test("Partial selection + digit replaces only the selected range")
    func partialSelectionDigitReplaces() {
        // "1234", select "23" (range 1..<3), press 9 => "194"
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(9),
            currentText: "1234",
            selection: 1..<3,
            mode: .integer
        )
        #expect(result.text == "194")
        #expect(result.cursor == 2)
    }

    @Test("Partial selection + delete removes selection only")
    func partialSelectionDeleteRemovesSelectionOnly() {
        // "1234", select "23", delete => "14", caret at 1
        let result = NumericKeypadInputHandler.handleKeyPress(
            .delete,
            currentText: "1234",
            selection: 1..<3,
            mode: .integer
        )
        #expect(result.text == "14")
        #expect(result.cursor == 1)
    }

    @Test("Partial selection over decimal + decimal press allows re-insert")
    func selectionCoversExistingDecimalAllowsReinsert() {
        // "1.5", select "." (range 1..<2), press "." => "1.5", caret 2
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: "1.5",
            selection: 1..<2,
            mode: .decimal
        )
        #expect(result.text == "1.5")
        #expect(result.cursor == 2)
    }

    @Test("Partial selection outside existing decimal + decimal press is no-op")
    func selectionOutsideExistingDecimalIsNoOp() {
        // "1.5", select "5" (range 2..<3), press "." — remaining "1." already has ".",
        // so decimal is refused and caret collapses to end of selection.
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: "1.5",
            selection: 2..<3,
            mode: .decimal
        )
        #expect(result.text == "1.5")
        #expect(result.cursor == 3)
    }

    @Test("Empty selection at end preserves append behavior")
    func emptySelectionAtEndAppends() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(8),
            currentText: "60",
            selection: 2..<2,
            mode: .decimal
        )
        #expect(result.text == "608")
        #expect(result.cursor == 3)
    }

    @Test("Empty selection at end + delete preserves backspace behavior")
    func emptySelectionAtEndDeletes() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .delete,
            currentText: "608",
            selection: 3..<3,
            mode: .decimal
        )
        #expect(result.text == "60")
        #expect(result.cursor == 2)
    }

    @Test("Empty selection with duplicate decimal is no-op")
    func emptySelectionDuplicateDecimalNoOp() {
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: "12.5",
            selection: 4..<4,
            mode: .decimal
        )
        #expect(result.text == "12.5")
        #expect(result.cursor == 4)
    }

    @Test("Selection bounds are clamped to text length")
    func selectionBoundsClamped() {
        // Selection extends beyond text; should be clamped, not crash.
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(1),
            currentText: "ab",
            selection: 0..<99,
            mode: .integer
        )
        #expect(result.text == "1")
        #expect(result.cursor == 1)
    }
}

// MARK: - Coordinator guard regression (PR #353 P1 → MY-1346)

#if canImport(UIKit) && !os(macOS)

/// Regression coverage for the `SelectAllTextField.Coordinator` no-op guard.
///
/// The initial PR #353 short-circuited `handleKeyPress(_:on:)` whenever
/// `result.text == current && result.cursor == selection.upperBound`. That
/// condition is also true for a same-text press over a non-empty selection
/// (e.g. `"12"` with `"2"` selected + digit `2` → handler returns
/// `text=="12", cursor==2==selection.upperBound`), which meant the visual
/// highlight was retained and the NEXT key press would replace unrelated
/// content. Fix: only short-circuit on a truly empty selection.
@Suite("SelectAllTextField.Coordinator effect guard (PR #353 P1)")
@MainActor
struct SelectAllTextFieldCoordinatorEffectTests {
    typealias Coord = SelectAllTextField.Coordinator

    // Regression: selecting "2" in "12" and pressing "2" must collapse the
    // caret. Previously the guard returned early and the highlight persisted.
    @Test("Same-text digit press over selection collapses caret (regression)")
    func sameTextDigitOverSelectionCollapsesCaret() {
        let current = "12"
        let selection = 1..<2 // the trailing "2"
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(2),
            currentText: current,
            selection: selection,
            mode: .integer
        )
        // Handler is deterministic — same text, cursor at end of insertion.
        #expect(result.text == "12")
        #expect(result.cursor == 2)

        let effect = Coord.computeEffect(current: current, selection: selection, result: result)
        // Must produce an Effect (not nil) so the caller collapses the highlight.
        #expect(effect != nil)
        #expect(effect?.shouldWriteText == false) // text really is unchanged
        #expect(effect?.newText == "12")
        #expect(effect?.newCursor == 2) // caret collapsed to end of what was selected
    }

    // Same-text press over selection in decimal mode: same regression, decimal key.
    @Test("Same-text decimal press over selection collapses caret (decimal mode)")
    func sameTextDecimalOverSelectionCollapsesCaret() {
        let current = "1.5"
        let selection = 1..<2 // the "." character
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: current,
            selection: selection,
            mode: .decimal
        )
        #expect(result.text == "1.5")
        #expect(result.cursor == 2)

        let effect = Coord.computeEffect(current: current, selection: selection, result: result)
        #expect(effect != nil)
        #expect(effect?.shouldWriteText == false)
        #expect(effect?.newText == "1.5")
        #expect(effect?.newCursor == 2)
    }

    // Integer-mode decimal press over selection: handler returns text unchanged
    // with cursor at selection.upperBound. Must still collapse the highlight.
    @Test("Integer-mode decimal press over selection still collapses caret")
    func integerModeDecimalOverSelectionCollapsesCaret() {
        let current = "60"
        let selection = 0..<2
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: current,
            selection: selection,
            mode: .integer
        )
        #expect(result.text == "60") // integer mode swallows decimal
        #expect(result.cursor == 2)  // collapsed to end of previous selection

        let effect = Coord.computeEffect(current: current, selection: selection, result: result)
        #expect(effect != nil, "non-empty selection must never be a true no-op")
        #expect(effect?.shouldWriteText == false)
        #expect(effect?.newCursor == 2)
    }

    // Empty-selection duplicate-decimal press is still a genuine no-op — the
    // guard should return nil here so we don't perturb the caret needlessly.
    @Test("Empty selection duplicate decimal is a true no-op")
    func emptySelectionDuplicateDecimalIsNoOp() {
        let current = "12.5"
        let selection = 4..<4
        let result = NumericKeypadInputHandler.handleKeyPress(
            .decimal,
            currentText: current,
            selection: selection,
            mode: .decimal
        )
        #expect(result.text == "12.5")
        #expect(result.cursor == 4)

        let effect = Coord.computeEffect(current: current, selection: selection, result: result)
        #expect(effect == nil)
    }

    // A normal text-changing press still produces an Effect and writes text.
    @Test("Text-changing press produces write-text effect")
    func textChangingPressWritesText() {
        let current = "60"
        let selection = 0..<2
        let result = NumericKeypadInputHandler.handleKeyPress(
            .digit(8),
            currentText: current,
            selection: selection,
            mode: .decimal
        )
        let effect = Coord.computeEffect(current: current, selection: selection, result: result)
        #expect(effect != nil)
        #expect(effect?.shouldWriteText == true)
        #expect(effect?.newText == "8")
        #expect(effect?.newCursor == 1)
    }
}

#endif
