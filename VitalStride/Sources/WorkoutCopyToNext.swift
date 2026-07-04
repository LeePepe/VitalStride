import Foundation
import SwiftData
import VitalModels

/// MY-1073 — Copy-to-next helper for `SetRow`'s Copy key.
///
/// Extracted from `ActiveExerciseSection` so it can be unit-tested without
/// having to instantiate the SwiftUI view. Two branches:
///
/// * **Overwrite:** if a next set exists after `source` (main or sub), copy
///   `weight`, `weightRight`, `reps`, `setType`, `isUnilateral` from `source`
///   onto it. `isCompleted` and `restDuration` are preserved.
/// * **Append:** if `source` is the last set, insert a new main set at the
///   end of the exercise, using the same ordering rules as
///   `ActiveExerciseSection.addSet()` (new `order` = current count).
enum WorkoutCopyToNext {
    static func apply(
        from source: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) {
        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        guard let sourceIndex = sortedSets.firstIndex(where: {
            $0.persistentModelID == source.persistentModelID
        }) else { return }

        let nextIndex = sourceIndex + 1
        if nextIndex < sortedSets.count {
            let target = sortedSets[nextIndex]
            target.weight = source.weight
            target.weightRight = source.weightRight
            target.reps = source.reps
            target.setType = source.setType
            target.isUnilateral = source.isUnilateral
        } else {
            let order = workoutExercise.sets?.count ?? 0
            let newSet = ExerciseSet(
                order: order,
                weight: source.weight,
                reps: source.reps,
                setType: source.setType,
                isUnilateral: source.isUnilateral,
                weightRight: source.weightRight
            )
            newSet.workoutExercise = workoutExercise
            modelContext.insert(newSet)
        }
    }
}
