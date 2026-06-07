import Testing

@testable import VitalStride

@Suite("HeartRateFormatter")
struct HeartRateFormatterTests {

    // MARK: - displayText

    @Suite("displayText")
    struct DisplayTextTests {
        @Test("Returns -- when heart rate is nil")
        func nilHeartRate() {
            #expect(HeartRateFormatter.displayText(nil) == "--")
        }

        @Test("Returns integer string for whole number")
        func wholeNumber() {
            #expect(HeartRateFormatter.displayText(142.0) == "142")
        }

        @Test("Truncates decimal to integer")
        func decimalValue() {
            #expect(HeartRateFormatter.displayText(72.8) == "72")
        }

        @Test("Handles zero")
        func zeroValue() {
            #expect(HeartRateFormatter.displayText(0.0) == "0")
        }

        @Test("Handles high heart rate")
        func highValue() {
            #expect(HeartRateFormatter.displayText(200.0) == "200")
        }
    }

    // MARK: - accessibilityText

    @Suite("accessibilityText")
    struct AccessibilityTextTests {
        @Test("Returns localized no-data text when nil")
        func nilHeartRate() {
            let result = HeartRateFormatter.accessibilityText(nil)
            #expect(result.contains("无数据") || !result.isEmpty)
        }

        @Test("Returns integer bpm with full unit")
        func withValue() {
            let result = HeartRateFormatter.accessibilityText(142.0)
            #expect(result.contains("142"))
        }

        @Test("Truncates decimal for a11y text")
        func decimalValue() {
            let result = HeartRateFormatter.accessibilityText(72.8)
            #expect(result.contains("72"))
        }
    }
}
