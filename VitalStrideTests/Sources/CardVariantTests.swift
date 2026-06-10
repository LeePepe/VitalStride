import Foundation
import Testing
import AIService

@testable import VitalStride

@Suite("CardVariantFactory Tests")
struct CardVariantFactoryTests {

    // MARK: - Factory dispatch for all 13 valid variants

    @Test("Factory.makeCard dispatches without crash for all 13 whitelisted variants")
    func factoryMakeCardDispatchesAllValid() {
        let validCombinations: [(String, String)] = [
            ("small", "metric"),
            ("small", "action"),
            ("medium", "metric"),
            ("medium", "trend"),
            ("medium", "insight"),
            ("wide", "insight"),
            ("wide", "list"),
            ("wide", "summary"),
            ("wide", "action"),
            ("wide", "trend"),
            ("large", "trend"),
            ("large", "list"),
            ("large", "summary"),
        ]

        for (size, type) in validCombinations {
            let insight = OverviewInsight(
                key: "test_\(size)_\(type)",
                cardType: type,
                cardSize: size,
                title: "Test",
                content: sampleContent(for: type)
            )
            #expect(insight.isValidVariant, "Expected \(size)×\(type) to be a valid variant")
            let _ = CardVariantFactory.makeCard(for: insight)
        }
    }

    @Test("Factory.makeCard handles invalid combinations gracefully")
    func factoryMakeCardHandlesInvalidCombinations() {
        let invalidCombinations: [(String, String)] = [
            ("small", "insight"),
            ("large", "metric"),
            ("tiny", "metric"),
            ("small", "chart"),
            ("", ""),
        ]

        for (size, type) in invalidCombinations {
            let insight = OverviewInsight(
                key: "test_\(size)_\(type)",
                cardType: type,
                cardSize: size,
                title: "Test",
                content: "content"
            )
            #expect(!insight.isValidVariant)
            let _ = CardVariantFactory.makeCard(for: insight)
        }
    }

    @Test("Factory.makeCard passes onAction to action cards")
    func factoryMakeCardPassesOnAction() {
        let insight = OverviewInsight(
            key: "action_test", cardType: "action", cardSize: "small",
            title: "Test", content: "Do something"
        )
        let _ = CardVariantFactory.makeCard(for: insight, onAction: { })
    }

    // MARK: - Helpers

    private func sampleContent(for type: String) -> String {
        switch type {
        case "metric":
            "8,543"
        case "trend":
            "[{\"date\":\"Mon\",\"value\":100},{\"date\":\"Tue\",\"value\":200}]"
        case "insight":
            "AI generated insight text"
        case "list":
            "[{\"label\":\"Item 1\",\"value\":\"10\"},{\"label\":\"Item 2\",\"value\":\"20\"}]"
        case "summary":
            "{\"Steps\":\"8K\",\"Calories\":\"500\"}"
        case "action":
            "Start your workout"
        default:
            "content"
        }
    }
}

@Suite("CardContentParser Tests")
struct CardContentParserTests {

    // MARK: - Trend Data

    @Test("parseTrendData with valid JSON array")
    func parseTrendDataValid() {
        let json = "[{\"date\":\"Mon\",\"value\":100},{\"date\":\"Tue\",\"value\":200}]"
        let result = CardContentParser.parseTrendData(json)
        #expect(result.count == 2)
        #expect(result[0].date == "Mon")
        #expect(result[0].value == 100)
        #expect(result[1].date == "Tue")
        #expect(result[1].value == 200)
    }

    @Test("parseTrendData with empty array")
    func parseTrendDataEmptyArray() {
        let result = CardContentParser.parseTrendData("[]")
        #expect(result.isEmpty)
    }

    @Test("parseTrendData with invalid JSON returns empty")
    func parseTrendDataInvalidJSON() {
        let result = CardContentParser.parseTrendData("not json")
        #expect(result.isEmpty)
    }

    @Test("parseTrendData with empty string returns empty")
    func parseTrendDataEmptyString() {
        let result = CardContentParser.parseTrendData("")
        #expect(result.isEmpty)
    }

    @Test("parseTrendData with wrong JSON shape returns empty")
    func parseTrendDataWrongShape() {
        let result = CardContentParser.parseTrendData("{\"key\":\"value\"}")
        #expect(result.isEmpty)
    }

    @Test("parseTrendData preserves decimal values")
    func parseTrendDataDecimalValues() {
        let json = "[{\"date\":\"Day1\",\"value\":3.14}]"
        let result = CardContentParser.parseTrendData(json)
        #expect(result.count == 1)
        #expect(result[0].value == 3.14)
    }

    // MARK: - List Items

    @Test("parseListItems with label-value objects")
    func parseListItemsLabelValue() {
        let json = "[{\"label\":\"Steps\",\"value\":\"8K\"},{\"label\":\"Cal\",\"value\":\"500\"}]"
        let result = CardContentParser.parseListItems(json)
        #expect(result.count == 2)
        #expect(result[0].label == "Steps")
        #expect(result[0].value == "8K")
        #expect(result[1].label == "Cal")
        #expect(result[1].value == "500")
    }

    @Test("parseListItems with label-only objects")
    func parseListItemsLabelOnly() {
        let json = "[{\"label\":\"Item 1\"},{\"label\":\"Item 2\"}]"
        let result = CardContentParser.parseListItems(json)
        #expect(result.count == 2)
        #expect(result[0].value == nil)
    }

    @Test("parseListItems with plain string array")
    func parseListItemsStringArray() {
        let json = "[\"First item\",\"Second item\",\"Third item\"]"
        let result = CardContentParser.parseListItems(json)
        #expect(result.count == 3)
        #expect(result[0].label == "First item")
        #expect(result[0].value == nil)
    }

    @Test("parseListItems with empty array")
    func parseListItemsEmptyArray() {
        let result = CardContentParser.parseListItems("[]")
        #expect(result.isEmpty)
    }

    @Test("parseListItems with invalid JSON returns empty")
    func parseListItemsInvalidJSON() {
        let result = CardContentParser.parseListItems("not json")
        #expect(result.isEmpty)
    }

    @Test("parseListItems with empty string returns empty")
    func parseListItemsEmptyString() {
        let result = CardContentParser.parseListItems("")
        #expect(result.isEmpty)
    }

    // MARK: - Summary Entries

    @Test("parseSummaryEntries with valid key-value dict")
    func parseSummaryEntriesValid() {
        let json = "{\"Steps\":\"8K\",\"Calories\":\"500\",\"Sleep\":\"7h\"}"
        let result = CardContentParser.parseSummaryEntries(json)
        #expect(result.count == 3)
        let keys = result.map(\.key)
        #expect(keys == keys.sorted())
    }

    @Test("parseSummaryEntries preserves key-value pairs")
    func parseSummaryEntriesPreservesData() {
        let json = "{\"Alpha\":\"100\",\"Beta\":\"200\"}"
        let result = CardContentParser.parseSummaryEntries(json)
        #expect(result.count == 2)
        #expect(result[0].key == "Alpha")
        #expect(result[0].value == "100")
        #expect(result[1].key == "Beta")
        #expect(result[1].value == "200")
    }

    @Test("parseSummaryEntries with empty object")
    func parseSummaryEntriesEmptyObject() {
        let result = CardContentParser.parseSummaryEntries("{}")
        #expect(result.isEmpty)
    }

    @Test("parseSummaryEntries with invalid JSON returns empty")
    func parseSummaryEntriesInvalidJSON() {
        let result = CardContentParser.parseSummaryEntries("not json")
        #expect(result.isEmpty)
    }

    @Test("parseSummaryEntries with empty string returns empty")
    func parseSummaryEntriesEmptyString() {
        let result = CardContentParser.parseSummaryEntries("")
        #expect(result.isEmpty)
    }

    @Test("parseSummaryEntries with array JSON returns empty")
    func parseSummaryEntriesArrayJSON() {
        let result = CardContentParser.parseSummaryEntries("[\"a\",\"b\"]")
        #expect(result.isEmpty)
    }
}
