import Foundation
import SwiftData

/// Sub-set tree queries — reads the positional parent/child relationship
/// encoded by `SetType.isSubSet` + order. Extracted from app target (MY-1432).
///
/// A sub-set (pyramid / dropSet) belongs to the nearest preceding main set.
/// A main set owns the run of consecutive sub-sets that follows it.
public enum WorkoutSetTree {
    /// Sets belonging to `workoutExercise`, ordered by `order`.
    nonisolated static func sortedSets(of workoutExercise: WorkoutExercise) -> [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    /// The run of consecutive sub-sets directly beneath `mainSet`. Empty for a
    /// sub-set, or for a main set with no children.
    public nonisolated static func subSetChildren(
        of mainSet: ExerciseSet,
        in workoutExercise: WorkoutExercise
    ) -> [ExerciseSet] {
        guard !mainSet.setType.isSubSet else { return [] }
        let sets = sortedSets(of: workoutExercise)
        guard let parentIndex = sets.firstIndex(where: {
            $0.persistentModelID == mainSet.persistentModelID
        }) else { return [] }

        var children: [ExerciseSet] = []
        var index = parentIndex + 1
        while index < sets.count && sets[index].setType.isSubSet {
            children.append(sets[index])
            index += 1
        }
        return children
    }

    /// Every set `WorkoutSetManager.deleteSet` would remove for this request:
    /// a sub-set removes only itself, a main set also takes its child run.
    public nonisolated static func deletionTargets(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise
    ) -> [ExerciseSet] {
        [exerciseSet] + subSetChildren(of: exerciseSet, in: workoutExercise)
    }
}
