import Foundation
import os

public actor HRVBaselineService {

    public static let defaultWindowDays: Int = 30
    public static let defaultMinimumSampleDays: Int = 14

    public enum SuggestionKey {
        public static let normal = "hrv.suggestion.normal"
        public static let mildLow = "hrv.suggestion.mild_low"
        public static let significantLow = "hrv.suggestion.significant_low"
        public static let critical = "hrv.suggestion.critical"
    }

    private let dataCache: HealthDataCache
    private let calendar: Calendar
    private let windowDays: Int
    private let minimumSampleDays: Int
    private let logger = Logger(subsystem: "com.vitalstride", category: "HRVBaselineService")

    public init(
        dataCache: HealthDataCache,
        calendar: Calendar = .current,
        windowDays: Int = HRVBaselineService.defaultWindowDays,
        minimumSampleDays: Int = HRVBaselineService.defaultMinimumSampleDays
    ) {
        self.dataCache = dataCache
        self.calendar = calendar
        self.windowDays = windowDays
        self.minimumSampleDays = minimumSampleDays
    }

    public func computeBaseline(referenceDate: Date = Date()) async throws -> HRVBaseline? {
        let dailyMeans = try await dailyMeansInBaselineWindow(referenceDate: referenceDate)

        guard dailyMeans.count >= minimumSampleDays else {
            logger.info(
                "hrv_baseline_insufficient_data sample_days=\(dailyMeans.count) minimum=\(self.minimumSampleDays)"
            )
            return nil
        }

        let count = Double(dailyMeans.count)
        let mean = dailyMeans.reduce(0.0, +) / count
        let variance = dailyMeans.reduce(0.0) { partial, value in
            let diff = value - mean
            return partial + diff * diff
        } / count
        let stdDev = variance.squareRoot()

        logger.info("hrv_baseline_computed sample_days=\(dailyMeans.count)")
        return HRVBaseline(
            rollingMean: mean,
            rollingStdDev: stdDev,
            sampleCount: dailyMeans.count,
            referenceDate: calendar.startOfDay(for: referenceDate)
        )
    }

    public func detectAnomaly(referenceDate: Date = Date()) async throws -> HRVAnomaly? {
        guard let baseline = try await computeBaseline(referenceDate: referenceDate) else {
            return nil
        }
        guard baseline.rollingMean > 0 else {
            logger.info("hrv_anomaly_skipped reason=non_positive_baseline")
            return nil
        }
        guard let todayMean = try await todayDailyMean(referenceDate: referenceDate) else {
            logger.info("hrv_anomaly_skipped reason=no_today_sample")
            return nil
        }

        let percentDeviation = (todayMean - baseline.rollingMean) / baseline.rollingMean * 100.0
        let severity = severity(for: percentDeviation)
        let suggestionKey = suggestionKey(for: severity)

        logger.info("hrv_anomaly_detected severity=\(severity.rawValue)")
        return HRVAnomaly(
            today: todayMean,
            baseline: baseline.rollingMean,
            percentDeviation: percentDeviation,
            severity: severity,
            suggestionKey: suggestionKey
        )
    }

    // MARK: - Private

    private func dailyMeansInBaselineWindow(referenceDate: Date) async throws -> [Double] {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else {
            return []
        }

        let range = DateInterval(start: windowStart, end: todayStart)
        let points = try await dataCache.data(for: .heartRateVariabilitySDNN, in: range)
        return dailyMeans(from: points)
    }

    private func todayDailyMean(referenceDate: Date) async throws -> Double? {
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return nil
        }
        let range = DateInterval(start: todayStart, end: todayEnd)
        let points = try await dataCache.data(for: .heartRateVariabilitySDNN, in: range)
        guard !points.isEmpty else { return nil }

        let sum = points.reduce(0.0) { $0 + $1.value }
        return sum / Double(points.count)
    }

    private func dailyMeans(from points: [HealthDataPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }

        var buckets: [Date: (sum: Double, count: Int)] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.startDate)
            var bucket = buckets[day] ?? (sum: 0.0, count: 0)
            bucket.sum += point.value
            bucket.count += 1
            buckets[day] = bucket
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { $0.value.sum / Double($0.value.count) }
    }

    private func severity(for percentDeviation: Double) -> HRVAnomaly.Severity {
        if percentDeviation > -10.0 {
            return .normal
        }
        if percentDeviation > -20.0 {
            return .mildLow
        }
        if percentDeviation >= -30.0 {
            return .significantLow
        }
        return .critical
    }

    private func suggestionKey(for severity: HRVAnomaly.Severity) -> String {
        switch severity {
        case .normal: return SuggestionKey.normal
        case .mildLow: return SuggestionKey.mildLow
        case .significantLow: return SuggestionKey.significantLow
        case .critical: return SuggestionKey.critical
        }
    }
}
