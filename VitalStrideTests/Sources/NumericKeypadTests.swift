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
