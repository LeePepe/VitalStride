import Foundation

public struct OverviewInsight: Codable, Sendable, Equatable {
    public let key: String
    public let cardType: String
    public let cardSize: String
    public let title: String
    public let content: String
    public let suggestion: String?
    public let iconName: String?

    public init(
        key: String,
        cardType: String,
        cardSize: String,
        title: String,
        content: String,
        suggestion: String? = nil,
        iconName: String? = nil
    ) {
        self.key = key
        self.cardType = cardType
        self.cardSize = cardSize
        self.title = title
        self.content = content
        self.suggestion = suggestion
        self.iconName = iconName
    }
}
