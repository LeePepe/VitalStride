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

extension HealthKitService: WorkoutDataProviding {}

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
    }

    private struct WorkoutCacheEntry {
        let workouts: [HealthWorkoutRecord]
        let coveredRange: DateInterval?
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

    private var cache: [HealthSampleType: CacheEntry] = [:]
    private var inFlightFetches: [FetchKey: Task<[HealthDataPoint], any Error>] = [:]
    private let dataProvider: any HealthDataProviding
    private var generation: UInt64 = 0

    private var hitCounts: [HealthSampleType: Int] = [:]
    private var missCounts: [HealthSampleType: Int] = [:]
    private var refreshCounts: [HealthSampleType: Int] = [:]

    private var workoutCache: WorkoutCacheEntry?
    private var workoutInFlightFetch: Task<[HealthWorkoutRecord], any Error>?
    private let workoutProvider: (any WorkoutDataProviding)?
    private var workoutHitCount: Int = 0
    private var workoutMissCount: Int = 0
    private var workoutRefreshCount: Int = 0

    private let logger = Logger(subsystem: "com.vitalstride", category: "HealthDataCache")
    private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "HealthDataCache")

    public init(dataProvider: any HealthDataProviding, workoutProvider: (any WorkoutDataProviding)? = nil) {
        self.dataProvider = dataProvider
        self.workoutProvider = workoutProvider
    }

    // MARK: - Query

    public func data(
        for sampleType: HealthSampleType,
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthDataPoint] {
        if let entry = cache[sampleType], Self.coversRange(entry.coveredRange, requested: dateRange) {
            hitCounts[sampleType, default: 0] += 1
            logger.info(
                "healthkit_cache_hit type=\(sampleType.rawValue) total=\(self.hitCounts[sampleType, default: 0])"
            )
            return Self.filtered(entry.dataPoints, by: dateRange)
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
        workoutCache = nil
        workoutInFlightFetch?.cancel()
        workoutInFlightFetch = nil
        resetTelemetry()
        logger.info("cache invalidated all")
    }

    // MARK: - Authorization

    public func handleAuthorizationRevoked(
        anchorStore: HealthKitAnchorStore,
        deviceIdentifier: String
    ) {
        invalidateAll()
        anchorStore.removeAllAnchors(for: deviceIdentifier)
        logger.info("authorization revoked — cache, anchors, and telemetry cleared")
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

    // MARK: - Workout Query

    public func workoutData(
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthWorkoutRecord] {
        guard let workoutProvider else {
            return []
        }

        if let entry = workoutCache, Self.coversRange(entry.coveredRange, requested: dateRange) {
            workoutHitCount += 1
            logger.info(
                "healthkit_workout_cache_hit total=\(self.workoutHitCount)"
            )
            return Self.filteredWorkouts(entry.workouts, by: dateRange)
        }

        workoutMissCount += 1
        logger.info(
            "healthkit_workout_cache_miss total=\(self.workoutMissCount)"
        )

        let workouts = try await fetchWorkoutCoalesced(dateRange: dateRange, provider: workoutProvider)
        return Self.filteredWorkouts(workouts, by: dateRange)
    }

    // MARK: - Workout Refresh

    public func refreshWorkouts(
        in dateRange: DateInterval? = nil
    ) async throws -> [HealthWorkoutRecord] {
        guard let workoutProvider else {
            return []
        }

        workoutInFlightFetch?.cancel()
        workoutInFlightFetch = nil

        workoutRefreshCount += 1
        logger.info(
            "healthkit_workout_cache_refresh total=\(self.workoutRefreshCount)"
        )

        let workouts = try await performWorkoutFetch(dateRange: dateRange, provider: workoutProvider)
        return Self.filteredWorkouts(workouts, by: dateRange)
    }

    // MARK: - Workout Invalidation

    public func invalidateWorkouts() {
        workoutCache = nil
        workoutInFlightFetch?.cancel()
        workoutInFlightFetch = nil
        logger.info("workout cache invalidated")
    }

    // MARK: - Private

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
                cache[sampleType] = CacheEntry(dataPoints: points, coveredRange: dateRange)
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
            return cached.start <= requested.start && cached.end >= requested.end
        }
    }

    // MARK: - Private Workout Helpers

    private func fetchWorkoutCoalesced(
        dateRange: DateInterval?,
        provider: any WorkoutDataProviding
    ) async throws -> [HealthWorkoutRecord] {
        if let existingTask = workoutInFlightFetch {
            return try await existingTask.value
        }
        return try await performWorkoutFetch(dateRange: dateRange, provider: provider)
    }

    private func performWorkoutFetch(
        dateRange: DateInterval?,
        provider: any WorkoutDataProviding
    ) async throws -> [HealthWorkoutRecord] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("healthkit_workout_fetch", id: signpostID)
        let start = ContinuousClock.now
        let fetchGeneration = generation

        let task = Task {
            try await provider.fetchWorkouts(dateRange: dateRange).workouts
        }
        workoutInFlightFetch = task

        do {
            let workouts = try await task.value
            workoutInFlightFetch = nil

            if generation == fetchGeneration {
                workoutCache = WorkoutCacheEntry(workouts: workouts, coveredRange: dateRange)
            }

            signposter.endInterval("healthkit_workout_fetch", state)
            logWorkoutFetchDuration(count: workouts.count, start: start)
            return workouts
        } catch {
            workoutInFlightFetch = nil
            signposter.endInterval("healthkit_workout_fetch", state)
            throw error
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

    private static func filteredWorkouts(
        _ workouts: [HealthWorkoutRecord],
        by dateRange: DateInterval?
    ) -> [HealthWorkoutRecord] {
        guard let dateRange else { return workouts }
        return workouts.filter { dateRange.contains($0.startDate) }
    }
}
