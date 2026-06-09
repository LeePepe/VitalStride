import Foundation
import SwiftData
import VitalModels

enum WorkoutSetManager {
    @discardableResult
    static func deleteSet(
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
