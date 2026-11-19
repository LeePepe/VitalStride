import Foundation
import Testing
@testable import VitalModels

@Suite("Physiological metrics DTOs")
struct PhysiologicalMetricsTests {
    @Test("All metric DTOs round-trip through Codable")
    func roundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let heart = HeartDomainSnapshot(
            restingHeartRate: RestingHeartRateSummary(
                averageBPM: 58,
                minimumBPM: 54,
                maximumBPM: 62,
                sampleCount: 7,
                periodStart: date,
                periodEnd: date,
                currentBPM: 57,
                sevenDayAverageBPM: 58,
                baselineBPM: 60,
                baselineDayCount: 30
            ),
            hrvCorridor: HRVCorridorSnapshot(
                baselineMilliseconds: 48,
                lowerBoundMilliseconds: 35,
                upperBoundMilliseconds: 61,
                sampleCount: 30,
                periodStart: date,
                periodEnd: date,
                currentMilliseconds: 45,
                sevenDayAverageMilliseconds: 47,
                sevenDaySampleCount: 7,
                baselineDayCount: 30
            ),
            zoneDistribution: HeartRateZoneDistribution(
                zone1: 60,
                zone2: 120,
                zone3: 30,
                zone4: 20,
                zone5: 5,
                resolvedMaximumHeartRateBPM: 190
            ),
            recovery: HeartRateRecoveryMetric(
                baselineBPM: 170,
                oneMinuteBPM: 125,
                twoMinuteBPM: 105,
                workoutEndDate: date
            )
        )
        let night = SleepArchitectureSnapshot(
            deepDuration: 4_800,
            remDuration: 5_400,
            coreDuration: 18_000,
            awakeDuration: 1_200,
            totalSleepDuration: 28_200,
            sleepEfficiency: 0.96,
            periodStart: date,
            periodEnd: date.addingTimeInterval(29_400),
            inBedDuration: 29_400,
            nightDate: date
        )
        let sleep = SleepDomainSnapshot(
            architecture: night,
            debt: SleepDebtSummary(
                sevenDayDebt: 3_600,
                fourteenDayDebt: 7_200,
                baselineSleepDuration: 25_200,
                targetSleepDuration: 28_800,
                observedNightCount7d: 6,
                missingNightCount7d: 1,
                observedNightCount14d: 12,
                missingNightCount14d: 2,
                isAvailable: true
            ),
            recentNights: [night]
        )
        let trajectoryPoint = TrainingLoadDailyPoint(
            date: date,
            dailyLoad: 64,
            acuteTrainingLoad: 80,
            chronicTrainingLoad: 70,
            trainingStressBalance: -10
        )
        let snapshot = PhysiologicalSnapshot(
            heart: heart,
            sleep: sleep,
            neat: NEATActivitySnapshot(
                dailySteps: 8_000,
                nonExerciseActiveEnergy: 420,
                basalEnergy: 1_600,
                hourlyMovementConsistency: 0.75,
                flightsClimbed: 8,
                periodStart: date,
                periodEnd: date.addingTimeInterval(86_400),
                nonWorkoutSteps: 6_500,
                workoutActiveEnergyExcluded: 310,
                standDuration: 2_700,
                activeNonWorkoutHourCount: 9,
                hourlyNonWorkoutDistribution: [9: 800, 10: 650, 14: 900]
            ),
            aerobic: AerobicEfficiencySnapshot(
                efficiencyFactor: 0.12,
                aerobicDecouplingPercentage: 3.2,
                vo2Max: 48,
                vo2MaxTrend: 1.1,
                sampleCount: 5
            ),
            trainingLoad: TrainingLoadSnapshot(
                acuteTrainingLoad: 80,
                chronicTrainingLoad: 70,
                trainingStressBalance: -10,
                acuteChronicWorkloadRatio: 1.14,
                trimp: 50,
                tss: 30,
                atlDelta7d: 8,
                ctlDelta7d: 3,
                ctlDelta14d: 6,
                tsbDelta7d: -5,
                deduplicatedWorkoutCount: 1,
                recentTrajectory: [trajectoryPoint]
            ),
            generatedAt: date
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.heart.zoneDistribution.zone5Duration == 5)
        #expect(decoded.heart.zoneDistribution.resolvedMaximumHeartRateBPM == 190)
        #expect(decoded.heart.restingHeartRate.deltaFromBaselineBPM == -3)
        #expect(decoded.heart.hrvCorridor.isWithinCorridor == true)
        #expect(decoded.sleep.debt.sevenDayCoverageRatio == 6.0 / 7.0)
        #expect(decoded.neat.nonWorkoutSteps == 6_500)
        #expect(decoded.trainingLoad.TSB == -10)
        #expect(decoded.availableDomains == Set(InsightDomain.allCases))
    }

    @Test("HRVCorridorSnapshot evaluates actual current and 7d HRV against 60d corridor bounds")
    func hrvCorridorMembershipIsNotTautological() {
        let crashedToday = HRVCorridorSnapshot(
            baselineMilliseconds: 60,
            lowerBoundMilliseconds: 52,
            upperBoundMilliseconds: 68,
            sampleCount: 30,
            currentMilliseconds: 18,
            sevenDayAverageMilliseconds: 54,
            sevenDaySampleCount: 7,
            baselineDayCount: 30
        )
        #expect(crashedToday.isWithinCorridor == false)

        let crashedSevenDay = HRVCorridorSnapshot(
            baselineMilliseconds: 60,
            lowerBoundMilliseconds: 52,
            upperBoundMilliseconds: 68,
            sampleCount: 30,
            currentMilliseconds: 55,
            sevenDayAverageMilliseconds: 42,
            sevenDaySampleCount: 7,
            baselineDayCount: 30
        )
        #expect(crashedSevenDay.isWithinCorridor == false)

        let emptyCorridor = HRVCorridorSnapshot(
            baselineMilliseconds: 0,
            lowerBoundMilliseconds: 0,
            upperBoundMilliseconds: 0,
            sampleCount: 0
        )
        #expect(emptyCorridor.isAvailable == false)
        #expect(emptyCorridor.isWithinCorridor == false)
    }

    @Test("HolisticFourLayerReport and StrengthWorkoutSummaryInput round-trip and decode legacy payloads")
    func reportAndLegacyRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let report = HolisticFourLayerReport(
            l1: [
                L1SingleMetricInsight(domain: .heart, metric: "hrvCorridor", value: 46, severity: .watch, message: "HRV slightly below corridor")
            ],
            l2: [
                L2CoupledInsight(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling", message: "Sleep debt requires load cap", severity: .warning),
                L2CoupledInsight(primaryDomain: .neat, secondaryDomain: .trainingLoad, relationship: "stepsBodyCoupling", message: "Maintain light NEAT circulation", severity: .normal)
            ],
            l3: L3ReadinessAndCycleInsight(
                readinessScore: 72,
                autonomicScore: 68,
                sleepRestorationScore: 74,
                fatigueBalanceScore: 75,
                mesocyclePhase: .accumulation,
                recommendedIntensityCap: 0.8,
                contributingInsights: ["Sleep debt requires load cap"]
            ),
            l4: L4HolisticNorthStarInsight(
                northStarScore: 76,
                directive: "Proceed with moderate aerobic and strength work.",
                prioritizedActions: ["Cap RPE at 8", "Extend sleep by 45m"]
            ),
            generatedAt: date
        )
        let encodedReport = try JSONEncoder().encode(report)
        let decodedReport = try JSONDecoder().decode(HolisticFourLayerReport.self, from: encodedReport)
        #expect(decodedReport == report)

        let legacyL3JSON = """
        {
          "readinessScore": 64,
          "mesocyclePhase": "intensification",
          "recommendedIntensityCap": 0.75
        }
        """.data(using: .utf8)!
        let decodedLegacyL3 = try JSONDecoder().decode(L3ReadinessAndCycleInsight.self, from: legacyL3JSON)
        #expect(decodedLegacyL3.readinessScore == 64)
        #expect(decodedLegacyL3.autonomicScore == 0)
        #expect(decodedLegacyL3.sleepRestorationScore == 0)
        #expect(decodedLegacyL3.fatigueBalanceScore == 0)
        #expect(decodedLegacyL3.contributingInsights.isEmpty)

        let legacyStrengthJSON = """
        {
          "startDate": 1700000000,
          "endDate": 1700003600,
          "workingVolume": 8500,
          "setCount": 14,
          "estimatedRPE": 8.0
        }
        """.data(using: .utf8)!
        let decodedLegacyStrength = try JSONDecoder().decode(StrengthWorkoutSummaryInput.self, from: legacyStrengthJSON)
        #expect(decodedLegacyStrength.workingVolume == 8_500)
        #expect(decodedLegacyStrength.setCount == 14)
        #expect(decodedLegacyStrength.estimatedRPE == 8.0)
        #expect(decodedLegacyStrength.healthKitUUID == nil)
    }

    @Test("SwiftData Workout projects into actor-safe StrengthWorkoutSummaryInput")
    func workoutStrengthProjection() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)
        let warmup = ExerciseSet(order: 0, weight: 60, reps: 10, setType: .warmup, isCompleted: true, rpe: 5)
        let working1 = ExerciseSet(order: 1, weight: 100, reps: 8, setType: .working, isCompleted: true, rpe: 8)
        let working2 = ExerciseSet(order: 2, weight: 40, reps: 10, setType: .working, isCompleted: true, isUnilateral: true, weightRight: 45, rpe: 9)
        let exercise = WorkoutExercise(order: 0, sets: [warmup, working1, working2])
        let workout = Workout(
            type: .strength,
            startDate: start,
            endDate: end,
            source: .recorded,
            healthKitUUID: "11111111-2222-3333-4444-555555555555",
            exercises: [exercise]
        )
        exercise.workout = workout

        let summary = workout.strengthSummaryInput
        #expect(summary != nil)
        #expect(summary?.startDate == start)
        #expect(summary?.endDate == end)
        // working1 = 800, working2 unilateral = 40*10 + 45*10 = 850 => 1650 (warmup excluded)
        #expect(summary?.workingVolume == 1_650)
        #expect(summary?.setCount == 2)
        #expect(summary?.estimatedRPE == 8.5)
        #expect(summary?.healthKitUUID == "11111111-2222-3333-4444-555555555555")

        let inProgress = Workout(type: .strength, startDate: start, endDate: nil, source: .recorded, exercises: [])
        #expect(inProgress.strengthSummaryInput == nil)
    }

    @Test("Non-finite numbers are sanitized so JSON encoding never traps")
    func nonFiniteSanitization() throws {
        let heart = HeartDomainSnapshot(
            restingHeartRate: RestingHeartRateSummary(averageBPM: .nan, minimumBPM: .infinity, maximumBPM: -.infinity, sampleCount: 0),
            hrvCorridor: HRVCorridorSnapshot(baselineMilliseconds: .infinity, lowerBoundMilliseconds: .nan, upperBoundMilliseconds: .nan),
            zoneDistribution: HeartRateZoneDistribution(zone1: .nan, zone2: .infinity, zone3: -10, zone4: 0, zone5: 30, resolvedMaximumHeartRateBPM: .nan),
            recovery: HeartRateRecoveryMetric(baselineBPM: .nan, oneMinuteBPM: .infinity, twoMinuteBPM: -5)
        )
        let sleep = SleepDomainSnapshot(
            architecture: SleepArchitectureSnapshot(deepDuration: .nan, remDuration: .infinity, coreDuration: -1, awakeDuration: 0, totalSleepDuration: 0, sleepEfficiency: .nan),
            debt: SleepDebtSummary(sevenDayDebt: .nan, fourteenDayDebt: .infinity, baselineSleepDuration: -1, targetSleepDuration: 28_800, observedNightCount7d: 0, missingNightCount7d: 7, observedNightCount14d: 0, missingNightCount14d: 14, isAvailable: false)
        )
        let snapshot = PhysiologicalSnapshot(
            heart: heart,
            sleep: sleep,
            neat: NEATActivitySnapshot(dailySteps: .nan, nonExerciseActiveEnergy: .infinity, basalEnergy: -5, hourlyMovementConsistency: .nan, flightsClimbed: .nan),
            aerobic: AerobicEfficiencySnapshot(efficiencyFactor: .nan, aerobicDecouplingPercentage: .infinity, vo2Max: -10, vo2MaxTrend: .nan, sampleCount: 0),
            trainingLoad: TrainingLoadSnapshot(acuteTrainingLoad: .nan, chronicTrainingLoad: .infinity, trainingStressBalance: .nan, acuteChronicWorkloadRatio: .nan, trimp: .nan, tss: .infinity)
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: encoded)
        #expect(decoded.heart.zoneDistribution.zone5Duration == 30)
        #expect(decoded.heart.restingHeartRate.isAvailable == false)
        #expect(decoded.sleep.isAvailable == false)
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
