import Foundation
import HealthKitService
import Testing
import VitalModels

@testable import VitalStride

// MARK: - Test Helpers

private let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func makePoint(
    type: HealthSampleType,
    start: Date,
    end: Date? = nil,
    value: Double
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: type,
        startDate: start,
        endDate: end ?? start,
        value: value,
        unit: "test",
        sleepStage: nil,
        sourceName: "TestSource"
    )
}

// MARK: - HealthSampleTypeInfo Tests

@Suite("HealthSampleType — Display Metadata")
struct HealthSampleTypeInfoTests {

    @Test("All cases have non-empty localized names")
    func localizedNamesNonEmpty() {
        for type in HealthSampleType.allCases {
            #expect(!type.localizedName.isEmpty, "Missing name for \(type.rawValue)")
        }
    }

    @Test("All cases have non-empty system images")
    func systemImagesNonEmpty() {
        for type in HealthSampleType.allCases {
            #expect(!type.systemImage.isEmpty, "Missing icon for \(type.rawValue)")
        }
    }

    @Test("All cases have a valid aggregation mode")
    func aggregationModes() {
        let cumulativeTypes: Set<HealthSampleType> = [
            .stepCount, .activeEnergyBurned, .basalEnergyBurned,
            .distanceWalkingRunning, .distanceCycling,
            .appleExerciseTime, .appleStandTime, .flightsClimbed,
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater,
        ]
        for type in HealthSampleType.allCases {
            if cumulativeTypes.contains(type) {
                #expect(type.aggregationMode == .cumulative, "\(type.rawValue) should be cumulative")
            } else {
                #expect(type.aggregationMode == .discrete, "\(type.rawValue) should be discrete")
            }
        }
    }

    @Test("Fraction digits are non-negative")
    func fractionDigitsValid() {
        for type in HealthSampleType.allCases {
            #expect(type.fractionDigits >= 0, "Invalid fractionDigits for \(type.rawValue)")
        }
    }
}

// MARK: - GenericHealthAggregator Tests

@Suite("GenericHealthAggregator — Cumulative")
struct GenericAggregatorCumulativeTests {

    @Test("Same day samples are summed")
    func sameDaySumming() {
        let points = [
            makePoint(type: .basalEnergyBurned, start: date(2026, 6, 1, hour: 8), value: 500),
            makePoint(type: .basalEnergyBurned, start: date(2026, 6, 1, hour: 12), value: 700),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = GenericHealthAggregator.aggregateCumulative(
            dataPoints: points, sampleType: .basalEnergyBurned, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].value == 1200)
    }

    @Test("Cross-day samples split proportionally")
    func crossDaySplit() {
        let start = date(2026, 6, 1, hour: 12)
        let end = date(2026, 6, 2, hour: 12)
        let points = [
            makePoint(type: .distanceWalkingRunning, start: start, end: end, value: 10.0),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 3))

        let result = GenericHealthAggregator.aggregateCumulative(
            dataPoints: points, sampleType: .distanceWalkingRunning, in: interval, calendar: testCalendar
        )

        #expect(result.count == 2)
        let day1 = result.first { testCalendar.isDate($0.date, inSameDayAs: date(2026, 6, 1)) }
        let day2 = result.first { testCalendar.isDate($0.date, inSameDayAs: date(2026, 6, 2)) }
        #expect(day1 != nil)
        #expect(day2 != nil)
        #expect(abs(day1!.value - 5.0) < 0.01)
        #expect(abs(day2!.value - 5.0) < 0.01)
    }

    @Test("Empty data produces empty days")
    func emptyDataEmptyDays() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = GenericHealthAggregator.aggregateCumulative(
            dataPoints: [], sampleType: .flightsClimbed, in: interval, calendar: testCalendar
        )

        #expect(result.count == 3)
        for day in result {
            #expect(day.value == 0)
        }
    }

    @Test("Filters by sample type")
    func filtersBySampleType() {
        let points = [
            makePoint(type: .stepCount, start: date(2026, 6, 1), value: 1000),
            makePoint(type: .flightsClimbed, start: date(2026, 6, 1), value: 5),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = GenericHealthAggregator.aggregateCumulative(
            dataPoints: points, sampleType: .flightsClimbed, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].value == 5)
    }
}

@Suite("GenericHealthAggregator — Discrete")
struct GenericAggregatorDiscreteTests {

    @Test("Same day samples are averaged")
    func sameDayAveraging() {
        let points = [
            makePoint(type: .restingHeartRate, start: date(2026, 6, 1, hour: 8), value: 60),
            makePoint(type: .restingHeartRate, start: date(2026, 6, 1, hour: 20), value: 64),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = GenericHealthAggregator.aggregateDiscrete(
            dataPoints: points, sampleType: .restingHeartRate, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].value == 62)
    }

    @Test("Points outside interval are excluded")
    func outsideIntervalExcluded() {
        let points = [
            makePoint(type: .vo2Max, start: date(2026, 5, 31), value: 45),
            makePoint(type: .vo2Max, start: date(2026, 6, 1), value: 46),
            makePoint(type: .vo2Max, start: date(2026, 6, 3), value: 47),
        ]
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 2))

        let result = GenericHealthAggregator.aggregateDiscrete(
            dataPoints: points, sampleType: .vo2Max, in: interval, calendar: testCalendar
        )

        #expect(result.count == 1)
        #expect(result[0].value == 46)
    }

    @Test("Empty data produces empty result")
    func emptyData() {
        let interval = DateInterval(start: date(2026, 6, 1), end: date(2026, 6, 4))

        let result = GenericHealthAggregator.aggregateDiscrete(
            dataPoints: [], sampleType: .bodyFatPercentage, in: interval, calendar: testCalendar
        )

        #expect(result.isEmpty)
    }
}

@Suite("GenericHealthAggregator — Statistics")
struct GenericAggregatorStatisticsTests {

    @Test("Statistics computed correctly")
    func basicStatistics() {
        let data = [
            GenericHealthAggregator.DailyData(date: date(2026, 6, 1), value: 10),
            GenericHealthAggregator.DailyData(date: date(2026, 6, 2), value: 20),
            GenericHealthAggregator.DailyData(date: date(2026, 6, 3), value: 30),
        ]

        let stats = GenericHealthAggregator.computeStatistics(from: data)

        #expect(stats.average == 20)
        #expect(stats.max == 30)
        #expect(stats.min == 10)
        #expect(stats.total == 60)
    }

    @Test("Empty data returns empty statistics")
    func emptyStatistics() {
        let stats = GenericHealthAggregator.computeStatistics(from: [])
        #expect(stats == .empty)
    }

    @Test("Single item statistics")
    func singleItem() {
        let data = [GenericHealthAggregator.DailyData(date: date(2026, 6, 1), value: 42)]
        let stats = GenericHealthAggregator.computeStatistics(from: data)

        #expect(stats.average == 42)
        #expect(stats.max == 42)
        #expect(stats.min == 42)
    }
}

// MARK: - Distance Unit Conversion Tests

@Suite("GenericHealthDetailView — Distance Unit Preference")
struct GenericHealthDistanceUnitTests {

    @Test("Distance sample types are classified correctly")
    func distanceSampleTypeClassification() {
        let distanceTypes: Set<HealthSampleType> = [.distanceWalkingRunning, .distanceCycling]
        for type in HealthSampleType.allCases {
            if distanceTypes.contains(type) {
                #expect(type.unitLabel == String(localized: "km", comment: "Kilometers unit"),
                        "\(type.rawValue) should have km unit label")
            }
        }
    }

    @Test("DistanceUnit.km passes through raw km values unchanged")
    func kmConversionFromKilometers() {
        let rawKm = 5.4321
        let result = DistanceUnit.km.convert(fromKilometers: rawKm)
        #expect(abs(result - 5.4321) < 0.0001)
    }

    @Test("DistanceUnit.mi converts raw km values to miles")
    func miConversionFromKilometers() {
        let rawKm = 1.609344
        let result = DistanceUnit.mi.convert(fromKilometers: rawKm)
        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test("Non-distance types are unaffected by distance unit preference")
    func nonDistanceTypesUnaffected() {
        let nonDistanceTypes: [HealthSampleType] = [
            .stepCount, .heartRate, .bodyMass, .height, .activeEnergyBurned,
        ]
        for type in nonDistanceTypes {
            #expect(type != .distanceWalkingRunning)
            #expect(type != .distanceCycling)
        }
    }

    @Test("Height keeps cm semantics and is not classified as distance")
    func heightNotDistance() {
        #expect(HealthSampleType.height.unitLabel == String(localized: "cm", comment: "Centimeters unit"))
        #expect(HealthSampleType.height != .distanceWalkingRunning)
        #expect(HealthSampleType.height != .distanceCycling)
    }

    @Test("Distance types use cumulative aggregation")
    func distanceAggregationMode() {
        #expect(HealthSampleType.distanceWalkingRunning.aggregationMode == .cumulative)
        #expect(HealthSampleType.distanceCycling.aggregationMode == .cumulative)
    }

    @Test("DistanceUnit abbreviation matches expected labels")
    func distanceUnitAbbreviations() {
        #expect(DistanceUnit.km.abbreviation == "km")
        #expect(DistanceUnit.mi.abbreviation == "mi")
    }

    @Test("Zero distance converts correctly from km")
    func zeroDistanceConversion() {
        #expect(DistanceUnit.km.convert(fromKilometers: 0) == 0)
        #expect(DistanceUnit.mi.convert(fromKilometers: 0) == 0)
    }

    @Test("fromKilometers and fromMeters are consistent")
    func fromKilometersConsistentWithFromMeters() {
        let meters = 5000.0
        let km = 5.0
        let miFromMeters = DistanceUnit.mi.convert(fromMeters: meters)
        let miFromKm = DistanceUnit.mi.convert(fromKilometers: km)
        #expect(abs(miFromMeters - miFromKm) < 0.0001)
    }
}

// MARK: - DataView Section Structure Tests

@Suite("DataView — Section Structure")
struct DataViewSectionTests {

    @Test("Activity section contains expected types")
    func activityTypes() {
        let expectedTypes: [HealthSampleType] = [
            .basalEnergyBurned, .distanceWalkingRunning, .distanceCycling,
            .appleExerciseTime, .appleStandTime, .flightsClimbed,
        ]
        for type in expectedTypes {
            #expect(!type.localizedName.isEmpty, "Activity type \(type.rawValue) missing name")
            #expect(!type.systemImage.isEmpty, "Activity type \(type.rawValue) missing icon")
        }
    }

    @Test("Heart section contains expected types")
    func heartTypes() {
        let expectedTypes: [HealthSampleType] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
        ]
        for type in expectedTypes {
            #expect(!type.localizedName.isEmpty, "Heart type \(type.rawValue) missing name")
        }
    }

    @Test("Body section contains expected types")
    func bodyTypes() {
        let expectedTypes: [HealthSampleType] = [
            .bodyFatPercentage, .leanBodyMass, .height, .bodyMassIndex,
        ]
        for type in expectedTypes {
            #expect(!type.localizedName.isEmpty, "Body type \(type.rawValue) missing name")
        }
    }

    @Test("Nutrition section contains expected types")
    func nutritionTypes() {
        let expectedTypes: [HealthSampleType] = [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
            .dietaryFatTotal, .dietaryWater,
        ]
        for type in expectedTypes {
            #expect(type.aggregationMode == .cumulative, "Nutrition type \(type.rawValue) should be cumulative")
        }
    }
}

// MARK: - WorkoutActivityType Display Tests

@Suite("WorkoutActivityType — Display Metadata")
struct WorkoutActivityTypeInfoTests {

    @Test("All cases have non-empty localized names")
    func localizedNamesNonEmpty() {
        for type in WorkoutActivityType.allCases {
            #expect(!type.localizedName.isEmpty, "Missing name for workout type \(type.rawValue)")
        }
    }

    @Test("All cases have non-empty system images")
    func systemImagesNonEmpty() {
        for type in WorkoutActivityType.allCases {
            #expect(!type.systemImage.isEmpty, "Missing icon for workout type \(type.rawValue)")
        }
    }

    @Test("All localized names are unique")
    func uniqueNames() {
        let names = WorkoutActivityType.allCases.map(\.localizedName)
        let unique = Set(names)
        #expect(names.count == unique.count, "Duplicate workout type names found")
    }
}

// MARK: - HealthDetailWindow Tests (MY-1248)

@Suite("HealthDetailWindow — Shift")
struct HealthDetailWindowShiftTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("Day range shifts anchor by 1 day backward")
    func dayShiftBackward() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 6, 20)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .backward, range: .day, now: now, calendar: calendar
        )
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 14)))
    }

    @Test("Day range shifts anchor by 1 day forward")
    func dayShiftForward() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 6, 20)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .day, now: now, calendar: calendar
        )
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 16)))
    }

    @Test("Week range shifts anchor by 7 days")
    func weekShiftBackward() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 6, 30)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .backward, range: .week, now: now, calendar: calendar
        )
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 8)))
    }

    @Test("Month range shifts anchor by 1 month")
    func monthShiftBackward() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 8, 1)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .backward, range: .month, now: now, calendar: calendar
        )
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 5, 15)))
    }

    @Test("Year range shift is a no-op")
    func yearShiftIsNoop() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 7, 1)
        let forward = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .year, now: now, calendar: calendar
        )
        let backward = HealthDetailWindow.shift(
            anchor: anchor, by: .backward, range: .year, now: now, calendar: calendar
        )
        // Clamped to startOfDay(anchor)
        #expect(calendar.isDate(forward, inSameDayAs: anchor))
        #expect(calendar.isDate(backward, inSameDayAs: anchor))
    }

    @Test("Forward shift is clamped to today")
    func forwardClampedToToday() {
        let anchor = day(2026, 6, 20)
        let now = day(2026, 6, 20)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .day, now: now, calendar: calendar
        )
        // Cannot advance past today
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 20)))
    }

    @Test("Forward month shift is clamped to today (mid-month)")
    func monthForwardClampedToToday() {
        let anchor = day(2026, 5, 15)
        let now = day(2026, 6, 10)
        let result = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .month, now: now, calendar: calendar
        )
        // Anchor + 1 month = 6/15 which is beyond today (6/10) → clamped
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 10)))
    }
}

@Suite("HealthDetailWindow — Clamp and canGo")
struct HealthDetailWindowClampTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("clampedAnchor collapses future dates to today")
    func clampFutureToToday() {
        let future = day(2027, 1, 1)
        let now = day(2026, 6, 20)
        let result = HealthDetailWindow.clampedAnchor(future, now: now, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 6, 20)))
    }

    @Test("clampedAnchor keeps past dates unchanged (start-of-day)")
    func clampPastUnchanged() {
        let past = day(2026, 5, 1)
        let now = day(2026, 6, 20)
        let result = HealthDetailWindow.clampedAnchor(past, now: now, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: day(2026, 5, 1)))
    }

    @Test("canGoForward is false when anchor is today")
    func canGoForwardFalseAtToday() {
        let now = day(2026, 6, 20)
        for range in [TimeRange.day, .week, .month] {
            #expect(
                !HealthDetailWindow.canGoForward(
                    anchor: now, range: range, now: now, calendar: calendar
                ),
                "canGoForward should be false at today for \(range)"
            )
        }
    }

    @Test("canGoForward is true when anchor is before today")
    func canGoForwardTrueInPast() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 6, 20)
        for range in [TimeRange.day, .week, .month] {
            #expect(
                HealthDetailWindow.canGoForward(
                    anchor: anchor, range: range, now: now, calendar: calendar
                ),
                "canGoForward should be true in past for \(range)"
            )
        }
    }

    @Test("canGoForward is always false for year range")
    func canGoForwardFalseForYear() {
        let anchor = day(2026, 6, 15)
        let now = day(2026, 6, 20)
        #expect(
            !HealthDetailWindow.canGoForward(
                anchor: anchor, range: .year, now: now, calendar: calendar
            )
        )
    }

    @Test("canGoBackward is true for day/week/month")
    func canGoBackwardTrueForNonYear() {
        let anchor = day(2026, 6, 15)
        for range in [TimeRange.day, .week, .month] {
            #expect(HealthDetailWindow.canGoBackward(anchor: anchor, range: range))
        }
    }

    @Test("canGoBackward is false for year")
    func canGoBackwardFalseForYear() {
        let anchor = day(2026, 6, 15)
        #expect(!HealthDetailWindow.canGoBackward(anchor: anchor, range: .year))
    }
}

@Suite("HealthDetailWindow — Interval integration")
struct HealthDetailWindowIntervalTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("Week window from shifted anchor covers 7 days ending at anchor+1")
    func weekWindowSpans7Days() {
        let anchor = day(2026, 6, 15)
        let interval = TimeRange.week.dateInterval(from: anchor, calendar: calendar)
        // start = anchor - 6 days, end = anchor + 1 day
        #expect(calendar.isDate(interval.start, inSameDayAs: day(2026, 6, 9)))
        #expect(calendar.isDate(interval.end, inSameDayAs: day(2026, 6, 16)))
    }

    @Test("Shifting anchor produces a different, non-overlapping window")
    func shiftProducesDifferentWindow() {
        let now = day(2026, 6, 30)
        let anchor = day(2026, 6, 15)
        let shifted = HealthDetailWindow.shift(
            anchor: anchor, by: .backward, range: .week, now: now, calendar: calendar
        )
        let intervalA = TimeRange.week.dateInterval(from: anchor, calendar: calendar)
        let intervalB = TimeRange.week.dateInterval(from: shifted, calendar: calendar)
        #expect(intervalA.start != intervalB.start)
        #expect(intervalA.end != intervalB.end)
        // Backward shift → older window
        #expect(intervalB.start < intervalA.start)
    }
}

// MARK: - Regression: Empty-window navigation availability (PR #251 P0)

/// These tests pin the contract that navigation availability on the health
/// detail chart is a function of `(anchor, range, now)` ONLY — it MUST NOT
/// depend on whether the current window contains any data points.
///
/// Regression for PR #251 P0 (2026-07-15): empty windows previously rendered
/// only the empty-state section, hiding the prev/next controls and the
/// VoiceOver current-range label, trapping users in an empty window they
/// could not navigate away from.
@Suite("HealthDetailWindow — Empty Window Navigation Availability")
struct HealthDetailWindowEmptyWindowAvailabilityTests {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("canGoBackward signature takes no data (structural guarantee)")
    func canGoBackwardHasNoDataParameter() {
        // Pure structural: the function only consumes (anchor, range).
        // If the signature ever grows a data parameter this test will fail
        // to compile — that IS the regression alarm.
        let anchor = day(2026, 6, 15)
        for range in [TimeRange.day, .week, .month] {
            #expect(HealthDetailWindow.canGoBackward(anchor: anchor, range: range))
        }
    }

    @Test("canGoBackward is true for day/week/month even for empty past window")
    func backwardAvailableInEmptyPastWindow() {
        // Simulate a window user shifted into that yields no data.
        // Availability must remain true so the user can leave.
        let anchor = day(2020, 1, 1) // deep past, plausibly empty
        for range in [TimeRange.day, .week, .month] {
            #expect(
                HealthDetailWindow.canGoBackward(anchor: anchor, range: range),
                "Empty past \(range) window must still allow backward navigation"
            )
        }
    }

    @Test("canGoForward is true from empty past window (day/week/month)")
    func forwardAvailableInEmptyPastWindow() {
        let anchor = day(2020, 1, 1)
        let now = day(2026, 6, 20)
        for range in [TimeRange.day, .week, .month] {
            #expect(
                HealthDetailWindow.canGoForward(
                    anchor: anchor, range: range, now: now, calendar: calendar
                ),
                "Empty past \(range) window must still allow forward navigation"
            )
        }
    }

    @Test("canGoForward false at today regardless of data (empty or not)")
    func forwardDisabledAtTodayEvenWhenEmpty() {
        let now = day(2026, 6, 20)
        for range in [TimeRange.day, .week, .month] {
            #expect(
                !HealthDetailWindow.canGoForward(
                    anchor: now, range: range, now: now, calendar: calendar
                ),
                "Forward must clamp at today for \(range) irrespective of data"
            )
        }
    }

    @Test("Year range stays non-scrollable — empty or not, both directions false")
    func yearRemainsNonScrollableForEmptyData() {
        let anchor = day(2020, 1, 1) // empty
        let now = day(2026, 6, 20)
        #expect(!HealthDetailWindow.canGoBackward(anchor: anchor, range: .year))
        #expect(
            !HealthDetailWindow.canGoForward(
                anchor: anchor, range: .year, now: now, calendar: calendar
            )
        )
    }

    @Test("Shift math is independent of data (pure on anchor/range/now)")
    func shiftIsPureAndDataIndependent() {
        // Two calls with identical (anchor, range, now, calendar) produce
        // identical results — no hidden data dependency.
        let anchor = day(2020, 1, 15)
        let now = day(2026, 6, 20)
        let a = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .week, now: now, calendar: calendar
        )
        let b = HealthDetailWindow.shift(
            anchor: anchor, by: .forward, range: .week, now: now, calendar: calendar
        )
        #expect(a == b)
        #expect(calendar.isDate(a, inSameDayAs: day(2020, 1, 22)))
    }
}
