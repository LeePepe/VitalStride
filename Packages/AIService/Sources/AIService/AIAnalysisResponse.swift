import Foundation

public struct AIAnalysisResponse: Codable, Sendable, Equatable {
    public let headline: String?
    public let insights: [OverviewInsight]

    public init(headline: String? = nil, insights: [OverviewInsight]) {
        self.headline = headline
        self.insights = insights
    }
}
