import Foundation
import SwiftData

@Model
public final class OverviewInsightCache {
    public var contentJSON: String = ""
    public var generatedAt: Date = Date()
    public var expiresAt: Date = Date()

    public init(
        contentJSON: String,
        generatedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.contentJSON = contentJSON
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}
