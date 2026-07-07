import Foundation
import Testing
import VitalModels

@testable import VitalStride

@Suite("SmartProgressionAdvisor")
struct SmartProgressionAdvisorTests {

    // MARK: - Fixtures

    private func set(order: Int = 0, weight: Double, reps: Int) -> ExerciseSet {
        ExerciseSet(order: order, weight: weight, reps: reps, setType: .working)
    }

    private let range8to12: ClosedRange<Int> = 8...12
    private let range10only: ClosedRange<Int> = 10...10

    // MARK: - Empty history / graceful degradation

    @Test("Empty history returns nil so SetRow renders no chip")
    func emptyHistoryReturnsNil() {
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: [],
            userPreferredRepRange: range8to12,
            muscleGroup: .chest
        )
        #expect(advice == nil)
    }

    @Test("Empty history returns nil regardless of muscle group")
    func emptyHistoryReturnsNilWithNilMuscleGroup() {
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: [],
            userPreferredRepRange: range8to12,
            muscleGroup: nil
        )
        #expect(advice == nil)
    }

    // MARK: - All-hit upper bound → increaseWeight

    @Test("All sets hit upper bound → increaseWeight (small muscle +2.5 kg)")
    func allHitUpperBoundSmallMuscleIncrements2_5() {
        let sets = [
            set(order: 0, weight: 20, reps: 12),
            set(order: 1, weight: 20, reps: 12),
            set(order: 2, weight: 20, reps: 12),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .arms
        )
        guard case let .increaseWeight(weight, reps, reason) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 22.5)
        #expect(reps == 8)
        #expect(!reason.isEmpty)
    }

    @Test("All sets hit upper bound → increaseWeight (large muscle +5 kg)")
    func allHitUpperBoundLargeMuscleIncrements5() {
        let sets = [
            set(order: 0, weight: 80, reps: 12),
            set(order: 1, weight: 80, reps: 12),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .legs
        )
        guard case let .increaseWeight(weight, reps, _) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 85)
        #expect(reps == 8)
    }

    @Test("All sets hit upper bound with nil muscle group falls back to small (+2.5)")
    func allHitUpperBoundNilMuscleGroupUsesSmallIncrement() {
        let sets = [set(order: 0, weight: 15, reps: 12)]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: nil
        )
        guard case let .increaseWeight(weight, _, _) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 17.5)
    }

    @Test("Single set exceeding upper bound also triggers increaseWeight")
    func singleSetAboveUpperBoundIncreasesWeight() {
        let sets = [set(order: 0, weight: 40, reps: 15)]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .chest
        )
        guard case let .increaseWeight(weight, reps, _) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 45)
        #expect(reps == 8)
    }

    @Test("Increase-weight anchors off the first set's weight, not the last")
    func increaseWeightAnchorsOffFirstSet() {
        let sets = [
            set(order: 0, weight: 30, reps: 12),
            set(order: 1, weight: 20, reps: 12),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .arms
        )
        guard case let .increaseWeight(weight, _, _) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 32.5)
    }

    // MARK: - All-below lower bound → decreaseWeight

    @Test("All sets below lower bound → decreaseWeight (large muscle -5 kg)")
    func allBelowLowerBoundLargeMuscleDecrements5() {
        let sets = [
            set(order: 0, weight: 100, reps: 6),
            set(order: 1, weight: 100, reps: 5),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .back
        )
        guard case let .decreaseWeight(weight, reps, reason) = advice else {
            Issue.record("Expected .decreaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 95)
        #expect(reps == 12)
        #expect(!reason.isEmpty)
    }

    @Test("All sets below lower bound → decreaseWeight (small muscle -2.5 kg)")
    func allBelowLowerBoundSmallMuscleDecrements2_5() {
        let sets = [
            set(order: 0, weight: 20, reps: 5),
            set(order: 1, weight: 20, reps: 4),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .shoulders
        )
        guard case let .decreaseWeight(weight, reps, _) = advice else {
            Issue.record("Expected .decreaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 17.5)
        #expect(reps == 12)
    }

    @Test("DecreaseWeight clamps at 0 kg when the increment would go negative")
    func decreaseWeightClampsAtZero() {
        let sets = [set(order: 0, weight: 1, reps: 3)]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .legs
        )
        guard case let .decreaseWeight(weight, _, _) = advice else {
            Issue.record("Expected .decreaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 0)
    }

    // MARK: - Last-set drop-off → maintain

    @Test("Last set below lower bound, earlier sets held → maintain at last set")
    func lastSetDropOffMaintains() {
        let sets = [
            set(order: 0, weight: 60, reps: 10),
            set(order: 1, weight: 60, reps: 9),
            set(order: 2, weight: 60, reps: 5),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .chest
        )
        guard case let .maintain(weight, reps, reason) = advice else {
            Issue.record("Expected .maintain, got \(String(describing: advice))")
            return
        }
        #expect(weight == 60)
        #expect(reps == 5)
        #expect(!reason.isEmpty)
    }

    // MARK: - Mid / in-range → maintain

    @Test("All sets sit inside the target range → maintain at last set")
    func inRangeMaintains() {
        let sets = [
            set(order: 0, weight: 50, reps: 10),
            set(order: 1, weight: 50, reps: 9),
            set(order: 2, weight: 50, reps: 9),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .chest
        )
        guard case let .maintain(weight, reps, _) = advice else {
            Issue.record("Expected .maintain, got \(String(describing: advice))")
            return
        }
        #expect(weight == 50)
        #expect(reps == 9)
    }

    @Test("Mixed history without all-hit / all-below / last-drop → maintain")
    func mixedHistoryFallsThroughToMaintain() {
        let sets = [
            set(order: 0, weight: 70, reps: 12),
            set(order: 1, weight: 70, reps: 8),
            set(order: 2, weight: 70, reps: 10),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range8to12,
            muscleGroup: .back
        )
        guard case let .maintain(weight, reps, _) = advice else {
            Issue.record("Expected .maintain, got \(String(describing: advice))")
            return
        }
        #expect(weight == 70)
        #expect(reps == 10)
    }

    // MARK: - Boundary / degenerate ranges

    @Test("Degenerate range 10...10 treats reps == 10 as hitting the upper bound")
    func degenerateRangeAllHitTriggersIncrease() {
        let sets = [
            set(order: 0, weight: 40, reps: 10),
            set(order: 1, weight: 40, reps: 10),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range10only,
            muscleGroup: .arms
        )
        guard case let .increaseWeight(weight, reps, _) = advice else {
            Issue.record("Expected .increaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 42.5)
        #expect(reps == 10)
    }

    @Test("Degenerate range 10...10 with reps == 9 fires all-below decreaseWeight")
    func degenerateRangeAllBelowTriggersDecrease() {
        let sets = [
            set(order: 0, weight: 40, reps: 9),
            set(order: 1, weight: 40, reps: 9),
        ]
        let advice = SmartProgressionAdvisor.suggest(
            previousMainSets: sets,
            userPreferredRepRange: range10only,
            muscleGroup: .arms
        )
        guard case let .decreaseWeight(weight, _, _) = advice else {
            Issue.record("Expected .decreaseWeight, got \(String(describing: advice))")
            return
        }
        #expect(weight == 37.5)
    }

    // MARK: - Archetype table (loadIncrementKg)

    @Test("Large muscle groups (legs, back, chest, fullBody) receive +5 kg increment")
    func largeMuscleGroupIncrements() {
        for group in [MuscleGroup.legs, .back, .chest, .fullBody] {
            #expect(SmartProgressionAdvisor.loadIncrementKg(for: group) == 5.0)
        }
    }

    @Test("Small muscle groups (shoulders, arms, core) receive +2.5 kg increment")
    func smallMuscleGroupIncrements() {
        for group in [MuscleGroup.shoulders, .arms, .core] {
            #expect(SmartProgressionAdvisor.loadIncrementKg(for: group) == 2.5)
        }
    }

    @Test("Nil muscle group falls back to the conservative small-group increment")
    func nilMuscleGroupUsesSmallIncrement() {
        #expect(SmartProgressionAdvisor.loadIncrementKg(for: nil) == 2.5)
    }

    // MARK: - Uniform payload accessors

    @Test("suggestedWeight / suggestedReps / reason accessors surface every case's payload")
    func uniformAccessorsExposePayload() {
        let cases: [ProgressionAdvice] = [
            .maintain(weight: 10, reps: 9, reason: "m"),
            .increaseWeight(weight: 11, reps: 8, reason: "iw"),
            .increaseReps(weight: 12, reps: 10, reason: "ir"),
            .decreaseWeight(weight: 9, reps: 12, reason: "dw"),
        ]
        let expectedWeights = [10.0, 11.0, 12.0, 9.0]
        let expectedReps = [9, 8, 10, 12]
        let expectedReasons = ["m", "iw", "ir", "dw"]

        for (index, advice) in cases.enumerated() {
            #expect(advice.suggestedWeight == expectedWeights[index])
            #expect(advice.suggestedReps == expectedReps[index])
            #expect(advice.reason == expectedReasons[index])
        }
    }
}
