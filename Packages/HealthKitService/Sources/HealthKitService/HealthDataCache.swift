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

// MARK: - WorkoutDataProviding

public protocol WorkoutDataProviding: Sendable {
    func fetchWorkouts(dateRange: DateInterval?) async throws -> WorkoutFetchResult
}

protocol WorkoutPreparedDataProviding: WorkoutDataProviding {
    func prepareWorkoutSnapshot(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch
    func prepareWorkoutChanges(dateRange: DateInterval?) async throws -> PreparedWorkoutFetch
    func acceptPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch)
    func rejectPreparedWorkoutFetch(_ prepared: PreparedWorkoutFetch)
}

extension HealthKitService: WorkoutDataProviding {}
extension HealthKitService: WorkoutPreparedDataProviding {}

// MARK: - AvailableTypesProbing

public protocol AvailableTypesProbing: Sendable {
    func probeAvailableTypes(from types: Set<HealthSampleType>) async -> Set<HealthSampleType>
}

extension HealthKitService: AvailableTypesProbing {}

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

    private struct WorkoutCacheEntry {
        let workouts: [HealthWorkoutRecord]
        let coveredRange: DateInterval?
        let source: WorkoutAnchorSource
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
    private var persistTasks: [HealthSampleType: Task<Void, Never>] = [:]
    private let dataProvider: any HealthDataProviding
    private let persistence: (any HealthCachePersisting)?
    /// Optional cross-package revocation hooks. Each conformer is invoked
    /// best-effort during `handleAuthorizationRevoked` — one failure does
    /// not block the others. Populated by the app target (spec 019 Stage 3c
    /// injects `RoutingSignalStore` here so the Telemetry `.none` partition
    /// is purged on HealthKit revoke, per MY-1381 追加需求).
    private let revocationHandlers: [any AuthorizationRevocationHandling]
    private let cacheTTL: TimeInterval
    private var generation: UInt64 = 0
    // Per-type explicit-refresh generation. Bumped on every refresh() and on
    // invalidate/invalidateAll so any in-flight background refresh whose
    // performFetch started under the old value must NOT commit its result to
    // the cache (its result would race with — or worse, merge into — the
    // explicit refresh's whole-entry replacement).
    private var refreshGenerations: [HealthSampleType: UInt64] = [:]

    private var hitCounts: [HealthSampleType: Int] = [:]
    private var missCounts: [HealthSampleType: Int] = [:]
    private var refreshCounts: [HealthSampleType: Int] = [:]

    private struct WorkoutFetchKey: Hashable {
        let source: WorkoutAnchorSource
        let rangeStart: Date?
        let rangeEnd: Date?

        var dateRange: DateInterval? {
            guard let rangeStart, let rangeEnd else { return nil }
            return DateInterval(start: rangeStart, end: rangeEnd)
        }

        init(source: WorkoutAnchorSource, dateRange: DateInterval?) {
            self.source = source
            self.rangeStart = dateRange?.start
            self.rangeEnd = dateRange?.end
        }
    }

    private struct WorkoutInFlightFetch {
        let requestID: UUID
        let task: Task<[HealthWorkoutRecord], any Error>
    }

    private var workoutCache: WorkoutCacheEntry?
    private var workoutInFlightFetches: [WorkoutFetchKey: WorkoutInFlightFetch] = [:]
    private var workoutGeneration: UInt64 = 0
    private let workoutProvider: (any WorkoutDataProviding)?
    private var workoutHitCount: Int = 0
    private var workoutMissCount: Int = 0
    private var workoutRefreshCount: Int = 0

    private var availableTypes: Set<HealthSampleType>?
    private var availableTypesFetchedAt: Date?
    private var availableTypesProbeTask: Task<Void, Never>?
    private var availableTypesPersistTask: Task<Void, Never>?
    private let typesProber: (any AvailableTypesProbing)?

    private let logger = Logger(subsystem: "com.vitalstride", category: "HealthDataCache")
    private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "HealthDataCache")
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        dataProvider: any HealthDataProviding,
        workoutProvider: (any WorkoutDataProviding)? = nil,
        persistence: (any HealthCachePersisting)? = nil,
        typesProber: (any AvailableTypesProbing)? = nil,
        revocationHandlers: [any AuthorizationRevocationHandling] = [],
        cacheTTL: TimeInterval = HealthDataCache.defaultTTL
    ) {
        self.dataProvider = dataProvider
        self.workoutProvider = workoutProvider
        self.persistence = persistence
        self.typesProber = typesProber
        self.revocationHandlers = revocationHandlers
        self.cacheTTL = cacheTTL
    }

    // MARK: - Hydration

    public func hydrate(types: Set<HealthSampleType>? = nil) async {
        guard let persistence else { return }

        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("hydrate_available_types", id: signpostID)

        do {
            if let persisted = try await persistence.loadAvailableTypes() {
                let restored = Set(persisted.typeRawValues.compactMap { HealthSampleType(rawValue: $0) })
                availableTypes = restored
                availableTypesFetchedAt = persisted.fetchedAt
                logger.info("restored \(restored.count) available types from L2")
            } else {
                logger.info("first-time probe, no L2 available types data")
            }
        } catch {
            logger.info("available types L2 hydration failed")
        }

        signposter.endInterval("hydrate_available_types", state)

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
        // Cancel any already-scheduled background refresh for this type and
        // bump the per-type refresh generation. An in-flight background
        // refresh whose Task.cancel arrives too late — or whose performFetch
        // has already awaited the provider — will see the bumped generation
        // in performFetch's post-await guard and abandon its cache write.
        // This is what makes explicit refresh deterministically win over any
        // previously scheduled background refresh for the same sample type,
        // even when the background refresh completes strictly after the
        // explicit refresh has replaced the entry.
        backgroundRefreshTasks[sampleType]?.cancel()
        backgroundRefreshTasks[sampleType] = nil
        refreshGenerations[sampleType, default: 0] &+= 1

        refreshCounts[sampleType, default: 0] += 1
        logger.info(
            "healthkit_cache_refresh type=\(sampleType.rawValue) total=\(self.refreshCounts[sampleType, default: 0])"
        )

        let points = try await performFetch(
            sampleType: sampleType,
            dateRange: dateRange,
            replaceExistingRange: true
        )
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
        workoutGeneration &+= 1
        cache = [:]
        for task in inFlightFetches.values { task.cancel() }
        inFlightFetches = [:]
        for task in backgroundRefreshTasks.values { task.cancel() }
        backgroundRefreshTasks = [:]
        for task in persistTasks.values { task.cancel() }
        persistTasks = [:]
        workoutCache = nil
        for fetch in workoutInFlightFetches.values {
            fetch.task.cancel()
        }
        workoutInFlightFetches = [:]
        availableTypes = nil
        availableTypesFetchedAt = nil
        availableTypesProbeTask?.cancel()
        availableTypesProbeTask = nil
        availableTypesPersistTask?.cancel()
        availableTypesPersistTask = nil
        resetTelemetry()
        logger.info("cache invalidated all")
    }

    // MARK: - Authorization

    public func handleAuthorizationRevoked() async {
        invalidateAll()
        if let persistence {
            do {
                try await persistence.deleteAll()
                try await persistence.deleteAvailableTypes()
                logger.info("authorization revoked — cache and persistence cleared")
            } catch {
                logger.error("authorization revoked — cache cleared but persistence deleteAll failed: \(error)")
            }
        } else {
            logger.info("authorization revoked — cache cleared (no persistence)")
        }
        // 宪法 I / MY-1381 追加需求: purge cross-package Telemetry-partition
        // rows (e.g. `RoutingSignalEntry`) whose values may derive from
        // HealthKit. Each handler runs best-effort — one failure does not
        // block the others, and errors are logged category-only so no
        // health data or signal payload leaks into unified log.
        for (index, handler) in revocationHandlers.enumerated() {
            do {
                try await handler.purgeOnAuthorizationRevoked()
            } catch {
                logger.error("authorization revoked — revocation handler #\(index) purge failed category=\(String(describing: type(of: error)), privacy: .public)")
            }
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

    public func workoutTelemetry() -> CacheTelemetry {
        CacheTelemetry(
            hits: workoutHitCount,
            misses: workoutMissCount,
            refreshes: workoutRefreshCount
        )
    }

    public func cachedTypes() -> Set<HealthSampleType> {
        Set(cache.keys)
    }


    public func hasWorkoutCache() -> Bool {
        workoutCache != nil
    }

    // MARK: - Available Types

    public func getAvailableTypes() -> Set<HealthSampleType>? {
        availableTypes
    }

    public func probeAndUpdateAvailableTypes(from types: Set<HealthSampleType>) async {
        guard let typesProber else { return }

        let probeGeneration = generation
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("probe_available_types", id: signpostID)

        let probed = await typesProber.probeAvailableTypes(from: types)

        signposter.endInterval("probe_available_types", state)

        guard generation == probeGeneration else { return }
        let fetchedAt = Date()
        availableTypes = probed
        availableTypesFetchedAt = fetchedAt
        logger.info("probe updated: \(probed.count) available types")

        persistAvailableTypesInBackground(types: probed, fetchedAt: fetchedAt, probeGeneration: probeGeneration)
    }

    public func scheduleAvailableTypesProbe(from types: Set<HealthSampleType>) {
        guard typesProber != nil else { return }
        guard availableTypesProbeTask == nil else { return }

        let probeGeneration = generation
        let task = Task {
            defer { availableTypesProbeTask = nil }
            guard self.generation == probeGeneration else { return }
            await probeAndUpdateAvailableTypes(from: types)
        }
        availableTypesProbeTask = task
    }

    public func isAvailableTypesStale() -> Bool {
        guard let fetchedAt = availableTypesFetchedAt else { return true }
        return Self.isStale(fetchedAt, ttl: cacheTTL)
    }

    // MARK: - Workout Query

    public func workoutData(
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthWorkoutRecord] {
        guard let workoutProvider else {
            return []
        }

        if let entry = workoutCache {
            let defaultBaselineHit = entry.source != .explicitRangeSnapshot
                && dateRange == nil
            let rangeHit = dateRange != nil
                && entry.coveredRange != nil
                && Self.coversRange(entry.coveredRange, requested: dateRange)

            if defaultBaselineHit || rangeHit {
                workoutHitCount += 1
                logger.info(
                    "healthkit_workout_cache_hit total=\(self.workoutHitCount)"
                )
                return Self.filteredWorkouts(entry.workouts, by: dateRange)
            }
        }

        workoutMissCount += 1
        logger.info(
            "healthkit_workout_cache_miss total=\(self.workoutMissCount)"
        )

        let semantic: WorkoutFetchSemantic = selectWorkoutFetchSemantic(dateRange: dateRange)
        let workouts = try await fetchWorkoutCoalesced(
            dateRange: dateRange,
            provider: workoutProvider,
            semantic: semantic
        )
        return Self.filteredWorkouts(workouts, by: dateRange)
    }

    // MARK: - Workout Refresh

    public func refreshWorkouts(
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthWorkoutRecord] {
        guard let workoutProvider else {
            return []
        }

        // Refresh is a higher-priority request for the workout cache. Bumping
        // the per-workout generation invalidates any older in-flight fetch that
        // may still resolve later and try to repopulate the cache.
        workoutGeneration &+= 1
        for fetch in workoutInFlightFetches.values {
            fetch.task.cancel()
        }
        workoutInFlightFetches = [:]

        workoutRefreshCount += 1
        logger.info(
            "healthkit_workout_cache_refresh total=\(self.workoutRefreshCount)"
        )

        let semantic: WorkoutFetchSemantic = dateRange == nil ? .baselineSnapshot : .explicitRangeSnapshot
        let workouts = try await performWorkoutFetch(
            dateRange: dateRange,
            provider: workoutProvider,
            semantic: semantic
        )
        return Self.filteredWorkouts(workouts, by: dateRange)
    }

    // MARK: - Workout Invalidation

    public func invalidateWorkouts() {
        workoutGeneration &+= 1
        workoutCache = nil
        for fetch in workoutInFlightFetches.values {
            fetch.task.cancel()
        }
        workoutInFlightFetches = [:]
        logger.info("workout cache invalidated")
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
        dateRange: DateInterval?,
        mergeWithExisting: Bool = false,
        replaceExistingRange: Bool = false,
        scheduledRefreshGeneration: UInt64? = nil
    ) async throws -> [HealthDataPoint] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("healthkit_fetch", id: signpostID)
        let start = ContinuousClock.now
        let fetchGeneration = generation
        // For background refreshes, use the generation captured at SCHEDULE
        // time (in scheduleBackgroundRefresh). This closes the pre-dispatch
        // window: a bg refresh scheduled before refresh() bumped the counter
        // must not commit even if its Task body only starts executing after
        // the bump. For other callers, snapshot now — they cannot race with
        // themselves.
        let fetchRefreshGeneration = scheduledRefreshGeneration
            ?? refreshGenerations[sampleType, default: 0]

        let key = FetchKey(sampleType, dateRange)
        let task = Task { [dataProvider] in
            try await dataProvider.fetchData(for: sampleType, dateRange: dateRange).dataPoints
        }
        inFlightFetches[key] = task

        do {
            let points = try await task.value
            inFlightFetches[key] = nil

            var resultPoints = points
            let refreshWinsOverBackground =
                mergeWithExisting
                && refreshGenerations[sampleType, default: 0] != fetchRefreshGeneration
            if generation == fetchGeneration, !refreshWinsOverBackground {
                let existing = cache[sampleType]

                if mergeWithExisting, let existing {
                    // Background refresh path: merge fresh data into the existing
                    // entry and PRESERVE the existing coveredRange (never widen or
                    // shrink). Refreshing fetchedAt is required — otherwise the
                    // entry stays stale under TTL and every subsequent access
                    // re-schedules a redundant background refresh.
                    var pointsByID = Dictionary(
                        existing.dataPoints.map { ($0.id, $0) },
                        uniquingKeysWith: { _, new in new }
                    )
                    for point in points {
                        pointsByID[point.id] = point
                    }
                    let merged = Array(pointsByID.values).sorted { $0.startDate < $1.startDate }
                    cache[sampleType] = CacheEntry(
                        dataPoints: merged,
                        coveredRange: existing.coveredRange,
                        fetchedAt: Date()
                    )
                    persistInBackground(sampleType: sampleType, dataPoints: merged, dateRange: existing.coveredRange, fetchGeneration: fetchGeneration)
                    resultPoints = merged
                } else if !replaceExistingRange,
                          let existing,
                          Self.coversRange(existing.coveredRange, requested: dateRange)
                {
                    // Cache-miss path (not an explicit refresh): the existing entry
                    // already covers this fetch's range, so a narrower completed
                    // fetch must not overwrite the wider cached range. Serve the
                    // caller from the freshly-fetched narrow data and leave the
                    // wider cache entry intact (immutable — no in-place mutation).
                    resultPoints = points
                } else {
                    cache[sampleType] = CacheEntry(
                        dataPoints: points,
                        coveredRange: dateRange,
                        fetchedAt: Date()
                    )
                    persistInBackground(sampleType: sampleType, dataPoints: points, dateRange: dateRange, fetchGeneration: fetchGeneration)
                    resultPoints = points
                }
            } else if refreshWinsOverBackground {
                // An explicit refresh landed while this background refresh was
                // awaiting the provider. Return the freshly-fetched data to the
                // caller (for symmetry with other paths that do so) but do NOT
                // touch the cache — the explicit refresh's replacement is the
                // canonical entry.
                logger.info(
                    "healthkit_cache_bg_refresh_superseded type=\(sampleType.rawValue)"
                )
                resultPoints = points
            }

            signposter.endInterval("healthkit_fetch", state)
            logFetchDuration(sampleType: sampleType, count: resultPoints.count, start: start)
            return resultPoints
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

        let task = Task {
            defer { persistTasks[sampleType] = nil }
            guard self.generation == fetchGeneration else { return }
            do {
                try await persistence.upsert(entry)
                if self.generation != fetchGeneration {
                    try? await persistence.deleteAll()
                }
            } catch {
                logger.info("persistence write failed type=\(sampleType.rawValue)")
            }
        }
        persistTasks[sampleType] = task
    }

    private func persistAvailableTypesInBackground(
        types: Set<HealthSampleType>,
        fetchedAt: Date,
        probeGeneration: UInt64
    ) {
        guard let persistence else { return }

        let entry = PersistedAvailableTypes(
            typeRawValues: Set(types.map(\.rawValue)),
            fetchedAt: fetchedAt
        )

        let task = Task {
            defer { availableTypesPersistTask = nil }
            guard self.generation == probeGeneration else { return }
            do {
                try await persistence.saveAvailableTypes(entry)
                if self.generation != probeGeneration {
                    try? await persistence.deleteAvailableTypes()
                }
            } catch {
                logger.info("available types persistence write failed")
            }
        }
        availableTypesPersistTask = task
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
        // Capture the per-type refresh generation at SCHEDULE time, not when
        // the Task body starts executing. Passing this into performFetch as
        // scheduledRefreshGeneration closes the pre-dispatch window: a bg
        // refresh scheduled before an explicit refresh() bumps the counter
        // is rejected on completion, even if its Task body only starts
        // running (and would otherwise re-read the counter) after the bump.
        let scheduledRefreshGeneration = refreshGenerations[sampleType, default: 0]

        let task = Task {
            defer { backgroundRefreshTasks[sampleType] = nil }
            guard self.generation == refreshGeneration else { return }
            // Also short-circuit before dispatching the fetch when a
            // refresh() has already superseded us. This avoids a needless
            // provider round-trip; correctness still relies on the
            // post-await guard in performFetch, but this trims the window
            // when the bump lands between schedule and Task body start.
            guard refreshGenerations[sampleType, default: 0] == scheduledRefreshGeneration else {
                logger.info(
                    "healthkit_cache_bg_refresh_superseded_predispatch type=\(sampleType.rawValue)"
                )
                return
            }
            do {
                _ = try await performFetch(
                    sampleType: sampleType,
                    dateRange: dateRange,
                    mergeWithExisting: true,
                    scheduledRefreshGeneration: scheduledRefreshGeneration
                )
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
        workoutHitCount = 0
        workoutMissCount = 0
        workoutRefreshCount = 0
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
            return cached.start <= requested.start && requested.end <= cached.end
        }
    }

    private static func isStale(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) > ttl
    }


    // MARK: - Private Workout Helpers

    private enum WorkoutFetchSemantic: Hashable {
        case baselineSnapshot
        case explicitRangeSnapshot
        case anchoredChanges
    }

    private func selectWorkoutFetchSemantic(dateRange: DateInterval?) -> WorkoutFetchSemantic {
        if dateRange != nil {
            return .explicitRangeSnapshot
        }
        if let current = workoutCache, current.source != .explicitRangeSnapshot {
            return .anchoredChanges
        }
        return .baselineSnapshot
    }

    private func fetchWorkoutCoalesced(
        dateRange: DateInterval?,
        provider: any WorkoutDataProviding,
        semantic: WorkoutFetchSemantic
    ) async throws -> [HealthWorkoutRecord] {
        let key = WorkoutFetchKey(source: semanticSource(for: semantic), dateRange: dateRange)
        if let existing = workoutInFlightFetches[key] {
            return try await existing.task.value
        }
        return try await performWorkoutFetch(dateRange: dateRange, provider: provider, semantic: semantic)
    }

    private func performWorkoutFetch(
        dateRange: DateInterval?,
        provider: any WorkoutDataProviding,
        semantic: WorkoutFetchSemantic
    ) async throws -> [HealthWorkoutRecord] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("healthkit_workout_fetch", id: signpostID)
        let start = ContinuousClock.now
        let fetchGeneration = workoutGeneration
        let requestID = UUID()
        let key = WorkoutFetchKey(source: semanticSource(for: semantic), dateRange: dateRange)

        let task = Task { [provider] in
            if let preparedProvider = provider as? any WorkoutPreparedDataProviding {
                let prepared: PreparedWorkoutFetch
                switch semantic {
                case .baselineSnapshot, .explicitRangeSnapshot:
                    prepared = try await preparedProvider.prepareWorkoutSnapshot(dateRange: dateRange)
                case .anchoredChanges:
                    prepared = try await preparedProvider.prepareWorkoutChanges(dateRange: dateRange)
                }
                return try await self.acceptPreparedWorkoutFetch(
                    prepared,
                    provider: preparedProvider,
                    semantic: semantic,
                    key: key,
                    requestID: requestID,
                    generation: fetchGeneration
                )
            }

            let result = try await provider.fetchWorkouts(dateRange: dateRange)
            return try await self.acceptWorkoutFetchResult(
                result,
                semantic: semantic,
                key: key,
                requestID: requestID,
                generation: fetchGeneration
            )
        }
        workoutInFlightFetches[key] = WorkoutInFlightFetch(requestID: requestID, task: task)

        do {
            let workouts = try await task.value
            if workoutInFlightFetches[key]?.requestID == requestID {
                workoutInFlightFetches[key] = nil
            }

            signposter.endInterval("healthkit_workout_fetch", state)
            logWorkoutFetchDuration(count: workouts.count, start: start)
            return workouts
        } catch {
            if workoutInFlightFetches[key]?.requestID == requestID {
                workoutInFlightFetches[key] = nil
            }
            signposter.endInterval("healthkit_workout_fetch", state)
            throw error
        }
    }

    private func acceptPreparedWorkoutFetch(
        _ prepared: PreparedWorkoutFetch,
        provider: any WorkoutPreparedDataProviding,
        semantic: WorkoutFetchSemantic,
        key: WorkoutFetchKey,
        requestID: UUID,
        generation: UInt64
    ) async throws -> [HealthWorkoutRecord] {
        let normalized = Self.normalizeWorkoutProjection(prepared.workouts)
        let staleOwner = Task.isCancelled
            || workoutGeneration != generation
            || workoutInFlightFetches[key]?.requestID != requestID

        if staleOwner {
            provider.rejectPreparedWorkoutFetch(prepared)
            logger.info("healthkit_workout_fetch_stale")
            throw CancellationError()
        }

        let previous = workoutCache
        let preserveBaseline = semantic == .anchoredChanges
            && prepared.deletedObjectIDs.isEmpty
            && prepared.workouts.isEmpty
            && previous != nil

        if preserveBaseline {
            guard let previous else {
                provider.rejectPreparedWorkoutFetch(prepared)
                return normalized
            }
            provider.acceptPreparedWorkoutFetch(prepared)
            workoutCache = previous
            return Self.filteredWorkouts(previous.workouts, by: key.dateRange)
        }

        let nextWorkouts: [HealthWorkoutRecord]
        let nextCoverage: DateInterval?
        let nextSource: WorkoutAnchorSource

        if semantic == .anchoredChanges, let previous {
            if previous.source == .explicitRangeSnapshot {
                provider.rejectPreparedWorkoutFetch(prepared)
                logger.info("healthkit_workout_fetch_rejected_incompatible_anchored_base")
                throw CancellationError()
            }

            var merged = Dictionary(previous.workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for workout in normalized {
                merged[workout.id] = workout
            }
            for id in Set(prepared.deletedObjectIDs) {
                merged[id] = nil
            }
            nextWorkouts = Self.normalizeWorkoutProjection(Array(merged.values))
            nextCoverage = prepared.coverage ?? previous.coveredRange
            nextSource = previous.source
            if previous.source != .anchoredChanges {
                workoutGeneration &+= 1
                logger.info("healthkit_workout_fetch_generation_advanced incompatible_transition")
            }
        } else {
            nextWorkouts = normalized
            nextCoverage = prepared.coverage ?? key.dateRange ?? DateInterval(
                start: Date(timeIntervalSinceNow: -HealthKitService.defaultFirstSyncWindow),
                end: Date()
            )
            nextSource = semanticSource(for: semantic)
            if let previous, previous.source != nextSource {
                workoutGeneration &+= 1
                logger.info("healthkit_workout_fetch_generation_advanced incompatible_snapshot")
            }
        }

        workoutCache = WorkoutCacheEntry(
            workouts: nextWorkouts,
            coveredRange: nextCoverage,
            source: nextSource
        )
        provider.acceptPreparedWorkoutFetch(prepared)
        return nextWorkouts
    }

    private func acceptWorkoutFetchResult(
        _ result: WorkoutFetchResult,
        semantic: WorkoutFetchSemantic,
        key: WorkoutFetchKey,
        requestID: UUID,
        generation: UInt64
    ) async throws -> [HealthWorkoutRecord] {
        let normalized = Self.normalizeWorkoutProjection(result.workouts)
        let staleOwner = Task.isCancelled
            || workoutGeneration != generation
            || workoutInFlightFetches[key]?.requestID != requestID

        if staleOwner {
            logger.info("healthkit_workout_fetch_stale")
            throw CancellationError()
        }

        let previous = workoutCache
        let preserveBaseline = semantic == .anchoredChanges
            && result.deletedObjectIDs.isEmpty
            && result.workouts.isEmpty
            && previous != nil

        if preserveBaseline {
            guard let previous else {
                return normalized
            }
            return Self.filteredWorkouts(previous.workouts, by: key.dateRange)
        }

        let nextWorkouts: [HealthWorkoutRecord]
        let nextCoverage: DateInterval?
        let nextSource: WorkoutAnchorSource

        if semantic == .anchoredChanges, let previous {
            if previous.source == .explicitRangeSnapshot {
                nextWorkouts = normalized
                nextCoverage = result.coverage ?? key.dateRange ?? DateInterval(
                    start: Date(timeIntervalSinceNow: -HealthKitService.defaultFirstSyncWindow),
                    end: Date()
                )
                nextSource = .baselineSnapshot
                workoutGeneration &+= 1
                logger.info("healthkit_workout_fetch_generation_advanced incompatible_transition")
            } else {
                var merged = Dictionary(previous.workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                for workout in normalized {
                    merged[workout.id] = workout
                }
                for id in Set(result.deletedObjectIDs) {
                    merged[id] = nil
                }
                nextWorkouts = Self.normalizeWorkoutProjection(Array(merged.values))
                nextCoverage = result.coverage ?? previous.coveredRange
                nextSource = previous.source
                if previous.source != .anchoredChanges {
                    workoutGeneration &+= 1
                    logger.info("healthkit_workout_fetch_generation_advanced incompatible_transition")
                }
            }
        } else {
            nextWorkouts = normalized
            nextCoverage = result.coverage ?? key.dateRange ?? DateInterval(
                start: Date(timeIntervalSinceNow: -HealthKitService.defaultFirstSyncWindow),
                end: Date()
            )
            nextSource = semanticSource(for: semantic)
            if let previous, previous.source != nextSource {
                workoutGeneration &+= 1
                logger.info("healthkit_workout_fetch_generation_advanced incompatible_snapshot")
            }
        }

        workoutCache = WorkoutCacheEntry(
            workouts: nextWorkouts,
            coveredRange: nextCoverage,
            source: nextSource
        )
        return nextWorkouts
    }

    private func semanticSource(for semantic: WorkoutFetchSemantic) -> WorkoutAnchorSource {
        switch semantic {
        case .baselineSnapshot:
            return .baselineSnapshot
        case .explicitRangeSnapshot:
            return .explicitRangeSnapshot
        case .anchoredChanges:
            return .anchoredChanges
        }
    }

    private func logWorkoutFetchDuration(
        count: Int,
        start: ContinuousClock.Instant
    ) {
        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        logger.info(
            "healthkit_workout_fetch_duration_ms ms=\(ms) count=\(count)"
        )
    }

    private static func normalizeWorkoutProjection(
        _ workouts: [HealthWorkoutRecord]
    ) -> [HealthWorkoutRecord] {
        let unique = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return Array(unique.values).sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startDate > rhs.startDate
        }
    }

    private static func filteredWorkouts(
        _ workouts: [HealthWorkoutRecord],
        by dateRange: DateInterval?
    ) -> [HealthWorkoutRecord] {
        guard let dateRange else { return workouts }
        return workouts.filter { dateRange.contains($0.startDate) }
    }
}
