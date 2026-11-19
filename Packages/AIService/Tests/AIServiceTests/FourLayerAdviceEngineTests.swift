import Foundation
import Testing
@testable import AIService

@Suite("Four-layer advice engine")
struct FourLayerAdviceEngineTests {
    @Test("deterministic engine emits all four layers and two couplings")
    func deterministicReport() async {
        let engine = DeterministicFourLayerEngine()
        let report = await engine.generate(snapshot: snapshot())

        #expect(!report.l1.isEmpty)
        #expect(report.l2.map(\.relationship) == ["sleepTrainingCoupling", "stepsBodyCoupling"])
        #expect((0...100).contains(report.l3.readinessScore))
        #expect((0...100).contains(report.l3.autonomicScore))
        #expect(report.l4.prioritizedActions.count <= 3)
    }

    @Test("malformed model output falls back to deterministic report")
    func malformedOutputFallsBack() async {
        let report = await FourLayerAdviceEngine(provider: StubProvider(content: "not-json"))
            .generate(snapshot: snapshot())
        #expect(!report.l1.isEmpty)
        #expect(report.l2.count == 2)
    }

    @Test("valid model output is decoded without changing the wire shape")
    func validModelOutput() async throws {
        let expected = DeterministicFourLayerEngine().makeReport(from: snapshot())
        let content = try #require(String(data: JSONEncoder().encode(expected), encoding: .utf8))
        let report = await FourLayerAdviceEngine(provider: StubProvider(content: content))
            .generate(snapshot: snapshot())
        #expect(report == expected)
    }

    @Test("configuration exposes all supported modes and keeps fallback local")
    func configurationModes() async throws {
        #expect(Set(PluggableAIProvider.allCases) == [.foundationModels, .customOpenAICompatible, .jevGateway, .deterministicFallback])
        let config = UserAIModelConfiguration(provider: .deterministicFallback)
        let provider = config.makeProvider()
        let response = try await provider.chat(messages: [ChatMessage(role: "user", content: "hello")], model: nil)
        #expect(response.model == "deterministic-fallback")
        #expect(response.content.contains("available"))
    }

    private func snapshot() -> PhysiologicalSnapshot {
        PhysiologicalSnapshot(
            heart: HeartDomainSnapshot(
                restingHeartRate: RestingHeartRateSummary(averageBPM: 58, minimumBPM: 54, maximumBPM: 62),
                hrvCorridor: HRVCorridorSnapshot(baselineMilliseconds: 48, lowerBoundMilliseconds: 35, upperBoundMilliseconds: 61),
                zoneDistribution: HeartRateZoneDistribution(zone1: 60, zone2: 120, zone3: 30, zone4: 20, zone5: 5),
                recovery: HeartRateRecoveryMetric(baselineBPM: 170, oneMinuteBPM: 125)
            ),
            sleep: SleepDomainSnapshot(
                architecture: SleepArchitectureSnapshot(deepDuration: 4_800, remDuration: 5_400, coreDuration: 18_000, totalSleepDuration: 28_200, sleepEfficiency: 0.96),
                debt: SleepDebtSummary(sevenDayDebt: 3_600, fourteenDayDebt: 7_200, baselineSleepDuration: 25_200, targetSleepDuration: 28_800)
            ),
            neat: NEATActivitySnapshot(dailySteps: 8_000, nonExerciseActiveEnergy: 420, basalEnergy: 1_600, hourlyMovementConsistency: 0.75, flightsClimbed: 8),
            aerobic: AerobicEfficiencySnapshot(efficiencyFactor: 0.12, aerobicDecouplingPercentage: 3.2, vo2Max: 48, vo2MaxTrend: 1.1, sampleCount: 5),
            trainingLoad: TrainingLoadSnapshot(acuteTrainingLoad: 80, chronicTrainingLoad: 70, trainingStressBalance: -10, acuteChronicWorkloadRatio: 1.14, trimp: 50, tss: 30),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct StubProvider: AIProvider {
    let content: String

    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse {
        ChatResponse(content: content, model: "stub")
    }

    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ChatStreamChunk(content: content))
            continuation.finish()
        }
    }
}
