import Foundation
import HealthKitService
import Testing

@testable import VitalStride

private enum HRRTestError: Error {
    case healthKitUnavailable
}

@Suite("Workout Heart Rate Stats — HRR Tests")
struct WorkoutHeartRateStatsHRRTests {

    private func makeSample(offsetFromReference: TimeInterval, value: Double, reference: Date) -> HealthDataPoint {
        let date = reference.addingTimeInterval(offsetFromReference)
        return HealthDataPoint(
            id: UUID(),
            sampleType: .heartRate,
            startDate: date,
            endDate: date,
            value: value,
            unit: "bpm",
            sleepStage: nil,
            sourceName: nil
        )
    }

    // MARK: - computeHeartRateRecovery1Min (pure)

    @Test("computeHRR returns difference between last-in-workout and closest-to-60s post sample")
    func computeHRRNormalCase() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -600, value: 130, reference: endDate),
            makeSample(offsetFromReference: -300, value: 150, reference: endDate),
            makeSample(offsetFromReference: -30, value: 170, reference: endDate),
        ]
        let postWorkoutSamples = [
            makeSample(offsetFromReference: 50, value: 140, reference: endDate),
            makeSample(offsetFromReference: 60, value: 135, reference: endDate),
            makeSample(offsetFromReference: 75, value: 130, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postWorkoutSamples,
            workoutEndDate: endDate
        )

        #expect(hrr == 35)
    }

    @Test("computeHRR selects sample closest to target when several are inside the window")
    func computeHRRPicksClosestToTarget() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]
        let postWorkoutSamples = [
            makeSample(offsetFromReference: 46, value: 155, reference: endDate),
            makeSample(offsetFromReference: 58, value: 130, reference: endDate),
            makeSample(offsetFromReference: 89, value: 115, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postWorkoutSamples,
            workoutEndDate: endDate
        )

        #expect(hrr == 30)
    }

    @Test("computeHRR rounds toward nearest integer")
    func computeHRRRounding() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -5, value: 160.4, reference: endDate),
        ]
        let postWorkoutSamples = [
            makeSample(offsetFromReference: 60, value: 130.1, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postWorkoutSamples,
            workoutEndDate: endDate
        )

        #expect(hrr == 30)
    }

    @Test("computeHRR returns nil when workout samples are empty")
    func computeHRREmptyWorkoutSamples() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let postWorkoutSamples = [
            makeSample(offsetFromReference: 60, value: 130, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: [],
            postWorkoutSamples: postWorkoutSamples,
            workoutEndDate: endDate
        )

        #expect(hrr == nil)
    }

    @Test("computeHRR returns nil when post-workout samples are empty")
    func computeHRREmptyPostSamples() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: [],
            workoutEndDate: endDate
        )

        #expect(hrr == nil)
    }

    @Test("computeHRR returns nil when no post-workout sample lies inside the [45s, 90s] window")
    func computeHRRSparsePostSamplesReturnsNil() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -20, value: 160, reference: endDate),
        ]
        let postWorkoutSamples = [
            makeSample(offsetFromReference: 20, value: 155, reference: endDate),
            makeSample(offsetFromReference: 40, value: 150, reference: endDate),
            makeSample(offsetFromReference: 120, value: 120, reference: endDate),
        ]

        let hrr = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postWorkoutSamples,
            workoutEndDate: endDate
        )

        #expect(hrr == nil)
    }

    @Test("computeHRR includes window boundaries (45s and 90s)")
    func computeHRRWindowBoundaryInclusive() {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]
        let postAtLower = [
            makeSample(offsetFromReference: 45, value: 140, reference: endDate),
        ]
        let postAtUpper = [
            makeSample(offsetFromReference: 90, value: 130, reference: endDate),
        ]

        let hrrLower = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postAtLower,
            workoutEndDate: endDate
        )
        let hrrUpper = WorkoutHeartRateStats.computeHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            postWorkoutSamples: postAtUpper,
            workoutEndDate: endDate
        )

        #expect(hrrLower == 20)
        #expect(hrrUpper == 30)
    }

    // MARK: - loadHeartRateRecovery1Min (orchestration)

    @Test("loadHRR returns nil when post-workout fetch throws")
    func loadHRRFetchError() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]

        let hrr = await WorkoutHeartRateStats.loadHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            workoutEndDate: endDate
        ) { _ in
            throw HRRTestError.healthKitUnavailable
        }

        #expect(hrr == nil)
    }

    @Test("loadHRR returns nil when post-workout fetch returns no in-window samples")
    func loadHRRNoInWindowSamples() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]

        let hrr = await WorkoutHeartRateStats.loadHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            workoutEndDate: endDate
        ) { _ in
            []
        }

        #expect(hrr == nil)
    }

    @Test("loadHRR returns valid recovery value when fetch succeeds with in-window samples")
    func loadHRRSuccess() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let workoutSamples = [
            makeSample(offsetFromReference: -10, value: 160, reference: endDate),
        ]

        let hrr = await WorkoutHeartRateStats.loadHeartRateRecovery1Min(
            workoutSamples: workoutSamples,
            workoutEndDate: endDate
        ) { interval in
            #expect(interval.start == endDate)
            #expect(
                interval.end == endDate.addingTimeInterval(
                    WorkoutHeartRateStats.postWorkoutHRRWindowUpperSeconds
                )
            )
            return [self.makeSample(offsetFromReference: 60, value: 135, reference: endDate)]
        }

        #expect(hrr == 25)
    }

    // MARK: - load(...fetchPostWorkoutHeartRate:) (top-level orchestration)

    @Test("load populates heartRateRecovery1Min when both fetches succeed")
    func loadPopulatesHRR() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let startDate = endDate.addingTimeInterval(-1800)

        let stats = await WorkoutHeartRateStats.load(
            startDate: startDate,
            endDate: endDate,
            fetchHeartRate: { _ in
                [
                    self.makeSample(offsetFromReference: -600, value: 130, reference: endDate),
                    self.makeSample(offsetFromReference: -300, value: 150, reference: endDate),
                    self.makeSample(offsetFromReference: -10, value: 170, reference: endDate),
                ]
            },
            fetchPostWorkoutHeartRate: { _ in
                [self.makeSample(offsetFromReference: 60, value: 135, reference: endDate)]
            }
        )

        #expect(stats != nil)
        #expect(stats?.heartRateRecovery1Min == 35)
    }

    @Test("load returns stats with nil HRR when post-workout fetch produces no in-window samples")
    func loadKeepsStatsWhenHRRUnavailable() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let startDate = endDate.addingTimeInterval(-1800)

        let stats = await WorkoutHeartRateStats.load(
            startDate: startDate,
            endDate: endDate,
            fetchHeartRate: { _ in
                [
                    self.makeSample(offsetFromReference: -600, value: 130, reference: endDate),
                    self.makeSample(offsetFromReference: -10, value: 170, reference: endDate),
                ]
            },
            fetchPostWorkoutHeartRate: { _ in
                []
            }
        )

        #expect(stats != nil)
        #expect(stats?.heartRateRecovery1Min == nil)
        #expect(stats?.averageHeartRate == 150)
        #expect(stats?.maxHeartRate == 170)
    }

    @Test("load returns nil when endDate is nil and never invokes either fetch")
    func loadNilEndDateSkipsBothFetches() async {
        let stats = await WorkoutHeartRateStats.load(
            startDate: Date(),
            endDate: nil,
            fetchHeartRate: { _ in
                Issue.record("fetchHeartRate should not be called when endDate is nil")
                return []
            },
            fetchPostWorkoutHeartRate: { _ in
                Issue.record("fetchPostWorkoutHeartRate should not be called when endDate is nil")
                return []
            }
        )
        #expect(stats == nil)
    }

    @Test("load returns nil when workout heart-rate fetch throws")
    func loadWorkoutFetchError() async {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-1800)

        let stats = await WorkoutHeartRateStats.load(
            startDate: startDate,
            endDate: endDate,
            fetchHeartRate: { _ in
                throw HRRTestError.healthKitUnavailable
            },
            fetchPostWorkoutHeartRate: { _ in
                Issue.record("post-workout fetch should not be called when workout fetch fails")
                return []
            }
        )

        #expect(stats == nil)
    }

    @Test("load returns stats with nil HRR when post-workout fetch throws")
    func loadPostFetchErrorPreservesStats() async {
        let endDate = Date(timeIntervalSinceReferenceDate: 0)
        let startDate = endDate.addingTimeInterval(-1800)

        let stats = await WorkoutHeartRateStats.load(
            startDate: startDate,
            endDate: endDate,
            fetchHeartRate: { _ in
                [
                    self.makeSample(offsetFromReference: -600, value: 120, reference: endDate),
                    self.makeSample(offsetFromReference: -10, value: 160, reference: endDate),
                ]
            },
            fetchPostWorkoutHeartRate: { _ in
                throw HRRTestError.healthKitUnavailable
            }
        )

        #expect(stats != nil)
        #expect(stats?.heartRateRecovery1Min == nil)
        #expect(stats?.averageHeartRate == 140)
        #expect(stats?.maxHeartRate == 160)
    }
}
