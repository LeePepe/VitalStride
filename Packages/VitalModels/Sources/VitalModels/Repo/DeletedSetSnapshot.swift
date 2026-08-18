import Foundation
import SwiftData

/// Immutable capture of every persisted `ExerciseSet` field plus a stable
/// anchor describing where the set sat at delete time.
///
/// Value-typed on purpose: the SwiftData object it came from is deleted
/// immediately, so nothing here may reference it. Restoring produces a *new*
/// `ExerciseSet` with an equal field set.
///
/// Position is remembered as `predecessorIDs` rather than the raw `order`
/// integer, anchoring to "the nearest predecessor still alive" which is stable
/// under any amount of concurrent editing.
public struct DeletedSetSnapshot: Sendable, Equatable {
    let order: Int
    let weight: Double
    let reps: Int
    let setType: SetType
    let restDuration: TimeInterval?
    let isCompleted: Bool
    let isUnilateral: Bool
    let weightRight: Double?
    let rpe: Int?
    /// Rows that preceded this one at delete time, nearest last.
    let predecessorIDs: [PersistentIdentifier]
    /// Identity of the row this snapshot came from.
    let originalID: PersistentIdentifier

    init(_ exerciseSet: ExerciseSet, predecessorIDs: [PersistentIdentifier] = []) {
        order = exerciseSet.order
        weight = exerciseSet.weight
        reps = exerciseSet.reps
        setType = exerciseSet.setType
        restDuration = exerciseSet.restDuration
        isCompleted = exerciseSet.isCompleted
        isUnilateral = exerciseSet.isUnilateral
        weightRight = exerciseSet.weightRight
        rpe = exerciseSet.rpe
        self.predecessorIDs = predecessorIDs
        originalID = exerciseSet.persistentModelID
    }

    /// Rebuilds an unattached `ExerciseSet` carrying every captured field.
    func makeSet() -> ExerciseSet {
        ExerciseSet(
            order: order,
            weight: weight,
            reps: reps,
            setType: setType,
            restDuration: restDuration,
            isCompleted: isCompleted,
            isUnilateral: isUnilateral,
            weightRight: weightRight,
            rpe: rpe
        )
    }
}

/// Snapshot/restore logic for the set-deletion undo system (MY-1432).
public enum SetDeletionUndo {
    /// Captures `sets` together with the predecessor chain each one had inside
    /// `workoutExercise`, so restore can place them survivor-relative.
    public nonisolated static func snapshots(
        for sets: [ExerciseSet],
        in workoutExercise: WorkoutExercise
    ) -> [DeletedSetSnapshot] {
        let ordered = WorkoutSetTree.sortedSets(of: workoutExercise)
        return sets.map { set in
            let precedingIDs: [PersistentIdentifier]
            if let index = ordered.firstIndex(where: {
                $0.persistentModelID == set.persistentModelID
            }) {
                precedingIDs = ordered[..<index].map(\.persistentModelID)
            } else {
                precedingIDs = []
            }
            return DeletedSetSnapshot(set, predecessorIDs: precedingIDs)
        }
    }

    /// Re-inserts `snapshots` at their original *survivor-relative* positions
    /// and renumbers the whole sequence so `order` stays continuous (0..<n)
    /// and duplicate-free.
    @discardableResult
    public nonisolated static func restore(
        _ snapshots: [DeletedSetSnapshot],
        into workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) -> [ExerciseSet] {
        guard !snapshots.isEmpty else { return [] }

        var ordered = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        var restoredByOriginalID: [PersistentIdentifier: ExerciseSet] = [:]
        var restored: [ExerciseSet] = []
        restored.reserveCapacity(snapshots.count)

        for snapshot in snapshots.sorted(by: { $0.order < $1.order }) {
            let newSet = snapshot.makeSet()
            newSet.workoutExercise = workoutExercise
            modelContext.insert(newSet)

            let insertIndex = insertionIndex(
                for: snapshot,
                in: ordered,
                restoredByOriginalID: restoredByOriginalID
            )
            ordered.insert(newSet, at: insertIndex)
            restoredByOriginalID[snapshot.originalID] = newSet
            restored.append(newSet)
        }

        for (newOrder, set) in ordered.enumerated() {
            set.order = newOrder
        }
        return restored
    }

    /// Slot just after the nearest surviving predecessor, or the head of the
    /// list when none of them are left.
    private nonisolated static func insertionIndex(
        for snapshot: DeletedSetSnapshot,
        in ordered: [ExerciseSet],
        restoredByOriginalID: [PersistentIdentifier: ExerciseSet]
    ) -> Int {
        for predecessorID in snapshot.predecessorIDs.reversed() {
            let liveID = restoredByOriginalID[predecessorID]?.persistentModelID ?? predecessorID
            if let index = ordered.firstIndex(where: { $0.persistentModelID == liveID }) {
                return index + 1
            }
        }
        return 0
    }
}
