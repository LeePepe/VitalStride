import Foundation
import VitalModels

public struct TrainingLoadCalculator: Sendable {
    public init() {}

    /// Computes Acute Training Load (`ATL`, 7-day EWMA), Chronic Training Load (`CTL`, 42-day EWMA),
    /// Training Stress Balance (`TSB = CTL - ATL`), Acute:Chronic Workload Ratio (`ACWR`),
    /// and 7d/14d trajectory deltas across HealthKit workouts and SwiftData strength workouts.
    ///
    /// - Load normalization:
    ///   - Cardio / HR-tracked HealthKit workouts use Banister TRIMP (`durationMinutes * hrReserve * 0.64 * exp(1.92 * hrReserve)`),
    ///     producing ~30–140 stress units per hour.
    ///   - Strength workouts (`StrengthWorkoutSummaryInput`) use a session-RPE / TSS-equivalent formula bounded with set & volume density:
    ///     `durationHours * (RPE / 10)^2 * 100 * densityFactor`, producing ~25–120 stress units per hour on the same scale as TRIMP.
    /// - Temporal filtering:
    ///   - Future or incomplete workouts (`startDate > asOf` or `endDate > asOf` or `endDate <= startDate`) are excluded.
    /// - Deduplication:
    ///   - Mirrored HealthKit workouts matching `StrengthWorkoutSummaryInput.healthKitUUID` (case-insensitive UUID match) are excluded.
    ///   - When `healthKitUUID` is nil on a strength workout, any HealthKit strength workout (`.traditionalStrengthTraining`,
    ///     `.functionalStrengthTraining`, `.other`) whose `[startDate, endDate]` overlaps >= 50% of the shorter session's duration
    ///     (or starts within 5 minutes with overlapping window) is treated as a duplicate mirror and excluded.
    public func calculate(
        workouts: [HealthWorkoutRecord],
        strengthWorkouts: [StrengthWorkoutSummaryInput],
        asOf date: Date = Date(),
        restingHeartRate: Double = 60,
        maximumHeartRate: Double = 190,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> TrainingLoadSnapshot {
        let validRHR = (restingHeartRate.isFinite && restingHeartRate >= 30 && restingHeartRate <= 120) ? restingHeartRate : 60
        let validMaxHR = (maximumHeartRate.isFinite && maximumHeartRate > validRHR + 15 && maximumHeartRate <= 240)
            ? maximumHeartRate
            : max(190, validRHR + 40)

        let validStrengthWorkouts = strengthWorkouts.filter { workout in
            guard workout.endDate > workout.startDate, workout.startDate <= date else { return false }
            // Exclude future-started sessions; allow a session that started on/before `asOf` (e.g., when callers pass `asOf: workout.startDate` or `asOf` on the same day).
            return calendar.startOfDay(for: workout.endDate) <= calendar.startOfDay(for: date) || workout.endDate <= date
        }

        let validHealthWorkouts = workouts.filter { workout in
            let effectiveEnd = workout.endDate > workout.startDate
                ? workout.endDate
                : workout.startDate.addingTimeInterval(max(0, workout.duration))
            guard effectiveEnd > workout.startDate, workout.startDate <= date else { return false }
            return calendar.startOfDay(for: effectiveEnd) <= calendar.startOfDay(for: date) || effectiveEnd <= date
        }

        let (deduplicatedHKWorkouts, deduplicatedCount) = deduplicate(
            healthWorkouts: validHealthWorkouts,
            againstStrengthWorkouts: validStrengthWorkouts
        )

        let hkEvents = deduplicatedHKWorkouts.map {
            trainingStress(for: $0, restingHeartRate: validRHR, maximumHeartRate: validMaxHR)
        }
        let strengthEvents = validStrengthWorkouts.map(strengthStress(for:))
        let events = (hkEvents + strengthEvents).filter { $0.load.isFinite && $0.load > 0 }

        guard let earliest = events.map(\.date).min() else {
            return TrainingLoadSnapshot(
                acuteTrainingLoad: 0,
                chronicTrainingLoad: 0,
                trainingStressBalance: 0,
                acuteChronicWorkloadRatio: nil,
                trimp: 0,
                tss: 0,
                atlDelta7d: 0,
                ctlDelta7d: 0,
                ctlDelta14d: 0,
                tsbDelta7d: 0,
                deduplicatedWorkoutCount: deduplicatedCount,
                recentTrajectory: []
            )
        }

        let firstDay = calendar.startOfDay(for: earliest)
        let lastDay = calendar.startOfDay(for: date)
        guard firstDay <= lastDay else {
            return TrainingLoadSnapshot(
                acuteTrainingLoad: 0,
                chronicTrainingLoad: 0,
                trainingStressBalance: 0,
                acuteChronicWorkloadRatio: nil,
                trimp: 0,
                tss: 0,
                deduplicatedWorkoutCount: deduplicatedCount
            )
        }

        // Group daily load by startOfDay for O(N + D) iteration including rest days (load = 0).
        var dailyTRIMPByDay: [Date: Double] = [:]
        var dailyTSSByDay: [Date: Double] = [:]
        for event in events {
            let bucket = calendar.startOfDay(for: event.date)
            switch event.kind {
            case .trimp:
                dailyTRIMPByDay[bucket, default: 0] += event.load
            case .tss:
                dailyTSSByDay[bucket, default: 0] += event.load
            }
        }

        var atl = 0.0
        var ctl = 0.0
        var totalTRIMP = 0.0
        var totalTSS = 0.0
        var trajectory: [TrainingLoadDailyPoint] = []

        var day = firstDay
        while day <= lastDay {
            let dayTRIMP = dailyTRIMPByDay[day, default: 0]
            let dayTSS = dailyTSSByDay[day, default: 0]
            let dailyLoad = dayTRIMP + dayTSS
            atl = ewma(previous: atl, load: dailyLoad, period: 7)
            ctl = ewma(previous: ctl, load: dailyLoad, period: 42)
            totalTRIMP += dayTRIMP
            totalTSS += dayTSS
            trajectory.append(
                TrainingLoadDailyPoint(
                    date: day,
                    dailyLoad: dailyLoad,
                    acuteTrainingLoad: atl,
                    chronicTrainingLoad: ctl,
                    trainingStressBalance: ctl - atl
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else { break }
            day = nextDay
        }

        let tsb = ctl - atl
        let acwr: Double? = ctl > 0.001 ? atl / ctl : nil

        let point7dAgo = point(in: trajectory, daysBefore: 7, referenceDay: lastDay, calendar: calendar)
        let point14dAgo = point(in: trajectory, daysBefore: 14, referenceDay: lastDay, calendar: calendar)

        let atlDelta7d = atl - (point7dAgo?.acuteTrainingLoad ?? 0)
        let ctlDelta7d = ctl - (point7dAgo?.chronicTrainingLoad ?? 0)
        let ctlDelta14d = ctl - (point14dAgo?.chronicTrainingLoad ?? 0)
        let tsbDelta7d = tsb - (point7dAgo?.trainingStressBalance ?? 0)

        return TrainingLoadSnapshot(
            acuteTrainingLoad: atl,
            chronicTrainingLoad: ctl,
            trainingStressBalance: tsb,
            acuteChronicWorkloadRatio: acwr,
            trimp: totalTRIMP,
            tss: totalTSS,
            atlDelta7d: atlDelta7d,
            ctlDelta7d: ctlDelta7d,
            ctlDelta14d: ctlDelta14d,
            tsbDelta7d: tsbDelta7d,
            deduplicatedWorkoutCount: deduplicatedCount,
            recentTrajectory: Array(trajectory.suffix(14))
        )
    }

    public func trimp(
        duration: TimeInterval,
        averageHeartRate: Double,
        restingHeartRate: Double = 60,
        maximumHeartRate: Double = 190
    ) -> Double {
        guard duration.isFinite, averageHeartRate.isFinite, restingHeartRate.isFinite, maximumHeartRate.isFinite,
              duration > 0, maximumHeartRate > restingHeartRate else { return 0 }
        let intensity = min(max((averageHeartRate - restingHeartRate) / (maximumHeartRate - restingHeartRate), 0), 1)
        return (duration / 60.0) * intensity * (0.64 * exp(1.92 * intensity))
    }

    /// Computes normalized session-RPE / TSS-equivalent stress for a strength workout on a scale comparable to Banister TRIMP (~25–120 per hour).
    ///
    /// Formula:
    /// - Effective duration is capped to `[5 min, 180 min]` (with set-based floor so brief logged timestamps still reflect set work).
    /// - Intensity factor `IF = clamp(estimatedRPE, 1, 10) / 10`.
    /// - Base session stress = `durationHours * IF^2 * 100`.
    /// - Density multiplier in `[0.75, 1.35]` incorporates completed working sets (`setCount / 15`) and volume (`workingVolume / 10_000 kg`)
    ///   without allowing raw kg-volume to explode stress by 80×.
    public func strengthLoad(_ input: StrengthWorkoutSummaryInput) -> Double {
        guard input.endDate > input.startDate else { return 0 }
        guard input.workingVolume > 0 || input.setCount > 0 else { return 0 }
        let rawMinutes = input.endDate.timeIntervalSince(input.startDate) / 60.0
        guard rawMinutes.isFinite, rawMinutes > 0 else { return 0 }

        let setFloorMinutes = Double(min(max(input.setCount, 0), 40)) * 2.0
        let effectiveMinutes = min(max(rawMinutes, min(setFloorMinutes, 90.0), 5.0), 180.0)
        let durationHours = effectiveMinutes / 60.0

        let rpe = input.estimatedRPE.isFinite && input.estimatedRPE > 0
            ? min(max(input.estimatedRPE, 1.0), 10.0)
            : 7.0
        let intensityFactor = rpe / 10.0
        let baseSessionTSS = durationHours * intensityFactor * intensityFactor * 100.0

        let setFactor = min(Double(max(input.setCount, 0)) / 15.0, 1.5)
        let volumeFactor = min(max(input.workingVolume, 0) / 10_000.0, 1.5)
        let densityMultiplier = 0.75 + 0.25 * setFactor + 0.15 * volumeFactor

        return min(baseSessionTSS * densityMultiplier, 200.0)
    }

    // MARK: - Private Helpers

    private func deduplicate(
        healthWorkouts: [HealthWorkoutRecord],
        againstStrengthWorkouts strengthWorkouts: [StrengthWorkoutSummaryInput]
    ) -> (kept: [HealthWorkoutRecord], deduplicatedCount: Int) {
        guard !strengthWorkouts.isEmpty else { return (healthWorkouts, 0) }

        let mirroredUUIDs = Set(
            strengthWorkouts.compactMap { $0.healthKitUUID?.lowercased() }
        )
        let unlinkedStrength = strengthWorkouts.filter { $0.healthKitUUID == nil }
        let strengthCompatibleTypes: Set<WorkoutActivityType> = [
            .traditionalStrengthTraining,
            .functionalStrengthTraining,
            .other
        ]

        var kept: [HealthWorkoutRecord] = []
        var deduplicatedCount = 0

        for hk in healthWorkouts {
            if mirroredUUIDs.contains(hk.id.uuidString.lowercased()) {
                deduplicatedCount += 1
                continue
            }

            if strengthCompatibleTypes.contains(hk.activityType),
               unlinkedStrength.contains(where: { isMirroredWindowOverlap(hk: hk, strength: $0) }) {
                deduplicatedCount += 1
                continue
            }

            kept.append(hk)
        }

        return (kept, deduplicatedCount)
    }

    private func isMirroredWindowOverlap(hk: HealthWorkoutRecord, strength: StrengthWorkoutSummaryInput) -> Bool {
        let hkEnd = hk.endDate > hk.startDate ? hk.endDate : hk.startDate.addingTimeInterval(max(0, hk.duration))
        let overlapStart = max(hk.startDate, strength.startDate)
        let overlapEnd = min(hkEnd, strength.endDate)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 0 else { return false }

        let hkDuration = max(1, hkEnd.timeIntervalSince(hk.startDate))
        let strengthDuration = max(1, strength.endDate.timeIntervalSince(strength.startDate))
        let minDuration = min(hkDuration, strengthDuration)
        let overlapRatio = overlap / minDuration
        let startDelta = abs(hk.startDate.timeIntervalSince(strength.startDate))
        return overlapRatio >= 0.5 || (startDelta <= 300 && overlapRatio >= 0.25)
    }

    private func trainingStress(
        for workout: HealthWorkoutRecord,
        restingHeartRate: Double,
        maximumHeartRate: Double
    ) -> LoadEvent {
        let effectiveDuration = workout.duration > 0
            ? workout.duration
            : max(0, workout.endDate.timeIntervalSince(workout.startDate))
        let load: Double
        let kind: LoadKind
        if let averageHeartRate = workout.averageHeartRate, averageHeartRate > 0 {
            load = trimp(
                duration: effectiveDuration,
                averageHeartRate: Double(averageHeartRate),
                restingHeartRate: restingHeartRate,
                maximumHeartRate: maximumHeartRate
            )
            kind = .trimp
        } else {
            // Moderate aerobic/mixed default (~45 TSS/hour) when HR was not recorded
            load = max(0, (effectiveDuration / 60.0) * 0.75)
            kind = .tss
        }
        return LoadEvent(date: workout.startDate, load: load, kind: kind)
    }

    private func strengthStress(for workout: StrengthWorkoutSummaryInput) -> LoadEvent {
        LoadEvent(date: workout.startDate, load: strengthLoad(workout), kind: .tss)
    }

    private func ewma(previous: Double, load: Double, period: Double) -> Double {
        let alpha = 2.0 / (period + 1.0)
        return previous + alpha * (load - previous)
    }

    private func point(
        in trajectory: [TrainingLoadDailyPoint],
        daysBefore: Int,
        referenceDay: Date,
        calendar: Calendar
    ) -> TrainingLoadDailyPoint? {
        guard let targetDate = calendar.date(byAdding: .day, value: -daysBefore, to: referenceDay) else {
            return nil
        }
        return trajectory.first { $0.date == targetDate }
    }

    private struct LoadEvent: Sendable {
        let date: Date
        let load: Double
        let kind: LoadKind
    }

    private enum LoadKind: Sendable {
        case trimp
        case tss
    }
}
