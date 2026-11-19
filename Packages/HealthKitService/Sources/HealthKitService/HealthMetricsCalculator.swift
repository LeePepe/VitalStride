import Foundation
import VitalModels

public struct HealthMetricsCalculator: Sendable {
    /// Maximum inter-sample gap inferred for instantaneous (`startDate == endDate`) heart-rate samples (15 seconds).
    public static let defaultInstantaneousHeartRateSampleStep: TimeInterval = 5
    public static let defaultMaximumHeartRateGap: TimeInterval = 15

    public init() {}

    // MARK: - 1. Resting Heart Rate & HRV Corridor

    /// Computes Resting Heart Rate summary anchored to `asOf` (or latest sample date when `asOf` is nil),
    /// with 7-day rolling mean, 60-day daily-baseline mean, and latest observation.
    ///
    /// - Valid physical range: `25...220 bpm` (finite). Future samples (`startDate > asOf` or `endDate > asOf`) and
    ///   samples older than 60 calendar days before the anchor day are excluded.
    public func restingHeartRateSummary(
        from points: [HealthDataPoint],
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> RestingHeartRateSummary? {
        let valid = points
            .filter { point in
                guard point.sampleType == .restingHeartRate,
                      point.value.isFinite,
                      point.value >= 25,
                      point.value <= 220,
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

        guard let latestSample = valid.last else { return nil }
        let anchorDate = asOf ?? latestSample.endDate
        let anchorDay = calendar.startOfDay(for: anchorDate)
        let start60d = calendar.date(byAdding: .day, value: -59, to: anchorDay) ?? anchorDay.addingTimeInterval(-59 * 86_400)
        let start7d = calendar.date(byAdding: .day, value: -6, to: anchorDay) ?? anchorDay.addingTimeInterval(-6 * 86_400)

        let window60d = valid.filter { $0.startDate >= start60d && $0.startDate <= anchorDate }
        guard !window60d.isEmpty else { return nil }

        let dailyMeans60d = dailyMeans(for: window60d, calendar: calendar)
        let baselineBPM = dailyMeans60d.isEmpty
            ? window60d.map(\.value).reduce(0, +) / Double(window60d.count)
            : dailyMeans60d.map(\.mean).reduce(0, +) / Double(dailyMeans60d.count)

        let dailyMeans7d = dailyMeans60d.filter { $0.day >= start7d && $0.day <= anchorDay }
        let currentBPM = dailyMeans60d.last?.mean ?? window60d.last?.value ?? baselineBPM
        let sevenDayAverageBPM = dailyMeans7d.isEmpty
            ? currentBPM
            : dailyMeans7d.map(\.mean).reduce(0, +) / Double(dailyMeans7d.count)

        let values = window60d.map(\.value)
        let averageBPM = values.reduce(0, +) / Double(values.count)

        return RestingHeartRateSummary(
            averageBPM: averageBPM,
            minimumBPM: values.min(),
            maximumBPM: values.max(),
            sampleCount: window60d.count,
            periodStart: window60d.map(\.startDate).min(),
            periodEnd: window60d.map(\.endDate).max(),
            currentBPM: currentBPM,
            sevenDayAverageBPM: sevenDayAverageBPM,
            baselineBPM: baselineBPM,
            baselineDayCount: dailyMeans60d.count
        )
    }

    /// Computes HRV SDNN 60-day baseline corridor and 7-day rolling / current comparison anchored to `asOf`.
    ///
    /// - Valid physical range: `1...300 ms` (finite). Future samples (`> asOf`) and samples older than 60 calendar days
    ///   before the anchor day are excluded.
    /// - Daily buckets (`calendar.startOfDay`) prevent high-frequency single-day measurements from skewing the 60-day baseline.
    /// - `baselineMilliseconds`, `lowerBoundMilliseconds`, and `upperBoundMilliseconds` represent the 60-day daily-mean ± `k * SD` corridor.
    /// - `currentMilliseconds` is the latest daily mean (`<= asOf`) and `sevenDayAverageMilliseconds` is the trailing 7-day daily mean.
    public func hrvCorridor(
        from points: [HealthDataPoint],
        standardDeviationMultiplier: Double = 1,
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> HRVCorridorSnapshot? {
        let validMultiplier = standardDeviationMultiplier.isFinite ? max(0, standardDeviationMultiplier) : 1
        let valid = points
            .filter { point in
                guard point.sampleType == .heartRateVariabilitySDNN,
                      point.value.isFinite,
                      point.value >= 1,
                      point.value <= 300,
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

        guard let latestSample = valid.last else { return nil }
        let anchorDate = asOf ?? latestSample.endDate
        let anchorDay = calendar.startOfDay(for: anchorDate)
        let start60d = calendar.date(byAdding: .day, value: -59, to: anchorDay) ?? anchorDay.addingTimeInterval(-59 * 86_400)
        let start7d = calendar.date(byAdding: .day, value: -6, to: anchorDay) ?? anchorDay.addingTimeInterval(-6 * 86_400)

        let window60d = valid.filter { $0.startDate >= start60d && $0.startDate <= anchorDate }
        guard !window60d.isEmpty else { return nil }

        let dailyMeans60d = dailyMeans(for: window60d, calendar: calendar)
        let seriesForBaseline: [Double] = dailyMeans60d.count >= 2
            ? dailyMeans60d.map(\.mean)
            : window60d.map(\.value)

        let mean = seriesForBaseline.reduce(0, +) / Double(seriesForBaseline.count)
        let variance = seriesForBaseline.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(seriesForBaseline.count)
        let deviation = sqrt(variance) * validMultiplier

        let window7d = window60d.filter { calendar.startOfDay(for: $0.startDate) >= start7d }
        let dailyMeans7d = dailyMeans60d.filter { $0.day >= start7d && $0.day <= anchorDay }
        let currentHRV = window60d.last?.value ?? dailyMeans60d.last?.mean ?? mean
        let sevenDayHRV: Double
        if !dailyMeans7d.isEmpty {
            sevenDayHRV = dailyMeans7d.map(\.mean).reduce(0, +) / Double(dailyMeans7d.count)
        } else {
            sevenDayHRV = currentHRV
        }

        return HRVCorridorSnapshot(
            baselineMilliseconds: mean,
            lowerBoundMilliseconds: max(0, mean - deviation),
            upperBoundMilliseconds: mean + deviation,
            sampleCount: window60d.count,
            periodStart: window60d.map(\.startDate).min(),
            periodEnd: window60d.map(\.endDate).max(),
            currentMilliseconds: currentHRV,
            sevenDayAverageMilliseconds: sevenDayHRV,
            sevenDaySampleCount: window7d.count,
            baselineDayCount: dailyMeans60d.count
        )
    }

    // MARK: - 2. Heart Rate Zones 1–5

    /// Resolves effective maximum heart rate (`bpm`) using explicit override -> age-estimated (`208 - 0.7 * age`) ->
    /// observed peak heart rate fallback -> default `190 bpm`.
    public func resolveMaximumHeartRate(
        userMaximumHeartRate: Double? = nil,
        userAgeYears: Int? = nil,
        points: [HealthDataPoint] = [],
        asOf: Date? = nil
    ) -> Double {
        if let userMax = userMaximumHeartRate, userMax.isFinite, userMax >= 120, userMax <= 240 {
            return userMax
        }
        let observedPeak = points
            .filter { point in
                guard point.sampleType == .heartRate,
                      point.value.isFinite,
                      point.value >= 40,
                      point.value <= 240 else { return false }
                if let asOf { return point.startDate <= asOf }
                return true
            }
            .map(\.value)
            .max()

        if let age = userAgeYears, (10...100).contains(age) {
            let tanakaEstimate = 208.0 - 0.7 * Double(age)
            if let observedPeak {
                return max(tanakaEstimate, observedPeak)
            }
            return tanakaEstimate
        }

        if let observedPeak, observedPeak >= 140 {
            return observedPeak
        }
        return 190.0
    }

    /// Computes Heart Rate Zones 1–5 time distribution (`<60%`, `60–70%`, `70–80%`, `80–90%`, `>=90%` of effective max HR).
    ///
    /// - Supports both explicit-duration HR intervals (`endDate > startDate`) and realistic instantaneous Apple Watch / strap
    ///   samples (`startDate == endDate`) by inferring bounded inter-sample intervals (`min(next.startDate - current.startDate, maxSampleGap)`
    ///   with a fallback step of `defaultInstantaneousHeartRateSampleStep` for the terminal sample in a contiguous burst).
    /// - Deduplicates simultaneous multi-source samples and sweeps non-overlapping timeline segments so overlapping Watch + strap
    ///   samples never double-count duration.
    /// - Clips intervals to `clipIntervals` (e.g., workout windows) when provided.
    public func heartRateZones(
        from points: [HealthDataPoint],
        maximumHeartRate: Double? = nil,
        userAgeYears: Int? = nil,
        clipIntervals: [DateInterval]? = nil,
        maxSampleGap: TimeInterval = defaultMaximumHeartRateGap,
        asOf: Date? = nil
    ) -> HeartRateZoneDistribution {
        let resolvedMaxHR = resolveMaximumHeartRate(
            userMaximumHeartRate: maximumHeartRate,
            userAgeYears: userAgeYears,
            points: points,
            asOf: asOf
        )
        guard resolvedMaxHR.isFinite, resolvedMaxHR > 0 else {
            return HeartRateZoneDistribution()
        }

        let validHR = points
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

        guard !validHR.isEmpty else {
            return HeartRateZoneDistribution(resolvedMaximumHeartRateBPM: resolvedMaxHR)
        }

        let mergedClipWindows: [(start: Date, end: Date)]? = clipIntervals.map { windows in
            SleepArchitectureAnalyzer.mergeIntervals(
                windows.compactMap { window in
                    guard window.duration > 0 else { return nil }
                    return (start: window.start, end: window.end)
                }
            )
        }
        if let mergedClipWindows, mergedClipWindows.isEmpty {
            return HeartRateZoneDistribution(resolvedMaximumHeartRateBPM: resolvedMaxHR)
        }

        // Collapse simultaneous timestamps (e.g., Apple Watch + chest strap at identical second) using mean BPM and max endDate.
        struct NormalizedSample {
            let start: Date
            let explicitEnd: Date
            let bpm: Double
        }

        var collapsed: [NormalizedSample] = []
        var idx = 0
        while idx < validHR.count {
            let start = validHR[idx].startDate
            var bpmSum = 0.0
            var count = 0
            var maxEnd = validHR[idx].endDate
            while idx < validHR.count && abs(validHR[idx].startDate.timeIntervalSince(start)) < 0.001 {
                let candidateEnd = asOf.map { min(validHR[idx].endDate, $0) } ?? validHR[idx].endDate
                maxEnd = max(maxEnd, candidateEnd)
                bpmSum += validHR[idx].value
                count += 1
                idx += 1
            }
            collapsed.append(
                NormalizedSample(
                    start: start,
                    explicitEnd: max(start, maxEnd),
                    bpm: bpmSum / Double(max(count, 1))
                )
            )
        }

        // Convert to non-overlapping intervals.
        let effectiveMaxGap = maxSampleGap.isFinite && maxSampleGap > 0 ? maxSampleGap : Self.defaultMaximumHeartRateGap
        let defaultStep = min(Self.defaultInstantaneousHeartRateSampleStep, effectiveMaxGap)

        var rawSegments: [(start: Date, end: Date, bpm: Double)] = []
        for i in 0..<collapsed.count {
            let current = collapsed[i]
            let nextStart: Date? = (i + 1 < collapsed.count) ? collapsed[i + 1].start : nil

            let inferredEnd: Date
            if current.explicitEnd > current.start {
                if let nextStart {
                    inferredEnd = min(current.explicitEnd, nextStart)
                } else {
                    inferredEnd = current.explicitEnd
                }
            } else {
                // Instantaneous sample (`startDate == endDate`)
                if let nextStart {
                    let gap = nextStart.timeIntervalSince(current.start)
                    if gap > 0 && gap <= effectiveMaxGap {
                        inferredEnd = nextStart
                    } else if gap > effectiveMaxGap {
                        inferredEnd = current.start.addingTimeInterval(defaultStep)
                    } else {
                        inferredEnd = current.start
                    }
                } else if i > 0 {
                    let prevGap = current.start.timeIntervalSince(collapsed[i - 1].start)
                    let step = (prevGap > 0 && prevGap <= effectiveMaxGap) ? prevGap : defaultStep
                    inferredEnd = current.start.addingTimeInterval(step)
                } else {
                    inferredEnd = current.start.addingTimeInterval(defaultStep)
                }
            }

            let cappedEnd = asOf.map { min(inferredEnd, $0) } ?? inferredEnd
            if cappedEnd > current.start {
                rawSegments.append((start: current.start, end: cappedEnd, bpm: current.bpm))
            }
        }

        var durations = Dictionary(uniqueKeysWithValues: HeartRateZone.allCases.map { ($0, 0.0) })
        var cursor: Date?

        for segment in rawSegments {
            let segStart = cursor.map { max(segment.start, $0) } ?? segment.start
            guard segment.end > segStart else { continue }
            cursor = segment.end

            let zone = classifyZone(bpm: segment.bpm, maximumHeartRate: resolvedMaxHR)
            if let mergedClipWindows {
                for window in mergedClipWindows {
                    let overlapStart = max(segStart, window.start)
                    let overlapEnd = min(segment.end, window.end)
                    if overlapEnd > overlapStart {
                        durations[zone, default: 0] += overlapEnd.timeIntervalSince(overlapStart)
                    }
                }
            } else {
                durations[zone, default: 0] += segment.end.timeIntervalSince(segStart)
            }
        }

        return HeartRateZoneDistribution(
            durationsByZone: durations,
            resolvedMaximumHeartRateBPM: resolvedMaxHR
        )
    }

    // MARK: - 3. Post-Workout Heart Rate Recovery (HRR)

    public func heartRateRecovery(
        baselineBPM: Double,
        oneMinuteBPM: Double?,
        twoMinuteBPM: Double?,
        workoutEndDate: Date? = nil
    ) -> HeartRateRecoveryMetric {
        HeartRateRecoveryMetric(
            baselineBPM: baselineBPM,
            oneMinuteBPM: oneMinuteBPM,
            twoMinuteBPM: twoMinuteBPM,
            workoutEndDate: workoutEndDate
        )
    }

    /// Computes post-workout 1-minute and 2-minute Heart Rate Recovery (`HRR`) anchored to the latest completed workout (`<= asOf`).
    ///
    /// - Selects the most recent completed workout from `workouts` and `strengthWorkouts` whose `endDate <= asOf` (or any completed workout when `asOf` is nil).
    /// - Baseline BPM is anchored to the heart-rate sample closest to `workout.endDate` within `[max(workout.startDate, endDate - 120s), endDate + 15s]`
    ///   (falling back to `workout.averageHeartRate` only if no end-of-workout sample exists).
    /// - 1-minute recovery BPM selects the sample closest to `endDate + 60s` within `[endDate + 45s, endDate + 90s]`.
    /// - 2-minute recovery BPM selects the sample closest to `endDate + 120s` within `[endDate + 105s, endDate + 150s]`.
    /// - Missing post-workout samples remain `nil` (never substituted from unrelated historical resting HR).
    public func heartRateRecovery(
        from points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord] = [],
        strengthWorkouts: [StrengthWorkoutSummaryInput] = [],
        asOf: Date? = nil
    ) -> HeartRateRecoveryMetric? {
        let validHR = points
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
            .sorted { $0.startDate < $1.startDate }

        guard !validHR.isEmpty else { return nil }

        struct CompletedWorkoutWindow {
            let start: Date
            let end: Date
            let fallbackAverageHR: Double?
        }

        var candidates: [CompletedWorkoutWindow] = []
        for workout in workouts {
            let end = workout.endDate > workout.startDate
                ? workout.endDate
                : workout.startDate.addingTimeInterval(max(0, workout.duration))
            guard end > workout.startDate else { continue }
            if let asOf, end > asOf { continue }
            candidates.append(
                CompletedWorkoutWindow(
                    start: workout.startDate,
                    end: end,
                    fallbackAverageHR: workout.averageHeartRate.map(Double.init)
                )
            )
        }
        for strength in strengthWorkouts {
            guard strength.endDate > strength.startDate else { continue }
            if let asOf, strength.endDate > asOf { continue }
            candidates.append(
                CompletedWorkoutWindow(
                    start: strength.startDate,
                    end: strength.endDate,
                    fallbackAverageHR: nil
                )
            )
        }

        candidates.sort { $0.end < $1.end }
        guard !candidates.isEmpty else { return nil }

        // Evaluate from most recent completed workout backward to find one with valid baseline HR near workout end.
        for candidate in candidates.reversed() {
            let workoutEnd = candidate.end
            let baselineWindowStart = max(candidate.start, workoutEnd.addingTimeInterval(-120))
            let baselineWindowEnd = workoutEnd.addingTimeInterval(15)

            let baselineSamples = validHR.filter { sample in
                sample.startDate >= baselineWindowStart && sample.startDate <= baselineWindowEnd
            }
            let baselineBPM: Double? = baselineSamples
                .min(by: { abs($0.startDate.timeIntervalSince(workoutEnd)) < abs($1.startDate.timeIntervalSince(workoutEnd)) })?
                .value ?? candidate.fallbackAverageHR

            guard let baselineBPM, baselineBPM > 0 else { continue }

            let target1Min = workoutEnd.addingTimeInterval(60)
            let window1MinStart = workoutEnd.addingTimeInterval(45)
            let window1MinEnd = workoutEnd.addingTimeInterval(90)
            let oneMinSample = validHR
                .filter { $0.startDate >= window1MinStart && $0.startDate <= window1MinEnd }
                .min(by: { abs($0.startDate.timeIntervalSince(target1Min)) < abs($1.startDate.timeIntervalSince(target1Min)) })

            let target2Min = workoutEnd.addingTimeInterval(120)
            let window2MinStart = workoutEnd.addingTimeInterval(105)
            let window2MinEnd = workoutEnd.addingTimeInterval(150)
            let twoMinSample = validHR
                .filter { $0.startDate >= window2MinStart && $0.startDate <= window2MinEnd }
                .min(by: { abs($0.startDate.timeIntervalSince(target2Min)) < abs($1.startDate.timeIntervalSince(target2Min)) })

            return HeartRateRecoveryMetric(
                baselineBPM: baselineBPM,
                oneMinuteBPM: oneMinSample?.value,
                twoMinuteBPM: twoMinSample?.value,
                workoutEndDate: workoutEnd
            )
        }

        return nil
    }

    // MARK: - 5. Steps & NEAT (Non-Exercise Activity Thermogenesis)

    /// Computes daily steps, non-workout steps, non-exercise active energy (excluding unioned workout intervals),
    /// basal energy, flights climbed, `.appleStandTime`, and non-workout hourly movement consistency.
    ///
    /// - Period scoping:
    ///   - When `period` is nil, scopes to the single calendar day of `asOf` (or the latest sample's calendar day when `asOf` is nil),
    ///     never summing 60-day history into a single day's step/energy count.
    ///   - Interval samples crossing the day/period boundary or a workout boundary are proportionally clipped.
    public func neatSnapshot(
        from points: [HealthDataPoint],
        period: DateInterval? = nil,
        workouts: [HealthWorkoutRecord] = [],
        strengthWorkouts: [StrengthWorkoutSummaryInput] = [],
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> NEATActivitySnapshot {
        let neatTypes: Set<HealthSampleType> = [
            .stepCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .flightsClimbed,
            .appleStandTime
        ]
        let validPoints = points.filter { point in
            guard neatTypes.contains(point.sampleType),
                  point.value.isFinite,
                  point.value >= 0,
                  point.endDate >= point.startDate else { return false }
            if let asOf {
                return point.startDate <= asOf
            }
            return true
        }

        let targetPeriod: DateInterval
        if let period {
            if let asOf, period.end > asOf, asOf > period.start {
                targetPeriod = DateInterval(start: period.start, end: asOf)
            } else {
                targetPeriod = period
            }
        } else {
            let referenceDate = asOf ?? validPoints.map(\.startDate).max() ?? Date()
            let dayStart = calendar.startOfDay(for: referenceDate)
            let fullDayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            let effectiveEnd = asOf.map { min(fullDayEnd, max(dayStart.addingTimeInterval(1), $0)) } ?? fullDayEnd
            targetPeriod = DateInterval(start: dayStart, end: max(dayStart.addingTimeInterval(1), effectiveEnd))
        }

        let unionedWorkouts = buildUnionedWorkoutWindows(
            workouts: workouts,
            strengthWorkouts: strengthWorkouts,
            clippedTo: targetPeriod
        )

        var dailySteps = 0.0
        var nonWorkoutSteps = 0.0
        var totalActiveEnergy = 0.0
        var nonExerciseActiveEnergy = 0.0
        var basalEnergy = 0.0
        var flightsClimbed = 0.0
        var standDurationSeconds = 0.0
        var hourlyNonWorkoutSteps: [Int: Double] = [:]
        var hourlyNonWorkoutEnergy: [Int: Double] = [:]
        var hourlyStandSeconds: [Int: Double] = [:]
        var matchedBounds: [Date] = []

        for point in validPoints {
            guard let clippedValue = proportionalValue(of: point, within: targetPeriod), clippedValue > 0 else {
                continue
            }
            let overlapStart = max(point.startDate, targetPeriod.start)
            let overlapEnd = min(max(point.startDate, point.endDate), targetPeriod.end)
            matchedBounds.append(overlapStart)
            matchedBounds.append(overlapEnd)

            let nonWorkoutValue = proportionalValueExcluding(
                point: point,
                within: targetPeriod,
                excluding: unionedWorkouts
            )

            switch point.sampleType {
            case .stepCount:
                dailySteps += clippedValue
                nonWorkoutSteps += nonWorkoutValue
                distributeByHour(
                    point: point,
                    within: targetPeriod,
                    excluding: unionedWorkouts,
                    calendar: calendar,
                    into: &hourlyNonWorkoutSteps
                )
            case .activeEnergyBurned:
                totalActiveEnergy += clippedValue
                nonExerciseActiveEnergy += nonWorkoutValue
                distributeByHour(
                    point: point,
                    within: targetPeriod,
                    excluding: unionedWorkouts,
                    calendar: calendar,
                    into: &hourlyNonWorkoutEnergy
                )
            case .basalEnergyBurned:
                basalEnergy += clippedValue
            case .flightsClimbed:
                flightsClimbed += clippedValue
            case .appleStandTime:
                let seconds = standSampleSeconds(point: point, rawValue: nonWorkoutValue)
                standDurationSeconds += seconds
                let scale = nonWorkoutValue > 0 ? seconds / nonWorkoutValue : 1.0
                var rawHourMap: [Int: Double] = [:]
                distributeByHour(
                    point: point,
                    within: targetPeriod,
                    excluding: unionedWorkouts,
                    calendar: calendar,
                    into: &rawHourMap
                )
                for (hour, val) in rawHourMap {
                    hourlyStandSeconds[hour, default: 0] += val * scale
                }
            default:
                break
            }
        }

        // Determine active non-workout hours across the 24h day:
        // An hour counts as an active non-workout movement hour if it has non-workout steps > 0,
        // non-workout stand time > 0, or non-workout active energy >= 5 kcal.
        var activeHours = Set<Int>()
        for (hour, steps) in hourlyNonWorkoutSteps where steps > 0 {
            activeHours.insert(hour)
        }
        for (hour, standSec) in hourlyStandSeconds where standSec > 0 {
            activeHours.insert(hour)
        }
        for (hour, kcal) in hourlyNonWorkoutEnergy where kcal >= 5 {
            activeHours.insert(hour)
        }

        let hourlyDistribution: [Int: Double] = !hourlyNonWorkoutSteps.isEmpty
            ? hourlyNonWorkoutSteps
            : (!hourlyStandSeconds.isEmpty ? hourlyStandSeconds : hourlyNonWorkoutEnergy)

        // Normalize movement consistency against waking / non-workout opportunity hours (default 16 waking hours minus workout hours, bounded to [1, 16]).
        let workoutHours = unionedWorkouts.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 3_600.0
        let denominatorHours = max(1.0, min(16.0, 16.0 - workoutHours))
        let hourConsistency = Double(activeHours.count) / denominatorHours
        // Stand time goal benchmark: 12 stand hours (~720 minutes or 12 stood hours; 180s+ per hour)
        let standGoalSeconds = denominatorHours * 300.0 // 5 min/hour of standing movement across waking non-workout hours
        let standRatio = standDurationSeconds > 0 ? min(standDurationSeconds / max(standGoalSeconds, 1), 1.0) : 0.0
        let combinedConsistency: Double
        if standDurationSeconds > 0 && !activeHours.isEmpty {
            combinedConsistency = min(1.0, max(hourConsistency, 0.7 * hourConsistency + 0.3 * standRatio))
        } else {
            combinedConsistency = min(1.0, max(hourConsistency, standRatio))
        }

        let workoutExcludedEnergy = max(0, totalActiveEnergy - nonExerciseActiveEnergy)

        return NEATActivitySnapshot(
            dailySteps: dailySteps,
            nonExerciseActiveEnergy: nonExerciseActiveEnergy,
            basalEnergy: basalEnergy,
            hourlyMovementConsistency: combinedConsistency,
            flightsClimbed: flightsClimbed,
            periodStart: matchedBounds.min() ?? (validPoints.isEmpty ? nil : targetPeriod.start),
            periodEnd: matchedBounds.max() ?? (validPoints.isEmpty ? nil : targetPeriod.end),
            nonWorkoutSteps: nonWorkoutSteps,
            workoutActiveEnergyExcluded: workoutExcludedEnergy,
            standDuration: standDurationSeconds,
            activeNonWorkoutHourCount: activeHours.count,
            hourlyNonWorkoutDistribution: hourlyDistribution
        )
    }

    // MARK: - 8. Aggregate Physiological Snapshot (Graceful Partial-Data Degradation)

    /// Builds the aggregate `PhysiologicalSnapshot` across all 5 domains (`heart`, `sleep`, `neat`, `aerobic`, `trainingLoad`).
    ///
    /// - Graceful degradation: returns a usable `PhysiologicalSnapshot` whenever at least one domain has valid observations
    ///   (e.g., Steps-only, Workouts-only, or missing Sleep/HRV), recording active domains in `availableDomains` and keeping
    ///   missing domains explicitly marked `isAvailable == false` rather than returning `nil` or fabricating healthy values.
    /// - Returns `nil` only when all domains are completely empty (no valid observations `<= generatedAt`).
    public func physiologicalSnapshot(
        from points: [HealthDataPoint],
        workouts: [HealthWorkoutRecord] = [],
        strengthWorkouts: [StrengthWorkoutSummaryInput] = [],
        maximumHeartRate: Double? = nil,
        userAgeYears: Int? = nil,
        targetSleepDuration: TimeInterval = 8 * 60 * 60,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> PhysiologicalSnapshot? {
        let resting = restingHeartRateSummary(from: points, asOf: generatedAt, calendar: calendar)
            ?? RestingHeartRateSummary(averageBPM: 0, sampleCount: 0)
        let hrv = hrvCorridor(from: points, asOf: generatedAt, calendar: calendar)
            ?? HRVCorridorSnapshot(baselineMilliseconds: 0, lowerBoundMilliseconds: 0, upperBoundMilliseconds: 0, sampleCount: 0)

        let zones = heartRateZones(
            from: points,
            maximumHeartRate: maximumHeartRate,
            userAgeYears: userAgeYears,
            asOf: generatedAt
        )
        let recovery = heartRateRecovery(
            from: points,
            workouts: workouts,
            strengthWorkouts: strengthWorkouts,
            asOf: generatedAt
        ) ?? HeartRateRecoveryMetric(baselineBPM: 0, oneMinuteBPM: nil, twoMinuteBPM: nil)

        let heartDomain = HeartDomainSnapshot(
            restingHeartRate: resting,
            hrvCorridor: hrv,
            zoneDistribution: zones,
            recovery: recovery
        )

        let sleepAnalyzer = SleepArchitectureAnalyzer()
        let sleepDomain = sleepAnalyzer.domainSnapshot(
            points: points,
            targetSleepDuration: targetSleepDuration,
            asOf: generatedAt,
            calendar: calendar
        )

        let neatDomain = neatSnapshot(
            from: points,
            period: nil,
            workouts: workouts,
            strengthWorkouts: strengthWorkouts,
            asOf: generatedAt,
            calendar: calendar
        )

        let aerobicDomain = AerobicEfficiencyCalculator().calculate(
            from: points,
            workouts: workouts,
            asOf: generatedAt
        ) ?? AerobicEfficiencySnapshot()

        let effectiveRHR = resting.isAvailable ? (resting.baselineBPM ?? resting.averageBPM) : 60.0
        let effectiveMaxHR = zones.resolvedMaximumHeartRateBPM ?? resolveMaximumHeartRate(
            userMaximumHeartRate: maximumHeartRate,
            userAgeYears: userAgeYears,
            points: points,
            asOf: generatedAt
        )
        let trainingLoadDomain = TrainingLoadCalculator().calculate(
            workouts: workouts,
            strengthWorkouts: strengthWorkouts,
            asOf: generatedAt,
            restingHeartRate: effectiveRHR,
            maximumHeartRate: effectiveMaxHR,
            calendar: calendar
        )

        let snapshot = PhysiologicalSnapshot(
            heart: heartDomain,
            sleep: sleepDomain,
            neat: neatDomain,
            aerobic: aerobicDomain,
            trainingLoad: trainingLoadDomain,
            generatedAt: generatedAt
        )

        guard !snapshot.availableDomains.isEmpty else {
            return nil
        }
        return snapshot
    }

    // MARK: - Private Helpers

    private func dailyMeans(
        for points: [HealthDataPoint],
        calendar: Calendar
    ) -> [(day: Date, mean: Double)] {
        var buckets: [Date: [Double]] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.startDate)
            buckets[day, default: []].append(point.value)
        }
        return buckets.keys.sorted().compactMap { day in
            guard let values = buckets[day], !values.isEmpty else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            return (day: day, mean: mean)
        }
    }

    private func classifyZone(bpm: Double, maximumHeartRate: Double) -> HeartRateZone {
        let fraction = bpm / maximumHeartRate
        switch fraction {
        case ..<0.60: return .zone1
        case ..<0.70: return .zone2
        case ..<0.80: return .zone3
        case ..<0.90: return .zone4
        default: return .zone5
        }
    }

    private func buildUnionedWorkoutWindows(
        workouts: [HealthWorkoutRecord],
        strengthWorkouts: [StrengthWorkoutSummaryInput],
        clippedTo period: DateInterval
    ) -> [(start: Date, end: Date)] {
        var rawWindows: [(start: Date, end: Date)] = []
        for workout in workouts {
            let end = workout.endDate > workout.startDate
                ? workout.endDate
                : workout.startDate.addingTimeInterval(max(0, workout.duration))
            let start = max(workout.startDate, period.start)
            let clippedEnd = min(end, period.end)
            if clippedEnd > start {
                rawWindows.append((start: start, end: clippedEnd))
            }
        }
        for strength in strengthWorkouts {
            let start = max(strength.startDate, period.start)
            let clippedEnd = min(strength.endDate, period.end)
            if clippedEnd > start {
                rawWindows.append((start: start, end: clippedEnd))
            }
        }
        return SleepArchitectureAnalyzer.mergeIntervals(rawWindows)
    }

    private func proportionalValue(of point: HealthDataPoint, within period: DateInterval) -> Double? {
        guard point.value.isFinite, point.value >= 0 else { return nil }
        let sampleDuration = point.endDate.timeIntervalSince(point.startDate)
        if sampleDuration <= 0 {
            guard point.startDate >= period.start && point.startDate <= period.end else { return nil }
            return point.value
        }
        let overlapStart = max(point.startDate, period.start)
        let overlapEnd = min(point.endDate, period.end)
        guard overlapEnd > overlapStart else { return nil }
        let ratio = overlapEnd.timeIntervalSince(overlapStart) / sampleDuration
        return point.value * min(max(ratio, 0), 1)
    }

    private func proportionalValueExcluding(
        point: HealthDataPoint,
        within period: DateInterval,
        excluding workoutWindows: [(start: Date, end: Date)]
    ) -> Double {
        guard point.value.isFinite, point.value > 0 else { return 0 }
        let sampleDuration = point.endDate.timeIntervalSince(point.startDate)
        if sampleDuration <= 0 {
            guard point.startDate >= period.start && point.startDate <= period.end else { return 0 }
            let insideWorkout = workoutWindows.contains { point.startDate >= $0.start && point.startDate < $0.end }
            return insideWorkout ? 0 : point.value
        }
        let overlapStart = max(point.startDate, period.start)
        let overlapEnd = min(point.endDate, period.end)
        guard overlapEnd > overlapStart else { return 0 }
        let remaining = SleepArchitectureAnalyzer.subtractIntervals(
            from: [(start: overlapStart, end: overlapEnd)],
            subtract: workoutWindows
        )
        let nonWorkoutDuration = SleepArchitectureAnalyzer.totalDuration(of: remaining)
        let ratio = nonWorkoutDuration / sampleDuration
        return point.value * min(max(ratio, 0), 1)
    }

    private func distributeByHour(
        point: HealthDataPoint,
        within period: DateInterval,
        excluding workoutWindows: [(start: Date, end: Date)],
        calendar: Calendar,
        into map: inout [Int: Double]
    ) {
        guard point.value.isFinite, point.value > 0 else { return }
        let sampleDuration = point.endDate.timeIntervalSince(point.startDate)
        if sampleDuration <= 0 {
            guard point.startDate >= period.start && point.startDate <= period.end else { return }
            let insideWorkout = workoutWindows.contains { point.startDate >= $0.start && point.startDate < $0.end }
            guard !insideWorkout else { return }
            let hour = calendar.component(.hour, from: point.startDate)
            map[hour, default: 0] += point.value
            return
        }

        let overlapStart = max(point.startDate, period.start)
        let overlapEnd = min(point.endDate, period.end)
        guard overlapEnd > overlapStart else { return }
        let nonWorkoutSegments = SleepArchitectureAnalyzer.subtractIntervals(
            from: [(start: overlapStart, end: overlapEnd)],
            subtract: workoutWindows
        )

        for segment in nonWorkoutSegments {
            var cursor = segment.start
            while cursor < segment.end {
                let hour = calendar.component(.hour, from: cursor)
                let nextHourBoundary: Date = {
                    if let startOfHour = calendar.dateInterval(of: .hour, for: cursor)?.end, startOfHour > cursor {
                        return startOfHour
                    }
                    return cursor.addingTimeInterval(3_600)
                }()
                let sliceEnd = min(segment.end, nextHourBoundary)
                let sliceDuration = max(0, sliceEnd.timeIntervalSince(cursor))
                if sliceDuration > 0 {
                    map[hour, default: 0] += point.value * (sliceDuration / sampleDuration)
                }
                cursor = sliceEnd
            }
        }
    }

    private func standSampleSeconds(point: HealthDataPoint, rawValue: Double) -> TimeInterval {
        let lowerUnit = point.unit.lowercased()
        if lowerUnit == "min" || lowerUnit == "mins" || lowerUnit == "minute" || lowerUnit == "minutes" {
            return rawValue * 60.0
        }
        if lowerUnit == "hr" || lowerUnit == "hour" || lowerUnit == "hours" {
            return rawValue * 3_600.0
        }
        return rawValue
    }
}
