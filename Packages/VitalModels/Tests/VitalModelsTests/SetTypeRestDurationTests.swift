import Foundation
import Testing
@testable import VitalModels

@Suite("SetType.defaultRestDuration mapping")
struct SetTypeRestDurationTests {

    @Test("warmup default rest = 45s")
    func warmupDefault() {
        #expect(SetType.warmup.defaultRestDuration == 45)
    }

    @Test("working default rest = 120s")
    func workingDefault() {
        #expect(SetType.working.defaultRestDuration == 120)
    }

    @Test("dropSet default rest = 15s")
    func dropSetDefault() {
        #expect(SetType.dropSet.defaultRestDuration == 15)
    }

    @Test("pyramid default rest = 75s")
    func pyramidDefault() {
        #expect(SetType.pyramid.defaultRestDuration == 75)
    }

    /// Exhaustive guard: every SetType case must be covered by the mapping
    /// above. If a new case is added without extending the expected table,
    /// this test fails so the mapping cannot silently miss coverage.
    @Test("allCases exhaustive mapping guard")
    func exhaustiveMapping() {
        let expected: [SetType: TimeInterval] = [
            .warmup: 45,
            .working: 120,
            .dropSet: 15,
            .pyramid: 75,
        ]

        #expect(SetType.allCases.count == expected.count)
        for setType in SetType.allCases {
            let expectedValue = expected[setType]
            #expect(expectedValue != nil, "SetType.\(setType) missing from expected mapping")
            #expect(setType.defaultRestDuration == expectedValue)
        }
    }
}

/// Tests for the manual-rest-duration priority expression
/// `restDuration ?? setType.defaultRestDuration` (SC-002, spec Edge Cases).
///
/// This is the caller-side resolution used by RestTimer start callers when a
/// set is completed: an explicit manual `restDuration` always wins over the
/// `SetType` default, and changing `setType` after a manual value has been
/// pinned must NOT silently override it.
@Suite("Manual rest duration priority")
struct ManualRestDurationPriorityTests {

    // MARK: - Manual value wins (non-nil restDuration)

    @Test("manual value wins over working default")
    func manualWinsOverWorking() {
        let set = ExerciseSet(weight: 80, reps: 5, setType: .working, restDuration: 30)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 30)
        #expect(resolved != SetType.working.defaultRestDuration)
    }

    @Test("manual value wins over warmup default")
    func manualWinsOverWarmup() {
        let set = ExerciseSet(weight: 20, reps: 12, setType: .warmup, restDuration: 90)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 90)
    }

    @Test("manual value wins over dropSet default")
    func manualWinsOverDropSet() {
        let set = ExerciseSet(weight: 40, reps: 10, setType: .dropSet, restDuration: 60)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 60)
        #expect(resolved != SetType.dropSet.defaultRestDuration)
    }

    @Test("manual value wins over pyramid default")
    func manualWinsOverPyramid() {
        let set = ExerciseSet(weight: 60, reps: 8, setType: .pyramid, restDuration: 180)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 180)
    }

    @Test("manual value of zero is honored (not treated as unset)")
    func manualZeroIsHonored() {
        let set = ExerciseSet(weight: 100, reps: 3, setType: .working, restDuration: 0)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 0)
    }

    // MARK: - Fallback to setType default (nil restDuration)

    @Test("nil restDuration falls back to warmup default")
    func nilFallsBackToWarmup() {
        let set = ExerciseSet(weight: 20, reps: 12, setType: .warmup, restDuration: nil)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 45)
    }

    @Test("nil restDuration falls back to working default")
    func nilFallsBackToWorking() {
        let set = ExerciseSet(weight: 80, reps: 5, setType: .working, restDuration: nil)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 120)
    }

    @Test("nil restDuration falls back to dropSet default")
    func nilFallsBackToDropSet() {
        let set = ExerciseSet(weight: 40, reps: 10, setType: .dropSet, restDuration: nil)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 15)
    }

    @Test("nil restDuration falls back to pyramid default")
    func nilFallsBackToPyramid() {
        let set = ExerciseSet(weight: 60, reps: 8, setType: .pyramid, restDuration: nil)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 75)
    }

    @Test("default init leaves restDuration nil → falls back to setType default")
    func defaultInitFallsBack() {
        let set = ExerciseSet(weight: 80, reps: 5, setType: .working)
        #expect(set.restDuration == nil)
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == SetType.working.defaultRestDuration)
    }

    // MARK: - Edge case: changing setType after manual value is set

    /// spec Edge Cases: 用户手动设过 restDuration 后，即便 setType 变更，
    /// 手动值仍然优先，不能被新 setType 的默认值静默覆盖。
    @Test("changing setType does NOT override an already-set manual restDuration")
    func setTypeChangeDoesNotOverrideManual() {
        // Start as working with a manual override
        let set = ExerciseSet(weight: 80, reps: 5, setType: .working, restDuration: 42)
        var resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 42)

        // Switch setType — manual value must still win
        set.setType = .dropSet
        resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 42)
        #expect(resolved != SetType.dropSet.defaultRestDuration)

        // And again to a different type
        set.setType = .pyramid
        resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == 42)
        #expect(resolved != SetType.pyramid.defaultRestDuration)
    }

    /// Inverse of the above: if the user clears the manual value (sets it to
    /// nil), the resolution must fall back to the *current* setType default.
    @Test("clearing manual restDuration falls back to current setType default")
    func clearingManualFallsBackToCurrentSetType() {
        let set = ExerciseSet(weight: 80, reps: 5, setType: .working, restDuration: 42)
        #expect((set.restDuration ?? set.setType.defaultRestDuration) == 42)

        set.setType = .dropSet
        set.restDuration = nil
        let resolved = set.restDuration ?? set.setType.defaultRestDuration
        #expect(resolved == SetType.dropSet.defaultRestDuration)
        #expect(resolved == 15)
    }
}
