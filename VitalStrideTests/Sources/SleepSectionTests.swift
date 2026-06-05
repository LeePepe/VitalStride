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

private func makeSleepPoint(
    start: Date,
    end: Date,
    stage: SleepStage
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .sleepAnalysis,
        startDate: start,
        endDate: end,
        value: Double(stage.rawValueForTest),
        unit: "category",
        sleepStage: stage,
        sourceName: "TestSource"
    )
}

private extension SleepStage {
    var rawValueForTest: Int {
        switch self {
        case .inBed: 0
        case .asleepUnspecified: 1
        case .asleepCore: 4
        case .asleepDeep: 5
        case .asleepREM: 6
        case .awake: 2
        }
    }
}

// MARK: - SleepAggregator.nightDateFor Tests

@Suite("SleepAggregator — nightDateFor")
struct NightDateForTests {
    @Test("Early morning maps to previous day")
    func earlyMorning() {
        let d = date(2026, 6, 2, hour: 3)
        let result = SleepAggregator.nightDateFor(d, calendar: testCalendar)
        #expect(result == date(2026, 6, 1))
    }

    @Test("Late evening stays on same day")
    func lateEvening() {
        let d = date(2026, 6, 1, hour: 23)
        let result = SleepAggregator.nightDateFor(d, calendar: testCalendar)
        #expect(result == date(2026, 6, 1))
    }

    @Test("Afternoon maps to previous day")
    func afternoon() {
        let d = date(2026, 6, 2, hour: 14)
        let result = SleepAggregator.nightDateFor(d, calendar: testCalendar)
        #expect(result == date(2026, 6, 1))
    }

    @Test("Exactly 18:00 stays on same day")
    func exactly18() {
        let d = date(2026, 6, 1, hour: 18)
        let result = SleepAggregator.nightDateFor(d, calendar: testCalendar)
        #expect(result == date(2026, 6, 1))
    }
}

// MARK: - SleepAggregator.aggregateByNight Tests

@Suite("SleepAggregator — aggregateByNight")
struct AggregateByNightTests {
    @Test("Single night with multiple stages")
    func singleNight() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))
        let points = [
            makeSleepPoint(start: date(2026, 6, 1, hour: 22), end: date(2026, 6, 1, hour: 23), stage: .asleepCore),
            makeSleepPoint(start: date(2026, 6, 1, hour: 23), end: date(2026, 6, 2, hour: 1), stage: .asleepDeep),
            makeSleepPoint(start: date(2026, 6, 2, hour: 1), end: date(2026, 6, 2, hour: 3), stage: .asleepREM),
            makeSleepPoint(start: date(2026, 6, 2, hour: 3), end: date(2026, 6, 2, hour: 3, minute: 30), stage: .awake),
        ]
        let result = SleepAggregator.aggregateByNight(dataPoints: points, in: interval, calendar: testCalendar)
        #expect(result.count == 1)
        let night = result[0]
        #expect(night.date == date(2026, 6, 1))
        #expect(night.core == 3600)
        #expect(night.deep == 7200)
        #expect(night.rem == 7200)
        #expect(night.awake == 1800)
    }

    @Test("InBed stage is excluded")
    func inBedExcluded() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))
        let points = [
            makeSleepPoint(start: date(2026, 6, 1, hour: 22), end: date(2026, 6, 2, hour: 6), stage: .inBed),
            makeSleepPoint(start: date(2026, 6, 1, hour: 23), end: date(2026, 6, 2, hour: 1), stage: .asleepDeep),
        ]
        let result = SleepAggregator.aggregateByNight(dataPoints: points, in: interval, calendar: testCalendar)
        #expect(result.count == 1)
        #expect(result[0].deep == 7200)
        #expect(result[0].core == 0)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 8))
        let result = SleepAggregator.aggregateByNight(dataPoints: [], in: interval, calendar: testCalendar)
        #expect(result.isEmpty)
    }

    @Test("Multiple nights sorted by date")
    func multipleNights() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))
        let points = [
            makeSleepPoint(start: date(2026, 6, 2, hour: 22), end: date(2026, 6, 3, hour: 1), stage: .asleepCore),
            makeSleepPoint(start: date(2026, 6, 1, hour: 23), end: date(2026, 6, 2, hour: 2), stage: .asleepDeep),
        ]
        let result = SleepAggregator.aggregateByNight(dataPoints: points, in: interval, calendar: testCalendar)
        #expect(result.count == 2)
        #expect(result[0].date == date(2026, 6, 1))
        #expect(result[1].date == date(2026, 6, 2))
    }

    @Test("AsleepUnspecified maps to core")
    func unspecifiedMapsToCore() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))
        let points = [
            makeSleepPoint(start: date(2026, 6, 1, hour: 23), end: date(2026, 6, 2, hour: 2), stage: .asleepUnspecified),
        ]
        let result = SleepAggregator.aggregateByNight(dataPoints: points, in: interval, calendar: testCalendar)
        #expect(result.count == 1)
        #expect(result[0].core == 10800)
        #expect(result[0].deep == 0)
    }
}

// MARK: - SleepAggregator.computeStatistics Tests

@Suite("SleepAggregator — computeStatistics")
struct SleepStatisticsTests {
    @Test("Averages computed correctly")
    func averages() {
        let nights = [
            NightSleepData(date: date(2026, 6, 1), deep: 3600, core: 7200, rem: 5400, awake: 1800),
            NightSleepData(date: date(2026, 6, 2), deep: 7200, core: 3600, rem: 3600, awake: 900),
        ]
        let stats = SleepAggregator.computeStatistics(from: nights)
        #expect(stats.averageTotalSleep == (3600 + 7200 + 5400 + 7200 + 3600 + 3600) / 2)
        #expect(stats.averageDeep == (3600 + 7200) / 2)
        #expect(stats.averageREM == (5400 + 3600) / 2)
    }

    @Test("Empty returns zero stats")
    func emptyReturnsZero() {
        let stats = SleepAggregator.computeStatistics(from: [])
        #expect(stats == .empty)
    }

    @Test("Single night stats equal that night's values")
    func singleNight() {
        let night = NightSleepData(date: date(2026, 6, 1), deep: 3600, core: 7200, rem: 5400, awake: 1800)
        let stats = SleepAggregator.computeStatistics(from: [night])
        #expect(stats.averageTotalSleep == 16200)
        #expect(stats.averageDeep == 3600)
        #expect(stats.averageREM == 5400)
    }
}

// MARK: - NightSleepData Model Tests

@Suite("NightSleepData")
struct NightSleepDataTests {
    @Test("totalSleep excludes awake")
    func totalSleepExcludesAwake() {
        let night = NightSleepData(date: date(2026, 6, 1), deep: 3600, core: 7200, rem: 5400, awake: 1800)
        #expect(night.totalSleep == 16200)
        #expect(night.totalDuration == 18000)
    }

    @Test("id is date")
    func idIsDate() {
        let d = date(2026, 6, 1)
        let night = NightSleepData(date: d, deep: 0, core: 0, rem: 0, awake: 0)
        #expect(night.id == d)
    }
}

// MARK: - formatDuration Tests

@Suite("formatDuration")
struct FormatDurationTests {
    @Test("Hours and minutes")
    func hoursAndMinutes() {
        let result = formatDuration(7 * 3600 + 30 * 60)
        #expect(result.contains("7") && result.contains("30"))
    }

    @Test("Minutes only")
    func minutesOnly() {
        let result = formatDuration(45 * 60)
        #expect(result.contains("45"))
    }

    @Test("Zero duration")
    func zeroDuration() {
        let result = formatDuration(0)
        #expect(result.contains("0"))
    }
}
