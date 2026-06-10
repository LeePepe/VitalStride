import AIService

extension OverviewInsight {
    public var parsedCardSize: CardSize? {
        CardSize(rawValue: cardSize)
    }

    public var parsedCardType: CardType? {
        CardType(rawValue: cardType)
    }

    public var isValidVariant: Bool {
        guard let size = parsedCardSize, let type = parsedCardType else {
            return false
        }
        return CardVariant.isValid(size: size, type: type)
    }

    public var effectiveCardSize: CardSize {
        guard let size = parsedCardSize, let type = parsedCardType else {
            return .medium
        }
        if CardVariant.isValid(size: size, type: type) {
            return size
        }
        return CardVariant.defaultSize(for: type)
    }

    public var effectiveCardType: CardType {
        parsedCardType ?? .insight
    }

    public var hasValidOrFallbackVariant: Bool {
        parsedCardType != nil
    }
}

extension CardVariant {
    public static func defaultSize(for type: CardType) -> CardSize {
        switch type {
        case .metric: return .medium
        case .insight: return .medium
        case .trend: return .medium
        case .summary: return .wide
        case .list: return .wide
        case .action: return .small
        }
    }
}
