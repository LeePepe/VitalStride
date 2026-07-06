import Foundation

public struct HRVAnomaly: Sendable {
    public enum Severity: String, Sendable, Codable, CaseIterable {
        case normal
        case mildLow
        case significantLow
        case critical
    }

    public let today: Double
    public let baseline: Double
    public let percentDeviation: Double
    public let severity: Severity
    public let suggestionKey: String

    public init(
        today: Double,
        baseline: Double,
        percentDeviation: Double,
        severity: Severity,
        suggestionKey: String
    ) {
        self.today = today
        self.baseline = baseline
        self.percentDeviation = percentDeviation
        self.severity = severity
        self.suggestionKey = suggestionKey
    }
}
