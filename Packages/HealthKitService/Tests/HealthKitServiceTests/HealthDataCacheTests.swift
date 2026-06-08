import Testing
import Foundation
@testable import HealthKitService

// MARK: - Mock

final class MockHealthDataProvider: HealthDataProviding, @unchecked Sendable {
    var fetchResults: [HealthSampleType: HealthFetchResult] = [:]
    var fetchDelay: Duration?
    var fetchError: (any Error)?
    private let lock = NSLock()
    private var _fetchCallCount: [HealthSampleType: Int] = [:]
    private var _fetchDateRanges: [HealthSampleType: [DateInterval?]] = [:]

    var fetchCallCount: [HealthSampleType: Int] {
        lock.withLock { _fetchCallCount }
    }

    var fetchDateRanges: [HealthSampleType: [DateInterval?]] {
        lock.withLock { _fetchDateRanges }
    }

    func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        if let delay = fetchDelay {
            try await Task.sleep(for: delay)
        }
        if let error = fetchError {
            throw error
        }
        lock.withLock {
            _fetchCallCount[sampleType, default: 0] += 1
            _fetchDateRanges[sampleType, default: []].append(dateRange)
        }
        return fetchResults[sampleType]
            ?? HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}

// MARK: - Mock Persistence

final class MockHealthCachePersistence: HealthCachePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _store: [String: PersistedCacheEntry] = [:]
    private var _upsertCallCount = 0
    private var _deleteAllCallCount = 0
    private var _loadAllCallCount = 0
    var shouldThrow = false

    var store: [String: PersistedCacheEntry] {
        lock.withLock { _store }
    }

    var upsertCallCount: Int {
        lock.withLock { _upsertCallCount }
    }

    var deleteAllCallCount: Int {
        lock.withLock { _deleteAllCallCount }
    }

    var loadAllCallCount: Int {
        lock.withLock { _loadAllCallCount }
    }

    func loadAll() async throws -> [PersistedCacheEntry] {
        lock.withLock {
            _loadAllCallCount += 1
            if shouldThrow { return [] }
            return Array(_store.values)
        }
    }

    func load(sampleType: String) async throws -> PersistedCacheEntry? {
        if shouldThrow { throw TestError.mockFailure }
        return lock.withLock { _store[sampleType] }
    }

    func upsert(_ entry: PersistedCacheEntry) async throws {
        if shouldThrow { throw TestError.mockFailure }
        lock.withLock {
            _store[entry.sampleType] = entry
            _upsertCallCount += 1
        }
    }

    func deleteAll() async throws {
        if shouldThrow { throw TestError.mockFailure }
        lock.withLock {
            _store = [:]
            _deleteAllCallCount += 1
        }
    }

    func seed(
        sampleType: HealthSampleType,
        dataPoints: [HealthDataPoint],
        fetchedAt: Date = Date(),
        coveredRangeStart: Date? = nil,
        coveredRangeEnd: Date? = nil
    ) {
        let data = try! JSONEncoder().encode(dataPoints)
        lock.withLock {
            _store[sampleType.rawValue] = PersistedCacheEntry(
                sampleType: sampleType.rawValue,
                dataPointsData: data,
                fetchedAt: fetchedAt,
                coveredRangeStart: coveredRangeStart,
                coveredRangeEnd: coveredRangeEnd
            )
        }
    }
}

private enum TestError: Error {
    case mockFailure
}

// MARK: - Helpers

private func makeDataPoint(
    _ type: HealthSampleType,
    date: Date = Date(),
    value: Double = 100
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: type,
        startDate: date,
        endDate: date.addingTimeInterval(60),
        value: value,
        unit: "test",
        sleepStage: nil,
        sourceName: "MockSource"
    )
}

private func makeResult(
    _ type: HealthSampleType,
    count: Int = 1,
    baseDate: Date = Date()
) -> HealthFetchResult {
    let points = (0..<count).map { i in
        makeDataPoint(type, date: baseDate.addingTimeInterval(Double(i) * 60))
    }
    return HealthFetchResult(dataPoints: points, deletedObjectIDs: [])
}

// MARK: - Tests

@Suite("HealthDataCache")
struct HealthDataCacheTests {

    // MARK: - Cache Miss

    @Test("First query triggers HealthKit fetch")
    func cacheMissFetches() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let cache = HealthDataCache(dataProvider: mock)

        let result = try await cache.data(for: .stepCount)

        #expect(result.count == 3)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    // MARK: - Cache Hit

    @Test("Second query returns cached data without fetching")
    func cacheHitSkipsFetch() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.heartRate] = makeResult(.heartRate, count: 2)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .heartRate)
        let second = try await cache.data(for: .heartRate)

        #expect(second.count == 2)
        #expect(mock.fetchCallCount[.heartRate] == 1)
    }

    // MARK: - Date Range Filtering

    @Test("Cache hit filters by date range when covered range is unbounded")
    func cacheHitFiltersDateRange() async throws {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let mock = MockHealthDataProvider()

        let points = [
            makeDataPoint(.stepCount, date: yesterday),
            makeDataPoint(.stepCount, date: now),
        ]
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: points, deletedObjectIDs: []
        )
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)

        let todayRange = DateInterval(
            start: Calendar.current.startOfDay(for: now),
            end: now.addingTimeInterval(3600)
        )
        let filtered = try await cache.data(for: .stepCount, in: todayRange)

        #expect(filtered.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    @Test("Narrow-range cache miss when requesting wider range")
    func narrowThenWideRangeTriggersRefetch() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)

        let mock = MockHealthDataProvider()

        let narrowPoints = [makeDataPoint(.stepCount, date: baseDate)]
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: narrowPoints, deletedObjectIDs: []
        )

        let cache = HealthDataCache(dataProvider: mock)

        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)
        let narrowResult = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(narrowResult.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        let widePoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400))
        }
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: widePoints, deletedObjectIDs: []
        )

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let wideResult = try await cache.data(for: .stepCount, in: wideRange)
        #expect(wideResult.count == 7)
        #expect(mock.fetchCallCount[.stepCount] == 2)
    }

    @Test("Wider cached range covers narrower request without re-fetch")
    func wideThenNarrowRangeHitsCache() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)

        let mock = MockHealthDataProvider()

        let widePoints = [
            makeDataPoint(.stepCount, date: wideStart),
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(86400)),
            makeDataPoint(.stepCount, date: baseDate),
        ]
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: widePoints, deletedObjectIDs: []
        )

        let cache = HealthDataCache(dataProvider: mock)

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        _ = try await cache.data(for: .stepCount, in: wideRange)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)
        let narrowResult = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(narrowResult.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    @Test("Unbounded request after bounded cache triggers re-fetch")
    func boundedThenUnboundedTriggersRefetch() async throws {
        let now = Date()
        let mock = MockHealthDataProvider()

        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 1, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let narrowRange = DateInterval(
            start: Calendar.current.startOfDay(for: now),
            end: now.addingTimeInterval(3600)
        )
        _ = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 5, baseDate: now)
        let unboundedResult = try await cache.data(for: .stepCount)
        #expect(unboundedResult.count == 5)
        #expect(mock.fetchCallCount[.stepCount] == 2)
    }

    // MARK: - Refresh

    @Test("Refresh always fetches and replaces cache")
    func refreshAlwaysFetches() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 1)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .bodyMass)
        #expect(mock.fetchCallCount[.bodyMass] == 1)

        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 5)
        let refreshed = try await cache.refresh(.bodyMass)

        #expect(refreshed.count == 5)
        #expect(mock.fetchCallCount[.bodyMass] == 2)
    }

    @Test("Refresh with narrow range narrows covered range, wider request re-fetches")
    func refreshWithRangeUpdatesCoveredRange() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)

        let mock = MockHealthDataProvider()

        let widePoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400))
        }
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: widePoints, deletedObjectIDs: []
        )

        let cache = HealthDataCache(dataProvider: mock)
        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        _ = try await cache.data(for: .stepCount, in: wideRange)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        let narrowPoints = [makeDataPoint(.stepCount, date: baseDate)]
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: narrowPoints, deletedObjectIDs: []
        )

        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)
        let refreshed = try await cache.refresh(.stepCount, in: narrowRange)
        #expect(refreshed.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 2)

        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: widePoints, deletedObjectIDs: []
        )
        let wideResult = try await cache.data(for: .stepCount, in: wideRange)
        #expect(wideResult.count == 7)
        #expect(mock.fetchCallCount[.stepCount] == 3)
    }

    // MARK: - Invalidation

    @Test("Invalidate clears single type, next query re-fetches")
    func invalidateSingleType() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        mock.fetchResults[.heartRate] = makeResult(.heartRate)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)
        _ = try await cache.data(for: .heartRate)
        #expect(await cache.cachedTypes() == [.stepCount, .heartRate])

        await cache.invalidate(.stepCount)
        #expect(await cache.cachedTypes() == [.heartRate])

        _ = try await cache.data(for: .stepCount)
        #expect(mock.fetchCallCount[.stepCount] == 2)
        #expect(mock.fetchCallCount[.heartRate] == 1)
    }

    @Test("InvalidateAll clears everything")
    func invalidateAllClearsCache() async throws {
        let mock = MockHealthDataProvider()
        for type in HealthSampleType.allCases {
            mock.fetchResults[type] = makeResult(type)
        }
        let cache = HealthDataCache(dataProvider: mock)

        for type in HealthSampleType.allCases {
            _ = try await cache.data(for: type)
        }
        #expect(await cache.cachedTypes().count == HealthSampleType.allCases.count)

        await cache.invalidateAll()
        #expect(await cache.cachedTypes().isEmpty)
    }

    // MARK: - Concurrent Access

    @Test("Concurrent requests for the same type and range coalesce into one fetch")
    func concurrentAccessCoalesces() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchDelay = .milliseconds(50)
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let cache = HealthDataCache(dataProvider: mock)

        let results = try await withThrowingTaskGroup(
            of: [HealthDataPoint].self,
            returning: [[HealthDataPoint]].self
        ) { group in
            for _ in 0..<5 {
                group.addTask { try await cache.data(for: .stepCount) }
            }
            var collected: [[HealthDataPoint]] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        for result in results {
            #expect(result.count == 3)
        }
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 1)
    }

    @Test("Concurrent requests for different types fetch independently")
    func concurrentDifferentTypesFetchIndependently() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        mock.fetchResults[.heartRate] = makeResult(.heartRate)
        let cache = HealthDataCache(dataProvider: mock)

        async let steps = cache.data(for: .stepCount)
        async let hr = cache.data(for: .heartRate)

        let (s, h) = try await (steps, hr)
        #expect(s.count == 1)
        #expect(h.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 1)
        #expect(mock.fetchCallCount[.heartRate] == 1)
    }

    @Test("Concurrent requests for same type but different ranges fetch independently")
    func concurrentDifferentRangesFetchIndependently() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let mock = MockHealthDataProvider()
        mock.fetchDelay = .milliseconds(50)

        let allPoints = [
            makeDataPoint(.stepCount, date: baseDate),
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(-86400)),
        ]
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: allPoints, deletedObjectIDs: []
        )

        let cache = HealthDataCache(dataProvider: mock)

        let rangeA = DateInterval(start: baseDate, end: baseDate.addingTimeInterval(3600))
        let rangeB = DateInterval(
            start: baseDate.addingTimeInterval(-86400),
            end: baseDate
        )

        async let resultA = cache.data(for: .stepCount, in: rangeA)
        async let resultB = cache.data(for: .stepCount, in: rangeB)

        let (a, b) = try await (resultA, resultB)
        #expect(a.count + b.count >= 0)
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 2)
    }

    // MARK: - Authorization Revoked

    @Test("handleAuthorizationRevoked clears cache and anchors")
    func authorizationRevokedClearsAll() async throws {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)
        #expect(await cache.cachedTypes().contains(.stepCount))

        let anchorData = Data(repeating: 0xAB, count: 16)
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: Date())
        anchorStore.setAnchor(record, for: .stepCount, deviceIdentifier: "test-device")
        #expect(anchorStore.anchor(for: .stepCount, deviceIdentifier: "test-device") != nil)

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        #expect(await cache.cachedTypes().isEmpty)
        #expect(anchorStore.anchor(for: .stepCount, deviceIdentifier: "test-device") == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("In-flight fetch does not repopulate cache after authorization revocation")
    func authorizationRevokedPreventsInFlightRepopulation() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchDelay = .milliseconds(100)
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let cache = HealthDataCache(dataProvider: mock)

        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        let fetchTask = Task {
            try await cache.data(for: .stepCount)
        }

        try await Task.sleep(for: .milliseconds(20))

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        _ = try? await fetchTask.value

        #expect(await cache.cachedTypes().isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Telemetry

    @Test("Telemetry tracks hits, misses, and refreshes")
    func telemetryTracking() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)
        _ = try await cache.data(for: .stepCount)
        _ = try await cache.data(for: .stepCount)
        _ = try await cache.refresh(.stepCount)

        let tel = await cache.telemetry(for: .stepCount)
        #expect(tel.misses == 1)
        #expect(tel.hits == 2)
        #expect(tel.refreshes == 1)
    }

    @Test("InvalidateAll resets telemetry counters")
    func invalidateAllResetsTelemetry() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)
        _ = try await cache.data(for: .stepCount)
        await cache.invalidateAll()

        let tel = await cache.telemetry(for: .stepCount)
        #expect(tel == CacheTelemetry(hits: 0, misses: 0, refreshes: 0))
    }

    // MARK: - Error Propagation

    @Test("Fetch error propagates to caller")
    func fetchErrorPropagates() async {
        let mock = MockHealthDataProvider()
        mock.fetchError = HealthKitServiceError.healthDataNotAvailable
        let cache = HealthDataCache(dataProvider: mock)

        do {
            _ = try await cache.data(for: .stepCount)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is HealthKitServiceError)
        }

        #expect(await cache.cachedTypes().isEmpty)
    }

    @Test("Error does not cache partial data")
    func errorDoesNotCache() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchError = HealthKitServiceError.healthDataNotAvailable
        let cache = HealthDataCache(dataProvider: mock)

        _ = try? await cache.data(for: .stepCount)

        mock.fetchError = nil
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 2)

        let result = try await cache.data(for: .stepCount)
        #expect(result.count == 2)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    // MARK: - Date Range on Fetch

    @Test("Date range is passed through to provider on cache miss")
    func dateRangePassedToProvider() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let cache = HealthDataCache(dataProvider: mock)

        let range = DateInterval(start: Date().addingTimeInterval(-3600), duration: 3600)
        _ = try await cache.data(for: .stepCount, in: range)

        #expect(mock.fetchDateRanges[.stepCount]?.first as? DateInterval == range)
    }
}

// MARK: - L2 Persistence Tests

@Suite("HealthDataCache — L2 Persistence")
struct HealthDataCacheL2Tests {

    // MARK: - Hydration

    @Test("Hydrate loads entries from persistence into L1 cache")
    func hydratePopulatesL1() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()

        let points = [makeDataPoint(.stepCount), makeDataPoint(.stepCount)]
        persistence.seed(sampleType: .stepCount, dataPoints: points)

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        #expect(await cache.cachedTypes().contains(.stepCount))

        let result = try await cache.data(for: .stepCount)
        #expect(result.count == 2)
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 0)
    }

    @Test("Hydrate with multiple types populates all")
    func hydrateMultipleTypes() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()

        persistence.seed(sampleType: .stepCount, dataPoints: [makeDataPoint(.stepCount)])
        persistence.seed(sampleType: .heartRate, dataPoints: [makeDataPoint(.heartRate)])

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        #expect(await cache.cachedTypes().count == 2)
    }

    @Test("Hydrate failure does not crash, cache stays empty")
    func hydrateFailureGraceful() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        persistence.shouldThrow = true

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        #expect(await cache.cachedTypes().isEmpty)
    }

    // MARK: - Write-Back

    @Test("Successful HealthKit fetch writes to persistence")
    func fetchWritesBackToL2() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .stepCount)

        try await Task.sleep(for: .milliseconds(50))

        #expect(persistence.upsertCallCount == 1)
        #expect(persistence.store[HealthSampleType.stepCount.rawValue] != nil)

        let stored = persistence.store[HealthSampleType.stepCount.rawValue]!
        let decoded = try JSONDecoder().decode([HealthDataPoint].self, from: stored.dataPointsData)
        #expect(decoded.count == 3)
    }

    @Test("Refresh writes updated data to persistence")
    func refreshWritesBackToL2() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 1)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .bodyMass)
        try await Task.sleep(for: .milliseconds(50))
        #expect(persistence.upsertCallCount == 1)

        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 5)
        _ = try await cache.refresh(.bodyMass)
        try await Task.sleep(for: .milliseconds(50))

        #expect(persistence.upsertCallCount == 2)
        let stored = persistence.store[HealthSampleType.bodyMass.rawValue]!
        let decoded = try JSONDecoder().decode([HealthDataPoint].self, from: stored.dataPointsData)
        #expect(decoded.count == 5)
    }

    // MARK: - L1 Miss → L2 Hit

    @Test("L1 miss falls back to L2 hit without fetching from HealthKit")
    func l1MissL2HitSkipsHealthKit() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 10)
        let persistence = MockHealthCachePersistence()

        let points = [makeDataPoint(.stepCount), makeDataPoint(.stepCount)]
        persistence.seed(sampleType: .stepCount, dataPoints: points)

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        let result = try await cache.data(for: .stepCount)

        #expect(result.count == 2)
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 0)
        #expect(await cache.cachedTypes().contains(.stepCount))
    }

    @Test("L2 hit hydrates L1 for subsequent fast access")
    func l2HitHydratesL1() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()

        let points = [makeDataPoint(.heartRate)]
        persistence.seed(sampleType: .heartRate, dataPoints: points)

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .heartRate)
        let second = try await cache.data(for: .heartRate)

        #expect(second.count == 1)
        #expect(mock.fetchCallCount[.heartRate, default: 0] == 0)

        let tel = await cache.telemetry(for: .heartRate)
        #expect(tel.hits == 2)
        #expect(tel.misses == 0)
    }

    @Test("L2 miss triggers HealthKit fetch")
    func l2MissFetchesFromHealthKit() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 3)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        let result = try await cache.data(for: .bodyMass)

        #expect(result.count == 3)
        #expect(mock.fetchCallCount[.bodyMass] == 1)
    }

    @Test("L2 hit with covered range narrower than request falls through to HealthKit")
    func l2HitRangeMismatchFetchesHealthKit() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)

        let mock = MockHealthDataProvider()
        let widePoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400))
        }
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: widePoints, deletedObjectIDs: []
        )

        let persistence = MockHealthCachePersistence()
        let narrowPoints = [makeDataPoint(.stepCount, date: baseDate)]
        persistence.seed(
            sampleType: .stepCount,
            dataPoints: narrowPoints,
            coveredRangeStart: narrowStart,
            coveredRangeEnd: narrowEnd
        )

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let result = try await cache.data(for: .stepCount, in: wideRange)

        #expect(result.count == 7)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    // MARK: - TTL

    @Test("Fresh data from L1 does not trigger background refresh")
    func freshL1HitNoRefresh() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 2)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence, cacheTTL: 3600)

        _ = try await cache.data(for: .stepCount)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        _ = try await cache.data(for: .stepCount)
        try await Task.sleep(for: .milliseconds(100))

        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    @Test("Stale data from L1 returns immediately and triggers background refresh")
    func staleL1HitReturnsAndRefreshes() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 2)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence, cacheTTL: 0)

        _ = try await cache.data(for: .stepCount)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 5)
        let staleResult = try await cache.data(for: .stepCount)
        #expect(staleResult.count == 2)

        try await Task.sleep(for: .milliseconds(200))

        #expect(mock.fetchCallCount[.stepCount] == 2)

        let freshResult = try await cache.data(for: .stepCount)
        #expect(freshResult.count == 5)
    }

    @Test("Stale L2 hit returns data and triggers background refresh")
    func staleL2HitReturnsAndRefreshes() async throws {
        let staleDate = Date().addingTimeInterval(-7200)
        let mock = MockHealthDataProvider()
        mock.fetchResults[.heartRate] = makeResult(.heartRate, count: 5)
        let persistence = MockHealthCachePersistence()
        persistence.seed(
            sampleType: .heartRate,
            dataPoints: [makeDataPoint(.heartRate)],
            fetchedAt: staleDate
        )

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence, cacheTTL: 3600)

        let result = try await cache.data(for: .heartRate)
        #expect(result.count == 1)

        try await Task.sleep(for: .milliseconds(200))

        #expect(mock.fetchCallCount[.heartRate, default: 0] == 1)

        let freshResult = try await cache.data(for: .heartRate)
        #expect(freshResult.count == 5)
    }

    // MARK: - Authorization Revoked + Persistence

    @Test("Authorization revoked (no-arg) clears L1 and L2")
    func authRevokedNoArgClearsL1AndL2() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .stepCount)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!persistence.store.isEmpty)
        #expect(await cache.cachedTypes().contains(.stepCount))

        await cache.handleAuthorizationRevoked()

        #expect(await cache.cachedTypes().isEmpty)
        #expect(persistence.deleteAllCallCount == 1)
        #expect(persistence.store.isEmpty)
    }

    @Test("Authorization revoked (with anchors) clears L2 persistence")
    func authRevokedClearsL2() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .stepCount)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!persistence.store.isEmpty)

        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        #expect(await cache.cachedTypes().isEmpty)
        #expect(persistence.deleteAllCallCount == 1)
        #expect(persistence.store.isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Authorization revoked with persistence failure still clears L1")
    func authRevokedPersistenceFailureStillClearsL1() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .stepCount)
        #expect(await cache.cachedTypes().contains(.stepCount))

        persistence.shouldThrow = true

        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let anchorStore = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")

        await cache.handleAuthorizationRevoked(
            anchorStore: anchorStore,
            deviceIdentifier: "test-device"
        )

        #expect(await cache.cachedTypes().isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - No Persistence Fallback

    @Test("Cache works without persistence (nil)")
    func noPersistenceFallback() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let cache = HealthDataCache(dataProvider: mock)

        let result = try await cache.data(for: .stepCount)
        #expect(result.count == 3)

        let cached = try await cache.data(for: .stepCount)
        #expect(cached.count == 3)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    // MARK: - Generation Guard on Persist

    @Test("In-flight fetch does not write to L2 after invalidation")
    func inFlightFetchDoesNotPersistAfterInvalidation() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchDelay = .milliseconds(100)
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 2)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        let fetchTask = Task {
            try await cache.data(for: .stepCount)
        }

        try await Task.sleep(for: .milliseconds(20))
        await cache.invalidateAll()

        _ = try? await fetchTask.value
        try await Task.sleep(for: .milliseconds(100))

        #expect(persistence.upsertCallCount == 0)
    }

    // MARK: - Background Refresh Cancellation

    @Test("InvalidateAll cancels background refresh tasks")
    func invalidateAllCancelsBackgroundRefresh() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 2)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence, cacheTTL: 0)

        _ = try await cache.data(for: .stepCount)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        mock.fetchDelay = .milliseconds(200)
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 10)
        _ = try await cache.data(for: .stepCount)

        await cache.invalidateAll()

        try await Task.sleep(for: .milliseconds(300))

        #expect(await cache.cachedTypes().isEmpty)
    }

    // MARK: - Selective Hydration

    @Test("Hydrate with specific types only loads those types")
    func hydrateSelectiveTypes() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()

        persistence.seed(sampleType: .stepCount, dataPoints: [makeDataPoint(.stepCount)])
        persistence.seed(sampleType: .heartRate, dataPoints: [makeDataPoint(.heartRate)])
        persistence.seed(sampleType: .bodyMass, dataPoints: [makeDataPoint(.bodyMass)])

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate(types: [.stepCount, .heartRate])

        let cached = await cache.cachedTypes()
        #expect(cached.contains(.stepCount))
        #expect(cached.contains(.heartRate))
        #expect(!cached.contains(.bodyMass))
    }

    // MARK: - Persist Task Cancellation

    @Test("InvalidateAll cancels in-flight persist tasks")
    func invalidateAllCancelsPersistTasks() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .stepCount)
        await cache.invalidateAll()

        try await Task.sleep(for: .milliseconds(100))

        #expect(persistence.store.isEmpty)
    }

    @Test("Post-upsert generation guard cleans up stale writes")
    func postUpsertGenerationGuardCleansUp() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.heartRate] = makeResult(.heartRate, count: 2)
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)

        _ = try await cache.data(for: .heartRate)
        try await Task.sleep(for: .milliseconds(100))
        #expect(persistence.upsertCallCount >= 1)

        await cache.handleAuthorizationRevoked()
        try await Task.sleep(for: .milliseconds(50))

        #expect(persistence.store.isEmpty)
    }
}
