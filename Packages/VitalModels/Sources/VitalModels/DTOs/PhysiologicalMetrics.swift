import Foundation

public enum HeartRateZone: String, Codable, Sendable, Equatable, CaseIterable {
    case zone1
    case zone2
    case zone3
    case zone4
    case zone5
}

public struct RestingHeartRateSummary: Codable, Sendable, Equatable {
    public let averageBPM: Double
    public let minimumBPM: Double?
    public let maximumBPM: Double?
    public let sampleCount: Int
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        averageBPM: Double,
        minimumBPM: Double? = nil,
        maximumBPM: Double? = nil,
        sampleCount: Int = 0,
        periodStart: Date? = nil,
        periodEnd: Date? = nil
    ) {
        self.averageBPM = averageBPM
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
        self.sampleCount = sampleCount
        self.periodStart = periodStart
        self.periodEnd = periodEnd
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
    public let sampleCount: Int
    public let periodStart: Date?
    public let periodEnd: Date?

    public init(
        baselineMilliseconds: Double,
        lowerBoundMilliseconds: Double,
        upperBoundMilliseconds: Double,
        sampleCount: Int = 0,
        periodStart: Date? = nil,
        periodEnd: Date? = nil
    ) {
        self.baselineMilliseconds = baselineMilliseconds
        self.lowerBoundMilliseconds = lowerBoundMilliseconds
        self.upperBoundMilliseconds = upperBoundMilliseconds
        self.sampleCount = sampleCount
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    public var isWithinCorridor: Bool {
        (lowerBoundMilliseconds...upperBoundMilliseconds).contains(baselineMilliseconds)
    }
    public var baseline: Double { baselineMilliseconds }
    public var lowerBound: Double { lowerBoundMilliseconds }
    public var upperBound: Double { upperBoundMilliseconds }
}

public struct HeartRateZoneDistribution: Codable, Sendable, Equatable {
    public let durationsByZone: [HeartRateZone: TimeInterval]

    public init(durationsByZone: [HeartRateZone: TimeInterval] = [:]) {
        self.durationsByZone = HeartRateZone.allCases.reduce(into: [:]) { result, zone in
            result[zone] = max(0, durationsByZone[zone] ?? 0)
        }
    }

    public init(zone1: TimeInterval, zone2: TimeInterval, zone3: TimeInterval, zone4: TimeInterval, zone5: TimeInterval) {
        self.init(durationsByZone: [.zone1: zone1, .zone2: zone2, .zone3: zone3, .zone4: zone4, .zone5: zone5])
    }

    public init(zone1Duration: TimeInterval, zone2Duration: TimeInterval, zone3Duration: TimeInterval, zone4Duration: TimeInterval, zone5Duration: TimeInterval) {
        self.init(zone1: zone1Duration, zone2: zone2Duration, zone3: zone3Duration, zone4: zone4Duration, zone5: zone5Duration)
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

    public init(baselineBPM: Double, oneMinuteBPM: Double? = nil, twoMinuteBPM: Double? = nil) {
        self.baselineBPM = baselineBPM
        self.oneMinuteBPM = oneMinuteBPM
        self.twoMinuteBPM = twoMinuteBPM
    }

    public var oneMinuteDropBPM: Double? { oneMinuteBPM.map { baselineBPM - $0 } }
    public var twoMinuteDropBPM: Double? { twoMinuteBPM.map { baselineBPM - $0 } }
}

public struct SleepArchitectureSnapshot: Codable, Sendable, Equatable {
    public let deepDuration: TimeInterval
    public let remDuration: TimeInterval
    public let coreDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let totalSleepDuration: TimeInterval
    public let sleepEfficiency: Double
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
        periodEnd: Date? = nil
    ) {
        self.deepDuration = max(0, deepDuration)
        self.remDuration = max(0, remDuration)
        self.coreDuration = max(0, coreDuration)
        self.awakeDuration = max(0, awakeDuration)
        self.totalSleepDuration = max(0, totalSleepDuration)
        self.sleepEfficiency = min(max(sleepEfficiency, 0), 1)
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    public var totalInBedDuration: TimeInterval { totalSleepDuration + awakeDuration }
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

    public init(
        sevenDayDebt: TimeInterval,
        fourteenDayDebt: TimeInterval,
        baselineSleepDuration: TimeInterval,
        targetSleepDuration: TimeInterval
    ) {
        self.sevenDayDebt = max(0, sevenDayDebt)
        self.fourteenDayDebt = max(0, fourteenDayDebt)
        self.baselineSleepDuration = max(0, baselineSleepDuration)
        self.targetSleepDuration = max(0, targetSleepDuration)
    }
}

public struct NEATActivitySnapshot: Codable, Sendable, Equatable {
    public let dailySteps: Double
    public let nonExerciseActiveEnergy: Double
    public let basalEnergy: Double
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
        periodEnd: Date? = nil
    ) {
        self.dailySteps = max(0, dailySteps)
        self.nonExerciseActiveEnergy = max(0, nonExerciseActiveEnergy)
        self.basalEnergy = max(0, basalEnergy)
        self.hourlyMovementConsistency = min(max(hourlyMovementConsistency, 0), 1)
        self.flightsClimbed = max(0, flightsClimbed)
        self.periodStart = periodStart
        self.periodEnd = periodEnd
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
        self.efficiencyFactor = efficiencyFactor
        self.aerobicDecouplingPercentage = aerobicDecouplingPercentage
        self.vo2Max = vo2Max
        self.vo2MaxTrend = vo2MaxTrend
        self.sampleCount = sampleCount
    }

    public var EF: Double? { efficiencyFactor }
}

public struct StrengthWorkoutSummaryInput: Codable, Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let workingVolume: Double
    public let setCount: Int
    public let estimatedRPE: Double

    public init(startDate: Date, endDate: Date, workingVolume: Double, setCount: Int, estimatedRPE: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.workingVolume = max(0, workingVolume)
        self.setCount = max(0, setCount)
        self.estimatedRPE = min(max(estimatedRPE, 0), 10)
    }
}

public struct TrainingLoadSnapshot: Codable, Sendable, Equatable {
    public let acuteTrainingLoad: Double
    public let chronicTrainingLoad: Double
    public let trainingStressBalance: Double
    public let acuteChronicWorkloadRatio: Double?
    public let trimp: Double
    public let tss: Double

    public init(
        acuteTrainingLoad: Double,
        chronicTrainingLoad: Double,
        trainingStressBalance: Double,
        acuteChronicWorkloadRatio: Double? = nil,
        trimp: Double = 0,
        tss: Double = 0
    ) {
        self.acuteTrainingLoad = acuteTrainingLoad
        self.chronicTrainingLoad = chronicTrainingLoad
        self.trainingStressBalance = trainingStressBalance
        self.acuteChronicWorkloadRatio = acuteChronicWorkloadRatio
        self.trimp = trimp
        self.tss = tss
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
    public let generatedAt: Date

    public init(
        heart: HeartDomainSnapshot,
        sleep: SleepDomainSnapshot,
        neat: NEATActivitySnapshot,
        aerobic: AerobicEfficiencySnapshot,
        trainingLoad: TrainingLoadSnapshot,
        generatedAt: Date = Date()
    ) {
        self.heart = heart
        self.sleep = sleep
        self.neat = neat
        self.aerobic = aerobic
        self.trainingLoad = trainingLoad
        self.generatedAt = generatedAt
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
}

public struct SleepDomainSnapshot: Codable, Sendable, Equatable {
    public let architecture: SleepArchitectureSnapshot
    public let debt: SleepDebtSummary

    public init(architecture: SleepArchitectureSnapshot, debt: SleepDebtSummary) {
        self.architecture = architecture
        self.debt = debt
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
        self.value = value
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
        self.recommendedIntensityCap = min(max(recommendedIntensityCap, 0), 1)
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
