import Foundation
import os

// MARK: - HealthDataProviding

public protocol HealthDataProviding: Sendable {
    func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult
}

extension HealthKitService: HealthDataProviding {}

// MARK: - CacheTelemetry

public struct CacheTelemetry: Sendable, Equatable {
    public let hits: Int
    public let misses: Int
    public let refreshes: Int

    public init(hits: Int, misses: Int, refreshes: Int) {
        self.hits = hits
        self.misses = misses
        self.refreshes = refreshes
    }
}

// MARK: - HealthDataCache

public actor HealthDataCache {

    private struct CacheEntry {
        let dataPoints: [HealthDataPoint]
        let coveredRange: DateInterval?
        let fetchedAt: Date
    }

    private struct FetchKey: Hashable {
        let sampleType: HealthSampleType
        let rangeStart: Date?
        let rangeEnd: Date?

        init(_ sampleType: HealthSampleType, _ dateRange: DateInterval?) {
            self.sampleType = sampleType
            self.rangeStart = dateRange?.start
            self.rangeEnd = dateRange?.end
        }
    }

    public static let defaultTTL: TimeInterval = 3600

    private var cache: [HealthSampleType: CacheEntry] = [:]
    private var inFlightFetches: [FetchKey: Task<[HealthDataPoint], any Error>] = [:]
    private var backgroundRefreshTasks: [HealthSampleType: Task<Void, Never>] = [:]
    private let dataProvider: any HealthDataProviding
    private let persistence: (any HealthCachePersisting)?
    private let cacheTTL: TimeInterval
    private var generation: UInt64 = 0

    private var hitCounts: [HealthSampleType: Int] = [:]
    private var missCounts: [HealthSampleType: Int] = [:]
    private var refreshCounts: [HealthSampleType: Int] = [:]

    private let logger = Logger(subsystem: "com.vitalstride", category: "HealthDataCache")
    private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "HealthDataCache")
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        dataProvider: any HealthDataProviding,
        persistence: (any HealthCachePersisting)? = nil,
        cacheTTL: TimeInterval = HealthDataCache.defaultTTL
    ) {
        self.dataProvider = dataProvider
        self.persistence = persistence
        self.cacheTTL = cacheTTL
    }

    // MARK: - Hydration

    public func hydrate(types: Set<HealthSampleType>? = nil) async {
        guard let persistence else { return }
        do {
            let entries: [PersistedCacheEntry]
            if let types {
                entries = try await loadEntries(for: types, from: persistence)
            } else {
                entries = try await persistence.loadAll()
            }
            var hydratedCount = 0
            for entry in entries {
                guard let sampleType = HealthSampleType(rawValue: entry.sampleType) else { continue }
                guard let decoded = decodePersisted(entry) else { continue }
                cache[sampleType] = CacheEntry(
                    dataPoints: decoded.dataPoints,
                    coveredRange: decoded.coveredRange,
                    fetchedAt: entry.fetchedAt
                )
                hydratedCount += 1
            }
            logger.info("hydrated \(hydratedCount) entries from persistence")
        } catch {
            logger.info("persistence hydration failed")
        }
    }

    private func loadEntries(
        for types: Set<HealthSampleType>,
        from persistence: any HealthCachePersisting
    ) async throws -> [PersistedCacheEntry] {
        var results: [PersistedCacheEntry] = []
        for type in types {
            if let entry = try await persistence.load(sampleType: type.rawValue) {
                results.append(entry)
            }
        }
        return results
    }

    // MARK: - Query

    public func data(
        for sampleType: HealthSampleType,
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthDataPoint] {
        if let entry = cache[sampleType], Self.coversRange(entry.coveredRange, requested: dateRange) {
            hitCounts[sampleType, default: 0] += 1
            let stale = Self.isStale(entry.fetchedAt, ttl: cacheTTL)
            logger.info(
                "healthkit_cache_hit type=\(sampleType.rawValue) stale=\(stale) total=\(self.hitCounts[sampleType, default: 0])"
            )
            if stale {
                scheduleBackgroundRefresh(sampleType: sampleType, dateRange: entry.coveredRange)
            }
            return Self.filtered(entry.dataPoints, by: dateRange)
        }

        if let persistence, let persisted = try? await persistence.load(sampleType: sampleType.rawValue),
           let decoded = decodePersisted(persisted),
           Self.coversRange(decoded.coveredRange, requested: dateRange)
        {
            let entry = CacheEntry(
                dataPoints: decoded.dataPoints,
                coveredRange: decoded.coveredRange,
                fetchedAt: persisted.fetchedAt
            )
            cache[sampleType] = entry
            hitCounts[sampleType, default: 0] += 1
            logger.info(
                "healthkit_cache_l2_hit type=\(sampleType.rawValue) total=\(self.hitCounts[sampleType, default: 0])"
            )
            if Self.isStale(persisted.fetchedAt, ttl: cacheTTL) {
                scheduleBackgroundRefresh(sampleType: sampleType, dateRange: decoded.coveredRange)
            }
            return Self.filtered(decoded.dataPoints, by: dateRange)
        }

        missCounts[sampleType, default: 0] += 1
        logger.info(
            "healthkit_cache_miss type=\(sampleType.rawValue) total=\(self.missCounts[sampleType, default: 0])"
        )

        let points = try await fetchCoalesced(sampleType: sampleType, dateRange: dateRange)
        return Self.filtered(points, by: dateRange)
    }

    // MARK: - Refresh

    public func refresh(
        _ sampleType: HealthSampleType,
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthDataPoint] {
        cancelInFlightFetches(for: sampleType)

        refreshCounts[sampleType, default: 0] += 1
        logger.info(
            "healthkit_cache_refresh type=\(sampleType.rawValue) total=\(self.refreshCounts[sampleType, default: 0])"
        )

        let points = try await performFetch(sampleType: sampleType, dateRange: dateRange)
        return Self.filtered(points, by: dateRange)
    }

    // MARK: - Invalidation

    public func invalidate(_ sampleType: HealthSampleType) {
        cache[sampleType] = nil
        cancelInFlightFetches(for: sampleType)
        logger.info("cache invalidated type=\(sampleType.rawValue)")
    }

    public func invalidateAll() {
        generation &+= 1
        cache = [:]
        for task in inFlightFetches.values { task.cancel() }
        inFlightFetches = [:]
        for task in backgroundRefreshTasks.values { task.cancel() }
        backgroundRefreshTasks = [:]
        resetTelemetry()
        logger.info("cache invalidated all")
    }

    // MARK: - Authorization

    public func handleAuthorizationRevoked() async {
        invalidateAll()
        if let persistence {
            do {
                try await persistence.deleteAll()
                logger.info("authorization revoked — cache and persistence cleared")
            } catch {
                logger.error("authorization revoked — cache cleared but persistence deleteAll failed: \(error)")
            }
        } else {
            logger.info("authorization revoked — cache cleared (no persistence)")
        }
    }

    public func handleAuthorizationRevoked(
        anchorStore: HealthKitAnchorStore,
        deviceIdentifier: String
    ) async {
        await handleAuthorizationRevoked()
        anchorStore.removeAllAnchors(for: deviceIdentifier)
        logger.info("anchors cleared for device=\(deviceIdentifier)")
    }

    // MARK: - Telemetry

    public func telemetry(for sampleType: HealthSampleType) -> CacheTelemetry {
        CacheTelemetry(
            hits: hitCounts[sampleType, default: 0],
            misses: missCounts[sampleType, default: 0],
            refreshes: refreshCounts[sampleType, default: 0]
        )
    }

    public func cachedTypes() -> Set<HealthSampleType> {
        Set(cache.keys)
    }

    // MARK: - Private — Fetch

    private func fetchCoalesced(
        sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> [HealthDataPoint] {
        let key = FetchKey(sampleType, dateRange)
        if let existingTask = inFlightFetches[key] {
            return try await existingTask.value
        }
        return try await performFetch(sampleType: sampleType, dateRange: dateRange)
    }

    private func performFetch(
        sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> [HealthDataPoint] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("healthkit_fetch", id: signpostID)
        let start = ContinuousClock.now
        let fetchGeneration = generation

        let key = FetchKey(sampleType, dateRange)
        let task = Task { [dataProvider] in
            try await dataProvider.fetchData(for: sampleType, dateRange: dateRange).dataPoints
        }
        inFlightFetches[key] = task

        do {
            let points = try await task.value
            inFlightFetches[key] = nil

            if generation == fetchGeneration {
                cache[sampleType] = CacheEntry(
                    dataPoints: points,
                    coveredRange: dateRange,
                    fetchedAt: Date()
                )
                persistInBackground(sampleType: sampleType, dataPoints: points, dateRange: dateRange, fetchGeneration: fetchGeneration)
            }

            signposter.endInterval("healthkit_fetch", state)
            logFetchDuration(sampleType: sampleType, count: points.count, start: start)
            return points
        } catch {
            inFlightFetches[key] = nil
            signposter.endInterval("healthkit_fetch", state)
            throw error
        }
    }

    // MARK: - Private — Persistence

    private func persistInBackground(
        sampleType: HealthSampleType,
        dataPoints: [HealthDataPoint],
        dateRange: DateInterval?,
        fetchGeneration: UInt64
    ) {
        guard let persistence else { return }
        guard let data = try? jsonEncoder.encode(dataPoints) else { return }

        let entry = PersistedCacheEntry(
            sampleType: sampleType.rawValue,
            dataPointsData: data,
            fetchedAt: Date(),
            coveredRangeStart: dateRange?.start,
            coveredRangeEnd: dateRange?.end
        )

        Task {
            guard self.generation == fetchGeneration else { return }
            do {
                try await persistence.upsert(entry)
            } catch {
                logger.info("persistence write failed type=\(sampleType.rawValue)")
            }
        }
    }

    private func decodePersisted(
        _ persisted: PersistedCacheEntry
    ) -> (dataPoints: [HealthDataPoint], coveredRange: DateInterval?)? {
        guard let dataPoints = try? jsonDecoder.decode(
            [HealthDataPoint].self,
            from: persisted.dataPointsData
        ) else {
            return nil
        }
        let coveredRange: DateInterval?
        if let start = persisted.coveredRangeStart, let end = persisted.coveredRangeEnd {
            coveredRange = DateInterval(start: start, end: end)
        } else {
            coveredRange = nil
        }
        return (dataPoints, coveredRange)
    }

    // MARK: - Private — Background Refresh

    private func scheduleBackgroundRefresh(
        sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) {
        guard backgroundRefreshTasks[sampleType] == nil else { return }
        let refreshGeneration = generation

        let task = Task {
            defer { backgroundRefreshTasks[sampleType] = nil }
            guard self.generation == refreshGeneration else { return }
            do {
                _ = try await performFetch(sampleType: sampleType, dateRange: dateRange)
                refreshCounts[sampleType, default: 0] += 1
                logger.info("background refresh completed type=\(sampleType.rawValue)")
            } catch {
                logger.info("background refresh failed type=\(sampleType.rawValue)")
            }
        }
        backgroundRefreshTasks[sampleType] = task
    }

    // MARK: - Private — Helpers

    private func cancelInFlightFetches(for sampleType: HealthSampleType) {
        let keysToRemove = inFlightFetches.keys.filter { $0.sampleType == sampleType }
        for key in keysToRemove {
            inFlightFetches[key]?.cancel()
            inFlightFetches[key] = nil
        }
    }

    private func logFetchDuration(
        sampleType: HealthSampleType,
        count: Int,
        start: ContinuousClock.Instant
    ) {
        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        logger.info(
            "healthkit_fetch_duration_ms type=\(sampleType.rawValue) ms=\(ms) count=\(count)"
        )
    }

    private func resetTelemetry() {
        hitCounts = [:]
        missCounts = [:]
        refreshCounts = [:]
    }

    private static func filtered(
        _ points: [HealthDataPoint],
        by dateRange: DateInterval?
    ) -> [HealthDataPoint] {
        guard let dateRange else { return points }
        return points.filter { dateRange.contains($0.startDate) }
    }

    private static func coversRange(
        _ cached: DateInterval?,
        requested: DateInterval?
    ) -> Bool {
        switch (cached, requested) {
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (cached?, requested?):
            return cached.start <= requested.start && cached.end >= requested.end
        }
    }

    private static func isStale(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) > ttl
    }
}
