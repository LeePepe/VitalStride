import Foundation

public struct DataAnalysis: Codable, Sendable, Equatable {
    public let sampleType: String
    public let summary: String
    public let trend: String
    public let suggestion: String?

    public init(
        sampleType: String,
        summary: String,
        trend: String,
        suggestion: String? = nil
    ) {
        self.sampleType = sampleType
        self.summary = summary
        self.trend = trend
        self.suggestion = suggestion
    }
}
