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
    private var _availableTypes: PersistedAvailableTypes?
    private var _saveAvailableTypesCallCount = 0
    private var _deleteAvailableTypesCallCount = 0
    var shouldThrow = false
    var saveAvailableTypesDelay: Duration?

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

    var savedAvailableTypes: PersistedAvailableTypes? {
        lock.withLock { _availableTypes }
    }

    var saveAvailableTypesCallCount: Int {
        lock.withLock { _saveAvailableTypesCallCount }
    }

    var deleteAvailableTypesCallCount: Int {
        lock.withLock { _deleteAvailableTypesCallCount }
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

    func loadAvailableTypes() async throws -> PersistedAvailableTypes? {
        if shouldThrow { throw TestError.mockFailure }
        return lock.withLock { _availableTypes }
    }

    func saveAvailableTypes(_ entry: PersistedAvailableTypes) async throws {
        if shouldThrow { throw TestError.mockFailure }
        if let delay = saveAvailableTypesDelay {
            try? await Task.sleep(for: delay)
        }
        lock.withLock {
            _availableTypes = entry
            _saveAvailableTypesCallCount += 1
        }
    }

    func deleteAvailableTypes() async throws {
        if shouldThrow { throw TestError.mockFailure }
        lock.withLock {
            _availableTypes = nil
            _deleteAvailableTypesCallCount += 1
        }
    }

    func seedAvailableTypes(_ types: Set<HealthSampleType>, fetchedAt: Date = Date()) {
        lock.withLock {
            _availableTypes = PersistedAvailableTypes(
                typeRawValues: Set(types.map(\.rawValue)),
                fetchedAt: fetchedAt
            )
        }
    }

    func seed(
        sampleType: HealthSampleType,
        dataPoints: [HealthDataPoint],
        fetchedAt: Date = Date(),
        coveredRangeStart: Date? = nil,
        coveredRangeEnd: Date? = nil
    ) {
        let data = try! JSONEncoder().encode(dataPoints) // swiftlint:disable:this force_try
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
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
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
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
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

        let stored = persistence.store[HealthSampleType.stepCount.rawValue]! // swiftlint:disable:this force_unwrapping
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
        let stored = persistence.store[HealthSampleType.bodyMass.rawValue]! // swiftlint:disable:this force_unwrapping
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
        #expect(freshResult.count == 7)
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
        #expect(freshResult.count == 6)
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
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
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
        let defaults = UserDefaults(suiteName: suiteName)! // swiftlint:disable:this force_unwrapping
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

    // MARK: - Nil-dateRange Merge

    @Test("Background refresh with nil dateRange merges incremental data with existing cache")
    func backgroundRefreshMergesWithExisting() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let mock = MockHealthDataProvider()

        let originalPoints = (0..<5).map { i in
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(Double(i) * 60), value: Double(i))
        }
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: originalPoints, deletedObjectIDs: []
        )
        let cache = HealthDataCache(dataProvider: mock, cacheTTL: 0)

        _ = try await cache.data(for: .stepCount)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        let incrementalPoint = makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(600), value: 99)
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: [incrementalPoint], deletedObjectIDs: []
        )

        _ = try await cache.data(for: .stepCount)

        try await Task.sleep(for: .milliseconds(200))

        let cachedResult = try await cache.data(for: .stepCount)
        #expect(cachedResult.count == 6)
        #expect(cachedResult.contains { $0.id == incrementalPoint.id })
        for original in originalPoints {
            #expect(cachedResult.contains { $0.id == original.id })
        }
    }

    @Test("Explicit refresh with nil dateRange replaces cache entirely")
    func explicitRefreshReplacesCache() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let mock = MockHealthDataProvider()

        let originalPoints = (0..<5).map { i in
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(Double(i) * 60))
        }
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: originalPoints, deletedObjectIDs: []
        )
        let cache = HealthDataCache(dataProvider: mock)

        _ = try await cache.data(for: .stepCount)

        let newPoint = makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(600))
        mock.fetchResults[.stepCount] = HealthFetchResult(
            dataPoints: [newPoint], deletedObjectIDs: []
        )

        let result = try await cache.refresh(.stepCount)
        #expect(result.count == 1)
        #expect(result.first?.id == newPoint.id)
    }
}

// MARK: - Mock Types Prober

final class MockAvailableTypesProber: AvailableTypesProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _probeResult: Set<HealthSampleType> = []
    private var _probeCallCount = 0
    var probeDelay: Duration?

    var probeResult: Set<HealthSampleType> {
        get { lock.withLock { _probeResult } }
        set { lock.withLock { _probeResult = newValue } }
    }

    var probeCallCount: Int {
        lock.withLock { _probeCallCount }
    }

    func probeAvailableTypes(from types: Set<HealthSampleType>) async -> Set<HealthSampleType> {
        if let delay = probeDelay {
            try? await Task.sleep(for: delay)
        }
        return lock.withLock {
            _probeCallCount += 1
            return _probeResult.intersection(types)
        }
    }
}

// MARK: - Available Types Tests

@Suite("HealthDataCache — Available Types")
struct HealthDataCacheAvailableTypesTests {

    @Test("availableTypes is nil initially when no persistence")
    func initialNilWithoutPersistence() async {
        let mock = MockHealthDataProvider()
        let cache = HealthDataCache(dataProvider: mock)
        let result = await cache.getAvailableTypes()
        #expect(result == nil)
    }

    @Test("availableTypes is nil after hydrate when L2 has no data")
    func firstUseNilAfterHydrate() async {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()
        let result = await cache.getAvailableTypes()
        #expect(result == nil)
    }

    @Test("hydrate restores availableTypes from L2")
    func hydrateRestoresFromL2() async {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        persistence.seedAvailableTypes([.stepCount, .heartRate])

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        let result = await cache.getAvailableTypes()
        #expect(result == [.stepCount, .heartRate])
    }

    @Test("probeAndUpdateAvailableTypes updates L1 and persists to L2")
    func probeUpdatesL1AndL2() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount, .heartRate, .bodyMass]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount, .heartRate, .bodyMass, .sleepAnalysis])

        let result = await cache.getAvailableTypes()
        #expect(result == [.stepCount, .heartRate, .bodyMass])
        #expect(prober.probeCallCount == 1)

        try await Task.sleep(for: .milliseconds(50))
        #expect(persistence.saveAvailableTypesCallCount == 1)

        let saved = persistence.savedAvailableTypes
        #expect(saved != nil)
        let savedTypes = saved!.typeRawValues // swiftlint:disable:this force_unwrapping
        #expect(savedTypes.count == 3)
        #expect(savedTypes.contains("stepCount"))
        #expect(savedTypes.contains("heartRate"))
        #expect(savedTypes.contains("bodyMass"))
    }

    @Test("probeAndUpdateAvailableTypes does nothing without prober")
    func probeNoOpWithoutProber() async {
        let mock = MockHealthDataProvider()
        let cache = HealthDataCache(dataProvider: mock)

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount])

        let result = await cache.getAvailableTypes()
        #expect(result == nil)
    }

    @Test("scheduleAvailableTypesProbe runs probe in background")
    func scheduledProbeRunsInBackground() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.scheduleAvailableTypesProbe(from: [.stepCount, .heartRate])

        try await Task.sleep(for: .milliseconds(100))

        let result = await cache.getAvailableTypes()
        #expect(result == [.stepCount])
        #expect(prober.probeCallCount == 1)
    }

    @Test("invalidateAll clears availableTypes")
    func invalidateAllClearsAvailableTypes() async {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.heartRate]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.probeAndUpdateAvailableTypes(from: [.heartRate])
        #expect(await cache.getAvailableTypes() == [.heartRate])

        await cache.invalidateAll()
        #expect(await cache.getAvailableTypes() == nil)
    }

    @Test("handleAuthorizationRevoked clears L1 and L2 availableTypes")
    func authRevokedClearsAvailableTypes() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount, .heartRate]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount, .heartRate])
        try await Task.sleep(for: .milliseconds(50))
        #expect(persistence.savedAvailableTypes != nil)

        await cache.handleAuthorizationRevoked()

        #expect(await cache.getAvailableTypes() == nil)
        #expect(persistence.deleteAvailableTypesCallCount == 1)
    }

    @Test("isAvailableTypesStale returns true when no data")
    func staleWhenNoData() async {
        let mock = MockHealthDataProvider()
        let cache = HealthDataCache(dataProvider: mock)
        #expect(await cache.isAvailableTypesStale() == true)
    }

    @Test("isAvailableTypesStale returns false for fresh data")
    func freshDataNotStale() async {
        let mock = MockHealthDataProvider()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount]
        let cache = HealthDataCache(
            dataProvider: mock,
            typesProber: prober,
            cacheTTL: 3600
        )

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount])
        #expect(await cache.isAvailableTypesStale() == false)
    }

    @Test("isAvailableTypesStale returns true for expired data")
    func expiredDataIsStale() async {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let staleDate = Date().addingTimeInterval(-7200)
        persistence.seedAvailableTypes([.stepCount], fetchedAt: staleDate)

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            cacheTTL: 3600
        )
        await cache.hydrate()

        #expect(await cache.isAvailableTypesStale() == true)
    }

    @Test("Generation guard prevents stale probe from writing")
    func generationGuardPreventsStaleWrite() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        let prober = MockAvailableTypesProber()
        prober.probeDelay = .milliseconds(100)
        prober.probeResult = [.stepCount]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.scheduleAvailableTypesProbe(from: [.stepCount])
        try await Task.sleep(for: .milliseconds(20))

        await cache.invalidateAll()

        try await Task.sleep(for: .milliseconds(200))

        #expect(await cache.getAvailableTypes() == nil)
        #expect(persistence.savedAvailableTypes == nil)
    }

    @Test("Post-write generation check cleans up stale L2 data")
    func postWriteGenerationCheckCleansUpStaleL2() async throws {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        persistence.saveAvailableTypesDelay = .milliseconds(100)
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount]

        let cache = HealthDataCache(
            dataProvider: mock,
            persistence: persistence,
            typesProber: prober
        )

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount])
        try await Task.sleep(for: .milliseconds(20))

        await cache.invalidateAll()

        try await Task.sleep(for: .milliseconds(200))

        #expect(await cache.getAvailableTypes() == nil)
        #expect(persistence.savedAvailableTypes == nil)
        #expect(persistence.deleteAvailableTypesCallCount >= 1)
    }

    @Test("Hydrate failure for availableTypes is graceful, cache stays nil")
    func hydrateFailureGraceful() async {
        let mock = MockHealthDataProvider()
        let persistence = MockHealthCachePersistence()
        persistence.shouldThrow = true

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        #expect(await cache.getAvailableTypes() == nil)
    }

    @Test("Probe result replaces previous availableTypes")
    func probeReplacesPrevious() async {
        let mock = MockHealthDataProvider()
        let prober = MockAvailableTypesProber()
        prober.probeResult = [.stepCount]

        let cache = HealthDataCache(
            dataProvider: mock,
            typesProber: prober
        )

        await cache.probeAndUpdateAvailableTypes(from: [.stepCount, .heartRate])
        #expect(await cache.getAvailableTypes() == [.stepCount])

        prober.probeResult = [.stepCount, .heartRate, .bodyMass]
        await cache.probeAndUpdateAvailableTypes(from: [.stepCount, .heartRate, .bodyMass])
        #expect(await cache.getAvailableTypes() == [.stepCount, .heartRate, .bodyMass])
    }

    @Test("Hydrate does not affect existing data cache entries")
    func hydrateAvailableTypesDoesNotAffectDataCache() async throws {
        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3)
        let persistence = MockHealthCachePersistence()
        persistence.seedAvailableTypes([.stepCount, .heartRate])
        persistence.seed(sampleType: .stepCount, dataPoints: [makeDataPoint(.stepCount)])

        let cache = HealthDataCache(dataProvider: mock, persistence: persistence)
        await cache.hydrate()

        #expect(await cache.getAvailableTypes() == [.stepCount, .heartRate])
        #expect(await cache.cachedTypes().contains(.stepCount))

        let data = try await cache.data(for: .stepCount)
        #expect(data.count == 1)
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 0)
    }
}

// MARK: - Range Trampling Regression (MY-1076)

@Suite("HealthDataCache — Range Trampling (MY-1076)")
struct HealthDataCacheRangeTramplingTests {

    @Test("Narrower cache-miss fetch does not replace an existing wider cached range")
    func narrowFetchDoesNotShrinkWiderCachedRange() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-30 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)

        let widePoints = (0..<31).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400))
        }

        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = HealthFetchResult(dataPoints: widePoints, deletedObjectIDs: [])
        let cache = HealthDataCache(dataProvider: mock)

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let wideResult = try await cache.data(for: .stepCount, in: wideRange)
        #expect(wideResult.count == 31)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)
        let narrowFromCache = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(narrowFromCache.count == 1)
        #expect(mock.fetchCallCount[.stepCount] == 1, "wide range must cover narrow request")

        let wideAgain = try await cache.data(for: .stepCount, in: wideRange)
        #expect(wideAgain.count == 31)
        #expect(mock.fetchCallCount[.stepCount] == 1)
    }

    @Test("Out-of-order wide/narrow fetch completion preserves wider covered range")
    func outOfOrderWideNarrowCompletion() async throws {
        // Deterministic replacement for the previous timing-based sleep+ordering
        // test. Both provider calls are gated with independent continuations so
        // the test can:
        //   1. Enqueue narrow (deterministically wait until it is parked in the
        //      provider — no sleep-and-hope),
        //   2. Enqueue wide (wait until it too is parked in the provider),
        //   3. Release wide FIRST and await its return so the wider covered
        //      range is committed to the cache,
        //   4. Then release narrow — the narrow completion arrives AFTER wide
        //      populated the cache, exercising the exact ordering that must
        //      NOT shrink the covered range.
        // No Task.sleep, no wall-clock ordering assumptions.
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-30 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)

        let widePoints = (0..<31).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400))
        }
        let narrowPoints = [makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(60))]

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)
        let provider = GatedOrderedProvider(
            widePoints: widePoints,
            narrowPoints: narrowPoints,
            wideRange: wideRange,
            narrowRange: narrowRange
        )
        let cache = HealthDataCache(dataProvider: provider)

        // Step 1: enqueue the narrow fetch; bounded wait until it is parked
        // at its gate. If it never enters the provider within the timeout,
        // `waitUntil` records an Issue and the test fails terminally instead
        // of hanging forever.
        async let narrowTask = cache.data(for: .stepCount, in: narrowRange)
        try await waitUntil(timeout: .seconds(2)) {
            await provider.narrowEnteredSnapshot
        }

        // Step 2: enqueue the wide fetch; bounded wait until it is parked
        // at its gate.
        async let wideTask = cache.data(for: .stepCount, in: wideRange)
        try await waitUntil(timeout: .seconds(2)) {
            await provider.wideEnteredSnapshot
        }

        // Step 3: release wide first and await its result. Wide completes and
        // commits the wider covered range to the cache before narrow returns.
        await provider.releaseWide()
        let wideOut = try await wideTask
        #expect(wideOut.count == 31)

        // Step 4: release narrow AFTER wide has populated the cache. Narrow
        // completing here must not shrink the wider covered range.
        await provider.releaseNarrow()
        let narrowOut = try await narrowTask
        #expect(narrowOut.count == 1)

        let fetchCountAfterBoth = await provider.fetchCount
        #expect(fetchCountAfterBoth == 2)

        // A repeated wide request must hit the cache (no third provider call)
        // — proves the narrow completion did NOT overwrite the wider entry.
        let wideAgain = try await cache.data(for: .stepCount, in: wideRange)
        #expect(wideAgain.count == 31)
        let fetchCountAfterRepeat = await provider.fetchCount
        #expect(fetchCountAfterRepeat == 2, "wide entry must survive out-of-order narrow completion")
    }

    @Test("Immutable whole-entry replacement: explicit refresh replaces the entry")
    func explicitRefreshReplacesWholeEntry() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)

        let originalPoints = (0..<8).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400), value: Double(i))
        }
        let replacementPoints = (0..<3).map { i in
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(Double(i) * 60), value: Double(1000 + i))
        }

        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = HealthFetchResult(dataPoints: originalPoints, deletedObjectIDs: [])
        let cache = HealthDataCache(dataProvider: mock)

        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        _ = try await cache.data(for: .stepCount, in: wideRange)

        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)
        mock.fetchResults[.stepCount] = HealthFetchResult(dataPoints: replacementPoints, deletedObjectIDs: [])

        let refreshed = try await cache.refresh(
            .stepCount,
            in: DateInterval(start: narrowStart, end: narrowEnd)
        )
        #expect(refreshed.count == 3)

        mock.fetchResults[.stepCount] = HealthFetchResult(dataPoints: originalPoints, deletedObjectIDs: [])
        _ = try await cache.data(for: .stepCount, in: wideRange)
        #expect(mock.fetchCallCount[.stepCount] == 3, "wide re-fetch confirms explicit-refresh replacement")
    }

    @Test("Bounded stale entry refreshes once, subsequent access does not re-fetch")
    func boundedStaleRefreshesOnceAndPersists() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let boundedStart = baseDate.addingTimeInterval(-7 * 86400)
        let boundedEnd = baseDate.addingTimeInterval(86400)
        let boundedRange = DateInterval(start: boundedStart, end: boundedEnd)

        let originalPoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: boundedStart.addingTimeInterval(Double(i) * 86400), value: Double(i))
        }
        // Fresh payload = originals + one new point returned by the background
        // refresh; must survive the merge instead of being discarded.
        let freshPoints = originalPoints + [
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(3600), value: 99),
        ]

        let mock = MockHealthDataProvider()
        mock.fetchResults[.stepCount] = HealthFetchResult(dataPoints: freshPoints, deletedObjectIDs: [])

        // Seed L2 with a stale bounded entry (fetchedAt 2 hours ago, TTL 1h).
        // First access hydrates L1, sees the entry as stale, and schedules one
        // background refresh. Post-refresh the entry's fetchedAt is Date() and
        // is fresh under the 1h TTL, so subsequent access does not schedule
        // another refresh.
        let persistence = MockHealthCachePersistence()
        let staleDate = Date().addingTimeInterval(-7200)
        persistence.seed(
            sampleType: .stepCount,
            dataPoints: originalPoints,
            fetchedAt: staleDate,
            coveredRangeStart: boundedStart,
            coveredRangeEnd: boundedEnd
        )
        let cache = HealthDataCache(dataProvider: mock, persistence: persistence, cacheTTL: 3600)

        // Access #1: L1 miss → L2 hit (stale) → returns immediately and
        // schedules a background refresh for the bounded range.
        let firstHit = try await cache.data(for: .stepCount, in: boundedRange)
        #expect(firstHit.count == 7, "L2 hit returns immediately with stale data")
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 0, "no synchronous fetch yet")

        // Let the background refresh complete.
        try await Task.sleep(for: .milliseconds(200))
        #expect(mock.fetchCallCount[.stepCount, default: 0] == 1, "background refresh fired once")

        // Post-refresh: the bounded entry must contain the merged fresh points
        // AND have an updated fetchedAt — proving the fresh data was NOT
        // discarded (regression: previously the narrow-preservation branch
        // dropped the refresh's payload).
        let refreshedHit = try await cache.data(for: .stepCount, in: boundedRange)
        #expect(refreshedHit.count == 8, "background refresh merged fresh point into bounded entry")
        #expect(refreshedHit.contains { $0.value == 99 }, "fresh point is present")

        // Subsequent access must NOT schedule another refresh — the entry is
        // fresh under the 1h TTL because fetchedAt was updated.
        try await Task.sleep(for: .milliseconds(200))
        #expect(
            mock.fetchCallCount[.stepCount, default: 0] == 1,
            "bounded entry stays fresh after one refresh — no repeated re-fetching"
        )

        // One more access for good measure.
        _ = try await cache.data(for: .stepCount, in: boundedRange)
        try await Task.sleep(for: .milliseconds(200))
        #expect(
            mock.fetchCallCount[.stepCount, default: 0] == 1,
            "further accesses on a fresh bounded entry still do not re-fetch"
        )
    }

    @Test("Explicit refresh deterministically wins over a late-completing background refresh")
    func explicitRefreshWinsOverLateBackgroundRefresh() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)
        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)

        let originalPoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400), value: Double(i))
        }
        // Sentinel value 999 — must NOT end up in either L1 or L2 after
        // explicit refresh has replaced the entry.
        let bgRefreshPoints = originalPoints + [
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(-3600), value: 999),
        ]
        let explicitRefreshPoint = makeDataPoint(.stepCount, date: baseDate, value: 42)

        // Gated provider: the wide (background-refresh) call awaits a
        // continuation until the test explicitly releases it. That gives
        // deterministic control over the race:
        //   1. Background refresh dispatched → provider enters await, signals
        //      "started" via startedStream → then blocks on gate.
        //   2. Test awaits startedStream → knows bg provider is parked.
        //   3. Test invokes refresh(narrow) → bumps refresh generation,
        //      cancels the bg Task. Provider ignores cancellation.
        //   4. refresh() completes and replaces cache with narrow entry.
        //   5. Test releases the gate → bg provider returns → performFetch's
        //      post-await guard sees generation mismatch and drops the write.
        // The pre-dispatch race is also covered: the bg Task's provider call
        // is dispatched BEFORE refresh() is called, so `scheduledRefreshGen`
        // captured at schedule time is stale by the time it completes.
        let provider = GatedRefreshProvider(
            wideRange: wideRange,
            narrowRange: narrowRange,
            bgRefreshPoints: bgRefreshPoints,
            explicitRefreshPoints: [explicitRefreshPoint]
        )

        // Seed L2 with a stale wide entry so first access schedules a
        // background refresh over wideRange.
        let persistence = MockHealthCachePersistence()
        let staleDate = Date().addingTimeInterval(-7200)
        persistence.seed(
            sampleType: .stepCount,
            dataPoints: originalPoints,
            fetchedAt: staleDate,
            coveredRangeStart: wideStart,
            coveredRangeEnd: wideEnd
        )
        let cache = HealthDataCache(dataProvider: provider, persistence: persistence, cacheTTL: 3600)

        // Access #1: L2 hit (stale) → schedules a background refresh over
        // wideRange. The provider enters await synchronously.
        let firstHit = try await cache.data(for: .stepCount, in: wideRange)
        #expect(firstHit.count == 7)

        // Deterministic sync: wait for the provider to signal it has started
        // and is parked at the gate. NO sleeps.
        await provider.awaitBackgroundRefreshStarted()

        // Explicit refresh with a narrow range: bumps the per-type refresh
        // generation, cancels the bg Task, dispatches its own fast fetch.
        // The bg provider is still parked; explicit refresh proceeds
        // independently through its own provider path.
        let refreshed = try await cache.refresh(.stepCount, in: narrowRange)
        #expect(refreshed.count == 1)
        #expect(refreshed.first?.value == 42)

        // Confirm L2 already reflects the explicit refresh's narrow write
        // (persistInBackground is fire-and-forget; wait for it to land).
        try await waitUntil(timeout: .milliseconds(500)) {
            let stored = persistence.store[HealthSampleType.stepCount.rawValue]
            guard let stored else { return false }
            guard let decoded = try? JSONDecoder().decode([HealthDataPoint].self, from: stored.dataPointsData) else {
                return false
            }
            return decoded.count == 1
                && decoded.first?.value == 42
                && stored.coveredRangeStart == narrowStart
                && stored.coveredRangeEnd == narrowEnd
        }

        // Release the bg provider. Its Task was cancelled but the provider
        // ignores cancellation, so its result reaches performFetch. The
        // post-await guard MUST reject it: scheduledRefreshGeneration (0)
        // no longer matches refreshGenerations (1). And even if the guard
        // were absent, the pre-dispatch guard would have short-circuited
        // when the Task body first ran — but here the Task body is already
        // past that check, awaiting the provider, so only the post-await
        // guard fires. That is exactly what this test forces.
        await provider.releaseBackgroundRefresh()

        // Deterministic sync: wait for the bg provider to fully finish (its
        // fetchCount stops changing) so we know performFetch has run its
        // post-await guard. No sleeps beyond this bounded poll.
        try await waitUntil(timeout: .milliseconds(500)) {
            await provider.backgroundRefreshDidComplete
        }

        // L1 must still be the explicit refresh's narrow entry.
        let after = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(after.count == 1, "L1: explicit refresh entry survives late bg completion")
        #expect(after.first?.value == 42, "L1: explicit refresh's point remains")
        #expect(
            !after.contains { $0.value == 999 },
            "L1: background refresh's payload did NOT bleed into the explicit refresh entry"
        )

        // L2 must still be the explicit refresh's narrow entry — the bg
        // refresh's persistInBackground must NOT have run either.
        let l2 = persistence.store[HealthSampleType.stepCount.rawValue]
        #expect(l2 != nil, "L2 entry exists")
        if let l2 {
            let decoded = try JSONDecoder().decode([HealthDataPoint].self, from: l2.dataPointsData)
            #expect(decoded.count == 1, "L2: exactly one point (explicit refresh)")
            #expect(decoded.first?.value == 42, "L2: explicit refresh's point remains")
            #expect(!decoded.contains { $0.value == 999 }, "L2: bg refresh payload absent")
            #expect(l2.coveredRangeStart == narrowStart, "L2: coveredRange narrowed")
            #expect(l2.coveredRangeEnd == narrowEnd, "L2: coveredRange narrowed")
        }

        // A wider request now misses (covered range is narrow) — proving the
        // bg refresh did NOT silently restore the wide range in L1 or L2.
        let bgCountBefore = await provider.fetchCount
        _ = try await cache.data(for: .stepCount, in: wideRange)
        let bgCountAfter = await provider.fetchCount
        #expect(
            bgCountAfter > bgCountBefore,
            "wide request must miss and fetch — explicit refresh's narrow range is authoritative"
        )
    }

    @Test("Pre-dispatch race: bg Task scheduled but not yet executed cannot commit after refresh")
    func predispatchRaceRefreshWinsOverStalledBackgroundTask() async throws {
        // This regression proves ONLY the schedule-time (pre-dispatch) path:
        // `scheduleBackgroundRefresh` captures `scheduledRefreshGeneration`
        // at schedule time and enqueues a Task whose body must run AFTER an
        // explicit `refresh()` has bumped the per-type generation. Under the
        // fix, the bg Task body's second guard —
        //   `guard refreshGenerations[...] == scheduledRefreshGeneration`
        // — fires and the bg body returns WITHOUT calling into the provider.
        //
        // The pre-dispatch ordering (data schedules bg → refresh bumps →
        // bg body runs and sees stale snapshot) is subject to actor FIFO/
        // priority scheduling, so we use a BOUNDED retry loop:
        //
        //   for attempt in 1...maxAttempts:
        //     1. Fresh cache seeded with stale L2.
        //     2. Enqueue `data(wide)` at .background — this schedules the bg
        //        Task, which inherits .background priority.
        //     3. Enqueue `refresh(narrow)` at .userInitiated — a higher-
        //        priority actor job. On the actor's job queue, this outranks
        //        the pending .background bg Task body.
        //     4. Drain the actor (bounded pings + Task.yield) so any pending
        //        bg Task body actually runs.
        //     5. Observe `provider.wideFetchCount`:
        //        • `== 0` → bg body reached the pre-dispatch guard AFTER
        //          refresh's bump; guard fired, provider never called.
        //          Success: exit the loop and assert L1/L2 invariants.
        //        • `> 0`  → this attempt raced past pre-dispatch; discard
        //          it and retry with a fresh setup.
        //
        // After `maxAttempts` retries, if no attempt has triggered pre-
        // dispatch, the test FAILS TERMINALLY with a clear diagnostic. This
        // bounds worst-case runtime and provides a single-path assertion:
        // when the loop exits successfully, ONLY the pre-dispatch path was
        // exercised in the winning attempt — no acceptance of the post-await
        // (provider-entered) branch.
        //
        // Terminal signal for the pre-dispatch path (provider was never
        // called for wideRange): `provider.wideFetchCount == 0` AND
        // `provider.wideEnteredSnapshot == false`. Stability is re-verified
        // via an additional drain: rejection must remain terminal — the
        // counters cannot rise afterward.

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let wideStart = baseDate.addingTimeInterval(-7 * 86400)
        let wideEnd = baseDate.addingTimeInterval(86400)
        let wideRange = DateInterval(start: wideStart, end: wideEnd)
        let narrowStart = baseDate
        let narrowEnd = baseDate.addingTimeInterval(3600)
        let narrowRange = DateInterval(start: narrowStart, end: narrowEnd)

        let originalPoints = (0..<7).map { i in
            makeDataPoint(.stepCount, date: wideStart.addingTimeInterval(Double(i) * 86400), value: Double(i))
        }
        // Sentinel 777 — must never end up in L1/L2 after the bg Task is rejected.
        let bgPoints = originalPoints + [
            makeDataPoint(.stepCount, date: baseDate.addingTimeInterval(-1800), value: 777),
        ]
        let explicitPoint = makeDataPoint(.stepCount, date: baseDate, value: 42)

        let maxAttempts = 20
        var winningProvider: GatedRefreshProvider?
        var winningPersistence: MockHealthCachePersistence?
        var winningCache: HealthDataCache?
        var attemptsUsed = 0

        for attempt in 1...maxAttempts {
            attemptsUsed = attempt

            // Wide gate stays CLOSED for the whole attempt. Under the pre-
            // dispatch path we want to observe, the bg body never reaches
            // the gate. If the fix regressed and the bg body DID dispatch
            // the provider call, the test would still be terminating on
            // this attempt (via wideFetchCount > 0) rather than hanging.
            let provider = GatedRefreshProvider(
                wideRange: wideRange,
                narrowRange: narrowRange,
                bgRefreshPoints: bgPoints,
                explicitRefreshPoints: [explicitPoint]
            )

            let persistence = MockHealthCachePersistence()
            let staleDate = Date().addingTimeInterval(-7200)
            persistence.seed(
                sampleType: .stepCount,
                dataPoints: originalPoints,
                fetchedAt: staleDate,
                coveredRangeStart: wideStart,
                coveredRangeEnd: wideEnd
            )
            let cache = HealthDataCache(dataProvider: provider, persistence: persistence, cacheTTL: 3600)

            // Access #1 runs at .background priority. The bg Task it
            // schedules inherits .background, so a later .userInitiated
            // actor job outranks it on the actor's job queue.
            let firstHit = try await Task.detached(priority: .background) {
                try await cache.data(for: .stepCount, in: wideRange)
            }.value
            #expect(firstHit.count == 7)

            // Explicit refresh runs at .userInitiated.
            let refreshedResult = try await Task.detached(priority: .userInitiated) {
                try await cache.refresh(.stepCount, in: narrowRange)
            }.value
            #expect(refreshedResult.count == 1)
            #expect(refreshedResult.first?.value == 42)

            // Drain the actor via bounded pings at .background priority so
            // the pending .background bg Task body actually gets scheduled.
            // `cachedTypes()` returns a snapshot; between iterations, other
            // queued jobs (the bg body) execute.
            for _ in 0..<40 {
                _ = await Task.detached(priority: .background) {
                    await cache.cachedTypes()
                }.value
                await Task.yield()
            }

            let wideFetchCount = await provider.wideFetchCount
            if wideFetchCount == 0 {
                // Pre-dispatch guard fired on this attempt: bg body ran the
                // schedule-time guard AFTER refresh's bump and returned
                // without calling `fetchData`. Capture state and exit the
                // loop; L1/L2 invariants are asserted below.
                winningProvider = provider
                winningPersistence = persistence
                winningCache = cache
                break
            }
            // This attempt raced past pre-dispatch (bg entered provider);
            // discard and retry with a fresh setup.
        }

        // Bounded terminal failure: if no attempt triggered pre-dispatch,
        // the test fails with a specific message. Priority-based ordering
        // did not deliver the required interleaving within `maxAttempts`.
        guard let provider = winningProvider,
              let persistence = winningPersistence,
              let cache = winningCache
        else {
            Issue.record(
                "Pre-dispatch guard was never observed to fire across \(maxAttempts) attempts. Either the fix has regressed, or actor priority scheduling no longer reliably orders .userInitiated refresh before .background background-refresh."
            )
            return
        }

        // TERMINAL SIGNAL for pre-dispatch:
        //   (a) `wideFetchCount == 0` — bg body never called `fetchData`
        //       on the wide range. It returned inside
        //       `scheduleBackgroundRefresh`'s Task body at the pre-dispatch
        //       guard, before reaching `performFetch`.
        //   (b) `wideEnteredSnapshot == false` — corollary of (a); no
        //       provider entry means no gate wait either.
        // These two together prove the bg Task's `defer` fired (Task body
        // returned) and the pre-dispatch path was the sole path taken.
        let wideFetchCountFinal = await provider.wideFetchCount
        let wideEnteredFinal = await provider.wideEnteredSnapshot
        #expect(
            wideFetchCountFinal == 0,
            "Pre-dispatch guard must fire: bg Task must NOT call the wide provider. Observed wideFetchCount=\(wideFetchCountFinal) on winning attempt (\(attemptsUsed))."
        )
        #expect(
            wideEnteredFinal == false,
            "Pre-dispatch guard must fire: bg Task must NOT enter the provider's wide path. Observed wideEnteredSnapshot=true — regression."
        )

        // Stability re-check: another round of actor pings must NOT flip
        // the rejection into a delayed provider call. If wideFetchCount
        // rises above 0 after this drain, the pre-dispatch signal was
        // premature — fail terminally.
        for _ in 0..<20 {
            _ = await Task.detached(priority: .background) {
                await cache.cachedTypes()
            }.value
            await Task.yield()
        }
        let wideFetchCountStable = await provider.wideFetchCount
        #expect(
            wideFetchCountStable == 0,
            "Pre-dispatch rejection must be terminal: wideFetchCount unchanged across drains. Observed \(wideFetchCountStable)."
        )

        // Terminal-rejection invariant: L1 holds the explicit refresh's
        // narrow entry; the bg sentinel (777) is absent.
        let after = try await cache.data(for: .stepCount, in: narrowRange)
        #expect(after.count == 1, "L1: narrow entry survives bg rejection")
        #expect(after.first?.value == 42, "L1: explicit refresh's point remains")
        #expect(!after.contains { $0.value == 777 }, "L1: bg sentinel absent — rejection is terminal")

        // Terminal-rejection invariant: L2 holds the explicit refresh's
        // narrow entry only; the bg sentinel is absent, coveredRange narrowed.
        try await waitUntil(timeout: .milliseconds(500)) {
            let stored = persistence.store[HealthSampleType.stepCount.rawValue]
            guard let stored else { return false }
            guard let decoded = try? JSONDecoder().decode([HealthDataPoint].self, from: stored.dataPointsData) else {
                return false
            }
            return decoded.count == 1
                && decoded.first?.value == 42
                && stored.coveredRangeStart == narrowStart
                && stored.coveredRangeEnd == narrowEnd
        }
        let l2 = persistence.store[HealthSampleType.stepCount.rawValue]
        #expect(l2 != nil)
        if let l2 {
            let decoded = try JSONDecoder().decode([HealthDataPoint].self, from: l2.dataPointsData)
            #expect(decoded.count == 1)
            #expect(!decoded.contains { $0.value == 777 }, "L2: bg sentinel absent")
            #expect(l2.coveredRangeStart == narrowStart)
            #expect(l2.coveredRangeEnd == narrowEnd)
        }
    }
}

// Deterministic polling helper — replaces raw `Task.sleep` in tests that
// otherwise couldn't observe an actor state change without a timeout. Polls
// every 5 ms until `check` returns true or the timeout elapses. Records an
// Issue on timeout unless `expectTimeoutOK` is true.
@discardableResult
private func waitUntil(
    timeout: Duration,
    expectTimeoutOK: Bool = false,
    check: @escaping @Sendable () async throws -> Bool
) async throws -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if try await check() { return true }
        try await Task.sleep(for: .milliseconds(5))
    }
    if !expectTimeoutOK {
        Issue.record("waitUntil timed out after \(timeout)")
    }
    return false
}

private actor GatedOrderedProvider: HealthDataProviding {
    let widePoints: [HealthDataPoint]
    let narrowPoints: [HealthDataPoint]
    let wideRange: DateInterval
    let narrowRange: DateInterval

    private var _fetchCount = 0

    private var wideEntered = false
    private var wideGateContinuation: CheckedContinuation<Void, Never>?
    private var wideReleased = false

    private var narrowEntered = false
    private var narrowGateContinuation: CheckedContinuation<Void, Never>?
    private var narrowReleased = false

    init(
        widePoints: [HealthDataPoint],
        narrowPoints: [HealthDataPoint],
        wideRange: DateInterval,
        narrowRange: DateInterval
    ) {
        self.widePoints = widePoints
        self.narrowPoints = narrowPoints
        self.wideRange = wideRange
        self.narrowRange = narrowRange
    }

    var fetchCount: Int { _fetchCount }
    var wideEnteredSnapshot: Bool { wideEntered }
    var narrowEnteredSnapshot: Bool { narrowEntered }

    func releaseWide() {
        wideReleased = true
        wideGateContinuation?.resume()
        wideGateContinuation = nil
    }

    func releaseNarrow() {
        narrowReleased = true
        narrowGateContinuation?.resume()
        narrowGateContinuation = nil
    }

    private func markWideEntered() {
        wideEntered = true
    }

    private func markNarrowEntered() {
        narrowEntered = true
    }

    private func awaitWideGate() async {
        if wideReleased { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wideGateContinuation = cont
        }
    }

    private func awaitNarrowGate() async {
        if narrowReleased { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            narrowGateContinuation = cont
        }
    }

    private func recordFetch() { _fetchCount += 1 }

    nonisolated func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        await recordFetch()
        if dateRange == wideRange {
            await markWideEntered()
            await awaitWideGate()
            return HealthFetchResult(dataPoints: widePoints, deletedObjectIDs: [])
        }
        if dateRange == narrowRange {
            await markNarrowEntered()
            await awaitNarrowGate()
            return HealthFetchResult(dataPoints: narrowPoints, deletedObjectIDs: [])
        }
        return HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}

private actor GatedRefreshProvider: HealthDataProviding {
    let wideRange: DateInterval
    let narrowRange: DateInterval
    let bgRefreshPoints: [HealthDataPoint]
    let explicitRefreshPoints: [HealthDataPoint]

    private var _fetchCount = 0
    private var _wideFetchCount = 0
    // Signal fired when the background (wide-range) provider call is entered.
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var startedFired = false
    // Gate that the background (wide-range) call awaits until released.
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private var gateReleased = false
    // Set to true after the background call has fully returned.
    private(set) var backgroundRefreshDidComplete = false

    init(
        wideRange: DateInterval,
        narrowRange: DateInterval,
        bgRefreshPoints: [HealthDataPoint],
        explicitRefreshPoints: [HealthDataPoint]
    ) {
        self.wideRange = wideRange
        self.narrowRange = narrowRange
        self.bgRefreshPoints = bgRefreshPoints
        self.explicitRefreshPoints = explicitRefreshPoints
    }

    var fetchCount: Int { _fetchCount }
    var wideFetchCount: Int { _wideFetchCount }
    var startedFiredSnapshot: Bool { startedFired }
    var wideEnteredSnapshot: Bool { startedFired }

    // Await inside the test until the bg provider call has been entered.
    func awaitBackgroundRefreshStarted() async {
        if startedFired { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            startedContinuation = cont
        }
    }

    func releaseBackgroundRefresh() {
        gateReleased = true
        gateContinuation?.resume()
        gateContinuation = nil
    }

    private func fireStarted() {
        startedFired = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    private func awaitGate() async {
        if gateReleased { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            gateContinuation = cont
        }
    }

    private func recordFetch() { _fetchCount += 1 }
    private func recordWideFetch() { _wideFetchCount += 1 }
    private func markBackgroundRefreshComplete() { backgroundRefreshDidComplete = true }

    nonisolated func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        await recordFetch()
        if dateRange == wideRange {
            // Background refresh path — count the entry, signal start, park
            // at gate, then return. The wide-fetch counter proves the bg
            // Task body reached `performFetch` (regression), independent of
            // whether it later parked at the gate or was already cancelled.
            await recordWideFetch()
            await fireStarted()
            await awaitGate()
            let payload = bgRefreshPoints
            await markBackgroundRefreshComplete()
            return HealthFetchResult(dataPoints: payload, deletedObjectIDs: [])
        }
        if dateRange == narrowRange {
            // Explicit refresh path — fast, ungated.
            return HealthFetchResult(dataPoints: explicitRefreshPoints, deletedObjectIDs: [])
        }
        return HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}
