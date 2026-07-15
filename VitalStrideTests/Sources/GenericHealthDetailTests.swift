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

// MARK: - Loading State Transition Tests (MY-1247)

@Suite("HealthDetailLoadingState — Loading transition contract")
struct HealthDetailLoadingStateTests {

    // Reproducible check for the MY-1247 "dark-mode black-flash on time-range switch"
    // bug: when the user switches the segmented picker while data is already on screen,
    // the resolver MUST NOT collapse the section to the full-height blank loader; it
    // MUST emit `.loadingOverlayOverContent` so the prior chart stays visible under a
    // themed overlay strip.
    @Test("Loading with prior data yields overlay, not blank full loader")
    func loadingWithPriorDataShowsOverlay() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: true, hasData: true, hasError: false
        )
        #expect(state == .loadingOverlayOverContent)
    }

    @Test("First-time loading with no prior data yields full loader")
    func firstLoadShowsFullLoader() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: true, hasData: false, hasError: false
        )
        #expect(state == .fullLoading)
    }

    @Test("Error with no prior data yields error section")
    func errorWithNoDataShowsError() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: false, hasData: false, hasError: true
        )
        #expect(state == .error)
    }

    @Test("Error while prior data present keeps content (does not blank the chart)")
    func errorWithPriorDataKeepsContent() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: false, hasData: true, hasError: true
        )
        #expect(state == .content)
    }

    @Test("No loading, no data, no error is empty")
    func idleEmptyShowsEmpty() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: false, hasData: false, hasError: false
        )
        #expect(state == .empty)
    }

    @Test("Idle with data shows content")
    func idleWithDataShowsContent() {
        let state = HealthDetailLoadingState.resolve(
            isLoading: false, hasData: true, hasError: false
        )
        #expect(state == .content)
    }
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
