import Foundation
import Testing
import AIService

@testable import VitalStride

@Suite("Card System Model Tests")
struct CardSystemModelTests {

    // MARK: - CardSize

    @Test("CardSize has all 4 expected cases")
    func cardSizeCaseCount() {
        #expect(CardSize.allCases.count == 4)
    }

    @Test("CardSize raw values match expected strings")
    func cardSizeRawValues() {
        #expect(CardSize.small.rawValue == "small")
        #expect(CardSize.medium.rawValue == "medium")
        #expect(CardSize.wide.rawValue == "wide")
        #expect(CardSize.large.rawValue == "large")
    }

    @Test("CardSize roundtrip from rawValue")
    func cardSizeRawValueRoundtrip() {
        for size in CardSize.allCases {
            #expect(CardSize(rawValue: size.rawValue) == size)
        }
    }

    @Test("CardSize invalid rawValue returns nil")
    func cardSizeInvalidRawValue() {
        #expect(CardSize(rawValue: "tiny") == nil)
        #expect(CardSize(rawValue: "SMALL") == nil)
        #expect(CardSize(rawValue: "") == nil)
    }

    @Test("CardSize JSON roundtrip")
    func cardSizeJSONRoundtrip() throws {
        for size in CardSize.allCases {
            let data = try JSONEncoder().encode(size)
            let decoded = try JSONDecoder().decode(CardSize.self, from: data)
            #expect(decoded == size)
        }
    }

    @Test("CardSize displayName is non-empty for all cases")
    func cardSizeDisplayNames() {
        for size in CardSize.allCases {
            #expect(!size.displayName.isEmpty)
        }
    }

    // MARK: - CardType

    @Test("CardType has all 6 expected cases")
    func cardTypeCaseCount() {
        #expect(CardType.allCases.count == 6)
    }

    @Test("CardType raw values match expected strings")
    func cardTypeRawValues() {
        #expect(CardType.metric.rawValue == "metric")
        #expect(CardType.trend.rawValue == "trend")
        #expect(CardType.insight.rawValue == "insight")
        #expect(CardType.list.rawValue == "list")
        #expect(CardType.summary.rawValue == "summary")
        #expect(CardType.action.rawValue == "action")
    }

    @Test("CardType roundtrip from rawValue")
    func cardTypeRawValueRoundtrip() {
        for type in CardType.allCases {
            #expect(CardType(rawValue: type.rawValue) == type)
        }
    }

    @Test("CardType invalid rawValue returns nil")
    func cardTypeInvalidRawValue() {
        #expect(CardType(rawValue: "chart") == nil)
        #expect(CardType(rawValue: "METRIC") == nil)
        #expect(CardType(rawValue: "") == nil)
    }

    @Test("CardType JSON roundtrip")
    func cardTypeJSONRoundtrip() throws {
        for type in CardType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(CardType.self, from: data)
            #expect(decoded == type)
        }
    }

    @Test("CardType displayName is non-empty for all cases")
    func cardTypeDisplayNames() {
        for type in CardType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    // MARK: - CardVariant Whitelist

    @Test("CardVariant whitelist contains 13 valid combinations")
    func cardVariantWhitelistCount() {
        #expect(CardVariant.validVariants.count == 13)
    }

    @Test("CardVariant isValid returns true for all whitelisted combinations")
    func cardVariantValidCombinations() {
        #expect(CardVariant.isValid(size: .small, type: .metric))
        #expect(CardVariant.isValid(size: .small, type: .action))
        #expect(CardVariant.isValid(size: .medium, type: .metric))
        #expect(CardVariant.isValid(size: .medium, type: .trend))
        #expect(CardVariant.isValid(size: .medium, type: .insight))
        #expect(CardVariant.isValid(size: .wide, type: .insight))
        #expect(CardVariant.isValid(size: .wide, type: .list))
        #expect(CardVariant.isValid(size: .wide, type: .summary))
        #expect(CardVariant.isValid(size: .wide, type: .action))
        #expect(CardVariant.isValid(size: .wide, type: .trend))
        #expect(CardVariant.isValid(size: .large, type: .trend))
        #expect(CardVariant.isValid(size: .large, type: .list))
        #expect(CardVariant.isValid(size: .large, type: .summary))
    }

    @Test("CardVariant isValid returns false for invalid combinations")
    func cardVariantInvalidCombinations() {
        #expect(!CardVariant.isValid(size: .small, type: .insight))
        #expect(!CardVariant.isValid(size: .small, type: .list))
        #expect(!CardVariant.isValid(size: .small, type: .summary))
        #expect(!CardVariant.isValid(size: .small, type: .trend))
        #expect(!CardVariant.isValid(size: .medium, type: .list))
        #expect(!CardVariant.isValid(size: .medium, type: .summary))
        #expect(!CardVariant.isValid(size: .medium, type: .action))
        #expect(!CardVariant.isValid(size: .large, type: .metric))
        #expect(!CardVariant.isValid(size: .large, type: .insight))
        #expect(!CardVariant.isValid(size: .large, type: .action))
        #expect(!CardVariant.isValid(size: .wide, type: .metric))
    }

    @Test("CardVariant JSON roundtrip")
    func cardVariantJSONRoundtrip() throws {
        let variant = CardVariant(size: .wide, type: .insight)
        let data = try JSONEncoder().encode(variant)
        let decoded = try JSONDecoder().decode(CardVariant.self, from: data)
        #expect(decoded == variant)
    }

    @Test("CardVariant Equatable and Hashable")
    func cardVariantEquatableHashable() {
        let a = CardVariant(size: .small, type: .metric)
        let b = CardVariant(size: .small, type: .metric)
        let c = CardVariant(size: .large, type: .trend)

        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - OverviewInsight Extension

    @Test("OverviewInsight parsedCardSize with valid value")
    func overviewInsightParsedCardSize() {
        let insight = OverviewInsight(
            key: "test", cardType: "metric", cardSize: "small",
            title: "T", content: "C"
        )
        #expect(insight.parsedCardSize == .small)
    }

    @Test("OverviewInsight parsedCardSize with invalid value returns nil")
    func overviewInsightParsedCardSizeInvalid() {
        let insight = OverviewInsight(
            key: "test", cardType: "metric", cardSize: "tiny",
            title: "T", content: "C"
        )
        #expect(insight.parsedCardSize == nil)
    }

    @Test("OverviewInsight parsedCardType with valid value")
    func overviewInsightParsedCardType() {
        let insight = OverviewInsight(
            key: "test", cardType: "insight", cardSize: "wide",
            title: "T", content: "C"
        )
        #expect(insight.parsedCardType == .insight)
    }

    @Test("OverviewInsight parsedCardType with invalid value returns nil")
    func overviewInsightParsedCardTypeInvalid() {
        let insight = OverviewInsight(
            key: "test", cardType: "chart", cardSize: "wide",
            title: "T", content: "C"
        )
        #expect(insight.parsedCardType == nil)
    }

    @Test("OverviewInsight isValidVariant with valid combination")
    func overviewInsightIsValidVariantTrue() {
        let insight = OverviewInsight(
            key: "test", cardType: "metric", cardSize: "small",
            title: "T", content: "C"
        )
        #expect(insight.isValidVariant)
    }

    @Test("OverviewInsight isValidVariant with invalid combination")
    func overviewInsightIsValidVariantFalse() {
        let insight = OverviewInsight(
            key: "test", cardType: "insight", cardSize: "small",
            title: "T", content: "C"
        )
        #expect(!insight.isValidVariant)
    }

    @Test("OverviewInsight isValidVariant with invalid cardSize string")
    func overviewInsightIsValidVariantInvalidSize() {
        let insight = OverviewInsight(
            key: "test", cardType: "metric", cardSize: "huge",
            title: "T", content: "C"
        )
        #expect(!insight.isValidVariant)
    }

    @Test("OverviewInsight isValidVariant with invalid cardType string")
    func overviewInsightIsValidVariantInvalidType() {
        let insight = OverviewInsight(
            key: "test", cardType: "unknown", cardSize: "small",
            title: "T", content: "C"
        )
        #expect(!insight.isValidVariant)
    }

    @Test("OverviewInsight isValidVariant with empty strings")
    func overviewInsightIsValidVariantEmptyStrings() {
        let insight = OverviewInsight(
            key: "test", cardType: "", cardSize: "",
            title: "T", content: "C"
        )
        #expect(!insight.isValidVariant)
    }

    @Test("All CardSize values parse correctly from OverviewInsight")
    func allCardSizesParseFromInsight() {
        for size in CardSize.allCases {
            let insight = OverviewInsight(
                key: "test", cardType: "metric", cardSize: size.rawValue,
                title: "T", content: "C"
            )
            #expect(insight.parsedCardSize == size)
        }
    }

    @Test("All CardType values parse correctly from OverviewInsight")
    func allCardTypesParseFromInsight() {
        for type in CardType.allCases {
            let insight = OverviewInsight(
                key: "test", cardType: type.rawValue, cardSize: "small",
                title: "T", content: "C"
            )
            #expect(insight.parsedCardType == type)
        }
    }
}
