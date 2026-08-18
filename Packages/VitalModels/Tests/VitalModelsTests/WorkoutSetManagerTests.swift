import Foundation
import SwiftData
import Testing

@testable import VitalModels

@Suite("WorkoutSetManager — group persistence API (MY-1432)")
struct WorkoutSetManagerTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Deleting a sub-set removes only that row

    @Test("Deleting a sub-set removes only that row and reflows order")
    func deleteSubSetRemovesOnlyThatRow() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let victim = sets[1]
        let survivorIDs = [sets[0], sets[2], sets[3]].map(\.persistentModelID)

        let deleted = WorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.map(\.persistentModelID) == survivorIDs)
        #expect(remaining.map(\.order) == [0, 1, 2])
    }

    @Test("Deleting the last sub-set leaves the parent with no children")
    func deleteLastSubSetLeavesPlainParent() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )
        let parent = sets[0]

        WorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()

        #expect(WorkoutSetTree.subSetChildren(of: parent, in: workoutExercise).isEmpty)
    }

    // MARK: - Min-one-set guard

    @Test("Cannot delete the only remaining set")
    func cannotDeleteOnlySet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80)]
        )

        let result = WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)

        #expect(!result)
        #expect(sorted(workoutExercise).count == 1)
    }

    @Test("Cannot delete a parent whose cascade would leave zero rows")
    func cannotDeleteParentWhenCascadeLeavesZero() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58)]
        )

        let result = WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)

        #expect(!result)
        #expect(sorted(workoutExercise).count == 3)
    }

    @Test("Cannot delete a set owned by another workout exercise")
    func cannotDeleteForeignSet() throws {
        let context = ModelContext(container)
        let (targetExercise, _) = makeExercise(
            context: context,
            sets: [(.working, 80), (.working, 85)]
        )
        let (ownerExercise, ownerSets) = makeExercise(
            context: context,
            sets: [(.working, 60), (.dropSet, 50)]
        )
        let foreignSetID = ownerSets[1].persistentModelID

        let result = WorkoutSetManager.deleteSet(
            ownerSets[1],
            from: targetExercise,
            using: context
        )
        try context.save()

        #expect(!result)
        #expect(sorted(targetExercise).count == 2)
        #expect(sorted(ownerExercise).map(\.persistentModelID).contains(foreignSetID))
    }

    // MARK: - Helpers

    private func sorted(_ workoutExercise: WorkoutExercise) -> [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    private func makeExercise(
        context: ModelContext,
        sets: [(SetType, Double)]
    ) -> (WorkoutExercise, [ExerciseSet]) {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let exerciseSets: [ExerciseSet] = sets.enumerated().map { idx, item in
            let set = ExerciseSet(order: idx, weight: item.1, reps: 8, setType: item.0)
            context.insert(set)
            return set
        }

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: exerciseSets)
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try? context.save()

        return (workoutExercise, exerciseSets)
    }
}
