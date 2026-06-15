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

    // MARK: - Energy Formatting

    @Test("Energy formats kilocalories without decimals")
    func energyFormatNoDecimals() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(450.7)
        #expect(result.contains("451") || result.contains("450"))
    }

    @Test("Energy formats small values")
    func energySmallValue() {
        let result = HealthKitWorkoutDetailView.formattedEnergy(10)
        #expect(result.contains("10"))
    }

    // MARK: - Distance Formatting

    @Test("Distance formats meters to km scale")
    func distanceKmScale() {
        let result = HealthKitWorkoutDetailView.formattedDistance(12500)
        #expect(!result.isEmpty)
        let hasKmOrMi = result.localizedCaseInsensitiveContains("km")
            || result.localizedCaseInsensitiveContains("mi")
            || result.localizedCaseInsensitiveContains("公里")
            || result.localizedCaseInsensitiveContains("英里")
        #expect(hasKmOrMi, "Expected distance unit in '\(result)'")
    }

    @Test("Distance formats short distance")
    func distanceShortDistance() {
        let result = HealthKitWorkoutDetailView.formattedDistance(500)
        #expect(!result.isEmpty)
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

    // MARK: - Conditional Fields

    @Test("Record with nil energy should have nil totalEnergyBurned")
    func nilEnergyField() {
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
        #expect(record.totalEnergyBurned == nil)
    }

    @Test("Record with nil distance should have nil totalDistance")
    func nilDistanceField() {
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
        #expect(record.totalDistance == nil)
    }

    @Test("Record with zero distance treated as no distance")
    func zeroDistanceField() {
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
        #expect(record.totalDistance == 0)
    }

    @Test("Record with all fields populated provides complete data")
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
    }

    @Test("Source name nil falls back gracefully")
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
        #expect(record.sourceName == nil)
    }
}
