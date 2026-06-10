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
}
