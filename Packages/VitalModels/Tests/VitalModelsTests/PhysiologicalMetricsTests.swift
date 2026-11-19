import Foundation
import Testing
@testable import VitalModels

@Suite("Physiological metrics DTOs")
struct PhysiologicalMetricsTests {
    @Test("All metric DTOs round-trip through Codable")
    func roundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let heart = HeartDomainSnapshot(
            restingHeartRate: RestingHeartRateSummary(averageBPM: 58, minimumBPM: 54, maximumBPM: 62, sampleCount: 7, periodStart: date, periodEnd: date),
            hrvCorridor: HRVCorridorSnapshot(baselineMilliseconds: 48, lowerBoundMilliseconds: 35, upperBoundMilliseconds: 61, sampleCount: 7),
            zoneDistribution: HeartRateZoneDistribution(zone1: 60, zone2: 120, zone3: 30, zone4: 20, zone5: 5),
            recovery: HeartRateRecoveryMetric(baselineBPM: 170, oneMinuteBPM: 125, twoMinuteBPM: 105)
        )
        let sleep = SleepDomainSnapshot(
            architecture: SleepArchitectureSnapshot(deepDuration: 4_800, remDuration: 5_400, coreDuration: 18_000, awakeDuration: 1_200, totalSleepDuration: 28_200, sleepEfficiency: 0.96),
            debt: SleepDebtSummary(sevenDayDebt: 3_600, fourteenDayDebt: 7_200, baselineSleepDuration: 25_200, targetSleepDuration: 28_800)
        )
        let snapshot = PhysiologicalSnapshot(
            heart: heart,
            sleep: sleep,
            neat: NEATActivitySnapshot(dailySteps: 8_000, nonExerciseActiveEnergy: 420, basalEnergy: 1_600, hourlyMovementConsistency: 0.75, flightsClimbed: 8),
            aerobic: AerobicEfficiencySnapshot(efficiencyFactor: 0.12, aerobicDecouplingPercentage: 3.2, vo2Max: 48, vo2MaxTrend: 1.1, sampleCount: 5),
            trainingLoad: TrainingLoadSnapshot(acuteTrainingLoad: 80, chronicTrainingLoad: 70, trainingStressBalance: -10, acuteChronicWorkloadRatio: 1.14, trimp: 50, tss: 30),
            generatedAt: date
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.heart.zoneDistribution.zone5Duration == 5)
        #expect(decoded.trainingLoad.TSB == -10)
    }

    @Test("Advice report keeps readiness and actions bounded")
    func adviceBounds() {
        let l3 = L3ReadinessAndCycleInsight(readinessScore: 120, mesocyclePhase: .deload, recommendedIntensityCap: -1)
        let l4 = L4HolisticNorthStarInsight(northStarScore: -10, directive: "recover", prioritizedActions: ["a", "b", "c", "d"])
        #expect(l3.readinessScore == 100)
        #expect(l3.recommendedIntensityCap == 0)
        #expect(l4.northStarScore == 0)
        #expect(l4.prioritizedActions.count == 3)
    }
}
