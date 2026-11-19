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
        unit: String? = nil,
        stage: SleepStage? = nil,
        sourceName: String? = nil
    ) -> HealthDataPoint {
        let begin = start.addingTimeInterval(offset)
        return HealthDataPoint(
            id: UUID(),
            sampleType: type,
            startDate: begin,
            endDate: begin.addingTimeInterval(duration),
            value: value,
            unit: unit ?? type.unitString,
            sleepStage: stage,
            sourceName: sourceName
        )
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

    @Test("HRV 7d/60d corridor detects acute crash, excludes >60d and future samples, and RHR computes baseline")
    func hrvCorridorAndRHRWindows() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let anchorDay = calendar.startOfDay(for: asOf)

        var points: [HealthDataPoint] = []
        // Out-of-window sample (75 days ago) that would distort mean if not excluded
        let dayMinus75 = calendar.date(byAdding: .day, value: -75, to: anchorDay)!
        points.append(
            HealthDataPoint(
                id: UUID(),
                sampleType: .heartRateVariabilitySDNN,
                startDate: dayMinus75.addingTimeInterval(28_800),
                endDate: dayMinus75.addingTimeInterval(28_860),
                value: 200,
                unit: "ms",
                sleepStage: nil,
                sourceName: nil
            )
        )

        // 59 prior days of steady HRV = 60 ms and RHR = 56 bpm
        for dayOffset in (-59)...(-1) {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: anchorDay)!
            let sampleTime = day.addingTimeInterval(28_800)
            points.append(
                HealthDataPoint(
                    id: UUID(),
                    sampleType: .heartRateVariabilitySDNN,
                    startDate: sampleTime,
                    endDate: sampleTime.addingTimeInterval(60),
                    value: 60,
                    unit: "ms",
                    sleepStage: nil,
                    sourceName: nil
                )
            )
            points.append(
                HealthDataPoint(
                    id: UUID(),
                    sampleType: .restingHeartRate,
                    startDate: sampleTime,
                    endDate: sampleTime.addingTimeInterval(60),
                    value: 56,
                    unit: "count/min",
                    sleepStage: nil,
                    sourceName: nil
                )
            )
        }

        // Today: acute crashed HRV = 18 ms and elevated RHR = 66 bpm
        let todaySampleTime = anchorDay.addingTimeInterval(28_800)
        points.append(
            HealthDataPoint(
                id: UUID(),
                sampleType: .heartRateVariabilitySDNN,
                startDate: todaySampleTime,
                endDate: todaySampleTime.addingTimeInterval(60),
                value: 18,
                unit: "ms",
                sleepStage: nil,
                sourceName: nil
            )
        )
        points.append(
            HealthDataPoint(
                id: UUID(),
                sampleType: .restingHeartRate,
                startDate: todaySampleTime,
                endDate: todaySampleTime.addingTimeInterval(60),
                value: 66,
                unit: "count/min",
                sleepStage: nil,
                sourceName: nil
            )
        )

        // Future sample (+1 day) and non-physical values that must be rejected
        let futureTime = asOf.addingTimeInterval(86_400)
        points.append(
            HealthDataPoint(
                id: UUID(),
                sampleType: .heartRateVariabilitySDNN,
                startDate: futureTime,
                endDate: futureTime.addingTimeInterval(60),
                value: 150,
                unit: "ms",
                sleepStage: nil,
                sourceName: nil
            )
        )
        points.append(
            HealthDataPoint(
                id: UUID(),
                sampleType: .heartRateVariabilitySDNN,
                startDate: todaySampleTime,
                endDate: todaySampleTime,
                value: .nan,
                unit: "ms",
                sleepStage: nil,
                sourceName: nil
            )
        )

        let calculator = HealthMetricsCalculator()
        let corridor = calculator.hrvCorridor(from: points, asOf: asOf, calendar: calendar)
        #expect(corridor != nil)
        #expect(corridor?.sampleCount == 60)
        #expect(corridor?.baselineDayCount == 60)
        #expect(corridor?.sevenDaySampleCount == 7)
        #expect(corridor?.currentMilliseconds == 18)
        // 59 days @ 60 + 1 day @ 18 => mean = 59.3 ms, SD ≈ 5.377 ms, lowerBound ≈ 53.92 ms
        #expect(abs((corridor?.baselineMilliseconds ?? 0) - 59.3) < 0.05)
        #expect((corridor?.lowerBoundMilliseconds ?? 0) > 53.0)
        // 7d average = (6 * 60 + 18) / 7 = 54.0 ms
        #expect(abs((corridor?.sevenDayAverageMilliseconds ?? 0) - 54.0) < 0.05)
        // Because currentMilliseconds = 18 is well below lowerBound (~53.92), isWithinCorridor MUST be false!
        #expect(corridor?.isWithinCorridor == false)

        let rhr = calculator.restingHeartRateSummary(from: points, asOf: asOf, calendar: calendar)
        #expect(rhr != nil)
        #expect(rhr?.sampleCount == 60)
        #expect(rhr?.currentBPM == 66)
        #expect(abs((rhr?.baselineBPM ?? 0) - 56.166) < 0.05)
        #expect((rhr?.deltaFromBaselineBPM ?? 0) > 9.5)
    }

    @Test("Heart rate zones handle instantaneous Watch samples, deduplicate dual sources, clip to workout windows, and resolve max HR")
    func heartRateZonesPointSamplesAndDeduplication() {
        var points: [HealthDataPoint] = []
        // 60 instantaneous Apple Watch samples spaced 5s apart (startDate == endDate) at 165 bpm
        for index in 0..<60 {
            let offset = TimeInterval(index * 5)
            points.append(point(.heartRate, value: 165, offset: offset, duration: 0, sourceName: "Apple Watch"))
            // Simultaneous chest strap sample at identical timestamp to verify no double-counting
            points.append(point(.heartRate, value: 165, offset: offset, duration: 0, sourceName: "Polar H10"))
        }
        // Out-of-workout resting sample 1 hour later
        points.append(point(.heartRate, value: 60, offset: 3_600, duration: 60, sourceName: "Apple Watch"))

        let calculator = HealthMetricsCalculator()
        let workoutWindow = DateInterval(start: start, end: start.addingTimeInterval(300))
        let zones = calculator.heartRateZones(
            from: points,
            maximumHeartRate: 190,
            clipIntervals: [workoutWindow]
        )
        // 165 / 190 = 0.868 -> Zone 4 (80%..<90%); 60 samples * 5s = 300s (no 600s double count, no Zone 1 resting leak)
        #expect(zones.zone4Duration == 300)
        #expect(zones.zone1Duration == 0)
        #expect(zones.totalDuration == 300)
        #expect(zones.resolvedMaximumHeartRateBPM == 190)

        // Age-estimated max HR resolution (age 40 -> Tanaka 208 - 28 = 180 bpm; 165 / 180 = 0.9167 -> Zone 5)
        let ageZones = calculator.heartRateZones(
            from: points,
            maximumHeartRate: nil,
            userAgeYears: 40,
            clipIntervals: [workoutWindow]
        )
        #expect(ageZones.resolvedMaximumHeartRateBPM == 180)
        #expect(ageZones.zone5Duration == 300)
    }

    @Test("Post-workout HRR anchors to latest workout endDate (+60s/+120s) and never uses days-old resting HR")
    func postWorkoutHeartRateRecovery() {
        // Day 1 morning resting HR samples at 08:00 and 08:01
        let day1Points = [
            point(.heartRate, value: 55, offset: 0, duration: 0),
            point(.heartRate, value: 56, offset: 60, duration: 0)
        ]
        // Day 7 workout ending at start + 600_000
        let workoutStart = start.addingTimeInterval(596_400)
        let workoutEnd = start.addingTimeInterval(600_000)
        let workout = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 3_600,
            totalEnergyBurned: 600,
            totalDistance: 10_000,
            startDate: workoutStart,
            endDate: workoutEnd,
            sourceName: "Watch",
            averageHeartRate: 158
        )
        let workoutAndPostPoints = [
            HealthDataPoint(id: UUID(), sampleType: .heartRate, startDate: workoutEnd.addingTimeInterval(-5), endDate: workoutEnd.addingTimeInterval(-5), value: 172, unit: "count/min", sleepStage: nil, sourceName: "Watch"),
            HealthDataPoint(id: UUID(), sampleType: .heartRate, startDate: workoutEnd.addingTimeInterval(60), endDate: workoutEnd.addingTimeInterval(60), value: 140, unit: "count/min", sleepStage: nil, sourceName: "Watch"),
            HealthDataPoint(id: UUID(), sampleType: .heartRate, startDate: workoutEnd.addingTimeInterval(120), endDate: workoutEnd.addingTimeInterval(120), value: 122, unit: "count/min", sleepStage: nil, sourceName: "Watch")
        ]

        let calculator = HealthMetricsCalculator()
        let hrr = calculator.heartRateRecovery(
            from: day1Points + workoutAndPostPoints,
            workouts: [workout],
            asOf: workoutEnd.addingTimeInterval(300)
        )
        #expect(hrr != nil)
        #expect(hrr?.baselineBPM == 172)
        #expect(hrr?.oneMinuteBPM == 140)
        #expect(hrr?.twoMinuteBPM == 122)
        #expect(hrr?.oneMinuteDropBPM == 32)
        #expect(hrr?.twoMinuteDropBPM == 50)

        // When post-workout samples are absent, oneMinuteBPM and twoMinuteBPM must be nil (not Day 1's 56 bpm!)
        let missingPostHRR = calculator.heartRateRecovery(
            from: day1Points + [workoutAndPostPoints[0]],
            workouts: [workout],
            asOf: workoutEnd.addingTimeInterval(300)
        )
        #expect(missingPostHRR?.baselineBPM == 172)
        #expect(missingPostHRR?.oneMinuteBPM == nil)
        #expect(missingPostHRR?.twoMinuteBPM == nil)
        #expect(missingPostHRR?.isAvailable == false)
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

    @Test("Sleep analyzer deduplicates overlapping stages, separates multi-night history, and tracks missing nights in 7d/14d debt")
    func sleepMultiNightAndOverlapDeduplication() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Base night 1: 2023-11-10 23:00 UTC to 2023-11-11 06:00 UTC (7h)
        let baseNightEvening = Date(timeIntervalSince1970: 1_699_657_200) // 2023-11-10 23:00:00 UTC

        // Overlapping dual-source segments on Night 1:
        // Watch records 1h Deep (23:00-00:00), 2h REM (00:00-02:00), 4h Core (02:00-06:00) = 7h total
        // iPhone simultaneously records 7h inBed + 7h asleepCore (23:00-06:00)
        let night1WatchDeep = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: baseNightEvening, endDate: baseNightEvening.addingTimeInterval(3_600), value: 1, unit: "hr", sleepStage: .asleepDeep, sourceName: "Watch")
        let night1WatchREM = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: baseNightEvening.addingTimeInterval(3_600), endDate: baseNightEvening.addingTimeInterval(10_800), value: 1, unit: "hr", sleepStage: .asleepREM, sourceName: "Watch")
        let night1WatchCore = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: baseNightEvening.addingTimeInterval(10_800), endDate: baseNightEvening.addingTimeInterval(25_200), value: 1, unit: "hr", sleepStage: .asleepCore, sourceName: "Watch")
        let night1PhoneCore = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: baseNightEvening, endDate: baseNightEvening.addingTimeInterval(25_200), value: 1, unit: "hr", sleepStage: .asleepCore, sourceName: "iPhone")
        let night1PhoneInBed = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: baseNightEvening, endDate: baseNightEvening.addingTimeInterval(25_200), value: 1, unit: "hr", sleepStage: .inBed, sourceName: "iPhone")

        // Night 2 (2023-11-11 23:00 UTC): 6.5h Core sleep (23,400s) -> 1.5h deficit vs 8h target
        let night2Evening = baseNightEvening.addingTimeInterval(86_400)
        let night2Core = HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: night2Evening, endDate: night2Evening.addingTimeInterval(23_400), value: 1, unit: "hr", sleepStage: .asleepCore, sourceName: "Watch")

        let analyzer = SleepArchitectureAnalyzer()
        let unorderedPoints = [night2Core, night1PhoneInBed, night1PhoneCore, night1WatchREM, night1WatchDeep, night1WatchCore]
        let nights = analyzer.analyzeByNight(
            points: unorderedPoints,
            targetSleepDuration: 28_800,
            asOf: night2Evening.addingTimeInterval(36_000),
            calendar: calendar
        )
        #expect(nights.count == 2)
        // Night 1 must be 7h (25,200s), NOT 14h double-counted
        #expect(nights[0].deepDuration == 3_600)
        #expect(nights[0].remDuration == 7_200)
        #expect(nights[0].coreDuration == 14_400)
        #expect(nights[0].totalSleepDuration == 25_200)
        // Latest night (analyze) must be Night 2 (6.5h = 23,400s), NOT Night 1 + Night 2 summed (48,600s)
        let latest = analyzer.analyze(
            points: unorderedPoints,
            targetSleepDuration: 28_800,
            asOf: night2Evening.addingTimeInterval(36_000),
            calendar: calendar
        )
        #expect(latest?.totalSleepDuration == 23_400)

        let debt = analyzer.debtSummary(
            points: unorderedPoints,
            targetSleepDuration: 28_800,
            asOf: night2Evening.addingTimeInterval(36_000),
            calendar: calendar
        )
        #expect(debt != nil)
        // Night 1 deficit = 1h (3,600s), Night 2 deficit = 1.5h (5,400s) => 9,000s total across 2 observed nights
        #expect(debt?.sevenDayDebt == 9_000)
        #expect(debt?.observedNightCount7d == 2)
        #expect(debt?.missingNightCount7d == 5)
        #expect(debt?.observedNightCount14d == 2)
        #expect(debt?.missingNightCount14d == 12)

        // Verify DST spring-forward boundary grouping (America/New_York 2023-03-12 02:00 -> 03:00):
        // Sleep starting at 23:30 on 2023-03-11 and continuing past 03:30 EDT on 2023-03-12 stays in a single night bucket.
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3_600)!
        let dstEvening = DateComponents(calendar: nyCalendar, year: 2023, month: 3, day: 11, hour: 23, minute: 30).date!
        let dstPoints = [
            HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: dstEvening, endDate: dstEvening.addingTimeInterval(3_600), value: 1, unit: "hr", sleepStage: .asleepDeep, sourceName: "Watch"),
            HealthDataPoint(id: UUID(), sampleType: .sleepAnalysis, startDate: dstEvening.addingTimeInterval(3_600), endDate: dstEvening.addingTimeInterval(18_000), value: 1, unit: "hr", sleepStage: .asleepCore, sourceName: "Watch")
        ]
        let dstNights = analyzer.analyzeByNight(points: dstPoints, targetSleepDuration: 28_800, calendar: nyCalendar)
        #expect(dstNights.count == 1)
        #expect(dstNights.first?.totalSleepDuration == 18_000)
    }

    @Test("NEAT scopes to target calendar day, excludes workout energy and movement, and includes stand time")
    func neatExcludesWorkoutsAndMultiDayHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let todayStart = calendar.startOfDay(for: start)
        let asOf = todayStart.addingTimeInterval(20 * 3_600)

        var points: [HealthDataPoint] = []
        // 6 prior days of 5,000 steps/day that must NOT be summed into today's dailySteps
        for dayOffset in (-6)...(-1) {
            let priorDay = calendar.date(byAdding: .day, value: dayOffset, to: todayStart)!
            points.append(
                HealthDataPoint(
                    id: UUID(),
                    sampleType: .stepCount,
                    startDate: priorDay.addingTimeInterval(10 * 3_600),
                    endDate: priorDay.addingTimeInterval(11 * 3_600),
                    value: 5_000,
                    unit: "count",
                    sleepStage: nil,
                    sourceName: nil
                )
            )
        }

        // Today non-workout movement at 09:00–09:30 (2,000 steps, 120 kcal, 10 min stand)
        let morning = todayStart.addingTimeInterval(9 * 3_600)
        points.append(HealthDataPoint(id: UUID(), sampleType: .stepCount, startDate: morning, endDate: morning.addingTimeInterval(1_800), value: 2_000, unit: "count", sleepStage: nil, sourceName: nil))
        points.append(HealthDataPoint(id: UUID(), sampleType: .activeEnergyBurned, startDate: morning, endDate: morning.addingTimeInterval(1_800), value: 120, unit: "kcal", sleepStage: nil, sourceName: nil))
        points.append(HealthDataPoint(id: UUID(), sampleType: .appleStandTime, startDate: morning, endDate: morning.addingTimeInterval(600), value: 10, unit: "min", sleepStage: nil, sourceName: nil))

        // Today running workout at 14:00–15:00 (6,000 steps, 800 kcal)
        let runStart = todayStart.addingTimeInterval(14 * 3_600)
        let runEnd = todayStart.addingTimeInterval(15 * 3_600)
        let runWorkout = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 3_600,
            totalEnergyBurned: 800,
            totalDistance: 10_000,
            startDate: runStart,
            endDate: runEnd,
            sourceName: "Watch",
            averageHeartRate: 160
        )
        points.append(HealthDataPoint(id: UUID(), sampleType: .stepCount, startDate: runStart, endDate: runEnd, value: 6_000, unit: "count", sleepStage: nil, sourceName: nil))
        points.append(HealthDataPoint(id: UUID(), sampleType: .activeEnergyBurned, startDate: runStart, endDate: runEnd, value: 800, unit: "kcal", sleepStage: nil, sourceName: nil))
        points.append(HealthDataPoint(id: UUID(), sampleType: .basalEnergyBurned, startDate: todayStart, endDate: asOf, value: 1_500, unit: "kcal", sleepStage: nil, sourceName: nil))

        let neat = HealthMetricsCalculator().neatSnapshot(
            from: points,
            workouts: [runWorkout],
            asOf: asOf,
            calendar: calendar
        )
        // Today's total steps = 2,000 + 6,000 = 8,000 (prior 30,000 excluded); non-workout steps = 2,000
        #expect(neat.dailySteps == 8_000)
        #expect(neat.nonWorkoutSteps == 2_000)
        // Non-exercise active energy = 120 kcal (800 kcal run excluded!)
        #expect(neat.nonExerciseActiveEnergy == 120)
        #expect(neat.workoutActiveEnergyExcluded == 800)
        #expect(neat.standDuration == 600)
        #expect(neat.activeNonWorkoutHourCount == 1)
        #expect(neat.hourlyNonWorkoutDistribution[9] == 2_000)
        #expect(neat.hourlyNonWorkoutDistribution[14] == nil)
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

    @Test("Aerobic decoupling detects 25% pace drop at constant HR and retains VO2max trend when distance is absent")
    func aerobicDecouplingAndVO2OnlyFallback() {
        // First 15 min (900s): 3,000m (12 km/h) @ 150 bpm -> EF1 = 12 / 150 = 0.08
        // Second 15 min (900s): 2,250m (9 km/h) @ 150 bpm -> EF2 = 9 / 150 = 0.06
        // Decoupling = (0.08 - 0.06) / 0.08 = 25%
        // Also include an earlier session 3 days ago and overnight resting HR to ensure multi-day gaps don't collapse speed
        let priorDayRun = point(.distanceWalkingRunning, value: 5_000, offset: -3 * 86_400, duration: 1_800)
        let overnightRestingHR = point(.heartRate, value: 52, offset: -36_000, duration: 60)

        let firstHalfDistance = point(.distanceWalkingRunning, value: 3_000, offset: 0, duration: 900)
        let secondHalfDistance = point(.distanceWalkingRunning, value: 2_250, offset: 900, duration: 900)
        let firstHalfHR = point(.heartRate, value: 150, offset: 0, duration: 900)
        let secondHalfHR = point(.heartRate, value: 150, offset: 900, duration: 900)
        let vo2First = point(.vo2Max, value: 49.0, offset: -7 * 86_400, duration: 0)
        let vo2Latest = point(.vo2Max, value: 50.5, offset: 0, duration: 0)
        let vo2Future = point(.vo2Max, value: 65.0, offset: 86_400, duration: 0)

        let calc = AerobicEfficiencyCalculator()
        let result = calc.calculate(
            from: [priorDayRun, overnightRestingHR, firstHalfDistance, secondHalfDistance, firstHalfHR, secondHalfHR, vo2First, vo2Latest, vo2Future],
            asOf: start.addingTimeInterval(3_600)
        )
        #expect(result != nil)
        // Overall speed = 5,250m in 1,800s = 10.5 km/h; EF = 10.5 / 150 = 0.07
        #expect(abs((result?.efficiencyFactor ?? 0) - 0.07) < 0.0001)
        #expect(abs((result?.aerobicDecouplingPercentage ?? 0) - 25.0) < 0.001)
        #expect(result?.vo2Max == 50.5)
        #expect(abs((result?.vo2MaxTrend ?? 0) - 1.5) < 0.001)

        // VO2-only input (no distance or HR) still returns VO2max and trend
        let vo2Only = calc.calculate(from: [vo2First, vo2Latest, vo2Future], asOf: start.addingTimeInterval(3_600))
        #expect(vo2Only?.efficiencyFactor == nil)
        #expect(vo2Only?.vo2Max == 50.5)
        #expect(abs((vo2Only?.vo2MaxTrend ?? 0) - 1.5) < 0.001)
    }

    @Test("Training load normalizes strength to TSS scale, deduplicates mirrored HK workouts, excludes future workouts, and tracks trajectory")
    func trainingLoadNormalizationDeduplicationAndTrajectory() {
        let calc = TrainingLoadCalculator()
        let mirrorUUID = UUID()
        let workoutStart = start
        let workoutEnd = start.addingTimeInterval(3_600)

        let strengthInput = StrengthWorkoutSummaryInput(
            startDate: workoutStart,
            endDate: workoutEnd,
            workingVolume: 10_000,
            setCount: 12,
            estimatedRPE: 8,
            healthKitUUID: mirrorUUID.uuidString
        )
        let singleStrengthLoad = calc.strengthLoad(strengthInput)
        // 1-hour RPE 8 strength session must be on a TSS-comparable scale (40..120), NOT 8,096!
        #expect(singleStrengthLoad >= 40 && singleStrengthLoad <= 120)

        let mirroredHK = HealthWorkoutRecord(
            id: mirrorUUID,
            activityTypeRawValue: WorkoutActivityType.traditionalStrengthTraining.rawValue,
            duration: 3_600,
            totalEnergyBurned: 400,
            totalDistance: nil,
            startDate: workoutStart,
            endDate: workoutEnd,
            sourceName: "VitalStride",
            averageHeartRate: 135
        )
        let futureHK = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 3_600,
            totalEnergyBurned: 700,
            totalDistance: 10_000,
            startDate: start.addingTimeInterval(2 * 86_400),
            endDate: start.addingTimeInterval(2 * 86_400 + 3_600),
            sourceName: "Watch",
            averageHeartRate: 165
        )

        let snapshot = calc.calculate(
            workouts: [mirroredHK, futureHK],
            strengthWorkouts: [strengthInput],
            asOf: workoutEnd.addingTimeInterval(600)
        )
        // Mirrored HK workout must be deduplicated, future workout excluded
        #expect(snapshot.deduplicatedWorkoutCount == 1)
        #expect(snapshot.trimp == 0)
        #expect(abs(snapshot.tss - singleStrengthLoad) < 0.001)
        #expect(!snapshot.recentTrajectory.isEmpty)

        // Fallback window-overlap deduplication when healthKitUUID is nil on StrengthWorkoutSummaryInput
        let unlinkedStrength = StrengthWorkoutSummaryInput(
            startDate: workoutStart,
            endDate: workoutEnd,
            workingVolume: 8_000,
            setCount: 10,
            estimatedRPE: 7.5,
            healthKitUUID: nil
        )
        let fallbackDedupSnapshot = calc.calculate(
            workouts: [mirroredHK],
            strengthWorkouts: [unlinkedStrength],
            asOf: workoutEnd.addingTimeInterval(600)
        )
        #expect(fallbackDedupSnapshot.deduplicatedWorkoutCount == 1)
        #expect(fallbackDedupSnapshot.trimp == 0)
    }

    @Test("physiologicalSnapshot degrades gracefully with Steps-only or missing Sleep/HRV without fabricating healthy values")
    func partialDataGracefulDegradation() {
        let stepsOnly = [
            point(.stepCount, value: 6_500, offset: 0, duration: 1_800)
        ]
        let calculator = HealthMetricsCalculator()
        let snapshot = calculator.physiologicalSnapshot(
            from: stepsOnly,
            maximumHeartRate: 190,
            targetSleepDuration: 28_800,
            generatedAt: start.addingTimeInterval(3_600)
        )
        #expect(snapshot != nil)
        #expect(snapshot?.availableDomains == [.neat])
        #expect(snapshot?.neat.dailySteps == 6_500)
        #expect(snapshot?.heart.isAvailable == false)
        #expect(snapshot?.heart.hrvCorridor.isWithinCorridor == false)
        #expect(snapshot?.sleep.isAvailable == false)
        #expect(snapshot?.sleep.debt.isAvailable == false)
        #expect(snapshot?.sleep.debt.missingNightCount7d == 7)

        // Completely empty input returns nil
        let emptySnapshot = calculator.physiologicalSnapshot(
            from: [],
            maximumHeartRate: 190,
            targetSleepDuration: 28_800,
            generatedAt: start
        )
        #expect(emptySnapshot == nil)
    }
}
