import Foundation
import VitalModels

public struct HealthMetricsCalculator: Sendable {
    public init() {}

    public func restingHeartRateSummary(from points: [HealthDataPoint]) -> RestingHeartRateSummary? {
        let values = points.filter { $0.sampleType == .restingHeartRate }.map(\.value)
        guard let first = points.filter({ $0.sampleType == .restingHeartRate }).map(\.startDate).min(),
              let last = points.filter({ $0.sampleType == .restingHeartRate }).map(\.endDate).max(),
              !values.isEmpty else { return nil }
        return RestingHeartRateSummary(
            averageBPM: values.reduce(0, +) / Double(values.count),
            minimumBPM: values.min(),
            maximumBPM: values.max(),
            sampleCount: values.count,
            periodStart: first,
            periodEnd: last
        )
    }

    public func hrvCorridor(from points: [HealthDataPoint], standardDeviationMultiplier: Double = 1) -> HRVCorridorSnapshot? {
        let values = points.filter { $0.sampleType == .heartRateVariabilitySDNN }.map(\.value)
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let deviation = sqrt(variance) * max(0, standardDeviationMultiplier)
        let matching = points.filter { $0.sampleType == .heartRateVariabilitySDNN }
        return HRVCorridorSnapshot(
            baselineMilliseconds: mean,
            lowerBoundMilliseconds: max(0, mean - deviation),
            upperBoundMilliseconds: mean + deviation,
            sampleCount: values.count,
            periodStart: matching.map(\.startDate).min(),
            periodEnd: matching.map(\.endDate).max()
        )
    }

    public func heartRateZones(from points: [HealthDataPoint], maximumHeartRate: Double) -> HeartRateZoneDistribution {
        guard maximumHeartRate > 0 else { return HeartRateZoneDistribution() }
        var durations = Dictionary(uniqueKeysWithValues: HeartRateZone.allCases.map { ($0, 0.0) })
        let heartPoints = points.filter { $0.sampleType == .heartRate }
        for point in heartPoints {
            let fraction = point.value / maximumHeartRate
            let zone: HeartRateZone
            switch fraction {
            case ..<0.60: zone = .zone1
            case ..<0.70: zone = .zone2
            case ..<0.80: zone = .zone3
            case ..<0.90: zone = .zone4
            default: zone = .zone5
            }
            durations[zone, default: 0] += max(0, point.endDate.timeIntervalSince(point.startDate))
        }
        return HeartRateZoneDistribution(durationsByZone: durations)
    }

    public func heartRateRecovery(baselineBPM: Double, oneMinuteBPM: Double?, twoMinuteBPM: Double?) -> HeartRateRecoveryMetric {
        HeartRateRecoveryMetric(baselineBPM: baselineBPM, oneMinuteBPM: oneMinuteBPM, twoMinuteBPM: twoMinuteBPM)
    }

    public func neatSnapshot(from points: [HealthDataPoint], period: DateInterval? = nil) -> NEATActivitySnapshot {
        let selected = period.map { interval in
            points.filter { interval.contains($0.startDate) || interval.contains($0.endDate) }
        } ?? points
        let steps = selected.filter { $0.sampleType == .stepCount }.reduce(0) { $0 + max(0, $1.value) }
        let active = selected.filter { $0.sampleType == .activeEnergyBurned }.reduce(0) { $0 + max(0, $1.value) }
        let basal = selected.filter { $0.sampleType == .basalEnergyBurned }.reduce(0) { $0 + max(0, $1.value) }
        let flights = selected.filter { $0.sampleType == .flightsClimbed }.reduce(0) { $0 + max(0, $1.value) }
        let movementHours = Set(selected.filter { $0.sampleType == .stepCount && $0.value > 0 }.map { Calendar.current.component(.hour, from: $0.startDate) })
        let consistency = Double(movementHours.count) / 24
        return NEATActivitySnapshot(
            dailySteps: steps,
            nonExerciseActiveEnergy: active,
            basalEnergy: basal,
            hourlyMovementConsistency: consistency,
            flightsClimbed: flights,
            periodStart: selected.map(\.startDate).min(),
            periodEnd: selected.map(\.endDate).max()
        )
    }

    public func physiologicalSnapshot(
        from points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord] = [],
        strengthWorkouts: [StrengthWorkoutSummaryInput] = [],
        maximumHeartRate: Double,
        targetSleepDuration: TimeInterval,
        generatedAt: Date = Date()
    ) -> PhysiologicalSnapshot? {
        guard let resting = restingHeartRateSummary(from: points),
              let hrv = hrvCorridor(from: points) else { return nil }
        let sleepAnalyzer = SleepArchitectureAnalyzer()
        guard let architecture = sleepAnalyzer.analyze(points: points, targetSleepDuration: targetSleepDuration) else { return nil }
        let sleepDebt = sleepAnalyzer.debtSummary(nights: [architecture], targetSleepDuration: targetSleepDuration)
        let heartRates = points.filter { $0.sampleType == .heartRate }.sorted { $0.startDate < $1.startDate }
        let recoveryStart = heartRates.first?.startDate ?? generatedAt
        let recovery = HeartRateRecoveryMetric(
            baselineBPM: heartRates.map(\.value).max() ?? resting.averageBPM,
            oneMinuteBPM: heartRates.first(where: { $0.startDate.timeIntervalSince(recoveryStart) >= 60 })?.value,
            twoMinuteBPM: heartRates.first(where: { $0.startDate.timeIntervalSince(recoveryStart) >= 120 })?.value
        )
        return PhysiologicalSnapshot(
            heart: HeartDomainSnapshot(restingHeartRate: resting, hrvCorridor: hrv, zoneDistribution: heartRateZones(from: points, maximumHeartRate: maximumHeartRate), recovery: recovery),
            sleep: SleepDomainSnapshot(architecture: architecture, debt: sleepDebt),
            neat: neatSnapshot(from: points),
            aerobic: AerobicEfficiencyCalculator().calculate(from: points) ?? AerobicEfficiencySnapshot(),
            trainingLoad: TrainingLoadCalculator().calculate(workouts: workouts, strengthWorkouts: strengthWorkouts, asOf: generatedAt),
            generatedAt: generatedAt
        )
    }
}
