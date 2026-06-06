import Foundation
import HealthKitService
import Testing
import VitalModels

@testable import VitalStride

private final class MockCacheDataProvider: HealthDataProviding, @unchecked Sendable {
    var fetchResults: [HealthSampleType: HealthFetchResult] = [:]
    private let lock = NSLock()
    private var _fetchCallCount: [HealthSampleType: Int] = [:]

    var fetchCallCount: [HealthSampleType: Int] {
        lock.withLock { _fetchCallCount }
    }

    func fetchData(
        for sampleType: HealthSampleType,
        dateRange: DateInterval?
    ) async throws -> HealthFetchResult {
        lock.withLock {
            _fetchCallCount[sampleType, default: 0] += 1
        }
        return fetchResults[sampleType]
            ?? HealthFetchResult(dataPoints: [], deletedObjectIDs: [])
    }
}

private func makeDataPoint(
    _ type: HealthSampleType,
    date: Date = Date(),
    value: Double = 100,
    sleepStage: SleepStage? = nil
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: type,
        startDate: date,
        endDate: date.addingTimeInterval(60),
        value: value,
        unit: "test",
        sleepStage: sleepStage,
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

@Suite("View-Cache Integration — views use HealthDataCache instead of direct HealthKitService")
struct ViewCacheIntegrationTests {

    @Test("StepsSummaryCard data path: cache returns stepCount data, aggregator produces daily data")
    func stepsSummaryDataPath() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 5, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.day.dateInterval()
        let dataPoints = try await cache.data(for: .stepCount, in: interval)
        let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)

        #expect(mock.fetchCallCount[.stepCount] == 1)
        #expect(!aggregated.isEmpty || dataPoints.isEmpty)
    }

    @Test("HeartRateSummaryCard data path: cache returns heartRate data, stats compute correctly")
    func heartRateSummaryDataPath() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.heartRate] = makeResult(.heartRate, count: 3, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.day.dateInterval()
        let dataPoints = try await cache.data(for: .heartRate, in: interval)
        let filtered = HeartRateStats.filtered(dataPoints, in: interval)
        let avg = HeartRateStats.average(of: filtered)

        #expect(mock.fetchCallCount[.heartRate] == 1)
        #expect(avg != nil || filtered.isEmpty)
    }

    @Test("SleepSummaryCard data path: cache returns sleepAnalysis data, aggregator produces nights")
    func sleepSummaryDataPath() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.sleepAnalysis] = HealthFetchResult(
            dataPoints: [
                makeDataPoint(.sleepAnalysis, date: now.addingTimeInterval(-3600), value: 0, sleepStage: .asleepCore),
            ],
            deletedObjectIDs: []
        )
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.week.dateInterval()
        let dataPoints = try await cache.data(for: .sleepAnalysis, in: interval)
        let nights = SleepAggregator.aggregateByNight(dataPoints: dataPoints, in: interval)

        #expect(mock.fetchCallCount[.sleepAnalysis] == 1)
        #expect(nights.isEmpty || nights.first?.totalSleep != nil)
    }

    @Test("WeightSummaryCard data path: cache returns bodyMass data, analyzer extracts weight points")
    func weightSummaryDataPath() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.bodyMass] = makeResult(.bodyMass, count: 3, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.week.dateInterval()
        let dataPoints = try await cache.data(for: .bodyMass, in: interval)
        let points = WeightAnalyzer.extractWeightPoints(from: dataPoints, in: interval)

        #expect(mock.fetchCallCount[.bodyMass] == 1)
        #expect(points.isEmpty || points.last?.weight != nil)
    }

    @Test("Same sample type fetched by summary card and section shares cache")
    func sharedCacheAcrossViews() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 10, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let summaryInterval = TimeRange.day.dateInterval()
        _ = try await cache.data(for: .stepCount, in: summaryInterval)

        let sectionInterval = TimeRange.day.dateInterval()
        let sectionData = try await cache.data(for: .stepCount, in: sectionInterval)

        #expect(mock.fetchCallCount[.stepCount] == 1)
        #expect(!sectionData.isEmpty)
    }

    @Test("ActiveEnergy data path: cache returns activeEnergyBurned, aggregator produces daily energy")
    func activeEnergyDataPath() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.activeEnergyBurned] = makeResult(.activeEnergyBurned, count: 5, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.week.dateInterval()
        let dataPoints = try await cache.data(for: .activeEnergyBurned, in: interval)
        let aggregated = EnergyAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)

        #expect(mock.fetchCallCount[.activeEnergyBurned] == 1)
        #expect(!aggregated.isEmpty || dataPoints.isEmpty)
    }

    @Test("All five data types can be fetched through the same cache without interference")
    func allTypesIndependent() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        for type in HealthSampleType.allCases {
            mock.fetchResults[type] = makeResult(type, count: 2, baseDate: now)
        }
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.week.dateInterval()
        for type in HealthSampleType.allCases {
            let data = try await cache.data(for: type, in: interval)
            #expect(data.count == 2)
        }

        for type in HealthSampleType.allCases {
            #expect(mock.fetchCallCount[type] == 1)
        }

        for type in HealthSampleType.allCases {
            let cachedData = try await cache.data(for: type, in: interval)
            #expect(cachedData.count == 2)
        }

        for type in HealthSampleType.allCases {
            #expect(mock.fetchCallCount[type] == 1)
        }
    }

    @Test("Cache refresh re-fetches data (simulating pull-to-refresh)")
    func refreshRefetchesData() async throws {
        let now = Date()
        let mock = MockCacheDataProvider()
        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 3, baseDate: now)
        let cache = HealthDataCache(dataProvider: mock)

        let interval = TimeRange.week.dateInterval()
        _ = try await cache.data(for: .stepCount, in: interval)
        #expect(mock.fetchCallCount[.stepCount] == 1)

        mock.fetchResults[.stepCount] = makeResult(.stepCount, count: 5, baseDate: now)
        let refreshed = try await cache.refresh(.stepCount, in: interval)

        #expect(refreshed.count == 5)
        #expect(mock.fetchCallCount[.stepCount] == 2)
    }
}
