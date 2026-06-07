import Foundation
import HealthKitService
import Testing

@testable import VitalStride

private enum HeartRateTestError: Error {
    case healthKitUnavailable
}

@Suite("Workout Heart Rate Stats Tests")
struct WorkoutHeartRateStatsTests {

    private func makeDataPoint(value: Double) -> HealthDataPoint {
        HealthDataPoint(
            id: UUID(),
            sampleType: .heartRate,
            startDate: Date(),
            endDate: Date(),
            value: value,
            unit: "bpm",
            sleepStage: nil,
            sourceName: nil
        )
    }

    // MARK: - Basic Calculations

    @Test("returns nil for empty data points")
    func emptyDataReturnsNil() {
        let result = WorkoutHeartRateStats.from(dataPoints: [])
        #expect(result == nil)
    }

    @Test("calculates average heart rate")
    func averageHeartRate() {
        let points = [120.0, 130.0, 140.0, 150.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats != nil)
        #expect(stats?.averageHeartRate == 135)
    }

    @Test("calculates max heart rate")
    func maxHeartRate() {
        let points = [100.0, 155.0, 130.0, 140.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats != nil)
        #expect(stats?.maxHeartRate == 155)
    }

    @Test("rounds average heart rate correctly")
    func averageRounding() {
        let points = [121.0, 122.0, 123.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats?.averageHeartRate == 122)
    }

    @Test("single data point returns stats with no zone distribution")
    func singleDataPoint() {
        let points = [makeDataPoint(value: 130)]
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats != nil)
        #expect(stats?.averageHeartRate == 130)
        #expect(stats?.maxHeartRate == 130)
        #expect(stats?.zoneDistribution == nil)
    }

    // MARK: - Zone Distribution

    @Test("no zone distribution when fewer than 5 samples")
    func noZonesWithFewSamples() {
        let points = [100.0, 120.0, 140.0, 160.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats != nil)
        #expect(stats?.zoneDistribution == nil)
    }

    @Test("zone distribution computed with 5 or more samples")
    func zonesWithEnoughSamples() {
        let points = [80.0, 110.0, 130.0, 150.0, 170.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        #expect(stats != nil)
        #expect(stats?.zoneDistribution != nil)
        #expect(stats?.zoneDistribution?.count == 5)
    }

    @Test("zone percentages sum to 100%")
    func zonePercentagesSum() {
        let points = [80.0, 90.0, 110.0, 115.0, 130.0, 135.0, 150.0, 155.0, 170.0, 180.0]
            .map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        guard let zones = stats?.zoneDistribution else {
            Issue.record("Expected zone distribution")
            return
        }
        let totalPercentage = zones.reduce(0.0) { $0 + $1.percentage }
        #expect(abs(totalPercentage - 1.0) < 0.001)
    }

    @Test("zones only include non-zero entries")
    func zonesExcludeEmpty() {
        let points = [130.0, 135.0, 125.0, 128.0, 132.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        guard let zones = stats?.zoneDistribution else {
            Issue.record("Expected zone distribution")
            return
        }
        #expect(zones.count == 1)
        #expect(zones[0].percentage == 1.0)
    }

    @Test("all samples in zone 1")
    func allInZone1() {
        let points = [60.0, 70.0, 80.0, 90.0, 95.0].map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        guard let zones = stats?.zoneDistribution else {
            Issue.record("Expected zone distribution")
            return
        }
        #expect(zones.count == 1)
        #expect(zones[0].id == 1)
        #expect(zones[0].percentage == 1.0)
    }

    @Test("boundary values assigned to correct zones")
    func boundaryValues() {
        let points = [99.0, 100.0, 119.0, 120.0, 139.0, 140.0, 159.0, 160.0, 200.0, 300.0]
            .map { makeDataPoint(value: $0) }
        let stats = WorkoutHeartRateStats.from(dataPoints: points)

        guard let zones = stats?.zoneDistribution else {
            Issue.record("Expected zone distribution")
            return
        }
        let zoneMap = Dictionary(uniqueKeysWithValues: zones.map { ($0.id, $0.percentage) })
        #expect(zoneMap[1] == 0.1)  // 99
        #expect(zoneMap[2] == 0.2)  // 100, 119
        #expect(zoneMap[3] == 0.2)  // 120, 139
        #expect(zoneMap[4] == 0.2)  // 140, 159
        #expect(zoneMap[5] == 0.3)  // 160, 200, 300
    }

    // MARK: - Load (endDate / error handling)

    @Test("load returns nil when endDate is nil")
    func loadNilEndDate() async {
        let stats = await WorkoutHeartRateStats.load(
            startDate: Date(),
            endDate: nil
        ) { _ in
            Issue.record("fetchHeartRate should not be called when endDate is nil")
            return []
        }
        #expect(stats == nil)
    }

    @Test("load returns nil when fetch throws")
    func loadFetchError() async {
        let start = Date().addingTimeInterval(-3600)
        let end = Date()
        let stats = await WorkoutHeartRateStats.load(
            startDate: start,
            endDate: end
        ) { _ in
            throw HeartRateTestError.healthKitUnavailable
        }
        #expect(stats == nil)
    }

    @Test("load returns nil when fetch returns empty data")
    func loadEmptyData() async {
        let start = Date().addingTimeInterval(-3600)
        let end = Date()
        let stats = await WorkoutHeartRateStats.load(
            startDate: start,
            endDate: end
        ) { _ in
            []
        }
        #expect(stats == nil)
    }

    @Test("load returns stats when fetch succeeds with data")
    func loadSuccess() async {
        let start = Date().addingTimeInterval(-3600)
        let end = Date()
        let stats = await WorkoutHeartRateStats.load(
            startDate: start,
            endDate: end
        ) { _ in
            [120.0, 130.0, 140.0].map { self.makeDataPoint(value: $0) }
        }
        #expect(stats != nil)
        #expect(stats?.averageHeartRate == 130)
        #expect(stats?.maxHeartRate == 140)
    }
}
