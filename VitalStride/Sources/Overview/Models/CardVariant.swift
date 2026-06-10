import Foundation

public struct CardVariant: Codable, Sendable, Equatable, Hashable {
    public let size: CardSize
    public let type: CardType

    public init(size: CardSize, type: CardType) {
        self.size = size
        self.type = type
    }

    public static let validVariants: Set<CardVariant> = [
        CardVariant(size: .small, type: .metric),
        CardVariant(size: .small, type: .action),
        CardVariant(size: .medium, type: .metric),
        CardVariant(size: .medium, type: .trend),
        CardVariant(size: .medium, type: .insight),
        CardVariant(size: .wide, type: .insight),
        CardVariant(size: .wide, type: .list),
        CardVariant(size: .wide, type: .summary),
        CardVariant(size: .wide, type: .action),
        CardVariant(size: .wide, type: .trend),
        CardVariant(size: .large, type: .trend),
        CardVariant(size: .large, type: .list),
        CardVariant(size: .large, type: .summary),
    ]

    public static func isValid(size: CardSize, type: CardType) -> Bool {
        validVariants.contains(CardVariant(size: size, type: type))
    }
}
