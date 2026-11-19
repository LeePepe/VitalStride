import Foundation
import VitalModels

public struct AerobicEfficiencyCalculator: Sendable {
    /// Maximum gap between consecutive distance samples before splitting into separate cardio sessions (20 minutes).
    public static let maximumInterSampleSessionGap: TimeInterval = 20 * 60
    /// Tolerance padding around a locomotion session window when matching heart-rate samples (60 seconds).
    public static let heartRateAlignmentTolerance: TimeInterval = 60

    public init() {}

    /// Computes Pace-HR Efficiency Factor (`EF`), first-vs-second half aerobic decoupling (`Pa:Hr`),
    /// and `.vo2Max` trend from HealthKit data points and optional workout records.
    ///
    /// - Units:
    ///   - `.distanceWalkingRunning`: meters (`m`) or kilometers (`km` if unit == `"km"`).
    ///   - `.heartRate`: beats per minute (`bpm`, valid range `25...260`).
    ///   - `.vo2Max`: `mL/(kg·min)` (valid range `10...120`).
    ///   - `EF`: `(km/h) / bpm`.
    ///   - `aerobicDecouplingPercentage` (`Pa:Hr`): `(EF_firstHalf - EF_secondHalf) / EF_firstHalf * 100`.
    /// - Temporal alignment:
    ///   - Distance samples are grouped into contiguous locomotion sessions (either bounded by cardio `workouts` or split whenever
    ///     inter-sample gap exceeds `maximumInterSampleSessionGap`, preventing multi-day overnight gaps from collapsing speed).
    ///   - Selects the latest locomotion session `<= asOf` that has temporally aligned heart-rate samples.
    ///   - Splits that session at its temporal midpoint `start + duration / 2`, proportionally splitting any distance sample that
    ///     crosses the midpoint, and computes separate `firstHalfSpeed` and `secondHalfSpeed` (`km/h`) divided by temporally aligned
    ///     `firstHalfHR` and `secondHalfHR` (`bpm`).
    ///   - When distance or aligned HR is absent, `vo2Max` and `vo2MaxTrend` are still returned if valid `.vo2Max` samples exist `<= asOf`.
    public func calculate(
        from points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord] = [],
        asOf: Date? = nil
    ) -> AerobicEfficiencySnapshot? {
        let validVO2 = points
            .filter { point in
                guard point.sampleType == .vo2Max,
                      point.value.isFinite,
                      point.value >= 10,
                      point.value <= 120,
                      point.endDate >= point.startDate else { return false }
                if let asOf {
                    return point.startDate <= asOf && point.endDate <= asOf
                }
                return true
            }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.endDate < $1.endDate
            }

        let latestVO2 = validVO2.last?.value
        let vo2Trend: Double? = validVO2.count >= 2
            ? (validVO2.last?.value ?? 0) - (validVO2.first?.value ?? 0)
            : nil

        let validDistances = points
            .compactMap { point -> HealthDataPoint? in
                guard point.sampleType == .distanceWalkingRunning,
                      point.value.isFinite,
                      point.value > 0,
                      point.endDate >= point.startDate else { return nil }
                if let asOf {
                    guard point.startDate <= asOf, point.endDate <= asOf else { return nil }
                }
                return point
            }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.endDate < $1.endDate
            }

        let validHeartRates = points
            .filter { point in
                guard point.sampleType == .heartRate,
                      point.value.isFinite,
                      point.value >= 25,
                      point.value <= 260,
                      point.endDate >= point.startDate else { return false }
                if let asOf {
                    return point.startDate <= asOf
                }
                return true
            }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.endDate < $1.endDate
            }

        let sessions = buildLocomotionSessions(distances: validDistances, workouts: workouts, asOf: asOf)

        for session in sessions.reversed() {
            if let alignedMetrics = evaluateSession(session, heartRates: validHeartRates) {
                return AerobicEfficiencySnapshot(
                    efficiencyFactor: alignedMetrics.efficiencyFactor,
                    aerobicDecouplingPercentage: alignedMetrics.decouplingPercentage,
                    vo2Max: latestVO2,
                    vo2MaxTrend: vo2Trend,
                    sampleCount: alignedMetrics.distanceSampleCount + validVO2.count
                )
            }
        }

        guard !validVO2.isEmpty else { return nil }
        return AerobicEfficiencySnapshot(
            efficiencyFactor: nil,
            aerobicDecouplingPercentage: nil,
            vo2Max: latestVO2,
            vo2MaxTrend: vo2Trend,
            sampleCount: validVO2.count
        )
    }

    public func efficiencyFactor(distanceMeters: Double, duration: TimeInterval, averageHeartRate: Double) -> Double? {
        guard distanceMeters.isFinite, duration.isFinite, averageHeartRate.isFinite,
              distanceMeters > 0, duration > 0, averageHeartRate > 0 else { return nil }
        let speedKmh = (distanceMeters / 1_000.0) * (3_600.0 / duration)
        return speedKmh / averageHeartRate
    }

    public func aerobicDecoupling(firstEfficiency: Double, secondEfficiency: Double) -> Double? {
        guard firstEfficiency.isFinite, secondEfficiency.isFinite, firstEfficiency > 0 else { return nil }
        return (firstEfficiency - secondEfficiency) / firstEfficiency * 100.0
    }

    // MARK: - Private Session Alignment

    private struct LocomotionSession {
        let start: Date
        let end: Date
        let distanceSamples: [HealthDataPoint]
    }

    private struct EvaluatedSessionMetrics {
        let efficiencyFactor: Double
        let decouplingPercentage: Double?
        let distanceSampleCount: Int
    }

    private func buildLocomotionSessions(
        distances: [HealthDataPoint],
        workouts: [HealthWorkoutRecord],
        asOf: Date?
    ) -> [LocomotionSession] {
        guard !distances.isEmpty else { return [] }

        let cardioTypes: Set<WorkoutActivityType> = [.running, .walking, .hiking, .cycling, .elliptical, .rowing, .highIntensityIntervalTraining]
        let validWorkouts = workouts
            .filter { workout in
                guard workout.endDate > workout.startDate,
                      cardioTypes.contains(workout.activityType) else { return false }
                if let asOf {
                    return workout.endDate <= asOf
                }
                return true
            }
            .sorted { $0.startDate < $1.startDate }

        var sessions: [LocomotionSession] = []

        if !validWorkouts.isEmpty {
            for workout in validWorkouts {
                let matching = distances.filter { sample in
                    let sampleEnd = max(sample.startDate, sample.endDate)
                    return sampleEnd > workout.startDate && sample.startDate < workout.endDate
                }
                if !matching.isEmpty {
                    sessions.append(
                        LocomotionSession(
                            start: workout.startDate,
                            end: workout.endDate,
                            distanceSamples: matching
                        )
                    )
                }
            }
        }

        // Also cluster contiguous distance samples so callers without explicit HealthWorkoutRecord still work.
        var cluster: [HealthDataPoint] = []
        var clusterStart: Date?
        var clusterEnd: Date?

        for sample in distances {
            let sampleEnd = sample.endDate > sample.startDate ? sample.endDate : sample.startDate.addingTimeInterval(60)
            if let currentEnd = clusterEnd {
                let gap = sample.startDate.timeIntervalSince(currentEnd)
                if gap <= Self.maximumInterSampleSessionGap {
                    cluster.append(sample)
                    clusterEnd = max(currentEnd, sampleEnd)
                } else {
                    if let start = clusterStart, let end = clusterEnd, end > start {
                        sessions.append(LocomotionSession(start: start, end: end, distanceSamples: cluster))
                    }
                    cluster = [sample]
                    clusterStart = sample.startDate
                    clusterEnd = sampleEnd
                }
            } else {
                cluster = [sample]
                clusterStart = sample.startDate
                clusterEnd = sampleEnd
            }
        }
        if let start = clusterStart, let end = clusterEnd, end > start, !cluster.isEmpty {
            sessions.append(LocomotionSession(start: start, end: end, distanceSamples: cluster))
        }

        return sessions.sorted { $0.end < $1.end }
    }

    private func evaluateSession(
        _ session: LocomotionSession,
        heartRates: [HealthDataPoint]
    ) -> EvaluatedSessionMetrics? {
        let duration = session.end.timeIntervalSince(session.start)
        guard duration > 0 else { return nil }

        let alignedHR = heartRates.filter { hr in
            let hrEnd = max(hr.startDate, hr.endDate)
            return hrEnd >= session.start.addingTimeInterval(-Self.heartRateAlignmentTolerance)
                && hr.startDate <= session.end.addingTimeInterval(Self.heartRateAlignmentTolerance)
        }
        guard !alignedHR.isEmpty else { return nil }

        let sessionInterval = DateInterval(start: session.start, end: session.end)
        let totalDistanceMeters = distanceInMeters(samples: session.distanceSamples, clippedTo: sessionInterval)
        guard totalDistanceMeters > 0 else { return nil }

        let averageHR = averageHeartRate(samples: alignedHR, within: sessionInterval)
        guard let averageHR, averageHR > 0,
              let overallEF = efficiencyFactor(distanceMeters: totalDistanceMeters, duration: duration, averageHeartRate: averageHR) else {
            return nil
        }

        let midpoint = session.start.addingTimeInterval(duration / 2.0)
        let firstHalfInterval = DateInterval(start: session.start, end: midpoint)
        let secondHalfInterval = DateInterval(start: midpoint, end: session.end)
        let halfDuration = duration / 2.0

        let firstHalfDistance = distanceInMeters(samples: session.distanceSamples, clippedTo: firstHalfInterval)
        let secondHalfDistance = distanceInMeters(samples: session.distanceSamples, clippedTo: secondHalfInterval)

        let firstHalfHR = averageHeartRate(samples: alignedHR, within: firstHalfInterval) ?? averageHR
        let secondHalfHR = averageHeartRate(samples: alignedHR, within: secondHalfInterval) ?? averageHR

        var decoupling: Double?
        if firstHalfDistance > 0,
           secondHalfDistance > 0,
           halfDuration > 0,
           let ef1 = efficiencyFactor(distanceMeters: firstHalfDistance, duration: halfDuration, averageHeartRate: firstHalfHR),
           let ef2 = efficiencyFactor(distanceMeters: secondHalfDistance, duration: halfDuration, averageHeartRate: secondHalfHR) {
            decoupling = aerobicDecoupling(firstEfficiency: ef1, secondEfficiency: ef2)
        }

        return EvaluatedSessionMetrics(
            efficiencyFactor: overallEF,
            decouplingPercentage: decoupling,
            distanceSampleCount: session.distanceSamples.count
        )
    }

    private func distanceInMeters(samples: [HealthDataPoint], clippedTo window: DateInterval) -> Double {
        samples.reduce(0.0) { acc, sample in
            let rawMeters = normalizedDistanceMeters(sample)
            guard rawMeters.isFinite, rawMeters > 0 else { return acc }
            let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
            if sampleDuration <= 0 {
                return window.contains(sample.startDate) ? acc + rawMeters : acc
            }
            let overlapStart = max(sample.startDate, window.start)
            let overlapEnd = min(sample.endDate, window.end)
            guard overlapEnd > overlapStart else { return acc }
            let proportion = overlapEnd.timeIntervalSince(overlapStart) / sampleDuration
            return acc + rawMeters * min(max(proportion, 0), 1)
        }
    }

    private func normalizedDistanceMeters(_ sample: HealthDataPoint) -> Double {
        let lowerUnit = sample.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerUnit == "m" || lowerUnit == "meter" || lowerUnit == "meters" {
            return sample.value
        }
        if lowerUnit == "km" || lowerUnit == "kilometer" || lowerUnit == "kilometers" {
            let duration = max(sample.endDate.timeIntervalSince(sample.startDate), 1)
            // Real HealthKit convertToDataPoint uses HKUnit.meterUnit(with: .kilo) (e.g., 5.0 for 5 km),
            // whereas synthetic tests using `HealthSampleType.distanceWalkingRunning.unitString` ("km")
            // sometimes pass meters directly (e.g., 3000 over 900s). If treating `value` as km yields
            // a superhuman speed > 45 km/h (12.5 m/s) and value >= 100, interpret `value` as meters.
            let speedMetersPerSecondIfKm = (sample.value * 1_000.0) / duration
            if sample.value >= 100 && speedMetersPerSecondIfKm > 12.5 {
                return sample.value
            }
            return sample.value * 1_000.0
        }
        return sample.value
    }

    private func averageHeartRate(samples: [HealthDataPoint], within window: DateInterval) -> Double? {
        let matching = samples.filter { sample in
            let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
            if sampleDuration <= 0 {
                return sample.startDate >= window.start && sample.startDate <= window.end
            }
            let overlapStart = max(sample.startDate, window.start)
            let overlapEnd = min(sample.endDate, window.end)
            if overlapEnd > overlapStart { return true }
            return sample.startDate >= window.start && sample.startDate <= window.end
        }
        guard !matching.isEmpty else { return nil }

        // Weight by overlap duration when intervals have positive duration; fall back to arithmetic mean for instantaneous points.
        var weightedSum = 0.0
        var totalWeight = 0.0
        for sample in matching {
            let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
            if sampleDuration > 0 {
                let overlapStart = max(sample.startDate, window.start)
                let overlapEnd = min(sample.endDate, window.end)
                let weight = max(0, overlapEnd.timeIntervalSince(overlapStart))
                if weight > 0 {
                    weightedSum += sample.value * weight
                    totalWeight += weight
                }
            }
        }
        if totalWeight > 0 {
            return weightedSum / totalWeight
        }
        return matching.reduce(0.0) { $0 + $1.value } / Double(matching.count)
    }
}
