import Foundation
import SwiftData

@Model
public final class HealthCacheEntry {
    #Unique<HealthCacheEntry>([\.sampleType, \.coveredRangeStart, \.coveredRangeEnd])

    public var sampleType: String = ""
    public var dataPointsData: Data = Data()
    public var fetchedAt: Date = Date()
    public var coveredRangeStart: Date?
    public var coveredRangeEnd: Date?

    public init(
        sampleType: String,
        dataPointsData: Data,
        fetchedAt: Date = Date(),
        coveredRangeStart: Date? = nil,
        coveredRangeEnd: Date? = nil
    ) {
        self.sampleType = sampleType
        self.dataPointsData = dataPointsData
        self.fetchedAt = fetchedAt
        self.coveredRangeStart = coveredRangeStart
        self.coveredRangeEnd = coveredRangeEnd
    }
}
