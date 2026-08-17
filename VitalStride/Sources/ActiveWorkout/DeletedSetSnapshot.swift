// Deleted-set snapshot + restore (MY-1420 / MY-1422).
//
// Deletion in the active workout is **immediate and real** — `WorkoutSetManager
// .deleteSet` runs the moment the user swipes or picks "删除", including its
// order renumbering. The 5s undo window therefore cannot be a deferred delete:
// `ActiveExerciseSection.addSet()` derives the new `order` from
// `workoutExercise.sets?.count`, so keeping a doomed row alive for 5s would
// hand out a colliding order to anything added inside the window.
//
// Instead we capture every persisted field before the delete and re-insert a
// fresh `ExerciseSet` at the original *relative* slot on undo. Global `order`
// is not promised to be bit-identical to the pre-delete instant — the user may
// legitimately have added or deleted other sets inside the window — but the
// restored set lands back in its original relative position and the resulting
// sequence is always continuous and duplicate-free.

import Foundation
import SwiftData
import VitalModels

/// How long a delete stays undoable. Longer than the 3s DesignKit default:
/// during a set the user's eyes leave the screen (rack, bar, mirror), so a
/// standard toast expires before it is ever read.
enum SetUndoTiming {
    static let window: TimeInterval = 5
}

/// Immutable capture of every persisted `ExerciseSet` field plus a stable
/// anchor describing where the set sat at delete time.
///
/// Value-typed on purpose: the SwiftData object it came from is deleted
/// immediately, so nothing here may reference it. Restoring produces a *new*
/// `ExerciseSet` with an equal field set — `persistentModelID` is necessarily
/// new, which is invisible in the UI because rows are keyed off the live model.
///
/// Position is remembered as `predecessorIDs` (the identities of every row
/// that preceded this one) rather than the raw `order` integer. `order` is an
/// absolute index into a list that keeps moving: deleting a row *before* the
/// snapshot inside the undo window shifts everything down, so replaying the
/// old number lands in the wrong slot. Concretely `[A,B,C,D]` → delete `C`
/// (order 2) → delete `A` → `[B,D]`; inserting at index 2 yields `[B,D,C]`
/// instead of the survivor-relative `[B,C,D]`. Anchoring to "the nearest
/// predecessor still alive" is stable under any amount of concurrent editing.
struct DeletedSetSnapshot: Sendable, Equatable {
    let order: Int
    let weight: Double
    let reps: Int
    let setType: SetType
    let restDuration: TimeInterval?
    let isCompleted: Bool
    let isUnilateral: Bool
    let weightRight: Double?
    let rpe: Int?
    /// Rows that preceded this one at delete time, nearest last. Includes rows
    /// deleted in the same batch — those are restored first (ascending order),
    /// so a parent is available as its children's anchor.
    let predecessorIDs: [PersistentIdentifier]
    /// Identity of the row this snapshot came from, so siblings restored in
    /// the same batch can anchor to it once it is back in the list.
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
    /// `order` is assigned by `SetDeletionUndo.restore` after re-insertion, so
    /// the value passed here is only a placeholder.
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

enum SetDeletionUndo {
    /// Captures `sets` (which must be in ascending `order`) together with the
    /// predecessor chain each one had inside `workoutExercise`, so restore can
    /// place them survivor-relative rather than by absolute index.
    nonisolated static func snapshots(
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
    ///
    /// Each snapshot lands directly after the nearest of its recorded
    /// predecessors that is still present — including one restored earlier in
    /// this same batch, which is what keeps a parent main set and its sub-set
    /// run together. When no predecessor survives, the set was at the head of
    /// the list and goes back to the head.
    ///
    /// Snapshots are applied in ascending `order` so a multi-row capture is
    /// rebuilt front to back.
    ///
    /// Nonisolated so tests can drive it with a bare `ModelContext` without
    /// hopping through `@MainActor` — matching `ActiveExerciseSection.copyToNext`.
    @discardableResult
    nonisolated static func restore(
        _ snapshots: [DeletedSetSnapshot],
        into workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) -> [ExerciseSet] {
        guard !snapshots.isEmpty else { return [] }

        var ordered = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        // Maps an original identity to the live row now standing in for it, so
        // siblings from the same batch can anchor to an already-restored row.
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
            // A predecessor deleted in the same batch is represented by the
            // row that replaced it.
            let liveID = restoredByOriginalID[predecessorID]?.persistentModelID ?? predecessorID
            if let index = ordered.firstIndex(where: { $0.persistentModelID == liveID }) {
                return index + 1
            }
        }
        return 0
    }
}
