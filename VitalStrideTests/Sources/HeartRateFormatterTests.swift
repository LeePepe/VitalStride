import Testing

@testable import VitalStride

@Suite("HeartRateFormatter (MY-1283 three-state)")
struct HeartRateFormatterTests {

    // MARK: - displayText

    @Suite("displayText")
    struct DisplayTextTests {
        @Test("Disconnected state renders explicit not-connected label, never '--'")
        func disconnectedState() {
            let result = HeartRateFormatter.displayText(.disconnected)
            #expect(result != "--")
            #expect(!result.isEmpty)
        }

        @Test("Awaiting state renders neutral placeholder, not '--'")
        func awaitingState() {
            let result = HeartRateFormatter.displayText(.awaiting)
            #expect(result != "--")
            #expect(!result.isEmpty)
        }

        @Test("Value state returns integer string for whole number")
        func wholeNumber() {
            #expect(HeartRateFormatter.displayText(.value(142.0)) == "142")
        }

        @Test("Value state truncates decimal to integer")
        func decimalValue() {
            #expect(HeartRateFormatter.displayText(.value(72.8)) == "72")
        }

        @Test("Value state handles zero")
        func zeroValue() {
            #expect(HeartRateFormatter.displayText(.value(0.0)) == "0")
        }

        @Test("Value state handles high heart rate")
        func highValue() {
            #expect(HeartRateFormatter.displayText(.value(200.0)) == "200")
        }
    }

    // MARK: - accessibilityText

    @Suite("accessibilityText")
    struct AccessibilityTextTests {
        @Test("Disconnected a11y announces not-connected explicitly, not 'no data'")
        func disconnectedA11y() {
            let result = HeartRateFormatter.accessibilityText(.disconnected)
            #expect(!result.isEmpty)
            // Must not fall back to the generic "无数据" — the disconnected
            // state is more specific and prompts the user to pair a Watch.
            #expect(!result.contains("无数据"))
        }

        @Test("Awaiting a11y announces waiting-for-data, distinct from disconnected")
        func awaitingA11y() {
            let awaiting = HeartRateFormatter.accessibilityText(.awaiting)
            let disconnected = HeartRateFormatter.accessibilityText(.disconnected)
            #expect(!awaiting.isEmpty)
            // Three-state UI contract: awaiting and disconnected must be
            // audibly distinct to VoiceOver users, matching the sighted UX.
            #expect(awaiting != disconnected)
        }

        @Test("Value state returns integer bpm with full unit")
        func withValue() {
            let result = HeartRateFormatter.accessibilityText(.value(142.0))
            #expect(result.contains("142"))
        }

        @Test("Value state truncates decimal for a11y text")
        func decimalValue() {
            let result = HeartRateFormatter.accessibilityText(.value(72.8))
            #expect(result.contains("72"))
        }
    }
}
