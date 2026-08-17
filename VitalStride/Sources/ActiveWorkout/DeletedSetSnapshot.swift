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

/// Immutable capture of every persisted `ExerciseSet` field plus the `order`
/// slot the set occupied at delete time.
///
/// Value-typed on purpose: the SwiftData object it came from is deleted
/// immediately, so nothing here may reference it. Restoring produces a *new*
/// `ExerciseSet` with an equal field set — `persistentModelID` is necessarily
/// new, which is invisible in the UI because rows are keyed off the live model.
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

    init(_ exerciseSet: ExerciseSet) {
        order = exerciseSet.order
        weight = exerciseSet.weight
        reps = exerciseSet.reps
        setType = exerciseSet.setType
        restDuration = exerciseSet.restDuration
        isCompleted = exerciseSet.isCompleted
        isUnilateral = exerciseSet.isUnilateral
        weightRight = exerciseSet.weightRight
        rpe = exerciseSet.rpe
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
    static func snapshots(for sets: [ExerciseSet]) -> [DeletedSetSnapshot] {
        sets.map(DeletedSetSnapshot.init)
    }

    /// Re-inserts `snapshots` into `workoutExercise` at their original relative
    /// positions and renumbers the whole sequence so `order` stays continuous
    /// (0..<n) and duplicate-free.
    ///
    /// Snapshots are applied in ascending `order` so a multi-row capture (a
    /// main set plus its sub-sets) lands back in its original run. Positions
    /// are clamped to the current bounds: if the user deleted other sets during
    /// the undo window the recorded slot may now be past the end, in which case
    /// the set is appended rather than dropped.
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
        var restored: [ExerciseSet] = []
        restored.reserveCapacity(snapshots.count)

        for snapshot in snapshots.sorted(by: { $0.order < $1.order }) {
            let newSet = snapshot.makeSet()
            newSet.workoutExercise = workoutExercise
            modelContext.insert(newSet)

            let insertIndex = min(max(0, snapshot.order), ordered.count)
            ordered.insert(newSet, at: insertIndex)
            restored.append(newSet)
        }

        for (newOrder, set) in ordered.enumerated() {
            set.order = newOrder
        }
        return restored
    }
}
