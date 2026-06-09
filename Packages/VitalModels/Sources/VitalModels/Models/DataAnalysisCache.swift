import Foundation
import SwiftData

@Model
public final class DataAnalysisCache {
    public var sampleType: String = ""
    public var contentJSON: String = ""
    public var generatedAt: Date = Date()
    public var expiresAt: Date = Date()

    public init(
        sampleType: String,
        contentJSON: String,
        generatedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.sampleType = sampleType
        self.contentJSON = contentJSON
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}
