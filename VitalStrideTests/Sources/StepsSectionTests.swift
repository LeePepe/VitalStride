import Foundation
import Testing

@testable import VitalStride

// MARK: - Test Helpers

private func makeStepPoint(
    date: Date,
    value: Double,
    endDate: Date? = nil
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .stepCount,
        startDate: date,
        endDate: endDate ?? date,
        value: value,
        unit: "count",
        sleepStage: nil,
        sourceName: "TestSource"
    )
}

private let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - StepsAggregator.aggregateByDay Tests

@Suite("StepsAggregator — aggregateByDay")
struct AggregateByDayTests {
    @Test("Multiple samples on the same day are summed")
    func sameDaySumming() {
        let day = date(2026, 6, 1)
        let points = [
            makeStepPoint(date: date(2026, 6, 1, hour: 8), value: 1000),
            makeStepPoint(date: date(2026, 6, 1, hour: 12), value: 2500),
            makeStepPoint(date: date(2026, 6, 1, hour: 18), value: 1500),
        ]
        let interval = DateInterval(start: day, end: date(2026, 6, 2))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].totalSteps == 5000)
    }

    @Test("Samples on different days are grouped correctly")
    func crossDayGrouping() {
        let points = [
            makeStepPoint(date: date(2026, 6, 1, hour: 9), value: 3000),
            makeStepPoint(date: date(2026, 6, 2, hour: 10), value: 5000),
            makeStepPoint(date: date(2026, 6, 3, hour: 14), value: 2000),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        #expect(result[0].date == date(2026, 6, 1))
        #expect(result[0].totalSteps == 3000)
        #expect(result[1].date == date(2026, 6, 2))
        #expect(result[1].totalSteps == 5000)
        #expect(result[2].date == date(2026, 6, 3))
        #expect(result[2].totalSteps == 2000)
    }

    @Test("Empty data points produce zero-filled days")
    func emptyDataPoints() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: [], in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        for day in result {
            #expect(day.totalSteps == 0)
        }
    }

    @Test("Days without samples remain zero")
    func gapDays() {
        let points = [
            makeStepPoint(date: date(2026, 6, 1, hour: 10), value: 8000),
            makeStepPoint(date: date(2026, 6, 3, hour: 10), value: 6000),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        #expect(result[0].totalSteps == 8000)
        #expect(result[1].totalSteps == 0)
        #expect(result[2].totalSteps == 6000)
    }

    @Test("Data points outside interval are ignored")
    func outsideIntervalIgnored() {
        let points = [
            makeStepPoint(date: date(2026, 5, 31, hour: 23), value: 999),
            makeStepPoint(date: date(2026, 6, 1, hour: 10), value: 5000),
            makeStepPoint(date: date(2026, 6, 3, hour: 1), value: 777),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 2)
        #expect(result[0].totalSteps == 5000)
        #expect(result[1].totalSteps == 0)
    }

    @Test("Non-stepCount sample types are filtered out")
    func filtersSampleType() {
        let stepPoint = makeStepPoint(date: date(2026, 6, 1, hour: 10), value: 3000)
        let heartRatePoint = HealthDataPoint(
            id: UUID(),
            sampleType: .heartRate,
            startDate: date(2026, 6, 1, hour: 10),
            endDate: date(2026, 6, 1, hour: 10),
            value: 72,
            unit: "bpm",
            sleepStage: nil,
            sourceName: "TestSource"
        )
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: [stepPoint, heartRatePoint], in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].totalSteps == 3000)
    }

    @Test("Results are sorted by date ascending")
    func sortedByDate() {
        let points = [
            makeStepPoint(date: date(2026, 6, 3, hour: 10), value: 100),
            makeStepPoint(date: date(2026, 6, 1, hour: 10), value: 300),
            makeStepPoint(date: date(2026, 6, 2, hour: 10), value: 200),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        #expect(result[0].date < result[1].date)
        #expect(result[1].date < result[2].date)
    }

    @Test("Single day interval produces one entry")
    func singleDayInterval() {
        let points = [makeStepPoint(date: date(2026, 6, 1, hour: 15), value: 4200)]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].totalSteps == 4200)
    }

    @Test("Sample spanning midnight splits proportionally between days")
    func midnightOverlapSplit() {
        let points = [
            makeStepPoint(
                date: date(2026, 6, 1, hour: 22),
                value: 1000,
                endDate: date(2026, 6, 2, hour: 2)
            ),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 2)
        #expect(result[0].totalSteps == 500)
        #expect(result[1].totalSteps == 500)
    }

    @Test("Sample spanning multiple days splits proportionally")
    func multiDayOverlapSplit() {
        let points = [
            makeStepPoint(
                date: date(2026, 6, 1, hour: 12),
                value: 3000,
                endDate: date(2026, 6, 3, hour: 12)
            ),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = StepsAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        #expect(result[0].totalSteps == 750)
        #expect(result[1].totalSteps == 1500)
        #expect(result[2].totalSteps == 750)
    }
}

// MARK: - StepsAggregator.splitAcrossDays Tests

@Suite("StepsAggregator — splitAcrossDays")
struct SplitAcrossDaysTests {
    @Test("Same-day sample returns single contribution")
    func sameDaySample() {
        let point = makeStepPoint(
            date: date(2026, 6, 1, hour: 10),
            value: 500,
            endDate: date(2026, 6, 1, hour: 11)
        )

        let result = StepsAggregator.splitAcrossDays(point: point, calendar: testCalendar)

        #expect(result.count == 1)
        #expect(result[0].day == date(2026, 6, 1))
        #expect(result[0].value == 500)
    }

    @Test("Point-in-time sample (start == end) returns single contribution")
    func pointSample() {
        let point = makeStepPoint(
            date: date(2026, 6, 1, hour: 10),
            value: 200
        )

        let result = StepsAggregator.splitAcrossDays(point: point, calendar: testCalendar)

        #expect(result.count == 1)
        #expect(result[0].value == 200)
    }

    @Test("Midnight-spanning sample returns two contributions")
    func midnightSpan() {
        let point = makeStepPoint(
            date: date(2026, 6, 1, hour: 20),
            value: 600,
            endDate: date(2026, 6, 2, hour: 4)
        )

        let result = StepsAggregator.splitAcrossDays(point: point, calendar: testCalendar)

        #expect(result.count == 2)
        #expect(result[0].day == date(2026, 6, 1))
        #expect(result[1].day == date(2026, 6, 2))
        let total = result.map(\.value).reduce(0, +)
        #expect(abs(total - 600) < 0.01)
    }
}

// MARK: - StepsAggregator.computeStatistics Tests

@Suite("StepsAggregator — computeStatistics")
struct ComputeStatisticsTests {
    @Test("Computes daily average correctly")
    func dailyAverage() {
        let data = [
            DailyStepData(date: date(2026, 6, 1), totalSteps: 6000),
            DailyStepData(date: date(2026, 6, 2), totalSteps: 8000),
            DailyStepData(date: date(2026, 6, 3), totalSteps: 10000),
        ]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.dailyAverage == 8000)
    }

    @Test("Identifies maximum single day")
    func maxSingleDay() {
        let data = [
            DailyStepData(date: date(2026, 6, 1), totalSteps: 3000),
            DailyStepData(date: date(2026, 6, 2), totalSteps: 12000),
            DailyStepData(date: date(2026, 6, 3), totalSteps: 7000),
        ]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.maxSingleDay == 12000)
    }

    @Test("Computes total steps correctly")
    func totalSteps() {
        let data = [
            DailyStepData(date: date(2026, 6, 1), totalSteps: 5000),
            DailyStepData(date: date(2026, 6, 2), totalSteps: 7000),
        ]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.totalSteps == 12000)
    }

    @Test("Empty input returns zero statistics")
    func emptyInput() {
        let stats = StepsAggregator.computeStatistics(from: [])

        #expect(stats == .empty)
        #expect(stats.dailyAverage == 0)
        #expect(stats.maxSingleDay == 0)
        #expect(stats.totalSteps == 0)
    }

    @Test("Single day data")
    func singleDay() {
        let data = [DailyStepData(date: date(2026, 6, 1), totalSteps: 9500)]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.dailyAverage == 9500)
        #expect(stats.maxSingleDay == 9500)
        #expect(stats.totalSteps == 9500)
    }

    @Test("Days with zero steps are included in average")
    func zeroDaysIncluded() {
        let data = [
            DailyStepData(date: date(2026, 6, 1), totalSteps: 10000),
            DailyStepData(date: date(2026, 6, 2), totalSteps: 0),
        ]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.dailyAverage == 5000)
        #expect(stats.maxSingleDay == 10000)
        #expect(stats.totalSteps == 10000)
    }

    @Test("Average truncates to integer (floor division)")
    func averageTruncation() {
        let data = [
            DailyStepData(date: date(2026, 6, 1), totalSteps: 10),
            DailyStepData(date: date(2026, 6, 2), totalSteps: 11),
            DailyStepData(date: date(2026, 6, 3), totalSteps: 12),
        ]

        let stats = StepsAggregator.computeStatistics(from: data)

        #expect(stats.dailyAverage == 11)
        #expect(stats.totalSteps == 33)
    }
}

// MARK: - Model Tests

@Suite("DailyStepData")
struct DailyStepDataTests {
    @Test("id matches date")
    func idMatchesDate() {
        let d = date(2026, 6, 1)
        let item = DailyStepData(date: d, totalSteps: 5000)
        #expect(item.id == d)
    }
}

@Suite("StepsStatistics")
struct StepsStatisticsTests {
    @Test("Empty constant has all zeros")
    func emptyConstant() {
        let empty = StepsStatistics.empty
        #expect(empty.dailyAverage == 0)
        #expect(empty.maxSingleDay == 0)
        #expect(empty.totalSteps == 0)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = StepsStatistics(dailyAverage: 100, maxSingleDay: 200, totalSteps: 300)
        let b = StepsStatistics(dailyAverage: 100, maxSingleDay: 200, totalSteps: 300)
        let c = StepsStatistics(dailyAverage: 100, maxSingleDay: 201, totalSteps: 300)
        #expect(a == b)
        #expect(a != c)
    }
}
