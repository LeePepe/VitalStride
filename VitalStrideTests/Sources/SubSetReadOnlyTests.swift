import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// MY-875 — SubSet 子组只读化与删除入口收敛
///
/// UI invariants (no SelectAllTextField, no Menu, no swipeActions on sub-set rows)
/// are enforced at the type-system level inside `SubSetRow` in
/// `ActiveWorkoutView.swift`: the row's body uses `Text(...)` only, has no
/// `@State` mirrors for weight/reps, and the enclosing `ForEach` branch for
/// `setType.isSubSet` no longer attaches `.swipeActions`. These tests cover the
/// data-layer invariants that the read-only UI relies on: parent cascade still
/// removes sub-sets atomically.
@Suite("SubSet Read-Only Invariants (MY-875)")
struct SubSetReadOnlyTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Cascade: parent main set deletion removes its sub-sets

    @Test("Deleting parent main set cascades to a single Drop Set sub-set")
    func deleteParentCascadesToDropSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.dropSet, 68.0),  // 80 * 0.85
                (.working, 80.0)   // second main keeps min-one-set invariant
            ]
        )
        let parent = sets[0]
        let child = sets[1]
        let unrelated = sets[2]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == unrelated.persistentModelID)
        // Child should be physically deleted from the store
        let stillThere = try context.fetch(FetchDescriptor<ExerciseSet>())
            .contains { $0.persistentModelID == child.persistentModelID }
        #expect(!stillThere)
    }

    @Test("Deleting parent main set cascades to a single Pyramid sub-set")
    func deleteParentCascadesToPyramid() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.pyramid, 92.0),  // 80 * 1.15
                (.working, 80.0)
            ]
        )
        let parent = sets[0]
        let child = sets[1]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 1)
        let stillThere = try context.fetch(FetchDescriptor<ExerciseSet>())
            .contains { $0.persistentModelID == child.persistentModelID }
        #expect(!stillThere)
    }

    @Test("Deleting parent main set cascades to multiple consecutive sub-sets")
    func deleteParentCascadesToMultipleSubSets() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.dropSet, 68.0),
                (.dropSet, 57.8),
                (.pyramid, 92.0),
                (.working, 80.0)
            ]
        )
        let parent = sets[0]
        let unrelated = sets[4]
        let childIDs = Set(sets[1...3].map { $0.persistentModelID })

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == unrelated.persistentModelID)
        let allSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(allSets.allSatisfy { !childIDs.contains($0.persistentModelID) })
    }

    @Test("Cascade stops at the next main set — second main and its sub-set survive")
    func cascadeStopsAtNextMainSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.dropSet, 68.0),
                (.working, 85.0),
                (.dropSet, 72.0)
            ]
        )
        let parent = sets[0]
        let secondMain = sets[2]
        let secondMainSubSet = sets[3]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 2)
        #expect(remaining[0].persistentModelID == secondMain.persistentModelID)
        #expect(remaining[1].persistentModelID == secondMainSubSet.persistentModelID)
        // Order is reflowed after deletion
        #expect(remaining[0].order == 0)
        #expect(remaining[1].order == 1)
    }

    // MARK: - Helpers

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
            let set = ExerciseSet(
                order: idx,
                weight: item.1,
                reps: 8,
                setType: item.0
            )
            context.insert(set)
            return set
        }

        let workoutExercise = WorkoutExercise(
            order: 0,
            exercise: exercise,
            sets: exerciseSets
        )
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try? context.save()

        return (workoutExercise, exerciseSets)
    }
}
