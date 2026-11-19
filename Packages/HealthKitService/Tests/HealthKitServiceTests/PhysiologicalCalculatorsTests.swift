import Foundation
import Testing
import VitalModels
@testable import HealthKitService

@Suite("Physiological calculators")
struct PhysiologicalCalculatorsTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(
        _ type: HealthSampleType,
        value: Double,
        offset: TimeInterval = 0,
        duration: TimeInterval = 60,
        stage: SleepStage? = nil
    ) -> HealthDataPoint {
        let begin = start.addingTimeInterval(offset)
        return HealthDataPoint(id: UUID(), sampleType: type, startDate: begin, endDate: begin.addingTimeInterval(duration), value: value, unit: type.unitString, sleepStage: stage, sourceName: nil)
    }

    @Test("Heart and NEAT metrics are calculated without side effects")
    func heartAndNeat() {
        let points = [
            point(.restingHeartRate, value: 55),
            point(.restingHeartRate, value: 65, offset: 60),
            point(.heartRateVariabilitySDNN, value: 40),
            point(.heartRateVariabilitySDNN, value: 60, offset: 60),
            point(.heartRate, value: 130, duration: 120),
            point(.heartRate, value: 180, offset: 120, duration: 60),
            point(.stepCount, value: 4_000),
            point(.activeEnergyBurned, value: 300),
            point(.basalEnergyBurned, value: 1_500),
            point(.flightsClimbed, value: 6)
        ]
        let calculator = HealthMetricsCalculator()
        let resting = calculator.restingHeartRateSummary(from: points)
        let corridor = calculator.hrvCorridor(from: points)
        let zones = calculator.heartRateZones(from: points, maximumHeartRate: 200)
        let neat = calculator.neatSnapshot(from: points)
        #expect(resting?.averageBPM == 60)
        #expect(corridor?.baselineMilliseconds == 50)
        #expect(zones.zone2Duration == 120)
        #expect(zones.zone5Duration == 60)
        #expect(neat.dailySteps == 4_000)
        #expect(neat.nonExerciseActiveEnergy == 300)
        #expect(neat.basalEnergy == 1_500)
    }

    @Test("Sleep analyzer computes architecture, efficiency, and debt")
    func sleep() {
        let points = [
            point(.sleepAnalysis, value: 1, duration: 3_600, stage: .asleepDeep),
            point(.sleepAnalysis, value: 1, offset: 3_600, duration: 3_600, stage: .asleepREM),
            point(.sleepAnalysis, value: 1, offset: 7_200, duration: 14_400, stage: .asleepCore),
            point(.sleepAnalysis, value: 1, offset: 21_600, duration: 1_800, stage: .awake),
            point(.sleepAnalysis, value: 1, offset: 23_400, duration: 600, stage: .inBed)
        ]
        let analyzer = SleepArchitectureAnalyzer()
        let snapshot = analyzer.analyze(points: points, targetSleepDuration: 28_800)
        let debt = analyzer.debtSummary(nights: [snapshot!], targetSleepDuration: 28_800)
        #expect(snapshot?.deepDuration == 3_600)
        #expect(snapshot?.remDuration == 3_600)
        #expect(snapshot?.coreDuration == 14_400)
        #expect(snapshot?.totalSleepDuration == 21_600)
        #expect(snapshot?.sleepEfficiency ?? 0 > 0.9)
        #expect(debt.sevenDayDebt == 7_200)
    }

    @Test("Aerobic efficiency and training load expose deterministic formulas")
    func aerobicAndTrainingLoad() {
        let points = [
            point(.distanceWalkingRunning, value: 5_000, duration: 1_800),
            point(.heartRate, value: 150, duration: 900),
            point(.heartRate, value: 155, offset: 900, duration: 900),
            point(.vo2Max, value: 45),
            point(.vo2Max, value: 47, offset: 86_400)
        ]
        let aerobic = AerobicEfficiencyCalculator().calculate(from: points)
        let training = TrainingLoadCalculator()
        let input = StrengthWorkoutSummaryInput(startDate: start, endDate: start.addingTimeInterval(3_600), workingVolume: 10_000, setCount: 12, estimatedRPE: 8)
        let load = training.calculate(workouts: [], strengthWorkouts: [input], asOf: start)
        #expect(aerobic?.efficiencyFactor != nil)
        #expect(aerobic?.vo2Max == 47)
        #expect(aerobic?.vo2MaxTrend == 2)
        #expect(load.tss > 0)
        #expect(load.CTL == load.chronicTrainingLoad)
        #expect(load.TSB == load.CTL - load.ATL)
    }
}
