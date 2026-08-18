import Foundation
import SwiftData

/// Manages deletion (and order reflow) of `ExerciseSet` rows within a
/// `WorkoutExercise`. Extracted from app target for layer compliance (MY-1432).
public enum WorkoutSetManager {
    /// Deletes `exerciseSet` from `workoutExercise`. A main set cascades to its
    /// consecutive sub-set run; a sub-set removes only itself. Returns `false`
    /// (and does nothing) when the delete would leave fewer than 1 row.
    @discardableResult
    public nonisolated static func deleteSet(
        _ exerciseSet: ExerciseSet,
        from workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) -> Bool {
        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }

        var toDelete = [exerciseSet]
        if !exerciseSet.setType.isSubSet {
            if let parentIndex = sortedSets.firstIndex(where: {
                $0.persistentModelID == exerciseSet.persistentModelID
            }) {
                var i = parentIndex + 1
                while i < sortedSets.count && sortedSets[i].setType.isSubSet {
                    toDelete.append(sortedSets[i])
                    i += 1
                }
            }
        }

        guard sortedSets.count - toDelete.count >= 1 else { return false }

        let deleteIDs = Set(toDelete.map { $0.persistentModelID })
        for set in toDelete {
            modelContext.delete(set)
        }
        let remaining = sortedSets.filter { !deleteIDs.contains($0.persistentModelID) }
        for (newOrder, set) in remaining.enumerated() {
            set.order = newOrder
        }
        return true
    }
}
