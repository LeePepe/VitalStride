import Foundation

private func clampNonNegativeFinite(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return max(0, value)
}

private func clampUnitFinite(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), 1)
}

private func clampFinite(_ value: Double, min lower: Double, max upper: Double) -> Double {
    guard value.isFinite else { return lower }
    return min(max(value, lower), upper)
}

private func sanitizeFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
}

private func sanitizePositiveFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
}

private func sanitizeNonNegativeFinite(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value >= 0 else { return nil }
    return value
}

public enum HeartRateZone: String, Codable, Sendable, Equatable, CaseIterable {
    case zone1
    case zone2
    case zone3
    case zone4
    case zone5
}

public struct RestingHeartRateSummary: Codable, Sendable, Equatable {
    public let averageBPM: Double
    public let currentBPM: Double?
    public let sevenDayAverageBPM: Double?
    public let baselineBPM: Double?
    public let minimumBPM: Double?
    public let maximumBPM: Double?
    public let sampleCount: Int
    public let baselineDayCount: Int
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        averageBPM: Double,
        minimumBPM: Double? = nil,
        maximumBPM: Double? = nil,
        sampleCount: Int = 0,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        currentBPM: Double? = nil,
        sevenDayAverageBPM: Double? = nil,
        baselineBPM: Double? = nil,
        baselineDayCount: Int = 0
    ) {
        let sanitizedAvg = clampNonNegativeFinite(averageBPM)
        let sanitizedCount = max(0, sampleCount)
        self.averageBPM = sanitizedAvg
        self.minimumBPM = sanitizePositiveFinite(minimumBPM)
        self.maximumBPM = sanitizePositiveFinite(maximumBPM)
        self.sampleCount = sanitizedCount
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        let resolvedCurrent = sanitizePositiveFinite(currentBPM) ?? (sanitizedCount > 0 && sanitizedAvg > 0 ? sanitizedAvg : nil)
        let resolvedBaseline = sanitizePositiveFinite(baselineBPM) ?? (sanitizedCount > 0 && sanitizedAvg > 0 ? sanitizedAvg : nil)
        self.currentBPM = resolvedCurrent
        self.sevenDayAverageBPM = sanitizePositiveFinite(sevenDayAverageBPM) ?? resolvedCurrent
        self.baselineBPM = resolvedBaseline
        self.baselineDayCount = max(0, baselineDayCount)
    }

    private enum CodingKeys: String, CodingKey {
        case averageBPM
        case currentBPM
        case sevenDayAverageBPM
        case baselineBPM
        case minimumBPM
        case maximumBPM
        case sampleCount
        case baselineDayCount
        case periodStart
        case periodEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let averageBPM = try container.decode(Double.self, forKey: .averageBPM)
        let minimumBPM = try container.decodeIfPresent(Double.self, forKey: .minimumBPM)
        let maximumBPM = try container.decodeIfPresent(Double.self, forKey: .maximumBPM)
        let sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        let periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
        let periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
        let currentBPM = try container.decodeIfPresent(Double.self, forKey: .currentBPM)
        let sevenDayAverageBPM = try container.decodeIfPresent(Double.self, forKey: .sevenDayAverageBPM)
        let baselineBPM = try container.decodeIfPresent(Double.self, forKey: .baselineBPM)
        let baselineDayCount = try container.decodeIfPresent(Int.self, forKey: .baselineDayCount) ?? 0
        self.init(
            averageBPM: averageBPM,
            minimumBPM: minimumBPM,
            maximumBPM: maximumBPM,
            sampleCount: sampleCount,
            periodStart: periodStart,
            periodEnd: periodEnd,
            currentBPM: currentBPM,
            sevenDayAverageBPM: sevenDayAverageBPM,
            baselineBPM: baselineBPM,
            baselineDayCount: baselineDayCount
        )
    }

    public var isAvailable: Bool { sampleCount > 0 && averageBPM > 0 }
    public var deltaFromBaselineBPM: Double? {
        guard let current = currentBPM ?? sevenDayAverageBPM,
              let baseline = baselineBPM else { return nil }
        return current - baseline
    }
    public var restingHeartRate: Double { averageBPM }
    public var average: Double { averageBPM }
    public var minimum: Double? { minimumBPM }
    public var maximum: Double? { maximumBPM }
}

public struct HRVCorridorSnapshot: Codable, Sendable, Equatable {
    public let baselineMilliseconds: Double
    public let lowerBoundMilliseconds: Double
    public let upperBoundMilliseconds: Double
    public let currentMilliseconds: Double?
    public let sevenDayAverageMilliseconds: Double?
    public let sampleCount: Int
    public let sevenDaySampleCount: Int
    public let baselineDayCount: Int
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        baselineMilliseconds: Double,
        lowerBoundMilliseconds: Double,
        upperBoundMilliseconds: Double,
        sampleCount: Int = 0,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        currentMilliseconds: Double? = nil,
        sevenDayAverageMilliseconds: Double? = nil,
        sevenDaySampleCount: Int = 0,
        baselineDayCount: Int = 0
    ) {
        let base = clampNonNegativeFinite(baselineMilliseconds)
        let lower = clampNonNegativeFinite(lowerBoundMilliseconds)
        let upper = max(lower, clampNonNegativeFinite(upperBoundMilliseconds))
        let count = max(0, sampleCount)
        self.baselineMilliseconds = base
        self.lowerBoundMilliseconds = lower
        self.upperBoundMilliseconds = upper
        self.sampleCount = count
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        let resolvedCurrent = sanitizePositiveFinite(currentMilliseconds)
        let resolvedSevenDay = sanitizePositiveFinite(sevenDayAverageMilliseconds)
        if resolvedCurrent == nil && resolvedSevenDay == nil && count > 0 && base > 0 {
            self.currentMilliseconds = base
            self.sevenDayAverageMilliseconds = base
        } else {
            self.currentMilliseconds = resolvedCurrent
            self.sevenDayAverageMilliseconds = resolvedSevenDay ?? resolvedCurrent
        }
        self.sevenDaySampleCount = max(0, sevenDaySampleCount)
        self.baselineDayCount = max(0, baselineDayCount)
    }

    private enum CodingKeys: String, CodingKey {
        case baselineMilliseconds
        case lowerBoundMilliseconds
        case upperBoundMilliseconds
        case currentMilliseconds
        case sevenDayAverageMilliseconds
        case sampleCount
        case sevenDaySampleCount
        case baselineDayCount
        case periodStart
        case periodEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseline = try container.decode(Double.self, forKey: .baselineMilliseconds)
        let lower = try container.decode(Double.self, forKey: .lowerBoundMilliseconds)
        let upper = try container.decode(Double.self, forKey: .upperBoundMilliseconds)
        let sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        let periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
        let periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
        let current = try container.decodeIfPresent(Double.self, forKey: .currentMilliseconds)
        let sevenDay = try container.decodeIfPresent(Double.self, forKey: .sevenDayAverageMilliseconds)
        let sevenDayCount = try container.decodeIfPresent(Int.self, forKey: .sevenDaySampleCount) ?? 0
        let baselineDays = try container.decodeIfPresent(Int.self, forKey: .baselineDayCount) ?? 0
        self.init(
            baselineMilliseconds: baseline,
            lowerBoundMilliseconds: lower,
            upperBoundMilliseconds: upper,
            sampleCount: sampleCount,
            periodStart: periodStart,
            periodEnd: periodEnd,
            currentMilliseconds: current,
            sevenDayAverageMilliseconds: sevenDay,
            sevenDaySampleCount: sevenDayCount,
            baselineDayCount: baselineDays
        )
    }

    public var isAvailable: Bool {
        sampleCount > 0 && baselineMilliseconds > 0 && (currentMilliseconds != nil || sevenDayAverageMilliseconds != nil)
    }

    public var isWithinCorridor: Bool {
        guard sampleCount > 0, baselineMilliseconds > 0 else { return false }
        let corridor = lowerBoundMilliseconds...upperBoundMilliseconds
        if let currentMilliseconds, let sevenDayAverageMilliseconds {
            return corridor.contains(currentMilliseconds) && corridor.contains(sevenDayAverageMilliseconds)
        }
        if let observed = currentMilliseconds ?? sevenDayAverageMilliseconds {
            return corridor.contains(observed)
        }
        return false
    }

    public var baseline: Double { baselineMilliseconds }
    public var lowerBound: Double { lowerBoundMilliseconds }
    public var upperBound: Double { upperBoundMilliseconds }
}

public struct HeartRateZoneDistribution: Codable, Sendable, Equatable {
    public let durationsByZone: [HeartRateZone: TimeInterval]
    public let resolvedMaximumHeartRateBPM: Double?

    public init(durationsByZone: [HeartRateZone: TimeInterval] = [:], resolvedMaximumHeartRateBPM: Double? = nil) {
        self.durationsByZone = HeartRateZone.allCases.reduce(into: [:]) { result, zone in
            result[zone] = clampNonNegativeFinite(durationsByZone[zone] ?? 0)
        }
        self.resolvedMaximumHeartRateBPM = sanitizePositiveFinite(resolvedMaximumHeartRateBPM)
    }

    public init(
        zone1: TimeInterval,
        zone2: TimeInterval,
        zone3: TimeInterval,
        zone4: TimeInterval,
        zone5: TimeInterval,
        resolvedMaximumHeartRateBPM: Double? = nil
    ) {
        self.init(
            durationsByZone: [.zone1: zone1, .zone2: zone2, .zone3: zone3, .zone4: zone4, .zone5: zone5],
            resolvedMaximumHeartRateBPM: resolvedMaximumHeartRateBPM
        )
    }

    public init(
        zone1Duration: TimeInterval,
        zone2Duration: TimeInterval,
        zone3Duration: TimeInterval,
        zone4Duration: TimeInterval,
        zone5Duration: TimeInterval,
        resolvedMaximumHeartRateBPM: Double? = nil
    ) {
        self.init(
            zone1: zone1Duration,
            zone2: zone2Duration,
            zone3: zone3Duration,
            zone4: zone4Duration,
            zone5: zone5Duration,
            resolvedMaximumHeartRateBPM: resolvedMaximumHeartRateBPM
        )
    }

    private enum CodingKeys: String, CodingKey {
        case durationsByZone
        case resolvedMaximumHeartRateBPM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let durations = try container.decodeIfPresent([HeartRateZone: TimeInterval].self, forKey: .durationsByZone) ?? [:]
        let maxHR = try container.decodeIfPresent(Double.self, forKey: .resolvedMaximumHeartRateBPM)
        self.init(durationsByZone: durations, resolvedMaximumHeartRateBPM: maxHR)
    }

    public func duration(in zone: HeartRateZone) -> TimeInterval { durationsByZone[zone] ?? 0 }
    public var totalDuration: TimeInterval { durationsByZone.values.reduce(0, +) }
    public var zone1Duration: TimeInterval { duration(in: .zone1) }
    public var zone2Duration: TimeInterval { duration(in: .zone2) }
    public var zone3Duration: TimeInterval { duration(in: .zone3) }
    public var zone4Duration: TimeInterval { duration(in: .zone4) }
    public var zone5Duration: TimeInterval { duration(in: .zone5) }
}

public struct HeartRateRecoveryMetric: Codable, Sendable, Equatable {
    public let baselineBPM: Double
    public let oneMinuteBPM: Double?
    public let twoMinuteBPM: Double?
    public let workoutEndDate: Date?

    public init(
        baselineBPM: Double,
        oneMinuteBPM: Double? = nil,
        twoMinuteBPM: Double? = nil,
        workoutEndDate: Date? = nil
    ) {
        self.baselineBPM = clampNonNegativeFinite(baselineBPM)
        self.oneMinuteBPM = sanitizePositiveFinite(oneMinuteBPM)
        self.twoMinuteBPM = sanitizePositiveFinite(twoMinuteBPM)
        self.workoutEndDate = workoutEndDate
    }

    private enum CodingKeys: String, CodingKey {
        case baselineBPM
        case oneMinuteBPM
        case twoMinuteBPM
        case workoutEndDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseline = try container.decode(Double.self, forKey: .baselineBPM)
        let oneMin = try container.decodeIfPresent(Double.self, forKey: .oneMinuteBPM)
        let twoMin = try container.decodeIfPresent(Double.self, forKey: .twoMinuteBPM)
        let endDate = try container.decodeIfPresent(Date.self, forKey: .workoutEndDate)
        self.init(baselineBPM: baseline, oneMinuteBPM: oneMin, twoMinuteBPM: twoMin, workoutEndDate: endDate)
    }

    public var isAvailable: Bool {
        baselineBPM > 0 && (oneMinuteBPM != nil || twoMinuteBPM != nil)
    }
    public var oneMinuteDropBPM: Double? {
        guard baselineBPM > 0, let oneMinuteBPM else { return nil }
        return baselineBPM - oneMinuteBPM
    }
    public var twoMinuteDropBPM: Double? {
        guard baselineBPM > 0, let twoMinuteBPM else { return nil }
        return baselineBPM - twoMinuteBPM
    }
}

public struct SleepArchitectureSnapshot: Codable, Sendable, Equatable {
    public let deepDuration: TimeInterval
    public let remDuration: TimeInterval
    public let coreDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let inBedDuration: TimeInterval
    public let totalSleepDuration: TimeInterval
    public let sleepEfficiency: Double
    public let nightDate: Date?
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        deepDuration: TimeInterval = 0,
        remDuration: TimeInterval = 0,
        coreDuration: TimeInterval = 0,
        awakeDuration: TimeInterval = 0,
        totalSleepDuration: TimeInterval = 0,
        sleepEfficiency: Double = 0,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        inBedDuration: TimeInterval? = nil,
        nightDate: Date? = nil
    ) {
        let deep = clampNonNegativeFinite(deepDuration)
        let rem = clampNonNegativeFinite(remDuration)
        let core = clampNonNegativeFinite(coreDuration)
        let awake = clampNonNegativeFinite(awakeDuration)
        let total = clampNonNegativeFinite(totalSleepDuration)
        self.deepDuration = deep
        self.remDuration = rem
        self.coreDuration = core
        self.awakeDuration = awake
        self.totalSleepDuration = total
        self.inBedDuration = max(total + awake, clampNonNegativeFinite(inBedDuration ?? (total + awake)))
        self.sleepEfficiency = clampUnitFinite(sleepEfficiency)
        self.nightDate = nightDate
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    private enum CodingKeys: String, CodingKey {
        case deepDuration
        case remDuration
        case coreDuration
        case awakeDuration
        case inBedDuration
        case totalSleepDuration
        case sleepEfficiency
        case nightDate
        case periodStart
        case periodEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deep = try container.decodeIfPresent(TimeInterval.self, forKey: .deepDuration) ?? 0
        let rem = try container.decodeIfPresent(TimeInterval.self, forKey: .remDuration) ?? 0
        let core = try container.decodeIfPresent(TimeInterval.self, forKey: .coreDuration) ?? 0
        let awake = try container.decodeIfPresent(TimeInterval.self, forKey: .awakeDuration) ?? 0
        let total = try container.decodeIfPresent(TimeInterval.self, forKey: .totalSleepDuration) ?? (deep + rem + core)
        let efficiency = try container.decodeIfPresent(Double.self, forKey: .sleepEfficiency) ?? 0
        let periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
        let periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
        let inBed = try container.decodeIfPresent(TimeInterval.self, forKey: .inBedDuration)
        let nightDate = try container.decodeIfPresent(Date.self, forKey: .nightDate)
        self.init(
            deepDuration: deep,
            remDuration: rem,
            coreDuration: core,
            awakeDuration: awake,
            totalSleepDuration: total,
            sleepEfficiency: efficiency,
            periodStart: periodStart,
            periodEnd: periodEnd,
            inBedDuration: inBed,
            nightDate: nightDate
        )
    }

    public var isAvailable: Bool { totalSleepDuration > 0 || awakeDuration > 0 }
    public var totalInBedDuration: TimeInterval { max(inBedDuration, totalSleepDuration + awakeDuration) }
    public var deepSleepDuration: TimeInterval { deepDuration }
    public var remSleepDuration: TimeInterval { remDuration }
    public var coreSleepDuration: TimeInterval { coreDuration }
    public var efficiency: Double { sleepEfficiency }
}

public struct SleepDebtSummary: Codable, Sendable, Equatable {
    public let sevenDayDebt: TimeInterval
    public let fourteenDayDebt: TimeInterval
    public let baselineSleepDuration: TimeInterval
    public let targetSleepDuration: TimeInterval
    public let observedNightCount7d: Int
    public let missingNightCount7d: Int
    public let observedNightCount14d: Int
    public let missingNightCount14d: Int
    public let isAvailable: Bool

    public init(
        sevenDayDebt: TimeInterval,
        fourteenDayDebt: TimeInterval,
        baselineSleepDuration: TimeInterval,
        targetSleepDuration: TimeInterval,
        observedNightCount7d: Int = 7,
        missingNightCount7d: Int = 0,
        observedNightCount14d: Int = 14,
        missingNightCount14d: Int = 0,
        isAvailable: Bool = true
    ) {
        self.sevenDayDebt = clampNonNegativeFinite(sevenDayDebt)
        self.fourteenDayDebt = clampNonNegativeFinite(fourteenDayDebt)
        self.baselineSleepDuration = clampNonNegativeFinite(baselineSleepDuration)
        self.targetSleepDuration = clampNonNegativeFinite(targetSleepDuration)
        let obs7 = min(max(0, observedNightCount7d), 7)
        let obs14 = min(max(0, observedNightCount14d), 14)
        self.observedNightCount7d = obs7
        self.missingNightCount7d = min(max(0, missingNightCount7d), 7 - obs7)
        self.observedNightCount14d = obs14
        self.missingNightCount14d = min(max(0, missingNightCount14d), 14 - obs14)
        self.isAvailable = isAvailable && (obs7 > 0 || obs14 > 0 || self.baselineSleepDuration > 0 || self.sevenDayDebt > 0 || self.fourteenDayDebt > 0)
    }

    private enum CodingKeys: String, CodingKey {
        case sevenDayDebt
        case fourteenDayDebt
        case baselineSleepDuration
        case targetSleepDuration
        case observedNightCount7d
        case missingNightCount7d
        case observedNightCount14d
        case missingNightCount14d
        case isAvailable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sevenDayDebt = try container.decode(TimeInterval.self, forKey: .sevenDayDebt)
        let fourteenDayDebt = try container.decode(TimeInterval.self, forKey: .fourteenDayDebt)
        let baselineSleepDuration = try container.decode(TimeInterval.self, forKey: .baselineSleepDuration)
        let targetSleepDuration = try container.decode(TimeInterval.self, forKey: .targetSleepDuration)
        let obs7 = try container.decodeIfPresent(Int.self, forKey: .observedNightCount7d) ?? 7
        let miss7 = try container.decodeIfPresent(Int.self, forKey: .missingNightCount7d) ?? max(0, 7 - obs7)
        let obs14 = try container.decodeIfPresent(Int.self, forKey: .observedNightCount14d) ?? 14
        let miss14 = try container.decodeIfPresent(Int.self, forKey: .missingNightCount14d) ?? max(0, 14 - obs14)
        let available = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
        self.init(
            sevenDayDebt: sevenDayDebt,
            fourteenDayDebt: fourteenDayDebt,
            baselineSleepDuration: baselineSleepDuration,
            targetSleepDuration: targetSleepDuration,
            observedNightCount7d: obs7,
            missingNightCount7d: miss7,
            observedNightCount14d: obs14,
            missingNightCount14d: miss14,
            isAvailable: available
        )
    }

    public var sevenDayCoverageRatio: Double { Double(observedNightCount7d) / 7.0 }
    public var fourteenDayCoverageRatio: Double { Double(observedNightCount14d) / 14.0 }
}

public struct NEATActivitySnapshot: Codable, Sendable, Equatable {
    public let dailySteps: Double
    public let nonWorkoutSteps: Double
    public let nonExerciseActiveEnergy: Double
    public let workoutActiveEnergyExcluded: Double
    public let basalEnergy: Double
    public let standDuration: TimeInterval
    public let activeNonWorkoutHourCount: Int
    public let hourlyNonWorkoutDistribution: [Int: Double]
    public let hourlyMovementConsistency: Double
    public let flightsClimbed: Double
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        dailySteps: Double,
        nonExerciseActiveEnergy: Double,
        basalEnergy: Double,
        hourlyMovementConsistency: Double,
        flightsClimbed: Double,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        nonWorkoutSteps: Double? = nil,
        workoutActiveEnergyExcluded: Double = 0,
        standDuration: TimeInterval = 0,
        activeNonWorkoutHourCount: Int = 0,
        hourlyNonWorkoutDistribution: [Int: Double] = [:]
    ) {
        let clampedSteps = clampNonNegativeFinite(dailySteps)
        self.dailySteps = clampedSteps
        self.nonWorkoutSteps = min(clampedSteps, clampNonNegativeFinite(nonWorkoutSteps ?? clampedSteps))
        self.nonExerciseActiveEnergy = clampNonNegativeFinite(nonExerciseActiveEnergy)
        self.workoutActiveEnergyExcluded = clampNonNegativeFinite(workoutActiveEnergyExcluded)
        self.basalEnergy = clampNonNegativeFinite(basalEnergy)
        self.standDuration = clampNonNegativeFinite(standDuration)
        self.activeNonWorkoutHourCount = min(max(0, activeNonWorkoutHourCount), 24)
        var sanitizedHours: [Int: Double] = [:]
        for (hour, value) in hourlyNonWorkoutDistribution where (0..<24).contains(hour) {
            sanitizedHours[hour] = clampNonNegativeFinite(value)
        }
        self.hourlyNonWorkoutDistribution = sanitizedHours
        self.hourlyMovementConsistency = clampUnitFinite(hourlyMovementConsistency)
        self.flightsClimbed = clampNonNegativeFinite(flightsClimbed)
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    private enum CodingKeys: String, CodingKey {
        case dailySteps
        case nonWorkoutSteps
        case nonExerciseActiveEnergy
        case workoutActiveEnergyExcluded
        case basalEnergy
        case standDuration
        case activeNonWorkoutHourCount
        case hourlyNonWorkoutDistribution
        case hourlyMovementConsistency
        case flightsClimbed
        case periodStart
        case periodEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dailySteps = try container.decode(Double.self, forKey: .dailySteps)
        let nonExerciseActiveEnergy = try container.decode(Double.self, forKey: .nonExerciseActiveEnergy)
        let basalEnergy = try container.decode(Double.self, forKey: .basalEnergy)
        let consistency = try container.decode(Double.self, forKey: .hourlyMovementConsistency)
        let flights = try container.decode(Double.self, forKey: .flightsClimbed)
        let periodStart = try container.decodeIfPresent(Date.self, forKey: .periodStart)
        let periodEnd = try container.decodeIfPresent(Date.self, forKey: .periodEnd)
        let nonWorkoutSteps = try container.decodeIfPresent(Double.self, forKey: .nonWorkoutSteps)
        let excluded = try container.decodeIfPresent(Double.self, forKey: .workoutActiveEnergyExcluded) ?? 0
        let stand = try container.decodeIfPresent(TimeInterval.self, forKey: .standDuration) ?? 0
        let activeHours = try container.decodeIfPresent(Int.self, forKey: .activeNonWorkoutHourCount) ?? 0
        let distribution = try container.decodeIfPresent([Int: Double].self, forKey: .hourlyNonWorkoutDistribution) ?? [:]
        self.init(
            dailySteps: dailySteps,
            nonExerciseActiveEnergy: nonExerciseActiveEnergy,
            basalEnergy: basalEnergy,
            hourlyMovementConsistency: consistency,
            flightsClimbed: flights,
            periodStart: periodStart,
            periodEnd: periodEnd,
            nonWorkoutSteps: nonWorkoutSteps,
            workoutActiveEnergyExcluded: excluded,
            standDuration: stand,
            activeNonWorkoutHourCount: activeHours,
            hourlyNonWorkoutDistribution: distribution
        )
    }

    public var isAvailable: Bool {
        dailySteps > 0 || nonExerciseActiveEnergy > 0 || basalEnergy > 0 || standDuration > 0 || flightsClimbed > 0
    }
}

public struct AerobicEfficiencySnapshot: Codable, Sendable, Equatable {
    public let efficiencyFactor: Double?
    public let aerobicDecouplingPercentage: Double?
    public let vo2Max: Double?
    public let vo2MaxTrend: Double?
    public let sampleCount: Int

    public init(
        efficiencyFactor: Double? = nil,
        aerobicDecouplingPercentage: Double? = nil,
        vo2Max: Double? = nil,
        vo2MaxTrend: Double? = nil,
        sampleCount: Int = 0
    ) {
        self.efficiencyFactor = sanitizePositiveFinite(efficiencyFactor)
        self.aerobicDecouplingPercentage = sanitizeFinite(aerobicDecouplingPercentage)
        self.vo2Max = sanitizePositiveFinite(vo2Max)
        self.vo2MaxTrend = sanitizeFinite(vo2MaxTrend)
        self.sampleCount = max(0, sampleCount)
    }

    public var EF: Double? { efficiencyFactor }
    public var isAvailable: Bool {
        sampleCount > 0 || efficiencyFactor != nil || vo2Max != nil
    }
}

public struct StrengthWorkoutSummaryInput: Codable, Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let workingVolume: Double
    public let setCount: Int
    public let estimatedRPE: Double
    public let healthKitUUID: String?

    public init(
        startDate: Date,
        endDate: Date,
        workingVolume: Double,
        setCount: Int,
        estimatedRPE: Double,
        healthKitUUID: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.workingVolume = clampNonNegativeFinite(workingVolume)
        self.setCount = max(0, setCount)
        self.estimatedRPE = clampFinite(estimatedRPE, min: 0, max: 10)
        if let trimmed = healthKitUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            self.healthKitUUID = trimmed
        } else {
            self.healthKitUUID = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case workingVolume
        case setCount
        case estimatedRPE
        case healthKitUUID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startDate: try container.decode(Date.self, forKey: .startDate),
            endDate: try container.decode(Date.self, forKey: .endDate),
            workingVolume: try container.decode(Double.self, forKey: .workingVolume),
            setCount: try container.decode(Int.self, forKey: .setCount),
            estimatedRPE: try container.decode(Double.self, forKey: .estimatedRPE),
            healthKitUUID: try container.decodeIfPresent(String.self, forKey: .healthKitUUID)
        )
    }
}

public struct TrainingLoadDailyPoint: Codable, Sendable, Equatable {
    public let date: Date
    public let dailyLoad: Double
    public let acuteTrainingLoad: Double
    public let chronicTrainingLoad: Double
    public let trainingStressBalance: Double

    public init(
        date: Date,
        dailyLoad: Double,
        acuteTrainingLoad: Double,
        chronicTrainingLoad: Double,
        trainingStressBalance: Double
    ) {
        self.date = date
        self.dailyLoad = clampNonNegativeFinite(dailyLoad)
        self.acuteTrainingLoad = clampNonNegativeFinite(acuteTrainingLoad)
        self.chronicTrainingLoad = clampNonNegativeFinite(chronicTrainingLoad)
        self.trainingStressBalance = trainingStressBalance.isFinite ? trainingStressBalance : 0
    }
}

public struct TrainingLoadSnapshot: Codable, Sendable, Equatable {
    public let acuteTrainingLoad: Double
    public let chronicTrainingLoad: Double
    public let trainingStressBalance: Double
    public let acuteChronicWorkloadRatio: Double?
    public let trimp: Double
    public let tss: Double
    public let atlDelta7d: Double
    public let ctlDelta7d: Double
    public let ctlDelta14d: Double
    public let tsbDelta7d: Double
    public let deduplicatedWorkoutCount: Int
    public let recentTrajectory: [TrainingLoadDailyPoint]

    public init(
        acuteTrainingLoad: Double,
        chronicTrainingLoad: Double,
        trainingStressBalance: Double,
        acuteChronicWorkloadRatio: Double? = nil,
        trimp: Double = 0,
        tss: Double = 0,
        atlDelta7d: Double = 0,
        ctlDelta7d: Double = 0,
        ctlDelta14d: Double = 0,
        tsbDelta7d: Double = 0,
        deduplicatedWorkoutCount: Int = 0,
        recentTrajectory: [TrainingLoadDailyPoint] = []
    ) {
        self.acuteTrainingLoad = clampNonNegativeFinite(acuteTrainingLoad)
        self.chronicTrainingLoad = clampNonNegativeFinite(chronicTrainingLoad)
        self.trainingStressBalance = trainingStressBalance.isFinite ? trainingStressBalance : (self.chronicTrainingLoad - self.acuteTrainingLoad)
        self.acuteChronicWorkloadRatio = sanitizeNonNegativeFinite(acuteChronicWorkloadRatio)
        self.trimp = clampNonNegativeFinite(trimp)
        self.tss = clampNonNegativeFinite(tss)
        self.atlDelta7d = atlDelta7d.isFinite ? atlDelta7d : 0
        self.ctlDelta7d = ctlDelta7d.isFinite ? ctlDelta7d : 0
        self.ctlDelta14d = ctlDelta14d.isFinite ? ctlDelta14d : 0
        self.tsbDelta7d = tsbDelta7d.isFinite ? tsbDelta7d : 0
        self.deduplicatedWorkoutCount = max(0, deduplicatedWorkoutCount)
        self.recentTrajectory = recentTrajectory
    }

    private enum CodingKeys: String, CodingKey {
        case acuteTrainingLoad
        case chronicTrainingLoad
        case trainingStressBalance
        case acuteChronicWorkloadRatio
        case trimp
        case tss
        case atlDelta7d
        case ctlDelta7d
        case ctlDelta14d
        case tsbDelta7d
        case deduplicatedWorkoutCount
        case recentTrajectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let atl = try container.decode(Double.self, forKey: .acuteTrainingLoad)
        let ctl = try container.decode(Double.self, forKey: .chronicTrainingLoad)
        let tsb = try container.decode(Double.self, forKey: .trainingStressBalance)
        let acwr = try container.decodeIfPresent(Double.self, forKey: .acuteChronicWorkloadRatio)
        let trimp = try container.decodeIfPresent(Double.self, forKey: .trimp) ?? 0
        let tss = try container.decodeIfPresent(Double.self, forKey: .tss) ?? 0
        let atlDelta7d = try container.decodeIfPresent(Double.self, forKey: .atlDelta7d) ?? 0
        let ctlDelta7d = try container.decodeIfPresent(Double.self, forKey: .ctlDelta7d) ?? 0
        let ctlDelta14d = try container.decodeIfPresent(Double.self, forKey: .ctlDelta14d) ?? 0
        let tsbDelta7d = try container.decodeIfPresent(Double.self, forKey: .tsbDelta7d) ?? 0
        let dedup = try container.decodeIfPresent(Int.self, forKey: .deduplicatedWorkoutCount) ?? 0
        let trajectory = try container.decodeIfPresent([TrainingLoadDailyPoint].self, forKey: .recentTrajectory) ?? []
        self.init(
            acuteTrainingLoad: atl,
            chronicTrainingLoad: ctl,
            trainingStressBalance: tsb,
            acuteChronicWorkloadRatio: acwr,
            trimp: trimp,
            tss: tss,
            atlDelta7d: atlDelta7d,
            ctlDelta7d: ctlDelta7d,
            ctlDelta14d: ctlDelta14d,
            tsbDelta7d: tsbDelta7d,
            deduplicatedWorkoutCount: dedup,
            recentTrajectory: trajectory
        )
    }

    public var isAvailable: Bool {
        acuteTrainingLoad > 0 || chronicTrainingLoad > 0 || trimp > 0 || tss > 0 || !recentTrajectory.isEmpty
    }
    public var ATL: Double { acuteTrainingLoad }
    public var CTL: Double { chronicTrainingLoad }
    public var TSB: Double { trainingStressBalance }
    public var atl: Double { acuteTrainingLoad }
    public var ctl: Double { chronicTrainingLoad }
    public var tsb: Double { trainingStressBalance }
}

public struct PhysiologicalSnapshot: Codable, Sendable, Equatable {
    public let heart: HeartDomainSnapshot
    public let sleep: SleepDomainSnapshot
    public let neat: NEATActivitySnapshot
    public let aerobic: AerobicEfficiencySnapshot
    public let trainingLoad: TrainingLoadSnapshot
    public let availableDomains: Set<InsightDomain>
    public let generatedAt: Date

    public init(
        heart: HeartDomainSnapshot,
        sleep: SleepDomainSnapshot,
        neat: NEATActivitySnapshot,
        aerobic: AerobicEfficiencySnapshot,
        trainingLoad: TrainingLoadSnapshot,
        generatedAt: Date = Date(),
        availableDomains: Set<InsightDomain>? = nil
    ) {
        self.heart = heart
        self.sleep = sleep
        self.neat = neat
        self.aerobic = aerobic
        self.trainingLoad = trainingLoad
        self.generatedAt = generatedAt
        if let availableDomains {
            self.availableDomains = availableDomains
        } else {
            var inferred: Set<InsightDomain> = []
            if heart.isAvailable { inferred.insert(.heart) }
            if sleep.isAvailable { inferred.insert(.sleep) }
            if neat.isAvailable { inferred.insert(.neat) }
            if aerobic.isAvailable { inferred.insert(.aerobic) }
            if trainingLoad.isAvailable { inferred.insert(.trainingLoad) }
            self.availableDomains = inferred
        }
    }

    private enum CodingKeys: String, CodingKey {
        case heart
        case sleep
        case neat
        case aerobic
        case trainingLoad
        case availableDomains
        case generatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let heart = try container.decode(HeartDomainSnapshot.self, forKey: .heart)
        let sleep = try container.decode(SleepDomainSnapshot.self, forKey: .sleep)
        let neat = try container.decode(NEATActivitySnapshot.self, forKey: .neat)
        let aerobic = try container.decode(AerobicEfficiencySnapshot.self, forKey: .aerobic)
        let trainingLoad = try container.decode(TrainingLoadSnapshot.self, forKey: .trainingLoad)
        let generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        let availableDomains = try container.decodeIfPresent(Set<InsightDomain>.self, forKey: .availableDomains)
        self.init(
            heart: heart,
            sleep: sleep,
            neat: neat,
            aerobic: aerobic,
            trainingLoad: trainingLoad,
            generatedAt: generatedAt,
            availableDomains: availableDomains
        )
    }
}

public struct HeartDomainSnapshot: Codable, Sendable, Equatable {
    public let restingHeartRate: RestingHeartRateSummary
    public let hrvCorridor: HRVCorridorSnapshot
    public let zoneDistribution: HeartRateZoneDistribution
    public let recovery: HeartRateRecoveryMetric

    public init(restingHeartRate: RestingHeartRateSummary, hrvCorridor: HRVCorridorSnapshot, zoneDistribution: HeartRateZoneDistribution, recovery: HeartRateRecoveryMetric) {
        self.restingHeartRate = restingHeartRate
        self.hrvCorridor = hrvCorridor
        self.zoneDistribution = zoneDistribution
        self.recovery = recovery
    }

    public var isAvailable: Bool {
        restingHeartRate.isAvailable || hrvCorridor.isAvailable || zoneDistribution.totalDuration > 0 || recovery.isAvailable
    }
}

public struct SleepDomainSnapshot: Codable, Sendable, Equatable {
    public let architecture: SleepArchitectureSnapshot
    public let debt: SleepDebtSummary
    public let recentNights: [SleepArchitectureSnapshot]

    public init(
        architecture: SleepArchitectureSnapshot,
        debt: SleepDebtSummary,
        recentNights: [SleepArchitectureSnapshot] = []
    ) {
        self.architecture = architecture
        self.debt = debt
        self.recentNights = recentNights
    }

    private enum CodingKeys: String, CodingKey {
        case architecture
        case debt
        case recentNights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let architecture = try container.decode(SleepArchitectureSnapshot.self, forKey: .architecture)
        let debt = try container.decode(SleepDebtSummary.self, forKey: .debt)
        let recentNights = try container.decodeIfPresent([SleepArchitectureSnapshot].self, forKey: .recentNights) ?? []
        self.init(architecture: architecture, debt: debt, recentNights: recentNights)
    }

    public var isAvailable: Bool {
        architecture.isAvailable || debt.isAvailable || !recentNights.isEmpty
    }
}

public enum InsightSeverity: String, Codable, Sendable, Equatable, CaseIterable {
    case normal
    case watch
    case warning
    case critical
}

public enum InsightDomain: String, Codable, Sendable, Equatable, CaseIterable {
    case heart
    case sleep
    case neat
    case aerobic
    case trainingLoad
}

public enum MesocyclePhase: String, Codable, Sendable, Equatable, CaseIterable {
    case accumulation
    case intensification
    case realization
    case deload
}

public struct L1SingleMetricInsight: Codable, Sendable, Equatable {
    public let domain: InsightDomain
    public let metric: String
    public let value: Double?
    public let severity: InsightSeverity
    public let message: String

    public init(domain: InsightDomain, metric: String, value: Double? = nil, severity: InsightSeverity = .normal, message: String) {
        self.domain = domain
        self.metric = metric
        self.value = sanitizeFinite(value)
        self.severity = severity
        self.message = message
    }
}

public struct L2CoupledInsight: Codable, Sendable, Equatable {
    public let primaryDomain: InsightDomain
    public let secondaryDomain: InsightDomain
    public let relationship: String
    public let message: String
    public let severity: InsightSeverity

    public init(primaryDomain: InsightDomain, secondaryDomain: InsightDomain, relationship: String, message: String, severity: InsightSeverity = .normal) {
        self.primaryDomain = primaryDomain
        self.secondaryDomain = secondaryDomain
        self.relationship = relationship
        self.message = message
        self.severity = severity
    }
}

public struct L3ReadinessAndCycleInsight: Codable, Sendable, Equatable {
    public let readinessScore: Int
    public let autonomicScore: Int
    public let sleepRestorationScore: Int
    public let fatigueBalanceScore: Int
    public let mesocyclePhase: MesocyclePhase
    public let recommendedIntensityCap: Double
    public let contributingInsights: [String]

    public init(
        readinessScore: Int,
        autonomicScore: Int = 0,
        sleepRestorationScore: Int = 0,
        fatigueBalanceScore: Int = 0,
        mesocyclePhase: MesocyclePhase,
        recommendedIntensityCap: Double,
        contributingInsights: [String] = []
    ) {
        self.readinessScore = min(max(readinessScore, 0), 100)
        self.autonomicScore = min(max(autonomicScore, 0), 100)
        self.sleepRestorationScore = min(max(sleepRestorationScore, 0), 100)
        self.fatigueBalanceScore = min(max(fatigueBalanceScore, 0), 100)
        self.mesocyclePhase = mesocyclePhase
        self.recommendedIntensityCap = clampUnitFinite(recommendedIntensityCap)
        self.contributingInsights = contributingInsights
    }

    private enum CodingKeys: String, CodingKey {
        case readinessScore
        case autonomicScore
        case sleepRestorationScore
        case fatigueBalanceScore
        case mesocyclePhase
        case recommendedIntensityCap
        case contributingInsights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            readinessScore: try container.decode(Int.self, forKey: .readinessScore),
            autonomicScore: try container.decodeIfPresent(Int.self, forKey: .autonomicScore) ?? 0,
            sleepRestorationScore: try container.decodeIfPresent(Int.self, forKey: .sleepRestorationScore) ?? 0,
            fatigueBalanceScore: try container.decodeIfPresent(Int.self, forKey: .fatigueBalanceScore) ?? 0,
            mesocyclePhase: try container.decode(MesocyclePhase.self, forKey: .mesocyclePhase),
            recommendedIntensityCap: try container.decode(Double.self, forKey: .recommendedIntensityCap),
            contributingInsights: try container.decodeIfPresent([String].self, forKey: .contributingInsights) ?? []
        )
    }
}

public struct L4HolisticNorthStarInsight: Codable, Sendable, Equatable {
    public let northStarScore: Int
    public let directive: String
    public let prioritizedActions: [String]

    public init(northStarScore: Int, directive: String, prioritizedActions: [String] = []) {
        self.northStarScore = min(max(northStarScore, 0), 100)
        self.directive = directive
        self.prioritizedActions = Array(prioritizedActions.prefix(3))
    }
}

public struct HolisticFourLayerReport: Codable, Sendable, Equatable {
    public let l1: [L1SingleMetricInsight]
    public let l2: [L2CoupledInsight]
    public let l3: L3ReadinessAndCycleInsight
    public let l4: L4HolisticNorthStarInsight
    public let generatedAt: Date

    public init(l1: [L1SingleMetricInsight], l2: [L2CoupledInsight], l3: L3ReadinessAndCycleInsight, l4: L4HolisticNorthStarInsight, generatedAt: Date = Date()) {
        self.l1 = l1
        self.l2 = l2
        self.l3 = l3
        self.l4 = l4
        self.generatedAt = generatedAt
    }
}
