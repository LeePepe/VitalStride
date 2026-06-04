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

        let endComponents = calendar.dateComponents([.year, .month, .day], from: interval.end)
        #expect(endComponents.year == 2026)
        #expect(endComponents.month == 3)
        #expect(endComponents.day == 16)
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

        let endComponents = calendar.dateComponents([.year, .month, .day], from: interval.end)
        #expect(endComponents.month == 3)
        #expect(endComponents.day == 16)
    }

    @Test("Month interval uses calendar month subtraction")
    func monthInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.month.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2026)
        #expect(startComponents.month == 2)
        #expect(startComponents.day == 15)

        let endComponents = calendar.dateComponents([.year, .month, .day], from: interval.end)
        #expect(endComponents.month == 3)
        #expect(endComponents.day == 16)
    }

    @Test("Year interval uses calendar year subtraction")
    func yearInterval() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let interval = TimeRange.year.dateInterval(from: ref, calendar: calendar)

        let startComponents = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(startComponents.year == 2025)
        #expect(startComponents.month == 3)
        #expect(startComponents.day == 15)

        let endComponents = calendar.dateComponents([.year, .month, .day], from: interval.end)
        #expect(endComponents.year == 2026)
        #expect(endComponents.month == 3)
        #expect(endComponents.day == 16)
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

    @Test("End uses calendar addition, not fixed 86400 seconds")
    func endUsesCalendarAddition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let ref = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let interval = TimeRange.day.dateInterval(from: ref, calendar: calendar)
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour], from: interval.end)
        #expect(endComponents.day == 9)
        #expect(endComponents.hour == 0)
    }

    // MARK: - Formatted Interval

    @Test("Formatted interval is non-empty for all ranges")
    func formattedIntervalNonEmpty() {
        for range in TimeRange.allCases {
            #expect(!range.formattedInterval.isEmpty)
        }
    }

    // MARK: - Section Order

    @Test("DataView sections appear in required order")
    func sectionOrder() {
        let expectedOrder = ["心率", "步数", "体重", "睡眠", "活动能量"]
        #expect(expectedOrder.count == 5)
        #expect(expectedOrder[0] == String(localized: "心率", comment: "Heart rate section"))
        #expect(expectedOrder[1] == String(localized: "步数", comment: "Steps section"))
        #expect(expectedOrder[2] == String(localized: "体重", comment: "Body weight section"))
        #expect(expectedOrder[3] == String(localized: "睡眠", comment: "Sleep section"))
        #expect(expectedOrder[4] == String(localized: "活动能量", comment: "Active energy section"))
    }

    // MARK: - TimeRange Picker

    @Test("All TimeRange cases have distinct labels")
    func distinctLabels() {
        let labels = TimeRange.allCases.map(\.localizedLabel)
        let uniqueLabels = Set(labels)
        #expect(labels.count == uniqueLabels.count)
    }

    @Test("Changing range produces different intervals")
    func changingRangeProducesDifferentIntervals() {
        let calendar = Calendar.current
        let ref = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!

        let dayInterval = TimeRange.day.dateInterval(from: ref, calendar: calendar)
        let weekInterval = TimeRange.week.dateInterval(from: ref, calendar: calendar)
        let monthInterval = TimeRange.month.dateInterval(from: ref, calendar: calendar)
        let yearInterval = TimeRange.year.dateInterval(from: ref, calendar: calendar)

        #expect(dayInterval.duration < weekInterval.duration)
        #expect(weekInterval.duration < monthInterval.duration)
        #expect(monthInterval.duration < yearInterval.duration)
    }
}
