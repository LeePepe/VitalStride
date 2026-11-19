import Foundation

/// Coaching heuristics, not medical assessment. Missing observations contribute
/// a cautious 40 rather than a fictitious perfect recovery score.
public struct DeterministicFourLayerEngine: AIProvider, Sendable {
    public init() {}

    public func makeReport(from snapshot: PhysiologicalSnapshot, generatedAt: Date? = nil) -> HolisticFourLayerReport {
        let rules = FourLayerRules(snapshot: snapshot)
        let autonomic = rules.autonomicScore
        let sleep = rules.sleepScore
        let fatigue = rules.fatigueScore
        let readiness = max(0, (autonomic + sleep + fatigue) / 3 - rules.couplingPenalty)
        let phase = rules.phase
        var cap: Double = readiness >= 80 ? 1 : readiness >= 60 ? 0.8 : readiness >= 40 ? 0.6 : 0.4
        if !rules.has(.heart) || !rules.has(.sleep) || !rules.has(.trainingLoad) { cap = min(cap, 0.6) }
        if phase == .deload || autonomic < 50 { cap = min(cap, 0.5) }
        let couplings = rules.couplings
        let l3 = L3ReadinessAndCycleInsight(
            readinessScore: readiness, autonomicScore: autonomic,
            sleepRestorationScore: sleep, fatigueBalanceScore: fatigue,
            mesocyclePhase: phase, recommendedIntensityCap: cap,
            contributingInsights: couplings.map(\.message)
        )
        let unknown = !rules.has(.heart) || !rules.has(.sleep) || !rules.has(.trainingLoad)
        let narrative = unknown
            ? "Recovery evidence is incomplete; keep effort conservative while rebuilding sleep, heart and load history."
            : readiness < 60 || phase == .deload
                ? "Sleep restoration and recovery signals do not fully support the current load; prioritize recovery over progression."
                : "Recovery and movement support controlled training in the \(phase.rawValue) phase; monitor how effort feels."
        var actions: [String] = []
        if unknown { actions.append("Collect missing recovery observations before increasing training intensity.") }
        if cap <= 0.6 { actions.append("Choose easy work and reduce demanding sets or intervals today.") }
        if rules.sleepScore < 70 { actions.append("Protect a consistent sleep opportunity and reassess restoration tomorrow.") }
        if rules.movementScore < 60 { actions.append("Use short easy walking and standing breaks, without chasing a step target.") }
        if actions.isEmpty { actions.append("Follow the planned session with controlled progression and regular recovery breaks.") }
        let l4 = L4HolisticNorthStarInsight(
            northStarScore: (readiness * 2 + rules.movementScore + rules.aerobicScore) / 4,
            directive: narrative, prioritizedActions: Array(actions.prefix(3))
        )
        return HolisticFourLayerReport(l1: rules.atomicInsights, l2: couplings, l3: l3, l4: l4,
                                      generatedAt: generatedAt ?? snapshot.generatedAt)
    }

    public func generate(snapshot: PhysiologicalSnapshot) async -> HolisticFourLayerReport {
        makeReport(from: snapshot)
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        try Task.checkCancellation()
        guard let content = messages.last(where: { $0.role == "user" })?.content,
              let data = content.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(PhysiologicalSnapshot.self, from: data) else {
            throw AIServiceError.noProviderAvailable
        }
        let encoded = try JSONEncoder().encode(makeReport(from: snapshot))
        guard let content = String(data: encoded, encoding: .utf8) else { throw AIServiceError.responseParsingFailed }
        return ChatResponse(content: content, model: "deterministic-fallback")
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await chat(messages: messages, model: model)
                    try Task.checkCancellation()
                    continuation.yield(ChatStreamChunk(content: response.content))
                    continuation.yield(ChatStreamChunk(content: "", isFinished: true))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct FourLayerRules {
    let snapshot: PhysiologicalSnapshot
    private let unknown = 40

    func has(_ domain: InsightDomain) -> Bool {
        guard snapshot.availableDomains.contains(domain) else { return false }
        switch domain {
        case .heart: return snapshot.heart.isAvailable
        case .sleep: return snapshot.sleep.isAvailable
        case .neat: return snapshot.neat.isAvailable
        case .aerobic: return snapshot.aerobic.isAvailable
        case .trainingLoad: return snapshot.trainingLoad.isAvailable
        }
    }

    private func score(_ value: Double) -> Int {
        guard value.isFinite else { return unknown }
        return Int(min(max(value, 0), 100).rounded())
    }
    private var stagesAvailable: Bool {
        let sleep = snapshot.sleep.architecture
        return has(.sleep) && sleep.deepDuration + sleep.remDuration + sleep.coreDuration > 0
    }
    private var debtAvailable: Bool {
        let sleep = snapshot.sleep
        return has(.sleep) && sleep.debt.isAvailable && sleep.debt.targetSleepDuration > 0
            && (sleep.architecture.isAvailable || !sleep.recentNights.isEmpty || sleep.debt.baselineSleepDuration > 0)
    }
    private var highIntensityFraction: Double {
        let zones = snapshot.heart.zoneDistribution
        return has(.heart) && zones.totalDuration > 0
            ? (zones.zone4Duration + zones.zone5Duration) / zones.totalDuration : 0
    }

    var autonomicScore: Int {
        guard has(.heart) else { return unknown }
        let heart = snapshot.heart
        var components: [Int] = []
        if heart.hrvCorridor.isAvailable && heart.hrvCorridor.baselineDayCount > 0 {
            let hrv = heart.hrvCorridor
            let acute = (hrv.currentMilliseconds ?? hrv.baselineMilliseconds) / hrv.baselineMilliseconds
            let rolling = hrv.sevenDaySampleCount > 0
                ? (hrv.sevenDayAverageMilliseconds ?? hrv.baselineMilliseconds) / hrv.baselineMilliseconds : acute
            components.append(score(90 - max(0, 1 - min(acute, rolling)) * 120 - (hrv.isWithinCorridor ? 0 : 10)))
        } else { components.append(unknown) }
        if heart.restingHeartRate.isAvailable, heart.restingHeartRate.baselineDayCount > 0,
           let delta = heart.restingHeartRate.deltaFromBaselineBPM {
            components.append(score(90 - max(0, delta) * 4))
        } else { components.append(unknown) }
        var recovery: [Int] = []
        if heart.recovery.isAvailable {
            if let drop = heart.recovery.oneMinuteDropBPM { recovery.append(score(drop / 30 * 90)) }
            if let drop = heart.recovery.twoMinuteDropBPM { recovery.append(score(drop / 45 * 90)) }
        }
        components.append(recovery.isEmpty ? unknown : recovery.reduce(0, +) / recovery.count)
        return components.reduce(0, +) / components.count
    }

    var sleepScore: Int {
        guard has(.sleep) else { return unknown }
        let sleep = snapshot.sleep
        let night = sleep.architecture
        var components: [Int] = []
        if night.isAvailable && night.totalSleepDuration > 0 {
            let target = sleep.debt.targetSleepDuration > 0 ? sleep.debt.targetSleepDuration : 28_800
            components.append(score(min(night.totalSleepDuration / target, 1) * 95))
            components.append(score(night.sleepEfficiency * 100))
        } else { components += [unknown, unknown] }
        if stagesAvailable && night.totalSleepDuration > 0 {
            let deep = min(night.deepDuration / night.totalSleepDuration / 0.15, 1)
            let rem = min(night.remDuration / night.totalSleepDuration / 0.20, 1)
            components.append(score((deep + rem) * 47.5))
        } else { components.append(unknown) }
        if debtAvailable {
            let debt = sleep.debt
            let penalty = min(debt.sevenDayDebt / debt.targetSleepDuration, 2) * 25
                + min(debt.fourteenDayDebt / (2 * debt.targetSleepDuration), 1) * 15
            let coverage = min(debt.sevenDayCoverageRatio, debt.fourteenDayCoverageRatio)
            components.append(score((95 - penalty) * coverage + Double(unknown) * (1 - coverage)))
        } else { components.append(unknown) }
        return components.reduce(0, +) / components.count
    }

    var fatigueScore: Int {
        guard has(.trainingLoad) else { return unknown }
        let load = snapshot.trainingLoad
        let ratio = load.acuteChronicWorkloadRatio ?? (load.chronicTrainingLoad > 0 ? load.acuteTrainingLoad / load.chronicTrainingLoad : 1.5)
        return score(90 - max(0, -load.trainingStressBalance) * 1.5
                     - max(0, ratio - 1.1) * 45 - max(0, load.atlDelta7d - load.ctlDelta7d) * 0.8)
    }

    var movementScore: Int {
        guard has(.neat) else { return unknown }
        let neat = snapshot.neat
        return score(min(neat.nonWorkoutSteps / 6_000, 1) * 40
                     + neat.hourlyMovementConsistency * 30 + min(neat.standDuration / 3_600, 1) * 15
                     + min(neat.nonExerciseActiveEnergy / 250, 1) * 15)
    }

    var aerobicScore: Int {
        guard has(.aerobic) else { return unknown }
        let aerobic = snapshot.aerobic
        var components: [Int] = []
        if let ef = aerobic.efficiencyFactor { components.append(ef > 0 ? 75 : unknown) }
        if let decoupling = aerobic.aerobicDecouplingPercentage { components.append(score(90 - max(0, decoupling - 5) * 3)) }
        if let trend = aerobic.vo2MaxTrend { components.append(score(75 + trend * 5)) }
        return components.isEmpty ? unknown : components.reduce(0, +) / components.count
    }

    private var sleepTrainingPenalty: Int {
        guard has(.sleep), has(.trainingLoad) else { return 5 }
        let demand = min(1, Double(100 - fatigueScore) / 60 + highIntensityFraction)
        return score(max(0, Double(75 - sleepScore)) * demand * 0.4)
    }
    private var movementRecoveryPenalty: Int {
        guard has(.neat), has(.heart) || has(.trainingLoad) else { return 5 }
        let neat = snapshot.neat
        let recovery = min(autonomicScore, fatigueScore)
        // Expenditure is not caloric balance: intake/body-composition are not in
        // this wire schema. Only compare observed activity burden with recovery.
        let burden = neat.basalEnergy > 0 ? neat.nonExerciseActiveEnergy / neat.basalEnergy : 0
        if recovery < 60 {
            return score(max(0, burden - 0.35) * 30 + (movementScore < 40 ? 7 : 0))
        }
        return movementScore < 40 ? 3 : 0
    }
    var couplingPenalty: Int { sleepTrainingPenalty + movementRecoveryPenalty }

    var couplings: [L2CoupledInsight] {
        let sleepKnown = has(.sleep) && has(.trainingLoad)
        let movementKnown = has(.neat) && (has(.heart) || has(.trainingLoad))
        return [
            .init(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling",
                  message: !sleepKnown ? "Sleep or training history is unknown; do not infer full restoration."
                    : sleepTrainingPenalty > 3 ? "Limited Deep/REM restoration or accumulated debt is less compatible with current fatigue and high-intensity exposure; reduce demanding work."
                    : "Observed sleep stages and debt are compatible with the current training load; maintain recovery as intensity progresses.",
                  severity: !sleepKnown ? .watch : sleepTrainingPenalty > 3 ? .warning : .normal),
            .init(primaryDomain: .neat, secondaryDomain: has(.heart) ? .heart : .trainingLoad, relationship: "stepsBodyCoupling",
                  message: !movementKnown ? "Movement or recovery evidence is unknown; body composition and energy intake are unavailable."
                    : movementRecoveryPenalty > 3 ? "Movement consistency or nonexercise energy burden is poorly matched to recovery; favor brief easy breaks rather than extra volume. Intake and body composition are unknown."
                    : "Nonexercise movement and energy expenditure fit current recovery signals; use easy activity without inferring caloric balance or body-composition change.",
                  severity: !movementKnown ? .watch : movementRecoveryPenalty > 3 ? .warning : .normal),
        ]
    }

    var phase: MesocyclePhase {
        guard has(.trainingLoad), snapshot.trainingLoad.chronicTrainingLoad > 0 else { return .deload }
        let load = snapshot.trainingLoad
        let history = load.recentTrajectory.filter { $0.date <= snapshot.generatedAt }.sorted { $0.date < $1.date }
        let atlChange = history.count >= 2 ? (history.last?.acuteTrainingLoad ?? 0) - (history.first?.acuteTrainingLoad ?? 0) : load.atlDelta7d
        let ctlChange = history.count >= 2 ? (history.last?.chronicTrainingLoad ?? 0) - (history.first?.chronicTrainingLoad ?? 0) : load.ctlDelta7d
        let tsbChange = history.count >= 2 ? (history.last?.trainingStressBalance ?? 0) - (history.first?.trainingStressBalance ?? 0) : load.tsbDelta7d
        let ratio = load.acuteChronicWorkloadRatio ?? (load.chronicTrainingLoad > 0 ? load.acuteTrainingLoad / load.chronicTrainingLoad : 1.5)
        if ratio > 1.5 || load.trainingStressBalance < -25 || load.ctlDelta7d > 12 { return .deload }
        if load.chronicTrainingLoad > 0 && ratio < 1 && atlChange < 0 && tsbChange > 0 && load.ctlDelta14d >= 0 { return .realization }
        if ratio >= 1.1 && (atlChange > 0 || ctlChange > 0) { return .intensification }
        return .accumulation
    }

    var atomicInsights: [L1SingleMetricInsight] {
        let heart = snapshot.heart
        let night = snapshot.sleep.architecture
        let debt = snapshot.sleep.debt
        let neat = snapshot.neat
        let aerobic = snapshot.aerobic
        let load = snapshot.trainingLoad
        let trajectoryKnown = load.recentTrajectory.filter { $0.date <= snapshot.generatedAt }.count >= 2
        let hrvBaselineKnown = heart.hrvCorridor.isAvailable && heart.hrvCorridor.baselineDayCount > 0
        func insight(_ domain: InsightDomain, _ metric: String, _ value: Double?, _ known: Bool,
                     _ warning: Bool = false, _ detail: String) -> L1SingleMetricInsight {
            let observed = known && has(domain) && value != nil
            return .init(domain: domain, metric: metric, value: observed ? value : nil,
                         severity: !observed ? .watch : warning ? .warning : .normal,
                         message: observed ? detail : "Unknown: insufficient observations for \(metric).")
        }
        var result: [L1SingleMetricInsight] = [
            insight(.heart, "restingHeartRate", heart.restingHeartRate.currentBPM, heart.restingHeartRate.isAvailable, (heart.restingHeartRate.deltaFromBaselineBPM ?? 0) > 7, "Current resting heart rate in bpm."),
            insight(.heart, "rhrBaselineDelta", heart.restingHeartRate.deltaFromBaselineBPM, heart.restingHeartRate.isAvailable && heart.restingHeartRate.baselineDayCount > 0, (heart.restingHeartRate.deltaFromBaselineBPM ?? 0) > 7, "Resting heart rate relative to personal baseline in bpm."),
            insight(.heart, "hrvCurrent", heart.hrvCorridor.currentMilliseconds, hrvBaselineKnown, !heart.hrvCorridor.isWithinCorridor, "Current HRV relative to the 60-day corridor in ms."),
            insight(.heart, "hrv7d", heart.hrvCorridor.sevenDayAverageMilliseconds, hrvBaselineKnown && heart.hrvCorridor.sevenDaySampleCount > 0, !heart.hrvCorridor.isWithinCorridor, "Seven-day HRV relative to the 60-day corridor in ms."),
            insight(.heart, "hrvBaseline60d", heart.hrvCorridor.baselineMilliseconds, hrvBaselineKnown, false, "Personal HRV baseline in ms."),
            insight(.heart, "heartRateRecovery1m", heart.recovery.oneMinuteDropBPM, heart.recovery.isAvailable, (heart.recovery.oneMinuteDropBPM ?? 30) < 20, "One-minute post-workout heart-rate drop in bpm; interpret with context."),
            insight(.heart, "heartRateRecovery2m", heart.recovery.twoMinuteDropBPM, heart.recovery.isAvailable, (heart.recovery.twoMinuteDropBPM ?? 45) < 30, "Two-minute post-workout heart-rate drop in bpm; not a diagnosis."),
        ]
        for zone in HeartRateZone.allCases {
            result.append(insight(.heart, zone.rawValue, heart.zoneDistribution.duration(in: zone), heart.zoneDistribution.totalDuration > 0, false, "Observed time in \(zone.rawValue), seconds."))
        }
        result += [
            insight(.sleep, "totalSleep", night.totalSleepDuration, night.totalSleepDuration > 0, sleepScore < 60, "Observed total sleep in seconds."),
            insight(.sleep, "deepSleep", night.deepDuration, stagesAvailable, sleepScore < 60, "Deep-stage sleep in seconds."),
            insight(.sleep, "remSleep", night.remDuration, stagesAvailable, sleepScore < 60, "REM-stage sleep in seconds."),
            insight(.sleep, "coreSleep", night.coreDuration, stagesAvailable, false, "Core-stage sleep in seconds."),
            insight(.sleep, "awakeSleep", night.awakeDuration, night.isAvailable, night.sleepEfficiency < 0.8, "Awake time within observed sleep opportunity, seconds."),
            insight(.sleep, "sleepEfficiency", night.sleepEfficiency, night.isAvailable, night.sleepEfficiency < 0.8, "Observed sleep efficiency, fraction 0–1."),
            insight(.sleep, "sleepDebt7d", debt.sevenDayDebt, debtAvailable, debt.sevenDayDebt > debt.targetSleepDuration * 0.5, "Observed seven-day sleep debt in seconds; missing nights remain unknown."),
            insight(.sleep, "sleepDebt14d", debt.fourteenDayDebt, debtAvailable, debt.fourteenDayDebt > debt.targetSleepDuration, "Observed fourteen-day sleep debt in seconds."),
            insight(.sleep, "sleepCoverage7d", debt.sevenDayCoverageRatio, debtAvailable, debt.sevenDayCoverageRatio < 1, "Coverage of seven calendar nights, fraction 0–1."),
            insight(.neat, "dailySteps", neat.dailySteps, neat.dailySteps > 0, false, "Observed total daily steps."),
            insight(.neat, "nonWorkoutSteps", neat.nonWorkoutSteps, neat.nonWorkoutSteps > 0, false, "Nonexercise steps support low-load movement."),
            insight(.neat, "nonExerciseEnergy", neat.nonExerciseActiveEnergy, neat.nonExerciseActiveEnergy > 0, false, "Nonexercise active energy in kcal; not intake or energy balance."),
            insight(.neat, "basalEnergy", neat.basalEnergy, neat.basalEnergy > 0, false, "Observed basal expenditure in kcal."),
            insight(.neat, "flightsClimbed", neat.flightsClimbed, neat.flightsClimbed > 0, false, "Observed floors climbed."),
            insight(.neat, "activeNonWorkoutHours", Double(neat.activeNonWorkoutHourCount), neat.activeNonWorkoutHourCount > 0, false, "Hours with observed nonexercise movement."),
            insight(.neat, "standDuration", neat.standDuration, neat.standDuration > 0, false, "Observed standing time in seconds."),
            insight(.neat, "movementConsistency", neat.hourlyMovementConsistency, neat.activeNonWorkoutHourCount > 0 || !neat.hourlyNonWorkoutDistribution.isEmpty, neat.hourlyMovementConsistency < 0.3, "Hourly nonexercise movement consistency, fraction 0–1."),
            insight(.aerobic, "efficiencyFactor", aerobic.efficiencyFactor, aerobic.efficiencyFactor != nil, false, "Aerobic efficiency in (km/h)/bpm; compare like sessions."),
            insight(.aerobic, "aerobicDecoupling", aerobic.aerobicDecouplingPercentage, aerobic.aerobicDecouplingPercentage != nil, (aerobic.aerobicDecouplingPercentage ?? 0) > 5, "Pace/heart-rate decoupling in percent."),
            insight(.aerobic, "vo2Max", aerobic.vo2Max, aerobic.vo2Max != nil, false, "Observed VO2max in mL/(kg·min)."),
            insight(.aerobic, "vo2MaxTrend", aerobic.vo2MaxTrend, aerobic.vo2MaxTrend != nil, (aerobic.vo2MaxTrend ?? 0) < 0, "Change in observed VO2max."),
            insight(.trainingLoad, "acuteTrainingLoad", load.acuteTrainingLoad, load.isAvailable, fatigueScore < 50, "Seven-day EWMA training stress (ATL)."),
            insight(.trainingLoad, "chronicTrainingLoad", load.chronicTrainingLoad, load.isAvailable, false, "Forty-two-day EWMA training stress (CTL)."),
            insight(.trainingLoad, "trainingStressBalance", load.trainingStressBalance, load.isAvailable, fatigueScore < 50, "CTL minus ATL; interpret alongside trajectory."),
            insight(.trainingLoad, "workloadRatio", load.acuteChronicWorkloadRatio, load.isAvailable, (load.acuteChronicWorkloadRatio ?? 0) > 1.5, "Acute/chronic workload ratio; undefined without a baseline."),
            insight(.trainingLoad, "atlDelta7d", load.atlDelta7d, trajectoryKnown || load.atlDelta7d != 0, false, "Seven-day change in acute load."),
            insight(.trainingLoad, "ctlDelta7d", load.ctlDelta7d, trajectoryKnown || load.ctlDelta7d != 0, load.ctlDelta7d > 12, "Seven-day chronic-load ramp."),
            insight(.trainingLoad, "ctlDelta14d", load.ctlDelta14d, trajectoryKnown || load.ctlDelta14d != 0, false, "Fourteen-day chronic-load progression."),
            insight(.trainingLoad, "tsbDelta7d", load.tsbDelta7d, trajectoryKnown || load.tsbDelta7d != 0, false, "Seven-day change in freshness."),
        ]
        return result
    }
}
