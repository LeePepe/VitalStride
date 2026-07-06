import Foundation
import HealthKitService

struct HeartRateZone: Sendable, Equatable, Identifiable {
    let id: Int
    let localizedName: String
    let range: ClosedRange<Double>
    let percentage: Double
}

struct WorkoutHeartRateStats: Sendable, Equatable {
    let averageHeartRate: Int
    let maxHeartRate: Int
    let zoneDistribution: [HeartRateZone]?
    let heartRateRecovery1Min: Int?

    init(
        averageHeartRate: Int,
        maxHeartRate: Int,
        zoneDistribution: [HeartRateZone]?,
        heartRateRecovery1Min: Int? = nil
    ) {
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.zoneDistribution = zoneDistribution
        self.heartRateRecovery1Min = heartRateRecovery1Min
    }

    /// Returns a copy of these stats with `heartRateRecovery1Min` replaced.
    /// Immutable — the receiver is not modified.
    func withHeartRateRecovery1Min(_ value: Int?) -> WorkoutHeartRateStats {
        WorkoutHeartRateStats(
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            zoneDistribution: zoneDistribution,
            heartRateRecovery1Min: value
        )
    }

    static func from(dataPoints: [HealthDataPoint]) -> WorkoutHeartRateStats? {
        guard !dataPoints.isEmpty else { return nil }

        let values = dataPoints.map(\.value)
        let avg = values.reduce(0, +) / Double(values.count)
        let max = values.max() ?? 0

        let zones: [HeartRateZone]? = if dataPoints.count >= 5 {
            Self.computeZones(values: values)
        } else {
            nil
        }

        return WorkoutHeartRateStats(
            averageHeartRate: Int(avg.rounded()),
            maxHeartRate: Int(max.rounded()),
            zoneDistribution: zones
        )
    }

    static func load(
        startDate: Date,
        endDate: Date?,
        fetchHeartRate: @Sendable (DateInterval) async throws -> [HealthDataPoint]
    ) async -> WorkoutHeartRateStats? {
        guard let endDate else { return nil }
        let dateRange = DateInterval(start: startDate, end: endDate)
        do {
            let dataPoints = try await fetchHeartRate(dateRange)
            return from(dataPoints: dataPoints)
        } catch {
            return nil
        }
    }

    /// Loads workout heart-rate stats and additionally orchestrates the post-workout HRR fetch,
    /// returning stats with `heartRateRecovery1Min` populated when a valid recovery sample is
    /// available. HRR unavailability (fetch failure, insufficient post-workout samples, nil
    /// endDate) yields `heartRateRecovery1Min == nil` without breaking average / max / zone
    /// stats. Sample values never enter logs (Constitution I / Bar B).
    static func load(
        startDate: Date,
        endDate: Date?,
        fetchHeartRate: @Sendable (DateInterval) async throws -> [HealthDataPoint],
        fetchPostWorkoutHeartRate: @Sendable (DateInterval) async throws -> [HealthDataPoint]
    ) async -> WorkoutHeartRateStats? {
        guard let endDate else { return nil }
        let dateRange = DateInterval(start: startDate, end: endDate)
        let workoutSamples: [HealthDataPoint]
        do {
            workoutSamples = try await fetchHeartRate(dateRange)
        } catch {
            return nil
        }
        guard let baseStats = from(dataPoints: workoutSamples) else { return nil }
        let hrr = await loadHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            workoutEndDate: endDate,
            fetchPostWorkoutHeartRate: fetchPostWorkoutHeartRate
        )
        return baseStats.withHeartRateRecovery1Min(hrr)
    }

    private static func zoneName(for id: Int) -> String {
        switch id {
        case 1: String(localized: "热身", comment: "Heart rate zone 1 name — Warm Up")
        case 2: String(localized: "燃脂", comment: "Heart rate zone 2 name — Fat Burn")
        case 3: String(localized: "有氧", comment: "Heart rate zone 3 name — Cardio")
        case 4: String(localized: "无氧", comment: "Heart rate zone 4 name — Anaerobic")
        case 5: String(localized: "极限", comment: "Heart rate zone 5 name — Maximum")
        default: ""
        }
    }

    private static let zoneRanges: [(id: Int, range: ClosedRange<Double>)] = [
        (1, 0...99),
        (2, 100...119),
        (3, 120...139),
        (4, 140...159),
        (5, 160...300),
    ]

    private static func computeZones(values: [Double]) -> [HeartRateZone] {
        let total = Double(values.count)
        return zoneRanges.compactMap { def -> HeartRateZone? in
            let count = values.filter { def.range.contains($0) }.count
            let pct = Double(count) / total
            guard pct > 0 else { return nil }
            return HeartRateZone(
                id: def.id,
                localizedName: zoneName(for: def.id),
                range: def.range,
                percentage: pct
            )
        }
    }

    static let postWorkoutHRRWindowLowerSeconds: TimeInterval = 45
    static let postWorkoutHRRWindowUpperSeconds: TimeInterval = 90
    static let postWorkoutHRRTargetOffsetSeconds: TimeInterval = 60

    /// Post-workout fetch orchestration for HRR.
    /// Constructs the `[endDate, endDate + postWorkoutHRRWindowUpperSeconds]` interval, invokes the
    /// injected fetch closure, and delegates to the pure `computeHeartRateRecovery1Min`.
    /// Returns `nil` on fetch failure or insufficient samples so HRR unavailability never breaks
    /// average / max / zone stats. Only fetch metadata is exposed via the return type; sample
    /// values never enter logs (Constitution I / Bar B).
    static func loadHeartRateRecovery1Min(
        workoutSamples: [HealthDataPoint],
        workoutEndDate: Date,
        fetchPostWorkoutHeartRate: @Sendable (DateInterval) async throws -> [HealthDataPoint]
    ) async -> Int? {
        let postWindow = DateInterval(
            start: workoutEndDate,
            end: workoutEndDate.addingTimeInterval(postWorkoutHRRWindowUpperSeconds)
        )
        let postSamples: [HealthDataPoint]
        do {
            postSamples = try await fetchPostWorkoutHeartRate(postWindow)
        } catch {
            return nil
        }
        return computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postSamples,
            workoutEndDate: workoutEndDate
        )
    }

    static func computeHeartRateRecovery1Min(
        workoutSamples: [HealthDataPoint],
        postWorkoutSamples: [HealthDataPoint],
        workoutEndDate: Date
    ) -> Int? {
        guard let lastInWorkout = workoutSamples.max(by: { $0.startDate < $1.startDate }) else {
            return nil
        }

        let windowStart = workoutEndDate.addingTimeInterval(postWorkoutHRRWindowLowerSeconds)
        let windowEnd = workoutEndDate.addingTimeInterval(postWorkoutHRRWindowUpperSeconds)
        let target = workoutEndDate.addingTimeInterval(postWorkoutHRRTargetOffsetSeconds)

        let candidates = postWorkoutSamples.filter { sample in
            sample.startDate >= windowStart && sample.startDate <= windowEnd
        }
        guard let closest = candidates.min(by: { lhs, rhs in
            abs(lhs.startDate.timeIntervalSince(target)) < abs(rhs.startDate.timeIntervalSince(target))
        }) else {
            return nil
        }

        return Int((lastInWorkout.value - closest.value).rounded())
    }
}
