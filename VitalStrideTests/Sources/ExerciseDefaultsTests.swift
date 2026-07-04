import Testing
import VitalModels

@testable import VitalStride

@Suite("ExerciseDefaults — resolveWeightKg priority chain")
struct ExerciseDefaultsWeightTests {

    // MARK: helpers

    private func makeExercise(
        low: Double? = nil,
        mid: Double? = nil,
        high: Double? = nil
    ) -> Exercise {
        Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            defaultWeightLow: low,
            defaultWeightMid: mid,
            defaultWeightHigh: high
        )
    }

    // MARK: seeded values

    @Test("Uses seeded high weight when present")
    func seededHigh() {
        let e = makeExercise(low: 100, mid: 80, high: 60)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .high, exercise: e, recentWeightKg: 999)
        #expect(w == 60)
    }

    @Test("Uses seeded mid weight when present")
    func seededMid() {
        let e = makeExercise(low: 100, mid: 80, high: 60)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .mid, exercise: e, recentWeightKg: 999)
        #expect(w == 80)
    }

    @Test("Uses seeded low weight when present")
    func seededLow() {
        let e = makeExercise(low: 100, mid: 80, high: 60)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .low, exercise: e, recentWeightKg: 999)
        #expect(w == 100)
    }

    // MARK: fallback to recent

    @Test("Falls back to recent weight when the requested bucket has no default")
    func fallbackRecentWhenBucketNil() {
        let e = makeExercise(low: 100, mid: nil, high: 60)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .mid, exercise: e, recentWeightKg: 42.5)
        #expect(w == 42.5)
    }

    @Test("Falls back to recent when exercise is nil")
    func fallbackRecentWhenExerciseNil() {
        let w = ExerciseDefaults.resolveWeightKg(bucket: .high, exercise: nil, recentWeightKg: 30)
        #expect(w == 30)
    }

    @Test("Skips seeded value of 0 (treated as unset), falls through")
    func zeroSeededIsSkipped() {
        let e = makeExercise(mid: 0)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .mid, exercise: e, recentWeightKg: 25)
        #expect(w == 25)
    }

    @Test("Skips negative seeded value, falls through")
    func negativeSeededIsSkipped() {
        let e = makeExercise(high: -5)
        let w = ExerciseDefaults.resolveWeightKg(bucket: .high, exercise: e, recentWeightKg: 20)
        #expect(w == 20)
    }

    // MARK: no fallback available

    @Test("Returns nil when no default and no recent")
    func nilWhenNoData() {
        let e = makeExercise()
        let w = ExerciseDefaults.resolveWeightKg(bucket: .low, exercise: e, recentWeightKg: nil)
        #expect(w == nil)
    }

    @Test("Returns nil when recent weight is 0 (invalid)")
    func zeroRecentIsRejected() {
        let e = makeExercise()
        let w = ExerciseDefaults.resolveWeightKg(bucket: .low, exercise: e, recentWeightKg: 0)
        #expect(w == nil)
    }
}

@Suite("ExerciseDefaults — reps cycling")
struct ExerciseDefaultsRepsTests {

    // MARK: cycle values

    @Test("Cycle for 15-20 is [15, 18, 20]")
    func cycleHigh() {
        #expect(ExerciseDefaults.cycleValues(for: 15...20) == [15, 18, 20])
    }

    @Test("Cycle for 8-12 is [8, 10, 12]")
    func cycleMid() {
        #expect(ExerciseDefaults.cycleValues(for: 8...12) == [8, 10, 12])
    }

    @Test("Cycle for 4-6 is [4, 5, 6]")
    func cycleLow() {
        #expect(ExerciseDefaults.cycleValues(for: 4...6) == [4, 5, 6])
    }

    // MARK: nextReps behavior

    @Test("nextReps starts at cycle[0] when previous is nil")
    func startAtLowWhenNil() {
        #expect(ExerciseDefaults.nextReps(in: 15...20, previous: nil) == 15)
        #expect(ExerciseDefaults.nextReps(in: 8...12, previous: nil) == 8)
        #expect(ExerciseDefaults.nextReps(in: 4...6, previous: nil) == 4)
    }

    @Test("nextReps advances through cycle then wraps for 15-20")
    func advanceHigh() {
        #expect(ExerciseDefaults.nextReps(in: 15...20, previous: 15) == 18)
        #expect(ExerciseDefaults.nextReps(in: 15...20, previous: 18) == 20)
        #expect(ExerciseDefaults.nextReps(in: 15...20, previous: 20) == 15) // wrap
    }

    @Test("nextReps advances through cycle then wraps for 8-12")
    func advanceMid() {
        #expect(ExerciseDefaults.nextReps(in: 8...12, previous: 8) == 10)
        #expect(ExerciseDefaults.nextReps(in: 8...12, previous: 10) == 12)
        #expect(ExerciseDefaults.nextReps(in: 8...12, previous: 12) == 8) // wrap
    }

    @Test("nextReps advances through cycle then wraps for 4-6")
    func advanceLow() {
        #expect(ExerciseDefaults.nextReps(in: 4...6, previous: 4) == 5)
        #expect(ExerciseDefaults.nextReps(in: 4...6, previous: 5) == 6)
        #expect(ExerciseDefaults.nextReps(in: 4...6, previous: 6) == 4) // wrap
    }

    @Test("nextReps resets to cycle[0] when previous is off-cycle")
    func offCycleReset() {
        // Someone typed 17 by hand — not in the [15, 18, 20] cycle.
        #expect(ExerciseDefaults.nextReps(in: 15...20, previous: 17) == 15)
        // 11 is in-range but not in the [8, 10, 12] cycle.
        #expect(ExerciseDefaults.nextReps(in: 8...12, previous: 11) == 8)
    }

    @Test("nextReps for a bucket range yields the same cycle regardless of source")
    func bucketMatchesRange() {
        for bucket in PresetRepBucket.allCases {
            let byBucket = ExerciseDefaults.nextReps(in: bucket.range, previous: nil)
            #expect(byBucket == bucket.range.lowerBound)
        }
    }
}

@Suite("ExerciseDefaults — resolvePreset combined")
struct ExerciseDefaultsResolvePresetTests {

    @Test("Cycles reps and returns seeded weight on first tap")
    func firstTapReturnsSeededWeightAndLowReps() {
        let e = Exercise(
            nameEn: "Squat", nameZh: "深蹲",
            muscleGroup: .legs, equipment: .barbell,
            defaultWeightLow: 120, defaultWeightMid: 100, defaultWeightHigh: 80
        )
        let r = ExerciseDefaults.resolvePreset(
            bucket: .mid,
            exercise: e,
            recentWeightKg: 200,
            previousReps: nil
        )
        #expect(r.weightKg == 100)
        #expect(r.reps == 8)
    }

    @Test("Cycles reps on second tap; weight stable")
    func secondTapAdvancesReps() {
        let e = Exercise(
            nameEn: "Squat", nameZh: "深蹲",
            muscleGroup: .legs, equipment: .barbell,
            defaultWeightMid: 100
        )
        let first = ExerciseDefaults.resolvePreset(
            bucket: .mid, exercise: e, recentWeightKg: nil, previousReps: nil
        )
        let second = ExerciseDefaults.resolvePreset(
            bucket: .mid, exercise: e, recentWeightKg: nil, previousReps: first.reps
        )
        #expect(first.reps == 8)
        #expect(second.reps == 10)
        #expect(second.weightKg == 100)
    }

    @Test("Returns nil weight when no data and reps still cycles")
    func noWeightStillCyclesReps() {
        let r = ExerciseDefaults.resolvePreset(
            bucket: .low,
            exercise: nil,
            recentWeightKg: nil,
            previousReps: 5
        )
        #expect(r.weightKg == nil)
        #expect(r.reps == 6)
    }
}

@Suite("ExerciseDefaults — unit conversion")
struct ExerciseDefaultsUnitTests {

    @Test("kg display passes through unchanged")
    func kgPassthrough() {
        #expect(ExerciseDefaults.displayWeight(fromKg: 40, unit: .kg) == 40)
        #expect(ExerciseDefaults.canonicalWeight(fromDisplay: 40, unit: .kg) == 40)
    }

    @Test("lb display uses 2.20462 factor")
    func lbConversion() {
        let display = ExerciseDefaults.displayWeight(fromKg: 100, unit: .lb)
        #expect(abs(display - 220.462) < 0.001)

        let canonical = ExerciseDefaults.canonicalWeight(fromDisplay: 220.462, unit: .lb)
        #expect(abs(canonical - 100) < 0.001)
    }

    @Test("Round-trip preserves value within epsilon")
    func lbRoundTrip() {
        let original: Double = 42.5
        let asLb = ExerciseDefaults.displayWeight(fromKg: original, unit: .lb)
        let back = ExerciseDefaults.canonicalWeight(fromDisplay: asLb, unit: .lb)
        #expect(abs(back - original) < 0.001)
    }
}

@Suite("SetField behavior")
struct SetFieldTests {

    @Test("weight and weightRight enable decimal input")
    func weightFieldsEnableDecimal() {
        #expect(SetField.weight.isDecimalEnabled)
        #expect(SetField.weightRight.isDecimalEnabled)
    }

    @Test("reps disables decimal input")
    func repsDisablesDecimal() {
        #expect(!SetField.reps.isDecimalEnabled)
    }

    @Test("isWeightField distinguishes weight vs reps")
    func isWeightField() {
        #expect(SetField.weight.isWeightField)
        #expect(SetField.weightRight.isWeightField)
        #expect(!SetField.reps.isWeightField)
    }
}
