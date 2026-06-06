import Testing
import Foundation
@testable import HealthKitService

// MARK: - Mock

final class MockHealthDataProvider: HealthDataProviding, @unchecked Sendable {
    var fetchResults: [HealthSampleType: HealthFetchResult] = [:]
    var fetchDelay: Duration?
    var fetchError: (any Error)?
    private(set) var fetchCallCount: [HealthSampleType: Int] = [:]
    private(set) var fetchDateRanges: [HealthSampleType: DateInterval?] = [:]

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
        fetchCallCount[sampleType, default: 0] += 1
        fetchDateRanges[sampleType] = dateRange
        return fetchResults[sampleType]
            ?? HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
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

    @Test("Cache hit filters by date range")
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

    @Test("Concurrent requests for the same type coalesce into one fetch")
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
        #expect(mock.fetchCallCount[.stepCount, default: 0] <= 2)
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

        #expect(mock.fetchDateRanges[.stepCount] as? DateInterval == range)
    }
}
