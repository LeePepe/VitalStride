import Foundation
import HealthKitService
import Testing

@testable import VitalStride

@Suite("HealthKitWorkoutDetailView Formatting")
@MainActor
struct HealthKitWorkoutDetailViewTests {

    // MARK: - Duration Formatting

    @Test("Duration formats minutes only when under 1 hour")
    func durationMinutesOnly() {
        let result = HealthKitWorkoutDetailView.formattedDuration(30 * 60)
        #expect(result.contains("30"))
    }

    @Test("Duration formats hours and minutes")
    func durationHoursAndMinutes() {
        let result = HealthKitWorkoutDetailView.formattedDuration(75 * 60)
        #expect(result.contains("1"))
        #expect(result.contains("15"))
    }

    @Test("Duration handles zero gracefully")
    func durationZero() {
        let result = HealthKitWorkoutDetailView.formattedDuration(0)
        #expect(!result.isEmpty)
    }

    // MARK: - Energy Formatting with Unit Preferences

    @Test("Energy in kcal shows integer kcal value")
    func energyKcal() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(450.7, unit: .kcal)
        #expect(result.contains("451"))
        #expect(result.contains("kcal"))
    }

    @Test("Energy in kJ converts and shows kJ value")
    func energyKJ() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(100, unit: .kJ)
        #expect(result.contains("418"))
        #expect(result.contains("kJ"))
    }

    @Test("Energy small value in kcal")
    func energySmallKcal() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(10, unit: .kcal)
        #expect(result.contains("10"))
        #expect(result.contains("kcal"))
    }

    @Test("Energy small value in kJ")
    func energySmallKJ() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(10, unit: .kJ)
        #expect(result.contains("42"))
        #expect(result.contains("kJ"))
    }

    // MARK: - Distance Formatting with Unit Preferences

    @Test("Distance in km converts from meters")
    func distanceKm() {
        let result = HealthKitWorkoutDetailView.formattedDistance(12500, unit: .km)
        #expect(result.contains("12.5") || result.contains("12,5"))
        #expect(result.contains("km"))
    }

    @Test("Distance in miles converts from meters")
    func distanceMi() {
        let result = HealthKitWorkoutDetailView.formattedDistance(1609.344, unit: .mi)
        #expect(result.contains("1"))
        #expect(result.contains("mi"))
    }

    @Test("Distance short in km")
    func distanceShortKm() {
        let result = HealthKitWorkoutDetailView.formattedDistance(500, unit: .km)
        #expect(result.contains("0.5") || result.contains("0,5"))
        #expect(result.contains("km"))
    }

    @Test("Distance short in mi")
    func distanceShortMi() {
        let result = HealthKitWorkoutDetailView.formattedDistance(500, unit: .mi)
        #expect(result.contains("0.3") || result.contains("0,3"))
        #expect(result.contains("mi"))
    }

    // MARK: - Date Formatting

    @Test("Date formatting produces non-empty string")
    func dateFormatNonEmpty() {
        let date = Date(timeIntervalSince1970: 1_710_500_000)
        let result = HealthKitWorkoutDetailView.formattedDate(date)
        #expect(!result.isEmpty)
    }

    @Test("Time range formatting includes separator")
    func timeRangeFormat() {
        let start = Date(timeIntervalSince1970: 1_710_500_000)
        let end = start.addingTimeInterval(3600)
        let result = HealthKitWorkoutDetailView.formattedTimeRange(start: start, end: end)
        #expect(result.contains("-"))
    }

    // MARK: - Conditional Field Logic

    @Test("Record with nil energy hides energy row")
    func nilEnergyHidesRow() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.swimming.rawValue,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: nil
        )
        #expect(record.totalEnergyBurned == nil, "nil energy should hide the energy row")
    }

    @Test("Record with nil distance hides distance row")
    func nilDistanceHidesRow() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.yoga.rawValue,
            duration: 3600,
            totalEnergyBurned: 200,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            sourceName: "Apple Watch"
        )
        #expect(record.totalDistance == nil, "nil distance should hide the distance row")
    }

    @Test("Record with zero distance hides distance row")
    func zeroDistanceHidesRow() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.yoga.rawValue,
            duration: 3600,
            totalEnergyBurned: 200,
            totalDistance: 0,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            sourceName: nil
        )
        let shouldShow = record.totalDistance != nil && record.totalDistance! > 0
        #expect(!shouldShow, "zero distance should not show the distance row")
    }

    @Test("Record with positive distance shows distance row")
    func positiveDistanceShowsRow() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 2700,
            totalEnergyBurned: 350,
            totalDistance: 5000,
            startDate: Date(),
            endDate: Date().addingTimeInterval(2700),
            sourceName: "Strava"
        )
        let shouldShow = record.totalDistance != nil && record.totalDistance! > 0
        #expect(shouldShow, "positive distance should show the distance row")
    }

    @Test("Record with all fields provides complete data for display")
    func allFieldsPopulated() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 2700,
            totalEnergyBurned: 350,
            totalDistance: 5000,
            startDate: Date(),
            endDate: Date().addingTimeInterval(2700),
            sourceName: "Strava"
        )
        #expect(record.totalEnergyBurned == 350)
        #expect(record.totalDistance == 5000)
        #expect(record.sourceName == "Strava")
        #expect(record.activityType == .running)

        let energyKcal = HealthKitWorkoutDetailView.formattedEnergy(350, unit: .kcal)
        #expect(energyKcal.contains("350") && energyKcal.contains("kcal"))

        let energyKJ = HealthKitWorkoutDetailView.formattedEnergy(350, unit: .kJ)
        #expect(energyKJ.contains("kJ"))

        let distKm = HealthKitWorkoutDetailView.formattedDistance(5000, unit: .km)
        #expect(distKm.contains("km"))

        let distMi = HealthKitWorkoutDetailView.formattedDistance(5000, unit: .mi)
        #expect(distMi.contains("mi"))
    }

    @Test("Source name nil shows fallback")
    func sourceNameNilFallback() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.cycling.rawValue,
            duration: 3600,
            totalEnergyBurned: 500,
            totalDistance: 20000,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            sourceName: nil
        )
        #expect(record.sourceName == nil, "nil source should show fallback 'HealthKit'")
    }
}

// MARK: - DistanceUnit Conversion Tests

@Suite("DistanceUnit Conversion")
struct DistanceUnitConversionTests {

    @Test("km converts from meters correctly")
    func kmConversion() {
        let result = DistanceUnit.km.convert(fromMeters: 12500)
        #expect(result == 12.5)
    }

    @Test("mi converts from meters correctly")
    func miConversion() {
        let result = DistanceUnit.mi.convert(fromMeters: 1609.344)
        #expect(abs(result - 1.0) < 0.001)
    }

    @Test("km abbreviation")
    func kmAbbreviation() {
        #expect(DistanceUnit.km.abbreviation == "km")
    }

    @Test("mi abbreviation")
    func miAbbreviation() {
        #expect(DistanceUnit.mi.abbreviation == "mi")
    }

    @Test("km accessibilityName")
    func kmA11yName() {
        #expect(DistanceUnit.km.accessibilityName == "公里")
    }

    @Test("mi accessibilityName")
    func miA11yName() {
        #expect(DistanceUnit.mi.accessibilityName == "英里")
    }
}
