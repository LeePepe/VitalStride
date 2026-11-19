import Foundation
import VitalModels

public struct SleepArchitectureAnalyzer: Sendable {
    public static let defaultNoonCutoffHour: Int = 18

    public init() {}

    /// Computes canonical night anchor date for a sleep sample start timestamp.
    /// Samples starting before `cutoffHour` (default 18:00 local time) belong to the previous calendar day's night,
    /// keeping cross-midnight sleep and DST transitions grouped into a single sleep night.
    public static func nightAnchorDate(
        for date: Date,
        calendar: Calendar = .current,
        cutoffHour: Int = defaultNoonCutoffHour
    ) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour < cutoffHour,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: date) {
            return calendar.startOfDay(for: previousDay)
        }
        return calendar.startOfDay(for: date)
    }

    /// Groups `.sleepAnalysis` samples into per-night `SleepArchitectureSnapshot` values,
    /// sorted ascending by `nightDate`.
    ///
    /// - Overlapping multi-source intervals are deduplicated with stage precedence:
    ///   `asleepDeep > asleepREM > asleepCore > asleepUnspecified`, while `awake` is unioned and subtracted from asleep stages
    ///   (or vice-versa: asleep stages take precedence over `.inBed`, and `awake` is subtracted from asleep stages when explicitly marked awake).
    ///   Specifically, within each night:
    ///   1. `awake` intervals are merged.
    ///   2. `deep` intervals are merged and have `awake` subtracted.
    ///   3. `rem` intervals are merged and have `awake + deep` subtracted.
    ///   4. `core` intervals are merged and have `awake + deep + rem` subtracted.
    ///   5. `unspecified` intervals are merged and have `awake + deep + rem + core` subtracted, then merged into `core`.
    ///   6. `inBed` intervals are unioned with all asleep + awake intervals to determine occupied in-bed time.
    /// - Input order is irrelevant; future samples (`startDate > asOf`) and invalid intervals (`endDate <= startDate`) are excluded.
    public func analyzeByNight(
        points: [HealthDataPoint],
        targetSleepDuration: TimeInterval = 8 * 60 * 60,
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> [SleepArchitectureSnapshot] {
        let validPoints = filteredSleepPoints(points: points, asOf: asOf)
        guard !validPoints.isEmpty else { return [] }

        var nightGroups: [Date: [HealthDataPoint]] = [:]
        for point in validPoints {
            let anchor = Self.nightAnchorDate(for: point.startDate, calendar: calendar)
            nightGroups[anchor, default: []].append(point)
        }

        return nightGroups.keys.sorted().compactMap { nightDate in
            guard let group = nightGroups[nightDate] else { return nil }
            return aggregateNight(
                nightDate: nightDate,
                points: group,
                targetSleepDuration: targetSleepDuration
            )
        }
    }

    /// Returns the latest night's `SleepArchitectureSnapshot` from `.sleepAnalysis` samples,
    /// rather than summing multi-night history into a single mega-night.
    public func analyze(
        points: [HealthDataPoint],
        targetSleepDuration: TimeInterval = 8 * 60 * 60,
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> SleepArchitectureSnapshot? {
        analyzeByNight(
            points: points,
            targetSleepDuration: targetSleepDuration,
            asOf: asOf,
            calendar: calendar
        ).last
    }

    /// Computes trailing 7-day and 14-day sleep debt from per-night snapshots.
    ///
    /// - When `nights` have `nightDate` populated (or `asOf` is provided), evaluates the trailing 7 and 14 calendar nights
    ///   anchored to the latest night (`<= asOf` when specified).
    /// - Personal baseline is the average `totalSleepDuration` of observed nights (up to 14 nights), or `targetSleepDuration` when specified as reference.
    ///   Each observed night's deficit is `max(0, effectiveReference - night.totalSleepDuration)`, where `effectiveReference` is
    ///   `targetSleepDuration > 0 ? targetSleepDuration : baselineSleepDuration`.
    /// - Missing nights in the 7-day / 14-day calendar window are explicitly reported in `missingNightCount7d` / `missingNightCount14d`
    ///   and when some nights are observed, missing nights are NOT fabricated as zero-debt surplus; when 0 nights are observed,
    ///   `isAvailable` is `false` and `missingNightCount7d == 7`, `missingNightCount14d == 14`.
    public func debtSummary(
        nights: [SleepArchitectureSnapshot],
        targetSleepDuration: TimeInterval,
        asOf: Date? = nil,
        calendar: Calendar = .current,
        usePersonalBaselineWhenHigher: Bool = false
    ) -> SleepDebtSummary {
        let sanitizedTarget = targetSleepDuration.isFinite ? max(0, targetSleepDuration) : 8 * 3_600
        let validNights = nights.filter { $0.isAvailable }
        guard !validNights.isEmpty else {
            return SleepDebtSummary(
                sevenDayDebt: 0,
                fourteenDayDebt: 0,
                baselineSleepDuration: 0,
                targetSleepDuration: sanitizedTarget,
                observedNightCount7d: 0,
                missingNightCount7d: 7,
                observedNightCount14d: 0,
                missingNightCount14d: 14,
                isAvailable: false
            )
        }

        // Check if nights carry calendar dates (`nightDate` or `periodStart`).
        let datedNights: [(anchor: Date, snapshot: SleepArchitectureSnapshot)] = validNights.compactMap { night in
            if let anchor = night.nightDate {
                return (calendar.startOfDay(for: anchor), night)
            }
            if let start = night.periodStart {
                return (Self.nightAnchorDate(for: start, calendar: calendar), night)
            }
            return nil
        }

        if datedNights.count == validNights.count {
            let cutoffAnchor: Date? = asOf.map { ref in
                // Latest completed night anchor relative to asOf
                let refStartOfDay = calendar.startOfDay(for: ref)
                return refStartOfDay
            }
            let filteredDated = datedNights.filter { entry in
                guard let cutoffAnchor else { return true }
                return entry.anchor <= cutoffAnchor
            }
            guard !filteredDated.isEmpty else {
                return SleepDebtSummary(
                    sevenDayDebt: 0,
                    fourteenDayDebt: 0,
                    baselineSleepDuration: 0,
                    targetSleepDuration: sanitizedTarget,
                    observedNightCount7d: 0,
                    missingNightCount7d: 7,
                    observedNightCount14d: 0,
                    missingNightCount14d: 14,
                    isAvailable: false
                )
            }

            // Deduplicate by night anchor (if caller passed multiple snapshots for same night, keep latest/longest)
            var byNight: [Date: SleepArchitectureSnapshot] = [:]
            for (anchor, snap) in filteredDated {
                if let existing = byNight[anchor] {
                    if snap.totalSleepDuration >= existing.totalSleepDuration {
                        byNight[anchor] = snap
                    }
                } else {
                    byNight[anchor] = snap
                }
            }

            let referenceAnchor = cutoffAnchor.map { min($0, byNight.keys.max() ?? $0) } ?? (byNight.keys.max() ?? Date())
            let start7d = calendar.date(byAdding: .day, value: -6, to: referenceAnchor) ?? referenceAnchor
            let start14d = calendar.date(byAdding: .day, value: -13, to: referenceAnchor) ?? referenceAnchor

            let nights7d = byNight.filter { $0.key >= start7d && $0.key <= referenceAnchor }.map(\.value)
            let nights14d = byNight.filter { $0.key >= start14d && $0.key <= referenceAnchor }.map(\.value)

            let baselinePool = nights14d.isEmpty ? Array(byNight.values) : nights14d
            let baseline = baselinePool.reduce(0.0) { $0 + $1.totalSleepDuration } / Double(baselinePool.count)
            let effectiveTarget = sanitizedTarget > 0
                ? (usePersonalBaselineWhenHigher ? max(sanitizedTarget, baseline) : sanitizedTarget)
                : baseline

            let observed7 = min(nights7d.count, 7)
            let missing7 = max(0, 7 - observed7)
            let observed14 = min(nights14d.count, 14)
            let missing14 = max(0, 14 - observed14)

            let sevenDebt = nights7d.reduce(0.0) { $0 + max(0, effectiveTarget - $1.totalSleepDuration) }
            let fourteenDebt = nights14d.reduce(0.0) { $0 + max(0, effectiveTarget - $1.totalSleepDuration) }

            return SleepDebtSummary(
                sevenDayDebt: sevenDebt,
                fourteenDayDebt: fourteenDebt,
                baselineSleepDuration: baseline,
                targetSleepDuration: effectiveTarget,
                observedNightCount7d: observed7,
                missingNightCount7d: missing7,
                observedNightCount14d: observed14,
                missingNightCount14d: missing14,
                isAvailable: observed14 > 0
            )
        } else {
            // Undated snapshots fallback (preserves legacy caller behavior where an array of Synthetic Night snapshots is passed without dates)
            let suffix7 = Array(validNights.suffix(7))
            let suffix14 = Array(validNights.suffix(14))
            let baseline = suffix14.reduce(0.0) { $0 + $1.totalSleepDuration } / Double(suffix14.count)
            let effectiveTarget = sanitizedTarget > 0
                ? (usePersonalBaselineWhenHigher ? max(sanitizedTarget, baseline) : sanitizedTarget)
                : baseline
            let sevenDebt = suffix7.reduce(0.0) { $0 + max(0, effectiveTarget - $1.totalSleepDuration) }
            let fourteenDebt = suffix14.reduce(0.0) { $0 + max(0, effectiveTarget - $1.totalSleepDuration) }
            return SleepDebtSummary(
                sevenDayDebt: sevenDebt,
                fourteenDayDebt: fourteenDebt,
                baselineSleepDuration: baseline,
                targetSleepDuration: effectiveTarget,
                observedNightCount7d: suffix7.count,
                missingNightCount7d: max(0, 7 - suffix7.count),
                observedNightCount14d: suffix14.count,
                missingNightCount14d: max(0, 14 - suffix14.count),
                isAvailable: true
            )
        }
    }

    public func debtSummary(
        points: [HealthDataPoint],
        targetSleepDuration: TimeInterval,
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> SleepDebtSummary? {
        let nights = analyzeByNight(
            points: points,
            targetSleepDuration: targetSleepDuration,
            asOf: asOf,
            calendar: calendar
        )
        guard !nights.isEmpty else { return nil }
        return debtSummary(
            nights: nights,
            targetSleepDuration: targetSleepDuration,
            asOf: asOf,
            calendar: calendar
        )
    }

    public func domainSnapshot(
        points: [HealthDataPoint],
        targetSleepDuration: TimeInterval = 8 * 60 * 60,
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> SleepDomainSnapshot {
        let sanitizedTarget = targetSleepDuration.isFinite ? max(0, targetSleepDuration) : 8 * 3_600
        let nights = analyzeByNight(
            points: points,
            targetSleepDuration: sanitizedTarget,
            asOf: asOf,
            calendar: calendar
        )
        guard let latestNight = nights.last else {
            return SleepDomainSnapshot(
                architecture: SleepArchitectureSnapshot(),
                debt: SleepDebtSummary(
                    sevenDayDebt: 0,
                    fourteenDayDebt: 0,
                    baselineSleepDuration: 0,
                    targetSleepDuration: sanitizedTarget,
                    observedNightCount7d: 0,
                    missingNightCount7d: 7,
                    observedNightCount14d: 0,
                    missingNightCount14d: 14,
                    isAvailable: false
                ),
                recentNights: []
            )
        }
        let debt = debtSummary(
            nights: nights,
            targetSleepDuration: sanitizedTarget,
            asOf: asOf,
            calendar: calendar
        )
        return SleepDomainSnapshot(
            architecture: latestNight,
            debt: debt,
            recentNights: Array(nights.suffix(14))
        )
    }

    // MARK: - Private Interval Helpers

    private func filteredSleepPoints(points: [HealthDataPoint], asOf: Date?) -> [HealthDataPoint] {
        points.compactMap { point -> HealthDataPoint? in
            guard point.sampleType == .sleepAnalysis else { return nil }
            guard point.value.isFinite else { return nil }
            let clippedEnd: Date
            if let asOf {
                guard point.startDate < asOf else { return nil }
                clippedEnd = min(point.endDate, asOf)
            } else {
                clippedEnd = point.endDate
            }
            guard clippedEnd > point.startDate else { return nil }
            if clippedEnd == point.endDate {
                return point
            }
            return HealthDataPoint(
                id: point.id,
                sampleType: point.sampleType,
                startDate: point.startDate,
                endDate: clippedEnd,
                value: point.value,
                unit: point.unit,
                sleepStage: point.sleepStage,
                sourceName: point.sourceName
            )
        }
        .sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.endDate < rhs.endDate
        }
    }

    private func aggregateNight(
        nightDate: Date,
        points: [HealthDataPoint],
        targetSleepDuration: TimeInterval
    ) -> SleepArchitectureSnapshot? {
        func rawIntervals(matching predicate: (SleepStage?) -> Bool) -> [(start: Date, end: Date)] {
            points.compactMap { point in
                guard predicate(point.sleepStage), point.endDate > point.startDate else { return nil }
                return (start: point.startDate, end: point.endDate)
            }
        }

        let deepMerged = Self.mergeIntervals(rawIntervals { $0 == .asleepDeep })
        let remMerged = Self.subtractIntervals(
            from: Self.mergeIntervals(rawIntervals { $0 == .asleepREM }),
            subtract: deepMerged
        )
        let coreOnly = Self.subtractIntervals(
            from: Self.mergeIntervals(rawIntervals { $0 == .asleepCore }),
            subtract: Self.mergeIntervals(deepMerged + remMerged)
        )
        let unspecifiedRemaining = Self.subtractIntervals(
            from: Self.mergeIntervals(rawIntervals { $0 == .asleepUnspecified }),
            subtract: Self.mergeIntervals(deepMerged + remMerged + coreOnly)
        )
        let coreMerged = Self.mergeIntervals(coreOnly + unspecifiedRemaining)
        let allSleepMerged = Self.mergeIntervals(deepMerged + remMerged + coreMerged)
        let awakeMerged = Self.subtractIntervals(
            from: Self.mergeIntervals(rawIntervals { $0 == .awake }),
            subtract: allSleepMerged
        )

        let inBedRaw = rawIntervals { $0 == .inBed || $0 == nil }

        let deepDuration = Self.totalDuration(of: deepMerged)
        let remDuration = Self.totalDuration(of: remMerged)
        let coreDuration = Self.totalDuration(of: coreMerged)
        let awakeDuration = Self.totalDuration(of: awakeMerged)
        let totalSleep = deepDuration + remDuration + coreDuration
        // Occupied bed time is the union of asleep + awake stages, or the explicit inBed union if it encloses the whole night.
        let stageOccupied = totalSleep + awakeDuration
        let rawInBedUnion = Self.totalDuration(of: Self.mergeIntervals(inBedRaw))
        let unionedInBed = rawInBedUnion >= stageOccupied ? rawInBedUnion : stageOccupied

        guard unionedInBed > 0 else { return nil }

        let efficiency: Double
        if unionedInBed > 0 {
            efficiency = totalSleep / unionedInBed
        } else if targetSleepDuration > 0 {
            efficiency = totalSleep / targetSleepDuration
        } else {
            efficiency = 0
        }

        return SleepArchitectureSnapshot(
            deepDuration: deepDuration,
            remDuration: remDuration,
            coreDuration: coreDuration,
            awakeDuration: awakeDuration,
            totalSleepDuration: totalSleep,
            sleepEfficiency: efficiency,
            periodStart: points.map(\.startDate).min(),
            periodEnd: points.map(\.endDate).max(),
            inBedDuration: unionedInBed,
            nightDate: nightDate
        )
    }

    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        let valid = intervals.filter { $0.end > $0.start }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        guard var current = valid.first else { return [] }
        var merged: [(start: Date, end: Date)] = []
        for next in valid.dropFirst() {
            if next.start <= current.end {
                current.end = max(current.end, next.end)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    static func subtractIntervals(
        from base: [(start: Date, end: Date)],
        subtract: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        let mergedBase = mergeIntervals(base)
        let mergedSub = mergeIntervals(subtract)
        guard !mergedBase.isEmpty, !mergedSub.isEmpty else { return mergedBase }

        var result: [(start: Date, end: Date)] = []
        for segment in mergedBase {
            var cursor = segment.start
            for sub in mergedSub {
                if sub.end <= cursor { continue }
                if sub.start >= segment.end { break }
                if sub.start > cursor {
                    result.append((start: cursor, end: sub.start))
                }
                cursor = max(cursor, sub.end)
                if cursor >= segment.end { break }
            }
            if cursor < segment.end {
                result.append((start: cursor, end: segment.end))
            }
        }
        return result
    }

    static func totalDuration(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        intervals.reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) }
    }
}
