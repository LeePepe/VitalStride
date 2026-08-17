// Sub-set tree queries for the active-workout list (MY-1420 / MY-1422).
//
// The sub-set tree is positional, not relational: a sub-set (pyramid /
// dropSet) belongs to the nearest preceding main set, and a main set owns the
// run of consecutive sub-sets that follows it. `WorkoutSetManager.deleteSet`
// already encodes that rule for the *delete* itself; this type answers the
// read-only questions the UI needs around it — how many children a parent has
// (for the count-aware confirmation), which rows a delete will consume (for
// the undo snapshot), and where VoiceOver focus should land afterwards.
//
// Deliberately does NOT reimplement the min-one-set guard or any counting
// rule that decides whether a delete is allowed: that stays solely in
// `WorkoutSetManager.deleteSet`, so the two can never drift apart.

import Foundation
import SwiftData
import VitalModels

enum WorkoutSetTree {
    /// Sets belonging to `workoutExercise`, ordered.
    nonisolated static func sortedSets(of workoutExercise: WorkoutExercise) -> [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    /// The run of consecutive sub-sets directly beneath `mainSet`. Empty for a
    /// sub-set, or for a main set with no children.
    nonisolated static func subSetChildren(
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
    /// Used to snapshot the rows before the delete so undo can restore all of
    /// them — mirrors the manager's cascade shape, not its allow/deny guard.
    nonisolated static func deletionTargets(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise
    ) -> [ExerciseSet] {
        [exerciseSet] + subSetChildren(of: exerciseSet, in: workoutExercise)
    }

    /// Index (into the *pre-deletion* row array) of the row that should take
    /// VoiceOver focus once `deletedIndices` are gone.
    ///
    /// Deleting a focused row silently drops VoiceOver focus or drifts it to an
    /// unrelated element, so the caller must move it explicitly. A sub-set
    /// hands focus back to its parent main set — that is the row the user was
    /// working within. Anything else (or a parent that is itself being
    /// deleted) falls through to the next surviving row, then the previous one.
    /// Returns nil only when nothing survives.
    ///
    /// `isSubSet` is indexed in the same order as the rendered rows.
    nonisolated static func focusIndexAfterDeletion(
        deleting deletedIndices: Set<Int>,
        isSubSet: [Bool]
    ) -> Int? {
        guard let first = deletedIndices.min(), let last = deletedIndices.max() else { return nil }

        if first < isSubSet.count && isSubSet[first] {
            var index = first - 1
            while index >= 0 {
                if !deletedIndices.contains(index) && !isSubSet[index] { return index }
                index -= 1
            }
        }

        var forward = last + 1
        while forward < isSubSet.count {
            if !deletedIndices.contains(forward) { return forward }
            forward += 1
        }

        var backward = first - 1
        while backward >= 0 {
            if !deletedIndices.contains(backward) { return backward }
            backward -= 1
        }
        return nil
    }
}
