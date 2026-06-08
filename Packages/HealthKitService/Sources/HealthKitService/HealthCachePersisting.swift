import Foundation

public struct PersistedCacheEntry: Sendable {
    public let sampleType: String
    public let dataPointsData: Data
    public let fetchedAt: Date
    public let coveredRangeStart: Date?
    public let coveredRangeEnd: Date?

    public init(
        sampleType: String,
        dataPointsData: Data,
        fetchedAt: Date,
        coveredRangeStart: Date?,
        coveredRangeEnd: Date?
    ) {
        self.sampleType = sampleType
        self.dataPointsData = dataPointsData
        self.fetchedAt = fetchedAt
        self.coveredRangeStart = coveredRangeStart
        self.coveredRangeEnd = coveredRangeEnd
    }
}

public protocol HealthCachePersisting: Sendable {
    func loadAll() async throws -> [PersistedCacheEntry]
    func load(sampleType: String) async throws -> PersistedCacheEntry?
    func upsert(_ entry: PersistedCacheEntry) async throws
    func deleteAll() async throws
}
