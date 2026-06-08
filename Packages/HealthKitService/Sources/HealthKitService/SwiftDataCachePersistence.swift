import Foundation
import SwiftData
import VitalModels

@ModelActor
public actor SwiftDataCachePersistence: HealthCachePersisting {

    public func loadAll() throws -> [PersistedCacheEntry] {
        let descriptor = FetchDescriptor<HealthCacheEntry>()
        let entries = try modelContext.fetch(descriptor)
        return entries.map { Self.toPersistedEntry($0) }
    }

    public func load(sampleType: String) throws -> PersistedCacheEntry? {
        var descriptor = FetchDescriptor<HealthCacheEntry>(
            predicate: #Predicate<HealthCacheEntry> { entry in
                entry.sampleType == sampleType
            }
        )
        descriptor.fetchLimit = 1
        descriptor.sortBy = [SortDescriptor(\.fetchedAt, order: .reverse)]
        return try modelContext.fetch(descriptor).first.map { Self.toPersistedEntry($0) }
    }

    public func upsert(_ entry: PersistedCacheEntry) throws {
        let targetType = entry.sampleType
        let existing = try modelContext.fetch(
            FetchDescriptor<HealthCacheEntry>(
                predicate: #Predicate<HealthCacheEntry> { e in
                    e.sampleType == targetType
                }
            )
        )
        for old in existing {
            modelContext.delete(old)
        }

        let newEntry = HealthCacheEntry(
            sampleType: entry.sampleType,
            dataPointsData: entry.dataPointsData,
            fetchedAt: entry.fetchedAt,
            coveredRangeStart: entry.coveredRangeStart,
            coveredRangeEnd: entry.coveredRangeEnd
        )
        modelContext.insert(newEntry)
        try modelContext.save()
    }

    public func deleteAll() throws {
        try modelContext.delete(model: HealthCacheEntry.self)
        try modelContext.save()
    }

    private static func toPersistedEntry(_ entry: HealthCacheEntry) -> PersistedCacheEntry {
        PersistedCacheEntry(
            sampleType: entry.sampleType,
            dataPointsData: entry.dataPointsData,
            fetchedAt: entry.fetchedAt,
            coveredRangeStart: entry.coveredRangeStart,
            coveredRangeEnd: entry.coveredRangeEnd
        )
    }
}
