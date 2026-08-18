import Foundation
import SwiftData
import Testing

@testable import VitalModels

@Suite("DeletedSetSnapshot + SetDeletionUndo — snapshot/restore (MY-1432)")
struct DeletedSetSnapshotTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Undo restores every field at the original relative position

    @Test("Undo restores all persisted fields of a deleted sub-set")
    func undoRestoresAllFields() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let victim = sets[1]
        victim.reps = 12
        victim.rpe = 9
        victim.isCompleted = true
        victim.isUnilateral = true
        victim.weightRight = 66
        victim.restDuration = 45
        try context.save()

        let snapshots = SetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        WorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        let restored = sorted(workoutExercise)[1]
        #expect(restored.setType == .dropSet)
        #expect(restored.weight == 68)
        #expect(restored.reps == 12)
        #expect(restored.rpe == 9)
        #expect(restored.isCompleted)
        #expect(restored.isUnilateral)
        #expect(restored.weightRight == 66)
        #expect(restored.restDuration == 45)
    }

    @Test("Undo returns the set to its original relative position")
    func undoRestoresRelativePosition() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let victim = sets[2]

        let snapshots = SetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        WorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()
        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        let weights = sorted(workoutExercise).map(\.weight)
        #expect(weights == [80, 68, 58, 85])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2, 3])
    }

    @Test("Undo restores a whole parent+children run in one step")
    func undoRestoresCascadedRun() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let parent = sets[0]

        let targets = WorkoutSetTree.deletionTargets(for: parent, in: workoutExercise)
        #expect(targets.count == 3)

        let snapshots = SetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).count == 1)

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [80, 68, 58, 85])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2, 3])
    }

    @Test("Undo after a concurrent add keeps order continuous and unique")
    func undoAfterConcurrentAddKeepsOrderContinuous() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let victim = sets[1]

        let snapshots = SetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        WorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        let added = ExerciseSet(
            order: workoutExercise.sets?.count ?? 0,
            weight: 90,
            reps: 5,
            setType: .working
        )
        added.workoutExercise = workoutExercise
        context.insert(added)
        try context.save()

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        let orders = sorted(workoutExercise).map(\.order)
        #expect(orders == Array(0..<orders.count))
        #expect(Set(orders).count == orders.count)
        #expect(sorted(workoutExercise).map(\.weight) == [80, 68, 85, 90])
    }

    // MARK: - Survivor-relative restore

    @Test("Undo lands survivor-relative when a preceding set is deleted first")
    func undoIsSurvivorRelativeAfterPrecedingDeletion() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 10), (.working, 20), (.working, 30), (.working, 40)]
        )

        let snapshots = SetDeletionUndo.snapshots(for: [sets[2]], in: workoutExercise)
        WorkoutSetManager.deleteSet(sets[2], from: workoutExercise, using: context)
        try context.save()

        WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [20, 40])

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [20, 30, 40])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2])
    }

    @Test("Parent+children run restores survivor-relative after a preceding deletion")
    func undoCascadeIsSurvivorRelativeAfterPrecedingDeletion() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 10),
                (.working, 20), (.dropSet, 18), (.dropSet, 16),
                (.working, 30)
            ]
        )

        let targets = WorkoutSetTree.deletionTargets(for: sets[1], in: workoutExercise)
        #expect(targets.count == 3)
        let snapshots = SetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        WorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()

        WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [30])

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [20, 18, 16, 30])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2, 3])
    }

    @Test("Undo returns to the head when every predecessor is gone")
    func undoFallsBackToHeadWhenAllPredecessorsDeleted() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 10), (.working, 20), (.working, 30)]
        )

        let snapshots = SetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise)
        WorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()
        WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [30])

        SetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [20, 30])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1])
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
