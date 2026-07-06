// swiftlint:disable identifier_name
import Foundation
import Testing
@testable import VitalModels

@Suite("ExerciseSet + WorkoutExercise 1RM Tests")
struct OneRepMaxTests {

    // MARK: - Epley Formula

    @Test("Epley formula: 80kg × 5 reps ≈ 93.33kg")
    func epleyFormula80x5() {
        let set = ExerciseSet(order: 0, weight: 80.0, reps: 5)
        let expected = 80.0 * (1.0 + 5.0 / 30.0)
        #expect(set.estimatedOneRepMax == expected)
        #expect(abs(set.estimatedOneRepMax - 93.333333) < 0.001)
    }

    @Test("Epley formula: 100kg × 1 rep equals weight")
    func epleyFormula100x1() {
        let set = ExerciseSet(order: 0, weight: 100.0, reps: 1)
        let expected = 100.0 * (1.0 + 1.0 / 30.0)
        #expect(set.estimatedOneRepMax == expected)
    }

    @Test("Epley formula: 60kg × 10 reps")
    func epleyFormula60x10() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 10)
        let expected = 60.0 * (1.0 + 10.0 / 30.0)
        #expect(set.estimatedOneRepMax == expected)
        #expect(abs(set.estimatedOneRepMax - 80.0) < 0.001)
    }

    @Test("Epley formula: zero weight yields zero 1RM")
    func epleyFormulaZeroWeight() {
        let set = ExerciseSet(order: 0, weight: 0.0, reps: 5)
        #expect(set.estimatedOneRepMax == 0.0)
    }

    // MARK: - Candidate Boundaries

    @Test("working set with reps 1 is a candidate")
    func candidateReps1() {
        let set = ExerciseSet(order: 0, weight: 100.0, reps: 1, setType: .working)
        #expect(set.isOneRepMaxCandidate == true)
    }

    @Test("working set with reps 12 is a candidate")
    func candidateReps12() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 12, setType: .working)
        #expect(set.isOneRepMaxCandidate == true)
    }

    @Test("working set with reps 0 is not a candidate")
    func nonCandidateReps0() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 0, setType: .working)
        #expect(set.isOneRepMaxCandidate == false)
    }

    @Test("working set with reps 13 is not a candidate")
    func nonCandidateReps13() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 13, setType: .working)
        #expect(set.isOneRepMaxCandidate == false)
    }

    @Test("working set with reps 20 is not a candidate")
    func nonCandidateReps20() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 20, setType: .working)
        #expect(set.isOneRepMaxCandidate == false)
    }

    // MARK: - Warmup Exclusion

    @Test("warmup set is not a candidate")
    func nonCandidateWarmup() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 8, setType: .warmup)
        #expect(set.isOneRepMaxCandidate == false)
    }

    @Test("dropSet is not a candidate (working only)")
    func nonCandidateDropSet() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 8, setType: .dropSet)
        #expect(set.isOneRepMaxCandidate == false)
    }

    @Test("pyramid is not a candidate (working only)")
    func nonCandidatePyramid() {
        let set = ExerciseSet(order: 0, weight: 60.0, reps: 8, setType: .pyramid)
        #expect(set.isOneRepMaxCandidate == false)
    }

    // MARK: - Invalid Weight

    @Test("zero weight is not a candidate")
    func nonCandidateZeroWeight() {
        let set = ExerciseSet(order: 0, weight: 0.0, reps: 5, setType: .working)
        #expect(set.isOneRepMaxCandidate == false)
    }

    @Test("negative weight is not a candidate")
    func nonCandidateNegativeWeight() {
        let set = ExerciseSet(order: 0, weight: -10.0, reps: 5, setType: .working)
        #expect(set.isOneRepMaxCandidate == false)
    }

    // MARK: - WorkoutExercise.bestEstimatedOneRepMax

    @Test("best 1RM picks highest candidate estimated 1RM")
    func bestPicksHighest() {
        let s1 = ExerciseSet(order: 0, weight: 80.0, reps: 5, setType: .working)
        let s2 = ExerciseSet(order: 1, weight: 100.0, reps: 3, setType: .working)
        let s3 = ExerciseSet(order: 2, weight: 60.0, reps: 10, setType: .working)
        let we = WorkoutExercise(order: 0, sets: [s1, s2, s3])
        let expected = max(s1.estimatedOneRepMax, s2.estimatedOneRepMax, s3.estimatedOneRepMax)
        #expect(we.bestEstimatedOneRepMax == expected)
    }

    @Test("best 1RM ignores warmup sets")
    func bestIgnoresWarmup() {
        let warmup = ExerciseSet(order: 0, weight: 200.0, reps: 5, setType: .warmup)
        let working = ExerciseSet(order: 1, weight: 80.0, reps: 5, setType: .working)
        let we = WorkoutExercise(order: 0, sets: [warmup, working])
        #expect(we.bestEstimatedOneRepMax == working.estimatedOneRepMax)
    }

    @Test("best 1RM ignores out-of-range rep sets")
    func bestIgnoresOutOfRange() {
        let highReps = ExerciseSet(order: 0, weight: 200.0, reps: 20, setType: .working)
        let working = ExerciseSet(order: 1, weight: 80.0, reps: 5, setType: .working)
        let we = WorkoutExercise(order: 0, sets: [highReps, working])
        #expect(we.bestEstimatedOneRepMax == working.estimatedOneRepMax)
    }

    @Test("best 1RM is nil when only warmup sets exist")
    func bestNilForWarmupOnly() {
        let w1 = ExerciseSet(order: 0, weight: 40.0, reps: 10, setType: .warmup)
        let w2 = ExerciseSet(order: 1, weight: 50.0, reps: 8, setType: .warmup)
        let we = WorkoutExercise(order: 0, sets: [w1, w2])
        #expect(we.bestEstimatedOneRepMax == nil)
    }

    @Test("best 1RM is nil when all working sets have reps > 12")
    func bestNilForOutOfRangeOnly() {
        let s1 = ExerciseSet(order: 0, weight: 40.0, reps: 15, setType: .working)
        let s2 = ExerciseSet(order: 1, weight: 30.0, reps: 20, setType: .working)
        let we = WorkoutExercise(order: 0, sets: [s1, s2])
        #expect(we.bestEstimatedOneRepMax == nil)
    }

    @Test("best 1RM is nil when weight is zero on working sets")
    func bestNilForZeroWeight() {
        let s1 = ExerciseSet(order: 0, weight: 0.0, reps: 5, setType: .working)
        let we = WorkoutExercise(order: 0, sets: [s1])
        #expect(we.bestEstimatedOneRepMax == nil)
    }

    @Test("best 1RM is nil when sets are empty")
    func bestNilForEmpty() {
        let we = WorkoutExercise(order: 0, sets: [])
        #expect(we.bestEstimatedOneRepMax == nil)
    }
}
// swiftlint:enable identifier_name
