import Foundation

public struct HRVBaseline: Sendable {
    public let rollingMean: Double
    public let rollingStdDev: Double
    public let sampleCount: Int
    public let referenceDate: Date

    public init(
        rollingMean: Double,
        rollingStdDev: Double,
        sampleCount: Int,
        referenceDate: Date
    ) {
        self.rollingMean = rollingMean
        self.rollingStdDev = rollingStdDev
        self.sampleCount = sampleCount
        self.referenceDate = referenceDate
    }
}
