import Foundation

/// Offline rule engine used when a network or on-device model cannot answer.
public struct DeterministicFourLayerEngine: AIProvider, Sendable {
    public init() {}

    public func makeReport(from snapshot: PhysiologicalSnapshot, generatedAt: Date = Date()) -> HolisticFourLayerReport {
        let l1 = makeL1(snapshot)
        let l2 = makeL2(snapshot)
        let autonomicScore = autonomicScore(snapshot.heart)
        let sleepScore = sleepRestorationScore(snapshot.sleep)
        let fatigueScore = fatigueBalanceScore(snapshot.trainingLoad)
        let readiness = (autonomicScore + sleepScore + fatigueScore) / 3
        let phase = mesocyclePhase(snapshot.trainingLoad)
        let l3 = L3ReadinessAndCycleInsight(
            readinessScore: readiness,
            autonomicScore: autonomicScore,
            sleepRestorationScore: sleepScore,
            fatigueBalanceScore: fatigueScore,
            mesocyclePhase: phase,
            recommendedIntensityCap: intensityCap(for: readiness),
            contributingInsights: l2.map(\.message)
        )
        let northStar = clamp((readiness + aerobicScore(snapshot.aerobic) + movementScore(snapshot.neat)) / 3)
        let l4 = L4HolisticNorthStarInsight(
            northStarScore: northStar,
            directive: directive(for: readiness, phase: phase),
            prioritizedActions: actions(for: readiness, snapshot: snapshot)
        )
        return HolisticFourLayerReport(l1: l1, l2: l2, l3: l3, l4: l4, generatedAt: generatedAt)
    }

    public func generate(snapshot: PhysiologicalSnapshot) async -> HolisticFourLayerReport {
        makeReport(from: snapshot)
    }

    public func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        guard let content = messages.last(where: { $0.role == "user" })?.content,
              let data = content.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(PhysiologicalSnapshot.self, from: data) else {
            return ChatResponse(content: "Deterministic fallback is available.", model: "deterministic-fallback")
        }
        let report = makeReport(from: snapshot)
        let encoded = try JSONEncoder().encode(report)
        guard let reportContent = String(data: encoded, encoding: .utf8) else {
            throw AIServiceError.responseParsingFailed
        }
        return ChatResponse(content: reportContent, model: "deterministic-fallback")
    }

    public func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await chat(messages: messages, model: model)
                    continuation.yield(ChatStreamChunk(content: response.content))
                    continuation.yield(ChatStreamChunk(content: "", isFinished: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeL1(_ snapshot: PhysiologicalSnapshot) -> [L1SingleMetricInsight] {
        [
            L1SingleMetricInsight(domain: .heart, metric: "restingHeartRate", value: snapshot.heart.restingHeartRate.averageBPM, severity: rhrSeverity(snapshot.heart.restingHeartRate), message: "Resting heart rate status"),
            L1SingleMetricInsight(domain: .heart, metric: "hrvCorridor", value: snapshot.heart.hrvCorridor.baselineMilliseconds, severity: snapshot.heart.hrvCorridor.isWithinCorridor ? .normal : .watch, message: "Heart-rate variability corridor status"),
            L1SingleMetricInsight(domain: .heart, metric: "heartRateRecovery", value: snapshot.heart.recovery.oneMinuteDropBPM, severity: recoverySeverity(snapshot.heart.recovery), message: "Heart-rate recovery status"),
            L1SingleMetricInsight(domain: .sleep, metric: "deepSleep", value: snapshot.sleep.architecture.deepDuration, severity: snapshot.sleep.architecture.deepDuration > 0 ? .normal : .watch, message: "Deep sleep status"),
            L1SingleMetricInsight(domain: .sleep, metric: "sleepDebt", value: snapshot.sleep.debt.sevenDayDebt, severity: snapshot.sleep.debt.sevenDayDebt > snapshot.sleep.debt.targetSleepDuration ? .warning : .normal, message: "Sleep debt status"),
            L1SingleMetricInsight(domain: .neat, metric: "dailySteps", value: snapshot.neat.dailySteps, severity: snapshot.neat.dailySteps > 0 ? .normal : .watch, message: "Daily movement status"),
            L1SingleMetricInsight(domain: .aerobic, metric: "efficiencyFactor", value: snapshot.aerobic.efficiencyFactor, severity: snapshot.aerobic.efficiencyFactor == nil ? .watch : .normal, message: "Aerobic efficiency status"),
            L1SingleMetricInsight(domain: .trainingLoad, metric: "trainingStressBalance", value: snapshot.trainingLoad.trainingStressBalance, severity: loadSeverity(snapshot.trainingLoad), message: "Training load balance status"),
        ]
    }

    private func makeL2(_ snapshot: PhysiologicalSnapshot) -> [L2CoupledInsight] {
        let sleepSeverity: InsightSeverity = snapshot.sleep.debt.sevenDayDebt > snapshot.sleep.debt.targetSleepDuration ? .warning : .normal
        let recoverySeverity = snapshot.trainingLoad.trainingStressBalance < -20 ? InsightSeverity.warning : .normal
        return [
            L2CoupledInsight(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling", message: "Sleep restoration modulates training readiness", severity: sleepSeverity),
            L2CoupledInsight(primaryDomain: .neat, secondaryDomain: .trainingLoad, relationship: "stepsBodyCoupling", message: "Daily movement supports active recovery", severity: recoverySeverity),
        ]
    }

    private func autonomicScore(_ heart: HeartDomainSnapshot) -> Int {
        let corridorScore = heart.hrvCorridor.isWithinCorridor ? 70 : 35
        let rhrScore: Int
        if let minimum = heart.restingHeartRate.minimumBPM, let maximum = heart.restingHeartRate.maximumBPM {
            let spread = maximum - minimum
            rhrScore = spread <= 10 ? 30 : 15
        } else {
            rhrScore = 20
        }
        return clamp(corridorScore + rhrScore)
    }

    private func sleepRestorationScore(_ sleep: SleepDomainSnapshot) -> Int {
        let efficiency = clampUnit(sleep.architecture.sleepEfficiency) * 60
        let target = max(sleep.debt.targetSleepDuration, 1)
        let debtPenalty = min(sleep.debt.sevenDayDebt / target, 1) * 40
        return clamp(Int((efficiency - debtPenalty).rounded()))
    }

    private func fatigueBalanceScore(_ load: TrainingLoadSnapshot) -> Int {
        let normalized = (load.trainingStressBalance + 30) / 60
        return clamp(Int((normalized * 100).rounded()))
    }

    private func mesocyclePhase(_ load: TrainingLoadSnapshot) -> MesocyclePhase {
        if load.trainingStressBalance <= -20 { return .deload }
        if load.trainingStressBalance >= 15 { return .realization }
        if load.acuteTrainingLoad > load.chronicTrainingLoad { return .intensification }
        return .accumulation
    }

    private func intensityCap(for readiness: Int) -> Double {
        switch readiness {
        case 80...100: return 1
        case 60..<80: return 0.8
        case 40..<60: return 0.6
        default: return 0.4
        }
    }

    private func aerobicScore(_ aerobic: AerobicEfficiencySnapshot) -> Int {
        guard let trend = aerobic.vo2MaxTrend else { return 50 }
        return clamp(Int((50 + trend * 10).rounded()))
    }

    private func movementScore(_ neat: NEATActivitySnapshot) -> Int {
        let stepScore = min(neat.dailySteps / 10_000, 1) * 70
        let consistencyScore = clampUnit(neat.hourlyMovementConsistency) * 30
        return clamp(Int((stepScore + consistencyScore).rounded()))
    }

    private func directive(for readiness: Int, phase: MesocyclePhase) -> String {
        if readiness < 40 || phase == .deload { return "Prioritize recovery and low-intensity movement today." }
        if readiness < 60 { return "Keep training controlled and leave room for recovery." }
        return "Proceed with the planned session while monitoring recovery."
    }

    private func actions(for readiness: Int, snapshot: PhysiologicalSnapshot) -> [String] {
        var result: [String] = []
        if readiness < 60 { result.append("Reduce intensity and extend recovery between efforts.") }
        if snapshot.sleep.debt.sevenDayDebt > 0 { result.append("Protect tonight's sleep opportunity.") }
        if snapshot.neat.dailySteps < 6_000 { result.append("Add an easy movement break during the day.") }
        if result.isEmpty { result.append("Follow the planned session and maintain consistent recovery habits.") }
        return Array(result.prefix(3))
    }

    private func rhrSeverity(_ summary: RestingHeartRateSummary) -> InsightSeverity {
        guard let minimum = summary.minimumBPM, let maximum = summary.maximumBPM else { return .normal }
        return maximum - minimum > 15 ? .watch : .normal
    }

    private func recoverySeverity(_ metric: HeartRateRecoveryMetric) -> InsightSeverity {
        guard let drop = metric.oneMinuteDropBPM else { return .watch }
        return drop < 20 ? .warning : .normal
    }

    private func loadSeverity(_ load: TrainingLoadSnapshot) -> InsightSeverity {
        load.trainingStressBalance <= -20 ? .warning : .normal
    }

    private func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }
    private func clampUnit(_ value: Double) -> Double { min(max(value, 0), 1) }
}
