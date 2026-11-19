import Foundation
import Testing
@testable import AIService

@Suite("Four-layer repair behavior")
struct FourLayerRepairTests {
    @Test("All L1 metrics and deterministic as-of survive offline and zero keys")
    func completeAndMissing() async throws {
        let full = try testSnapshot()
        let expected = DeterministicFourLayerEngine().makeReport(from: full)
        #expect(expected.l1.count >= 38)
        for metric in ["rhrBaselineDelta", "hrv7d", "hrvBaseline60d", "zone1", "zone5", "heartRateRecovery2m", "remSleep", "coreSleep", "awakeSleep", "sleepEfficiency", "sleepDebt14d", "nonExerciseEnergy", "standDuration", "movementConsistency", "aerobicDecoupling", "vo2MaxTrend", "acuteTrainingLoad", "chronicTrainingLoad", "workloadRatio", "ctlDelta14d"] {
            #expect(expected.l1.contains { $0.metric == metric })
        }
        #expect(expected.generatedAt == full.generatedAt)
        #expect(await FourLayerAdviceEngine().generate(snapshot: full) == expected)
        #expect(await FourLayerAdviceEngine(provider: ReplyProvider { _ in throw URLError(.notConnectedToInternet) }).generate(snapshot: full) == expected)
        let unconfiguredURL = try #require(URL(string: "https://unconfigured.invalid/v1"))
        #expect(await FourLayerAdviceEngine(provider: OpenAICompatibleProvider(baseURL: unconfiguredURL, model: "synthetic")).generate(snapshot: full) == expected)

        let missing = try testSnapshot("missing-snapshot")
        let report = await FourLayerAdviceEngine().generate(snapshot: missing)
        #expect(report.l1.allSatisfy { $0.value == nil && $0.severity == .watch && $0.message.contains("Unknown") })
        #expect(report.l3.autonomicScore == 40 && report.l3.sleepRestorationScore == 40 && report.l3.fatigueBalanceScore == 40)
        #expect(report.l3.readinessScore < 50 && report.l3.recommendedIntensityCap <= 0.6)
        #expect(!report.l4.directive.isEmpty && (1...3).contains(report.l4.prioritizedActions.count))
        #expect(report == DeterministicFourLayerEngine().makeReport(from: missing))
        let steps = DeterministicFourLayerEngine().makeReport(from: try testSnapshot("steps-snapshot"))
        #expect(steps.l1.first { $0.metric == "dailySteps" }?.value == 1200)
        #expect(steps.l1.filter { $0.domain != .neat }.allSatisfy { $0.value == nil })
        #expect(steps.l3.sleepRestorationScore == 40)
        let legacyEmpty = PhysiologicalSnapshot(
            heart: missing.heart,
            sleep: .init(architecture: .init(), debt: .init(sevenDayDebt: 0, fourteenDayDebt: 0, baselineSleepDuration: 0, targetSleepDuration: 28_800)),
            neat: missing.neat, aerobic: missing.aerobic, trainingLoad: missing.trainingLoad, generatedAt: missing.generatedAt
        )
        let legacyReport = DeterministicFourLayerEngine().makeReport(from: legacyEmpty)
        #expect(legacyReport.l3.sleepRestorationScore == 40)
        #expect(legacyReport.l1.filter { $0.domain == .sleep }.allSatisfy { $0.value == nil })
        let absentRolling = DeterministicFourLayerEngine().makeReport(from: try changing(full, ["heart", "hrvCorridor", "sevenDaySampleCount"], 0))
        #expect(absentRolling.l1.first { $0.metric == "hrv7d" }?.value == nil)
    }

    @Test("RHR baseline, acute/rolling HRV and both HRR observations affect readiness")
    func autonomicConsequences() throws {
        let snapshot = try testSnapshot()
        let engine = DeterministicFourLayerEngine()
        let baseline = engine.makeReport(from: snapshot)
        for (path, value) in [
            (["heart", "restingHeartRate", "currentBPM"], 85.0),
            (["heart", "hrvCorridor", "currentMilliseconds"], 18.0),
            (["heart", "hrvCorridor", "sevenDayAverageMilliseconds"], 25.0),
            (["heart", "recovery", "oneMinuteBPM"], 168.0),
            (["heart", "recovery", "twoMinuteBPM"], 168.0),
        ] {
            let report = engine.makeReport(from: try changing(snapshot, path, value))
            #expect(report.l3.autonomicScore < baseline.l3.autonomicScore)
            #expect(report.l3.readinessScore < baseline.l3.readinessScore)
        }
    }

    @Test("Sleep restoration and load/intensity each change their coupling's consequence")
    func sleepLoadCoupling() throws {
        let full = try testSnapshot()
        let engine = DeterministicFourLayerEngine()
        var poor = try changing(full, ["sleep", "architecture", "deepDuration"], 0)
        poor = try changing(poor, ["sleep", "architecture", "remDuration"], 0)
        poor = try changing(poor, ["sleep", "architecture", "sleepEfficiency"], 0.4)
        poor = try changing(poor, ["sleep", "debt", "sevenDayDebt"], 50_000)
        let poorReport = engine.makeReport(from: poor)
        let goodReport = engine.makeReport(from: full)
        #expect(poorReport.l3.sleepRestorationScore < goodReport.l3.sleepRestorationScore)
        #expect(poorReport.l2[0].severity == .warning && goodReport.l2[0].severity == .normal)
        #expect(couplingCost(poorReport) > couplingCost(goodReport))
        for stage in ["deepDuration", "remDuration"] {
            #expect(engine.makeReport(from: try changing(full, ["sleep", "architecture", stage], 0)).l3.sleepRestorationScore < goodReport.l3.sleepRestorationScore)
        }
        var heavy = try changing(poor, ["trainingLoad", "acuteTrainingLoad"], 90)
        heavy = try changing(heavy, ["trainingLoad", "trainingStressBalance"], -40)
        heavy = try changing(heavy, ["trainingLoad", "acuteChronicWorkloadRatio"], 1.8)
        let heavyReport = engine.makeReport(from: heavy)
        #expect(heavyReport.l3.readinessScore < poorReport.l3.readinessScore)
        #expect(couplingCost(heavyReport) > couplingCost(poorReport))
        #expect(heavyReport.l3.recommendedIntensityCap < poorReport.l3.recommendedIntensityCap)
        // Same load and sleep, but more Zone 4/5 exposure must amplify the coupling.
        var intensive = try changing(poor, ["heart", "zoneDistribution", "durationsByZone"], ["zone1", 0, "zone2", 0, "zone3", 0, "zone4", 3000, "zone5", 600])
        let intensiveReport = engine.makeReport(from: intensive)
        #expect(intensiveReport.l3.readinessScore < poorReport.l3.readinessScore)
        intensive = try changing(intensive, ["sleep", "debt", "observedNightCount7d"], 1)
        #expect(engine.makeReport(from: intensive).l3.sleepRestorationScore <= intensiveReport.l3.sleepRestorationScore)
    }

    @Test("Movement/energy burden and body recovery both change steps coupling")
    func movementRecoveryCoupling() throws {
        let full = try testSnapshot()
        let engine = DeterministicFourLayerEngine()
        var exhausted = try changing(full, ["heart", "restingHeartRate", "currentBPM"], 90)
        exhausted = try changing(exhausted, ["trainingLoad", "trainingStressBalance"], -35)
        let moderate = engine.makeReport(from: exhausted)
        let highBurden = try changing(exhausted, ["neat", "nonExerciseActiveEnergy"], 1500)
        let burdenReport = engine.makeReport(from: highBurden)
        #expect(burdenReport.l2[1].severity == .warning && moderate.l2[1].severity == .normal)
        #expect(burdenReport.l3.readinessScore < moderate.l3.readinessScore)
        let recovered = engine.makeReport(from: try changing(full, ["neat", "nonExerciseActiveEnergy"], 1500))
        #expect(recovered.l2[1].severity == .normal)
        #expect(recovered.l3.readinessScore > burdenReport.l3.readinessScore)
        #expect(couplingCost(burdenReport) > couplingCost(recovered))
        #expect(recovered.l2[1].message.contains("without inferring caloric balance"))
    }

    @Test("Normalized load trajectories select all four mesocycle phases")
    func phases() throws {
        let engine = DeterministicFourLayerEngine()
        let snapshot = try testSnapshot()
        for (phase, atl, ratio, atlDelta, ctlDelta, tsbDelta) in [
            (MesocyclePhase.accumulation, 50.0, 1.0, 0.0, 2.0, 0.0),
            (.intensification, 60, 1.2, 8, 2, -6),
            (.realization, 40, 0.8, -15, 0, 15),
            (.deload, 90, 1.8, 35, 3, -32),
        ] {
            var value = try changing(snapshot, ["trainingLoad", "recentTrajectory"], [])
            for (key, number) in [("acuteTrainingLoad", atl), ("trainingStressBalance", 50 - atl), ("acuteChronicWorkloadRatio", ratio), ("atlDelta7d", atlDelta), ("ctlDelta7d", ctlDelta), ("tsbDelta7d", tsbDelta)] {
                value = try changing(value, ["trainingLoad", key], number)
            }
            #expect(engine.makeReport(from: value).l3.mesocyclePhase == phase)
        }
        // Trajectory overrides zero legacy deltas; future points cannot select a phase.
        var taper = try changing(snapshot, ["trainingLoad", "acuteTrainingLoad"], 40)
        taper = try changing(taper, ["trainingLoad", "acuteChronicWorkloadRatio"], 0.8)
        taper = try changing(taper, ["trainingLoad", "recentTrajectory"], [
            ["date": 0, "dailyLoad": 50, "acuteTrainingLoad": 60, "chronicTrainingLoad": 50, "trainingStressBalance": -10],
            ["date": 86400, "dailyLoad": 0, "acuteTrainingLoad": 40, "chronicTrainingLoad": 50, "trainingStressBalance": 10],
            ["date": 200000, "dailyLoad": 200, "acuteTrainingLoad": 100, "chronicTrainingLoad": 50, "trainingStressBalance": -50],
        ])
        #expect(engine.makeReport(from: taper).l3.mesocyclePhase == .realization)
    }

    @Test("Semantic invalid JSON cannot be rescued by DTO clamping/defaults")
    func rejectsSemantics() async throws {
        let snapshot = try testSnapshot()
        let local = DeterministicFourLayerEngine().makeReport(from: snapshot)
        let candidateData = try jsonChanging(JSONEncoder().encode(local), ["l4", "directive"], "Candidate must be rejected, never silently clamped.")
        let mutations: [([String], Any)] = [
            (["l1"], []), (["l2"], []), (["l1"], [["domain": "heart", "metric": "x", "message": "", "severity": "normal"]]),
            (["l3", "readinessScore"], -1), (["l3", "autonomicScore"], 101),
            (["l3", "sleepRestorationScore"], NSNull()), (["l3", "fatigueBalanceScore"], 999),
            (["l3", "recommendedIntensityCap"], 1.1), (["l3", "recommendedIntensityCap"], "NaN"),
            (["l3", "recommendedIntensityCap"], -0.1), (["l3", "readinessScore"], 50.5),
            (["l3", "contributingInsights"], []), (["l3", "contributingInsights"], [" "]),
            (["l3", "mesocyclePhase"], "unsupported"), (["l4", "northStarScore"], 500),
            (["l4", "directive"], " \n"), (["l4", "prioritizedActions"], []),
            (["l4", "prioritizedActions"], ["a", "b", "c", "d"]), (["l4", "prioritizedActions"], [" "]),
            (["generatedAt"], 1e300),
        ]
        for (path, value) in mutations {
            let bad = try jsonChanging(candidateData, path, value)
            let engine = FourLayerAdviceEngine(provider: ReplyProvider { _ in String(decoding: bad, as: UTF8.self) })
            #expect(await engine.generate(snapshot: snapshot) == local, "Rejected path: \(path)")
        }
        var absent = try #require(JSONSerialization.jsonObject(with: candidateData) as? [String: Any])
        var l3 = try #require(absent["l3"] as? [String: Any])
        l3.removeValue(forKey: "autonomicScore")
        absent["l3"] = l3
        let absentData = try JSONSerialization.data(withJSONObject: absent)
        #expect(await FourLayerAdviceEngine(provider: ReplyProvider { _ in String(decoding: absentData, as: UTF8.self) }).generate(snapshot: snapshot) == local)
        var l2 = local.l2
        l2[1] = l2[0]
        let duplicate = HolisticFourLayerReport(l1: local.l1, l2: l2, l3: local.l3, l4: local.l4, generatedAt: local.generatedAt)
        let duplicateData = try JSONEncoder().encode(duplicate)
        #expect(await FourLayerAdviceEngine(provider: ReplyProvider { _ in String(decoding: duplicateData, as: UTF8.self) }).generate(snapshot: snapshot) == local)
    }

    @Test("Valid model response is accepted with schema-explicit prompt")
    func validAndPrompt() async throws {
        let snapshot = try testSnapshot()
        let local = DeterministicFourLayerEngine().makeReport(from: snapshot)
        let data = try jsonChanging(JSONEncoder().encode(local), ["l4", "directive"], "Model-specific cohesive coaching narrative.")
        let engine = FourLayerAdviceEngine(provider: ReplyProvider { messages in
            let system = try #require(messages.first?.content)
            #expect(system.contains("autonomicScore") && system.contains("sleepTrainingCoupling") && system.contains("0...100"))
            let input = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: Data(try #require(messages.last?.content).utf8))
            #expect(input == snapshot)
            return String(decoding: data, as: UTF8.self)
        })
        #expect(await engine.generate(snapshot: snapshot).l4.directive == "Model-specific cohesive coaching narrative.")
    }

    @Test("Cancellable facade propagates cancellation; legacy facade returns deterministic advice")
    func cancellation() async throws {
        let snapshot = try testSnapshot()
        let engine = FourLayerAdviceEngine(provider: ReplyProvider { _ in throw CancellationError() })
        await #expect(throws: CancellationError.self) { try await engine.generateCancellable(snapshot: snapshot) }
        #expect(await engine.generate(snapshot: snapshot) == DeterministicFourLayerEngine().makeReport(from: snapshot))
        let task = Task { () throws -> HolisticFourLayerReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.generateCancellable(snapshot: snapshot)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

struct ReplyProvider: AIProvider {
    let reply: @Sendable ([ChatMessage]) async throws -> String
    init(_ reply: @escaping @Sendable ([ChatMessage]) async throws -> String) { self.reply = reply }
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        ChatResponse(content: try await reply(messages), model: model ?? "synthetic")
    }
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIServiceError.noProviderAvailable) }
    }
}

func testSnapshot(_ name: String = "full-snapshot") throws -> PhysiologicalSnapshot {
    try JSONDecoder().decode(PhysiologicalSnapshot.self, from: wireFixture(name))
}

private func couplingCost(_ report: HolisticFourLayerReport) -> Int {
    (report.l3.autonomicScore + report.l3.sleepRestorationScore + report.l3.fatigueBalanceScore) / 3 - report.l3.readinessScore
}

private func changing(_ snapshot: PhysiologicalSnapshot, _ path: [String], _ value: Any) throws -> PhysiologicalSnapshot {
    try JSONDecoder().decode(PhysiologicalSnapshot.self, from: jsonChanging(JSONEncoder().encode(snapshot), path, value))
}

private func jsonChanging(_ data: Data, _ path: [String], _ value: Any) throws -> Data {
    func change(_ object: [String: Any], _ path: ArraySlice<String>) -> [String: Any] {
        guard let key = path.first else { return object }
        var result = object
        if path.count == 1 { result[key] = value }
        else if let child = object[key] as? [String: Any] { result[key] = change(child, path.dropFirst()) }
        return result
    }
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try JSONSerialization.data(withJSONObject: change(object, path[...]), options: [.sortedKeys])
}
