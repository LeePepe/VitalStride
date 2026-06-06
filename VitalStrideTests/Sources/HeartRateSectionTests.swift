import Foundation
import HealthKitService
import Testing

@testable import VitalStride

// MARK: - Test Helpers

private func makeHeartRatePoint(
    value: Double,
    at date: Date = Date()
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .heartRate,
        startDate: date,
        endDate: date,
        value: value,
        unit: "bpm",
        sleepStage: nil,
        sourceName: "Test"
    )
}

private let calendar = Calendar.current

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

// MARK: - Average Tests

@Suite("HeartRateStats.average")
struct HeartRateStatsAverageTests {
    @Test("Returns nil for empty array")
    func emptyArray() {
        #expect(HeartRateStats.average(of: []) == nil)
    }

    @Test("Returns value for single point")
    func singlePoint() {
        let points = [makeHeartRatePoint(value: 72)]
        #expect(HeartRateStats.average(of: points) == 72.0)
    }

    @Test("Computes correct average for multiple points")
    func multiplePoints() {
        let points = [
            makeHeartRatePoint(value: 60),
            makeHeartRatePoint(value: 80),
            makeHeartRatePoint(value: 100),
        ]
        #expect(HeartRateStats.average(of: points) == 80.0)
    }

    @Test("Handles fractional averages")
    func fractionalAverage() {
        let points = [
            makeHeartRatePoint(value: 71),
            makeHeartRatePoint(value: 72),
        ]
        #expect(HeartRateStats.average(of: points) == 71.5)
    }
}

// MARK: - Max Tests

@Suite("HeartRateStats.max")
struct HeartRateStatsMaxTests {
    @Test("Returns nil for empty array")
    func emptyArray() {
        #expect(HeartRateStats.max(of: []) == nil)
    }

    @Test("Returns value for single point")
    func singlePoint() {
        let points = [makeHeartRatePoint(value: 120)]
        #expect(HeartRateStats.max(of: points) == 120.0)
    }

    @Test("Finds maximum value")
    func findsMax() {
        let points = [
            makeHeartRatePoint(value: 60),
            makeHeartRatePoint(value: 150),
            makeHeartRatePoint(value: 90),
        ]
        #expect(HeartRateStats.max(of: points) == 150.0)
    }
}

// MARK: - Min Tests

@Suite("HeartRateStats.min")
struct HeartRateStatsMinTests {
    @Test("Returns nil for empty array")
    func emptyArray() {
        #expect(HeartRateStats.min(of: []) == nil)
    }

    @Test("Returns value for single point")
    func singlePoint() {
        let points = [makeHeartRatePoint(value: 55)]
        #expect(HeartRateStats.min(of: points) == 55.0)
    }

    @Test("Finds minimum value")
    func findsMin() {
        let points = [
            makeHeartRatePoint(value: 90),
            makeHeartRatePoint(value: 45),
            makeHeartRatePoint(value: 70),
        ]
        #expect(HeartRateStats.min(of: points) == 45.0)
    }
}

// MARK: - Filter Tests

@Suite("HeartRateStats.filtered")
struct HeartRateStatsFilterTests {
    @Test("Returns empty for empty input")
    func emptyInput() {
        let interval = DateInterval(
            start: date(2026, 6, 1),
            end: date(2026, 6, 2)
        )
        #expect(HeartRateStats.filtered([], in: interval).isEmpty)
    }

    @Test("Includes points within range")
    func withinRange() {
        let points = [
            makeHeartRatePoint(value: 72, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 14)),
        ]
        let interval = DateInterval(
            start: date(2026, 6, 1),
            end: date(2026, 6, 2)
        )
        let filtered = HeartRateStats.filtered(points, in: interval)
        #expect(filtered.count == 2)
    }

    @Test("Excludes points outside range")
    func outsideRange() {
        let points = [
            makeHeartRatePoint(value: 72, at: date(2026, 5, 31, 23)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 90, at: date(2026, 6, 2, 1)),
        ]
        let interval = DateInterval(
            start: date(2026, 6, 1),
            end: date(2026, 6, 2)
        )
        let filtered = HeartRateStats.filtered(points, in: interval)
        #expect(filtered.count == 1)
        #expect(filtered[0].value == 80)
    }

    @Test("Includes start boundary, excludes end boundary")
    func boundaryBehavior() {
        let startDate = date(2026, 6, 1)
        let endDate = date(2026, 6, 2)
        let points = [
            makeHeartRatePoint(value: 72, at: startDate),
            makeHeartRatePoint(value: 80, at: endDate),
        ]
        let interval = DateInterval(start: startDate, end: endDate)
        let filtered = HeartRateStats.filtered(points, in: interval)
        #expect(filtered.count == 1)
        #expect(filtered[0].value == 72)
    }
}

// MARK: - Nearest Point Tests

@Suite("HeartRateStats.nearest")
struct HeartRateStatsNearestTests {
    @Test("Returns nil for empty array")
    func emptyArray() {
        #expect(HeartRateStats.nearest(to: Date(), in: []) == nil)
    }

    @Test("Returns only point for single-element array")
    func singlePoint() {
        let point = makeHeartRatePoint(value: 72, at: date(2026, 6, 1, 12))
        let nearest = HeartRateStats.nearest(to: date(2026, 6, 1, 15), in: [point])
        #expect(nearest?.id == point.id)
    }

    @Test("Finds closest point by time")
    func findsClosest() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 8)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 12)),
            makeHeartRatePoint(value: 90, at: date(2026, 6, 1, 18)),
        ]
        let nearest = HeartRateStats.nearest(to: date(2026, 6, 1, 11), in: points)
        #expect(nearest?.value == 80)
    }

    @Test("Prefers earlier point when equidistant")
    func equidistant() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 14)),
        ]
        let nearest = HeartRateStats.nearest(to: date(2026, 6, 1, 12), in: points)
        #expect(nearest != nil)
    }
}

// MARK: - Combined Stats Tests

@Suite("HeartRateStats combined scenarios")
struct HeartRateStatsCombinedTests {
    @Test("All stats nil for empty data")
    func allNilForEmpty() {
        let empty: [HealthDataPoint] = []
        #expect(HeartRateStats.average(of: empty) == nil)
        #expect(HeartRateStats.max(of: empty) == nil)
        #expect(HeartRateStats.min(of: empty) == nil)
    }

    @Test("All stats equal for single data point")
    func allEqualForSingle() {
        let points = [makeHeartRatePoint(value: 72)]
        #expect(HeartRateStats.average(of: points) == 72)
        #expect(HeartRateStats.max(of: points) == 72)
        #expect(HeartRateStats.min(of: points) == 72)
    }

    @Test("Stats correct for realistic heart rate data")
    func realisticData() {
        let points = [
            makeHeartRatePoint(value: 62),
            makeHeartRatePoint(value: 68),
            makeHeartRatePoint(value: 75),
            makeHeartRatePoint(value: 130),
            makeHeartRatePoint(value: 145),
            makeHeartRatePoint(value: 88),
            makeHeartRatePoint(value: 72),
        ]
        let avg = HeartRateStats.average(of: points)!
        #expect(abs(avg - 91.43) < 0.01)
        #expect(HeartRateStats.max(of: points) == 145)
        #expect(HeartRateStats.min(of: points) == 62)
    }

    @Test("Filter then compute stats on subset")
    func filterThenCompute() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 8)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 12)),
            makeHeartRatePoint(value: 100, at: date(2026, 6, 2, 8)),
        ]
        let interval = DateInterval(
            start: date(2026, 6, 1),
            end: date(2026, 6, 2)
        )
        let filtered = HeartRateStats.filtered(points, in: interval)
        #expect(filtered.count == 2)
        #expect(HeartRateStats.average(of: filtered) == 70)
        #expect(HeartRateStats.max(of: filtered) == 80)
        #expect(HeartRateStats.min(of: filtered) == 60)
    }
}

// MARK: - Downsample Tests

@Suite("HeartRateStats.downsample")
struct HeartRateStatsDownsampleTests {
    @Test("Day range returns data unchanged")
    func dayPassthrough() {
        let points = [
            makeHeartRatePoint(value: 72, at: date(2026, 6, 1, 8)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 12)),
        ]
        let result = HeartRateStats.downsample(points, for: .day)
        #expect(result.count == 2)
        #expect(result[0].value == 72)
        #expect(result[1].value == 80)
    }

    @Test("Week range returns data unchanged")
    func weekPassthrough() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 90, at: date(2026, 6, 2, 10)),
        ]
        let result = HeartRateStats.downsample(points, for: .week)
        #expect(result.count == 2)
    }

    @Test("Month range aggregates by hour")
    func monthAggregation() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 80, at: calendar.date(byAdding: .minute, value: 15, to: date(2026, 6, 1, 10))!),
            makeHeartRatePoint(value: 100, at: calendar.date(byAdding: .minute, value: 30, to: date(2026, 6, 1, 10))!),
            makeHeartRatePoint(value: 72, at: date(2026, 6, 1, 11)),
        ]
        let result = HeartRateStats.downsample(points, for: .month)
        #expect(result.count == 2)
        let hourTenBucket = result.first { $0.startDate == date(2026, 6, 1, 10) }
        #expect(hourTenBucket != nil)
        #expect(hourTenBucket!.value == 80.0)
    }

    @Test("Year range aggregates by day")
    func yearAggregation() {
        let points = [
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 8)),
            makeHeartRatePoint(value: 80, at: date(2026, 6, 1, 12)),
            makeHeartRatePoint(value: 100, at: date(2026, 6, 1, 18)),
            makeHeartRatePoint(value: 72, at: date(2026, 6, 2, 10)),
        ]
        let result = HeartRateStats.downsample(points, for: .year)
        #expect(result.count == 2)
        let day1 = result.first { Calendar.current.isDate($0.startDate, inSameDayAs: date(2026, 6, 1)) }
        #expect(day1 != nil)
        #expect(day1!.value == 80.0)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let result = HeartRateStats.downsample([], for: .year)
        #expect(result.isEmpty)
    }

    @Test("Results are sorted by date")
    func sorted() {
        let points = [
            makeHeartRatePoint(value: 80, at: date(2026, 6, 3, 10)),
            makeHeartRatePoint(value: 60, at: date(2026, 6, 1, 10)),
            makeHeartRatePoint(value: 70, at: date(2026, 6, 2, 10)),
        ]
        let result = HeartRateStats.downsample(points, for: .year)
        #expect(result.count == 3)
        #expect(result[0].startDate < result[1].startDate)
        #expect(result[1].startDate < result[2].startDate)
    }
}
