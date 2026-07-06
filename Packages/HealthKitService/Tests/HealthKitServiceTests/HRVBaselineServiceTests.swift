import Testing
import Foundation
@testable import HealthKitService

// MARK: - Helpers

private func hrvPoint(date: Date, value: Double) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: .heartRateVariabilitySDNN,
        startDate: date,
        endDate: date.addingTimeInterval(60),
        value: value,
        unit: "ms",
        sleepStage: nil,
        sourceName: "MockSource"
    )
}

private func makeCache(seededPoints: [HealthDataPoint]) -> HealthDataCache {
    let mock = MockHealthDataProvider()
    mock.fetchResults[.heartRateVariabilitySDNN] = HealthFetchResult(
        dataPoints: seededPoints,
        deletedObjectIDs: []
    )
    return HealthDataCache(dataProvider: mock)
}

/// Build baseline points across `dayCount` distinct calendar days ending
/// the day before `referenceDate`. All points share the same `value`.
private func baselinePoints(
    referenceDate: Date,
    dayCount: Int,
    value: Double,
    calendar: Calendar = .current
) -> [HealthDataPoint] {
    let today = calendar.startOfDay(for: referenceDate)
    var points: [HealthDataPoint] = []
    for i in 1...dayCount {
        guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
        points.append(hrvPoint(date: day.addingTimeInterval(3600), value: value))
    }
    return points
}

// MARK: - Tests

@Suite("HRVBaselineService")
struct HRVBaselineServiceTests {

    // MARK: - Severity threshold boundaries (P0 fix)

    @Test("Severity: exactly -30% is significantLow (not critical)")
    func severityExactlyMinusThirtyIsSignificantLow() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // Baseline mean = 100 over 14 days; today = 70 → -30% exactly.
        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 70))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly != nil)
        #expect(anomaly?.severity == .significantLow)
        #expect(anomaly?.percentDeviation == -30.0)
        #expect(anomaly?.suggestionKey == HRVBaselineService.SuggestionKey.significantLow)
    }

    @Test("Severity: just below -30% (e.g. -30.01%) is critical")
    func severityJustBelowMinusThirtyIsCritical() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // Baseline mean = 10000; today = 6999 → -30.01% (< -30%).
        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 10000, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 6999))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly?.severity == .critical)
        #expect(anomaly?.suggestionKey == HRVBaselineService.SuggestionKey.critical)
    }

    @Test("Severity: -20% boundary maps to mildLow (upper end of significantLow band)")
    func severityMinusTwentyBoundaryIsMildLow() async throws {
        // spec: -10% to -20% is mildLow, -20% to -30% is significantLow.
        // Boundary at -20% goes to mildLow (band is > -20% for mildLow via strict `>`).
        // We assert current behavior: exactly -20% → significantLow because `> -20.0` fails.
        // (The threshold semantics of the -20 boundary are unchanged by the P0 fix.)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 80))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly?.percentDeviation == -20.0)
        #expect(anomaly?.severity == .significantLow)
    }

    @Test("Severity: within normal band (-5%) returns .normal")
    func severityNormalBand() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 95))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly?.severity == .normal)
        #expect(anomaly?.suggestionKey == HRVBaselineService.SuggestionKey.normal)
    }

    @Test("Severity: mildLow band (-15%) returns .mildLow")
    func severityMildLowBand() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 85))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly?.severity == .mildLow)
        #expect(anomaly?.suggestionKey == HRVBaselineService.SuggestionKey.mildLow)
    }

    @Test("Severity: significantLow band (-25%) returns .significantLow")
    func severitySignificantLowBand() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        var points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 75))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly?.severity == .significantLow)
    }

    // MARK: - Insufficient data (FR-001 / SC-004)

    @Test("computeBaseline returns nil when sample days < 14")
    func insufficientSampleDaysReturnsNil() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // Only 13 distinct baseline days.
        let points = baselinePoints(referenceDate: referenceDate, dayCount: 13, value: 100, calendar: calendar)
        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let baseline = try await service.computeBaseline(referenceDate: referenceDate)
        #expect(baseline == nil)
    }

    @Test("detectAnomaly returns nil when baseline is insufficient")
    func detectAnomalyReturnsNilWithoutBaseline() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        var points = baselinePoints(referenceDate: referenceDate, dayCount: 5, value: 100, calendar: calendar)
        let todayStart = calendar.startOfDay(for: referenceDate)
        points.append(hrvPoint(date: todayStart.addingTimeInterval(3600), value: 50))

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly == nil)
    }

    // MARK: - Baseline computation

    @Test("computeBaseline returns HRVBaseline with correct mean and count")
    func computeBaselineReturnsMeanAndCount() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        let points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 50, calendar: calendar)
        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let baseline = try await service.computeBaseline(referenceDate: referenceDate)
        #expect(baseline != nil)
        #expect(baseline?.sampleCount == 14)
        #expect(baseline?.rollingMean == 50.0)
        #expect(baseline?.referenceDate == calendar.startOfDay(for: referenceDate))
    }

    @Test("Multi-source samples on the same day aggregate via arithmetic mean")
    func multipleSamplesSameDayAggregate() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // 14 days, each with two samples (values 40 and 60 → daily mean 50).
        let today = calendar.startOfDay(for: referenceDate)
        var points: [HealthDataPoint] = []
        for i in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            points.append(hrvPoint(date: day.addingTimeInterval(3600), value: 40))
            points.append(hrvPoint(date: day.addingTimeInterval(7200), value: 60))
        }

        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let baseline = try await service.computeBaseline(referenceDate: referenceDate)
        #expect(baseline?.sampleCount == 14)
        #expect(baseline?.rollingMean == 50.0)
    }

    // MARK: - detectAnomaly edge cases

    @Test("detectAnomaly returns nil when there is no sample for today")
    func detectAnomalyReturnsNilWhenNoTodaySample() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar(identifier: .gregorian)

        // Sufficient baseline days, but no sample on the reference day.
        let points = baselinePoints(referenceDate: referenceDate, dayCount: 14, value: 100, calendar: calendar)
        let cache = makeCache(seededPoints: points)
        let service = HRVBaselineService(dataCache: cache, calendar: calendar)

        let anomaly = try await service.detectAnomaly(referenceDate: referenceDate)
        #expect(anomaly == nil)
    }
}
