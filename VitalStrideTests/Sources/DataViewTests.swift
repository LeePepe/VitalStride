import Foundation
import Testing

@testable import VitalStride

@Suite("TimeRange Tests")
struct TimeRangeTests {

    // MARK: - Identifiable & CaseIterable

    @Test("All cases present")
    func allCases() {
        let cases = TimeRange.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.day))
        #expect(cases.contains(.week))
        #expect(cases.contains(.month))
        #expect(cases.contains(.year))
    }

    @Test("id matches rawValue")
    func identifiable() {
        for range in TimeRange.allCases {
            #expect(range.id == range.rawValue)
        }
    }

    // MARK: - Localized Labels

    @Test("Localized labels are non-empty")
    func localizedLabelsNonEmpty() {
        for range in TimeRange.allCases {
            #expect(!range.localizedLabel.isEmpty)
        }
    }

    // MARK: - Date Interval

    @Test("Day interval spans exactly one day")
    func dayInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.day.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 3)
        #expect(startComponents.day == 15)

        let expectedDuration: TimeInterval = 86400
        #expect(abs(interval.duration - expectedDuration) < 1)
    }

    @Test("Week interval spans 7 days")
    func weekInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.week.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 3)
        #expect(startComponents.day == 9)

        let expectedDuration: TimeInterval = 7 * 86400
        #expect(abs(interval.duration - expectedDuration) < 1)
    }

    @Test("Month interval spans 30 days")
    func monthInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.month.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 2)
        #expect(startComponents.day == 14)

        let expectedDuration: TimeInterval = 30 * 86400
        #expect(abs(interval.duration - expectedDuration) < 1)
    }

    @Test("Year interval spans 365 days")
    func yearInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.year.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2025)
        #expect(startComponents.month == 3)
        #expect(startComponents.day == 16)

        let expectedDuration: TimeInterval = 365 * 86400
        #expect(abs(interval.duration - expectedDuration) < 1)
    }

    @Test("Interval end is start of next day after reference")
    func intervalEndIsNextDay() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 14, minute: 30))!

        for range in TimeRange.allCases {
            let interval = range.dateInterval(from: ref, calendar: calendar)
            let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: interval.end)
            #expect(endComponents.year == 2026)
            #expect(endComponents.month == 6)
            #expect(endComponents.day == 2)
            #expect(endComponents.hour == 0)
            #expect(endComponents.minute == 0)
        }
    }

    @Test("All intervals start at midnight")
    func intervalsStartAtMidnight() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 59))!

        for range in TimeRange.allCases {
            let interval = range.dateInterval(from: ref, calendar: calendar)
            let hour = calendar.component(.hour, from: interval.start)
            let minute = calendar.component(.minute, from: interval.start)
            #expect(hour == 0)
            #expect(minute == 0)
        }
    }

    @Test("Default reference date produces valid interval")
    func defaultReferenceDate() {
        let interval = TimeRange.week.dateInterval()
        #expect(interval.duration > 0)
        #expect(interval.start < interval.end)
    }
}
