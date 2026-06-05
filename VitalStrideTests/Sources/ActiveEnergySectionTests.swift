import Foundation
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

private func makeEnergyPoint(
    date: Date,
    value: Double,
    endDate: Date? = nil
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .activeEnergyBurned,
        startDate: date,
        endDate: endDate ?? date,
        value: value,
        unit: "kcal",
        sleepStage: nil,
        sourceName: "TestSource"
    )
}

// MARK: - EnergyAggregator.aggregateByDay Tests

@Suite("EnergyAggregator — aggregateByDay")
struct EnergyAggregateByDayTests {
    @Test("Multiple samples on the same day are summed")
    func sameDaySumming() {
        let day = date(2026, 6, 1)
        let points = [
            makeEnergyPoint(date: date(2026, 6, 1, hour: 8), value: 150.0),
            makeEnergyPoint(date: date(2026, 6, 1, hour: 12), value: 200.0),
            makeEnergyPoint(date: date(2026, 6, 1, hour: 18), value: 100.0),
        ]
        let interval = DateInterval(start: day, end: date(2026, 6, 2))

        let result = EnergyAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].totalEnergy == 450.0)
    }

    @Test("Samples on different days are grouped correctly")
    func crossDayGrouping() {
        let points = [
            makeEnergyPoint(date: date(2026, 6, 1, hour: 9), value: 300.0),
            makeEnergyPoint(date: date(2026, 6, 2, hour: 10), value: 500.0),
            makeEnergyPoint(date: date(2026, 6, 3, hour: 14), value: 200.0),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = EnergyAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        #expect(result[0].totalEnergy == 300.0)
        #expect(result[1].totalEnergy == 500.0)
        #expect(result[2].totalEnergy == 200.0)
    }

    @Test("Empty data points produce zero-filled days")
    func emptyDataPoints() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))
        let result = EnergyAggregator.aggregateByDay(
            dataPoints: [], in: interval, calendar: testCalendar
        )
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.totalEnergy == 0 })
    }

    @Test("Points outside interval are ignored")
    func outsideInterval() {
        let points = [
            makeEnergyPoint(date: date(2026, 5, 31), value: 500.0),
            makeEnergyPoint(date: date(2026, 6, 1, hour: 10), value: 300.0),
            makeEnergyPoint(date: date(2026, 6, 4), value: 400.0),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))

        let result = EnergyAggregator.aggregateByDay(
            dataPoints: points, in: interval, calendar: testCalendar
        )

        #expect(result.count == 2)
        #expect(result[0].totalEnergy == 300.0)
        #expect(result[1].totalEnergy == 0)
    }

    @Test("Filters by activeEnergyBurned sample type")
    func filtersBySampleType() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))
        let heartRatePoint = HealthDataPoint(
            id: UUID(),
            sampleType: .heartRate,
            startDate: date(2026, 6, 1, hour: 10),
            endDate: date(2026, 6, 1, hour: 10),
            value: 72.0,
            unit: "bpm",
            sleepStage: nil,
            sourceName: nil
        )
        let energyPoint = makeEnergyPoint(date: date(2026, 6, 1, hour: 12), value: 200.0)
        let result = EnergyAggregator.aggregateByDay(
            dataPoints: [heartRatePoint, energyPoint], in: interval, calendar: testCalendar
        )
        #expect(result.count == 1)
        #expect(result[0].totalEnergy == 200.0)
    }

    @Test("Results are sorted by date")
    func sortedByDate() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 5))
        let result = EnergyAggregator.aggregateByDay(
            dataPoints: [], in: interval, calendar: testCalendar
        )
        for i in 0..<(result.count - 1) {
            #expect(result[i].date < result[i + 1].date)
        }
    }
}

// MARK: - EnergyAggregator.splitAcrossDays Tests

@Suite("EnergyAggregator — splitAcrossDays")
struct EnergySplitAcrossDaysTests {
    @Test("Same-day point stays on one day")
    func sameDay() {
        let point = makeEnergyPoint(
            date: date(2026, 6, 1, hour: 10),
            value: 200.0,
            endDate: date(2026, 6, 1, hour: 11)
        )
        let result = EnergyAggregator.splitAcrossDays(point: point, calendar: testCalendar)
        #expect(result.count == 1)
        #expect(result[0].value == 200.0)
    }

    @Test("Midnight crossing splits proportionally")
    func midnightCrossing() {
        let point = makeEnergyPoint(
            date: date(2026, 6, 1, hour: 22),
            value: 100.0,
            endDate: date(2026, 6, 2, hour: 2)
        )
        let result = EnergyAggregator.splitAcrossDays(point: point, calendar: testCalendar)
        #expect(result.count == 2)
        #expect(abs(result[0].value - 50.0) < 0.01)
        #expect(abs(result[1].value - 50.0) < 0.01)
    }

    @Test("Point-in-time stays on one day")
    func pointInTime() {
        let d = date(2026, 6, 1, hour: 10)
        let point = makeEnergyPoint(date: d, value: 50.0, endDate: d)
        let result = EnergyAggregator.splitAcrossDays(point: point, calendar: testCalendar)
        #expect(result.count == 1)
        #expect(result[0].value == 50.0)
    }
}

// MARK: - EnergyAggregator.computeStatistics Tests

@Suite("EnergyAggregator — computeStatistics")
struct EnergyStatisticsTests {
    @Test("Computes daily average correctly")
    func dailyAverage() {
        let data = [
            DailyEnergyData(date: date(2026, 6, 1), totalEnergy: 300.0),
            DailyEnergyData(date: date(2026, 6, 2), totalEnergy: 500.0),
            DailyEnergyData(date: date(2026, 6, 3), totalEnergy: 200.0),
        ]
        let stats = EnergyAggregator.computeStatistics(from: data)
        #expect(abs(stats.dailyAverage - 333.33) < 0.1)
    }

    @Test("Computes max correctly")
    func maxSingleDay() {
        let data = [
            DailyEnergyData(date: date(2026, 6, 1), totalEnergy: 300.0),
            DailyEnergyData(date: date(2026, 6, 2), totalEnergy: 500.0),
        ]
        let stats = EnergyAggregator.computeStatistics(from: data)
        #expect(stats.maxSingleDay == 500.0)
    }

    @Test("Computes total correctly")
    func totalEnergy() {
        let data = [
            DailyEnergyData(date: date(2026, 6, 1), totalEnergy: 300.0),
            DailyEnergyData(date: date(2026, 6, 2), totalEnergy: 500.0),
        ]
        let stats = EnergyAggregator.computeStatistics(from: data)
        #expect(stats.totalEnergy == 800.0)
    }

    @Test("Empty returns zero stats")
    func emptyInput() {
        let stats = EnergyAggregator.computeStatistics(from: [])
        #expect(stats == .empty)
    }

    @Test("Single day stats")
    func singleDay() {
        let data = [DailyEnergyData(date: date(2026, 6, 1), totalEnergy: 450.0)]
        let stats = EnergyAggregator.computeStatistics(from: data)
        #expect(stats.dailyAverage == 450.0)
        #expect(stats.maxSingleDay == 450.0)
        #expect(stats.totalEnergy == 450.0)
    }
}

// MARK: - Model Tests

@Suite("Energy Models")
struct EnergyModelTests {
    @Test("DailyEnergyData id is date")
    func dailyEnergyDataId() {
        let d = date(2026, 6, 1)
        let data = DailyEnergyData(date: d, totalEnergy: 300.0)
        #expect(data.id == d)
    }

    @Test("EnergyStatistics equality")
    func statisticsEquality() {
        let a = EnergyStatistics(dailyAverage: 400.0, maxSingleDay: 600.0, totalEnergy: 2800.0)
        let b = EnergyStatistics(dailyAverage: 400.0, maxSingleDay: 600.0, totalEnergy: 2800.0)
        #expect(a == b)
    }
}
