import Foundation
import HealthKitService
import Testing

@testable import VitalStride

// MARK: - Test Helpers

private let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func makeWeightPoint(
    date: Date,
    value: Double
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .bodyMass,
        startDate: date,
        endDate: date,
        value: value,
        unit: "kg",
        sleepStage: nil,
        sourceName: "TestSource"
    )
}

// MARK: - WeightAnalyzer.extractWeightPoints Tests

@Suite("WeightAnalyzer — extractWeightPoints")
struct ExtractWeightPointsTests {
    @Test("Filters and sorts by date")
    func filtersAndSorts() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 8))
        let points = [
            makeWeightPoint(date: date(2026, 6, 3), value: 74.0),
            makeWeightPoint(date: date(2026, 6, 1), value: 75.0),
            makeWeightPoint(date: date(2026, 6, 5), value: 73.5),
        ]
        let result = WeightAnalyzer.extractWeightPoints(from: points, in: interval)
        #expect(result.count == 3)
        #expect(result[0].date == date(2026, 6, 1))
        #expect(result[1].date == date(2026, 6, 3))
        #expect(result[2].date == date(2026, 6, 5))
    }

    @Test("Excludes points outside interval")
    func excludesOutside() {
        let interval = DateInterval(start: date(2026, 6, 2), end: date(2026, 6, 4))
        let points = [
            makeWeightPoint(date: date(2026, 6, 1), value: 75.0),
            makeWeightPoint(date: date(2026, 6, 2, hour: 8), value: 74.5),
            makeWeightPoint(date: date(2026, 6, 5), value: 73.0),
        ]
        let result = WeightAnalyzer.extractWeightPoints(from: points, in: interval)
        #expect(result.count == 1)
        #expect(result[0].weight == 74.5)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 8))
        let result = WeightAnalyzer.extractWeightPoints(from: [], in: interval)
        #expect(result.isEmpty)
    }

    @Test("Filters by bodyMass sample type")
    func filtersBySampleType() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 8))
        let heartRatePoint = HealthDataPoint(
            id: UUID(),
            sampleType: .heartRate,
            startDate: date(2026, 6, 2),
            endDate: date(2026, 6, 2),
            value: 72.0,
            unit: "bpm",
            sleepStage: nil,
            sourceName: nil
        )
        let weightPoint = makeWeightPoint(date: date(2026, 6, 3), value: 74.0)
        let result = WeightAnalyzer.extractWeightPoints(from: [heartRatePoint, weightPoint], in: interval)
        #expect(result.count == 1)
        #expect(result[0].weight == 74.0)
    }
}

// MARK: - WeightAnalyzer.computeStatistics Tests

@Suite("WeightAnalyzer — computeStatistics")
struct ComputeWeightStatisticsTests {
    @Test("Computes all stats correctly")
    func allStats() {
        let points = [
            WeightDataPoint(date: date(2026, 6, 1), weight: 75.0),
            WeightDataPoint(date: date(2026, 6, 3), weight: 74.0),
            WeightDataPoint(date: date(2026, 6, 5), weight: 73.0),
        ]
        let stats = WeightAnalyzer.computeStatistics(from: points)
        #expect(stats.latest == 73.0)
        #expect(stats.change == -2.0)
        #expect(stats.max == 75.0)
        #expect(stats.min == 73.0)
    }

    @Test("Single point has no change")
    func singlePoint() {
        let points = [WeightDataPoint(date: date(2026, 6, 1), weight: 75.0)]
        let stats = WeightAnalyzer.computeStatistics(from: points)
        #expect(stats.latest == 75.0)
        #expect(stats.change == nil)
        #expect(stats.max == 75.0)
        #expect(stats.min == 75.0)
    }

    @Test("Empty input returns nil stats")
    func emptyInput() {
        let stats = WeightAnalyzer.computeStatistics(from: [])
        #expect(stats.latest == nil)
        #expect(stats.change == nil)
        #expect(stats.max == nil)
        #expect(stats.min == nil)
    }

    @Test("Positive change when weight increases")
    func positiveChange() {
        let points = [
            WeightDataPoint(date: date(2026, 6, 1), weight: 70.0),
            WeightDataPoint(date: date(2026, 6, 5), weight: 72.5),
        ]
        let stats = WeightAnalyzer.computeStatistics(from: points)
        #expect(stats.change == 2.5)
    }
}

// MARK: - WeightAnalyzer.movingAverage Tests

@Suite("WeightAnalyzer — movingAverage")
struct MovingAverageTests {
    @Test("Window size 3 calculates correctly")
    func windowSize3() {
        let points = [
            WeightDataPoint(date: date(2026, 6, 1), weight: 75.0),
            WeightDataPoint(date: date(2026, 6, 2), weight: 74.0),
            WeightDataPoint(date: date(2026, 6, 3), weight: 73.0),
            WeightDataPoint(date: date(2026, 6, 4), weight: 72.0),
        ]
        let result = WeightAnalyzer.movingAverage(of: points, windowSize: 3)
        #expect(result.count == 4)
        #expect(result[0].weight == 75.0)
        #expect(result[1].weight == 74.5)
        #expect(abs(result[2].weight - 74.0) < 0.01)
        #expect(abs(result[3].weight - 73.0) < 0.01)
    }

    @Test("Single point returns as-is")
    func singlePoint() {
        let points = [WeightDataPoint(date: date(2026, 6, 1), weight: 75.0)]
        let result = WeightAnalyzer.movingAverage(of: points)
        #expect(result.count == 1)
        #expect(result[0].weight == 75.0)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let result = WeightAnalyzer.movingAverage(of: [])
        #expect(result.isEmpty)
    }

    @Test("Window larger than data uses available points")
    func windowLargerThanData() {
        let points = [
            WeightDataPoint(date: date(2026, 6, 1), weight: 80.0),
            WeightDataPoint(date: date(2026, 6, 2), weight: 70.0),
        ]
        let result = WeightAnalyzer.movingAverage(of: points, windowSize: 10)
        #expect(result.count == 2)
        #expect(result[0].weight == 80.0)
        #expect(result[1].weight == 75.0)
    }
}

// MARK: - WeightAnalyzer.nearest Tests

@Suite("WeightAnalyzer — nearest")
struct NearestWeightTests {
    @Test("Finds closest point")
    func findsClosest() {
        let points = [
            WeightDataPoint(date: date(2026, 6, 1), weight: 75.0),
            WeightDataPoint(date: date(2026, 6, 5), weight: 74.0),
            WeightDataPoint(date: date(2026, 6, 10), weight: 73.0),
        ]
        let result = WeightAnalyzer.nearest(to: date(2026, 6, 4), in: points)
        #expect(result?.weight == 74.0)
    }

    @Test("Empty returns nil")
    func emptyReturnsNil() {
        let result = WeightAnalyzer.nearest(to: date(2026, 6, 1), in: [])
        #expect(result == nil)
    }
}

// MARK: - Model Tests

@Suite("Weight Models")
struct WeightModelTests {
    @Test("WeightDataPoint id is date")
    func weightDataPointId() {
        let d = date(2026, 6, 1)
        let point = WeightDataPoint(date: d, weight: 75.0)
        #expect(point.id == d)
    }

    @Test("WeightStatistics equality")
    func statisticsEquality() {
        let a = WeightStatistics(latest: 75.0, change: -1.0, max: 76.0, min: 74.0)
        let b = WeightStatistics(latest: 75.0, change: -1.0, max: 76.0, min: 74.0)
        #expect(a == b)
    }
}
