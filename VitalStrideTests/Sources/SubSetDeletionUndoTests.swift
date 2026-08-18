import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

private typealias AppWorkoutSetManager = VitalStride.WorkoutSetManager
private typealias AppSetDeletionUndo = VitalStride.SetDeletionUndo
private typealias AppWorkoutSetTree = VitalStride.WorkoutSetTree

/// MY-1420 / MY-1422 — sub-set delete entry points, cascade confirmation, and
/// the 5s undo window.
///
/// Before this issue, `SubSetRow` had no delete affordance at all: the only
/// way to remove a pyramid / drop-set row was deleting its parent main set,
/// which cascades (`WorkoutSetManager.deleteSet`) and takes the just-entered
/// main-set data with it. The data layer already supported deleting a lone
/// sub-set — the gap was purely in the UI, plus the safety net that makes an
/// undoable delete acceptable without a confirmation dialog on the fast path.
///
/// What is covered here is the logic those affordances route through, all of
/// which is deliberately view-independent: the confirm-vs-delete-now decision
/// (`SetDeletionPolicy`), the snapshot/restore round trip
/// (`DeletedSetSnapshot` + `SetDeletionUndo`), the parent/child tree queries
/// and VoiceOver focus target (`WorkoutSetTree`), and the bottom-snackbar
/// arbitration (`BottomSnackbarSlot` / `SetDeletionUndoController`).
@Suite("SubSet deletion, confirmation and undo (MY-1420)")
struct SubSetDeletionUndoTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Deleting a sub-set removes only that row

    @Test("Deleting a sub-set removes only that row and reflows order")
    func deleteSubSetRemovesOnlyThatRow() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let victim = sets[1]
        let survivorIDs = [sets[0], sets[2], sets[3]].map(\.persistentModelID)

        let deleted = AppWorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.map(\.persistentModelID) == survivorIDs)
        #expect(remaining.map(\.order) == [0, 1, 2])
    }

    @Test("Deleting the last sub-set leaves the parent as a plain main set")
    func deleteLastSubSetLeavesPlainParent() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )
        let parent = sets[0]

        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()

        // The tree-line presentation is driven entirely by whether any sub-set
        // rows follow the parent, so a parent with no children can no longer
        // render a dangling connector.
        #expect(AppWorkoutSetTree.subSetChildren(of: parent, in: workoutExercise).isEmpty)
        let ctxs = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        #expect(ctxs.allSatisfy { !$0.isLastSubSet })
    }

    // MARK: - Confirmation policy

    @Test("Parent with sub-sets requires a count-aware confirmation")
    func parentWithChildrenRequiresConfirmation() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )

        let intent = SetDeletionPolicy.intent(for: sets[0], in: workoutExercise)

        #expect(intent == .confirm(childCount: 2, kind: .dropSet))
    }

    @Test("Parent without sub-sets deletes directly — no confirmation regression")
    func parentWithoutChildrenDeletesDirectly() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.working, 85)]
        )

        #expect(SetDeletionPolicy.intent(for: sets[0], in: workoutExercise) == .immediate)
    }

    @Test("Deleting a sub-set never asks for confirmation")
    func subSetDeletesDirectly() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )

        #expect(SetDeletionPolicy.intent(for: sets[1], in: workoutExercise) == .immediate)
    }

    @Test("A mixed sub-set run is described generically, not by one of its types")
    func mixedChildRunUsesGenericKind() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.pyramid, 92), (.working, 85)]
        )

        #expect(SetDeletionPolicy.intent(for: sets[0], in: workoutExercise)
            == .confirm(childCount: 2, kind: .mixed))
    }

    @Test("Confirmation message states the real child count")
    func confirmMessageNamesChildCount() {
        let message = SetDeletionPolicy.confirmMessage(childCount: 3, kind: .dropSet)
        #expect(message.contains("3"))
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

        let snapshots = AppSetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
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

        let snapshots = AppSetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()
        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
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

        let targets = AppWorkoutSetTree.deletionTargets(for: parent, in: workoutExercise)
        #expect(targets.count == 3)

        let snapshots = AppSetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        AppWorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).count == 1)

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [80, 68, 58, 85])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2, 3])
    }

    /// The scenario that passes a naive acceptance pass but breaks in the
    /// field: the user deletes, adds another set inside the 5s window, then
    /// undoes. `order` must stay continuous and duplicate-free — this is why
    /// the implementation deletes immediately rather than deferring, since a
    /// deferred delete leaves `addSet()`'s `sets.count` order basis stale.
    @Test("Undo after a concurrent add keeps order continuous and unique")
    func undoAfterConcurrentAddKeepsOrderContinuous() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let victim = sets[1]

        let snapshots = AppSetDeletionUndo.snapshots(for: [victim], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(victim, from: workoutExercise, using: context)
        try context.save()

        // Concurrent add inside the undo window, mirroring `addSet()`.
        let added = ExerciseSet(
            order: workoutExercise.sets?.count ?? 0,
            weight: 90,
            reps: 5,
            setType: .working
        )
        added.workoutExercise = workoutExercise
        context.insert(added)
        try context.save()

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        let orders = sorted(workoutExercise).map(\.order)
        #expect(orders == Array(0..<orders.count))
        #expect(Set(orders).count == orders.count)
        // The restored sub-set is back between its parent and the next main
        // set; the concurrently added set stays at the tail.
        #expect(sorted(workoutExercise).map(\.weight) == [80, 68, 85, 90])
    }

    // MARK: - Undo controller lifecycle

    @MainActor
    @Test("A new deletion replaces the pending undo instead of stacking")
    func consecutiveDeletionsReplaceUndo() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "first",
            announcement: "first"
        )
        let firstID = controller.pending?.id

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[2]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "second",
            announcement: "second"
        )

        #expect(controller.pending?.id != firstID)
        #expect(controller.pending?.message == "second")
    }

    @MainActor
    @Test("Undo restores through the controller, then clears the window")
    func controllerUndoRestoresAndClears() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        let snapshots = AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()
        controller.record(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: "deleted"
        )

        #expect(controller.undo(using: context))
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [80, 92, 85])
        #expect(!controller.hasPendingUndo)
        // A second tap must not resurrect a duplicate.
        #expect(!controller.undo(using: context))
        #expect(sorted(workoutExercise).count == 3)
    }

    @MainActor
    @Test("The undo window expires on its own")
    func undoWindowExpires() async throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 0.05)

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: "deleted"
        )
        #expect(controller.hasPendingUndo)

        try await Task.sleep(for: .milliseconds(200))
        #expect(!controller.hasPendingUndo)
    }

    @Test("Undo window is 5s — longer than the 3s default, per the training context")
    func undoWindowIsFiveSeconds() {
        #expect(SetUndoTiming.window == 5)
    }

    // MARK: - Bottom snackbar arbitration

    @Test("Undo outranks the rest snackbar while a deletion is pending")
    func undoTakesPriorityOverRest() {
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .resting) == .undo)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .completed) == .undo)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .idle) == .undo)
    }

    @Test("Rest reappears once the undo window closes, and only while resting")
    func restResumesAfterUndoCloses() {
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .resting) == .rest)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle) == .none)
    }

    @MainActor
    @Test("Only one bottom snackbar is ever selected")
    func onlyOneSnackbarSlotAtATime() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        #expect(controller.slot(restPhase: .resting) == .rest)

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: "deleted"
        )
        // Resting is still active underneath — the slot resolves to exactly
        // one winner rather than presenting both.
        #expect(controller.slot(restPhase: .resting) == .undo)

        controller.clear()
        #expect(controller.slot(restPhase: .resting) == .rest)
    }

    // MARK: - VoiceOver focus after deletion

    @Test("Deleting a sub-set moves focus to its parent main set")
    func focusMovesToParentAfterSubSetDeletion() {
        // rows: main, sub, sub, main — delete index 1
        let isSubSet = [false, true, true, false]
        #expect(AppWorkoutSetTree.focusIndexAfterDeletion(deleting: [1], isSubSet: isSubSet) == 0)
    }

    @Test("Deleting a main set moves focus to the next surviving row")
    func focusMovesToNextRowAfterMainDeletion() {
        // rows: main, sub, main — deleting the first main also takes its sub,
        // so focus lands on the surviving main.
        let isSubSet = [false, true, false]
        #expect(AppWorkoutSetTree.focusIndexAfterDeletion(deleting: [0, 1], isSubSet: isSubSet) == 2)
    }

    @Test("Deleting the last row falls back to the previous one")
    func focusFallsBackToPreviousRow() {
        let isSubSet = [false, false]
        #expect(AppWorkoutSetTree.focusIndexAfterDeletion(deleting: [1], isSubSet: isSubSet) == 0)
    }

    @Test("Focus target is nil only when nothing survives")
    func focusIsNilWhenNothingSurvives() {
        #expect(AppWorkoutSetTree.focusIndexAfterDeletion(deleting: [0], isSubSet: [false]) == nil)
    }

    // MARK: - Parent exercise deleted inside the undo window
    //
    // Review finding on 2c2819b: deleting a whole exercise left its pending
    // set-undo armed, so tapping 撤销 afterwards would reattach fresh
    // `ExerciseSet` rows to a deleted `WorkoutExercise` — orphaned data, or a
    // SwiftData runtime failure. Fixed on both sides: `deleteExercise` clears
    // a matching undo up front, and `undo` refuses a dead parent regardless.

    @MainActor
    @Test("Deleting the parent exercise clears its pending set undo")
    func deletingExerciseClearsPendingUndo() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        let snapshots = AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()
        controller.record(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: "deleted"
        )
        #expect(controller.hasPendingUndo)

        // Mirrors `ActiveWorkoutView.deleteExercise`.
        controller.clearIfPending(for: workoutExercise)
        context.delete(workoutExercise)
        try context.save()

        // The snackbar must go with the rows it refers to.
        #expect(!controller.hasPendingUndo)
        #expect(controller.slot(restPhase: .idle) == .none)
    }

    @MainActor
    @Test("Undo refuses to reinsert into a deleted parent exercise")
    func undoRefusesDeletedParent() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        let snapshots = AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()
        controller.record(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: "deleted"
        )

        // Deliberately skip `clearIfPending` — this asserts the controller's
        // own guard, so a future caller that forgets it still can't produce
        // orphaned sets.
        context.delete(workoutExercise)
        try context.save()

        #expect(!controller.undo(using: context))
        #expect(!controller.hasPendingUndo)

        // Nothing was reattached to the dead parent.
        let orphans = try context.fetch(FetchDescriptor<ExerciseSet>())
            .filter { $0.workoutExercise?.persistentModelID == workoutExercise.persistentModelID }
        #expect(orphans.isEmpty)
    }

    @MainActor
    @Test("Deleting a different exercise leaves an unrelated undo intact")
    func deletingOtherExerciseKeepsUndo() throws {
        let context = ModelContext(container)
        let (first, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let (second, _) = makeExercise(context: context, sets: [(.working, 60), (.working, 65)])
        let controller = SetDeletionUndoController(window: 60)

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[1]], in: first),
            workoutExercise: first,
            message: "deleted",
            announcement: "deleted"
        )

        controller.clearIfPending(for: second)

        // Scoped by parent identity — an unrelated deletion must not silently
        // swallow the user's undo window.
        #expect(controller.hasPendingUndo)
    }

    @Test("A live exercise is restorable; a deleted one is not")
    func canRestorePredicateTracksParentLifetime() throws {
        let context = ModelContext(container)
        let (workoutExercise, _) = makeExercise(
            context: context,
            sets: [(.working, 80), (.working, 85)]
        )

        #expect(SetDeletionUndoController.canRestore(into: workoutExercise))

        context.delete(workoutExercise)
        try context.save()

        #expect(!SetDeletionUndoController.canRestore(into: workoutExercise))
    }

    // MARK: - Survivor-relative restore
    //
    // Review finding on b3c2ce9: restore replayed the snapshot's absolute
    // `order`, which is an index into a list that keeps moving. Deleting a row
    // *before* the snapshot inside the undo window shifts everything down, so
    // the old number lands in the wrong slot. Position is now anchored to the
    // nearest surviving predecessor instead.

    @Test("Undo lands survivor-relative when a preceding set is deleted first")
    func undoIsSurvivorRelativeAfterPrecedingDeletion() throws {
        let context = ModelContext(container)
        // [A,B,C,D] — delete C (order 2), then delete preceding A, leaving
        // [B,D]. Replaying index 2 would give [B,D,C]; correct is [B,C,D].
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 10), (.working, 20), (.working, 30), (.working, 40)]
        )

        let snapshots = AppSetDeletionUndo.snapshots(for: [sets[2]], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[2], from: workoutExercise, using: context)
        try context.save()

        AppWorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [20, 40])

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        #expect(sorted(workoutExercise).map(\.weight) == [20, 30, 40])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1, 2])
    }

    @Test("Parent+children run restores survivor-relative after a preceding deletion")
    func undoCascadeIsSurvivorRelativeAfterPrecedingDeletion() throws {
        let context = ModelContext(container)
        // [A, B(main), b1, b2, C] — delete B's whole run, then delete
        // preceding A, leaving [C]. The run must come back before C, in order.
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 10),
                (.working, 20), (.dropSet, 18), (.dropSet, 16),
                (.working, 30)
            ]
        )

        let targets = AppWorkoutSetTree.deletionTargets(for: sets[1], in: workoutExercise)
        #expect(targets.count == 3)
        let snapshots = AppSetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()

        AppWorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [30])

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        // Children stay attached behind their parent, ahead of the survivor.
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

        let snapshots = AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise)
        AppWorkoutSetManager.deleteSet(sets[1], from: workoutExercise, using: context)
        try context.save()
        AppWorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()
        #expect(sorted(workoutExercise).map(\.weight) == [30])

        AppSetDeletionUndo.restore(snapshots, into: workoutExercise, using: context)
        try context.save()

        // Its only predecessor (10) is gone, so it goes back to the head.
        #expect(sorted(workoutExercise).map(\.weight) == [20, 30])
        #expect(sorted(workoutExercise).map(\.order) == [0, 1])
    }

    // MARK: - Announcement identity
    //
    // Review finding on b3c2ce9: `lastAnnouncement` was a bare `String?`
    // observed with `onChange`. Two consecutive deletions of the same set type
    // produce byte-identical text, so the second assignment was not a change
    // and SwiftUI posted no second announcement — a screen-reader user simply
    // never heard about the second delete.

    @MainActor
    @Test("Two identical consecutive deletions each produce a distinct announcement")
    func identicalConsecutiveAnnouncementsAreDistinct() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)

        // Same parent set number and same set type → identical wording.
        let message = SetDeletionPolicy.deletionAnnouncement(
            setNumber: 1,
            setType: .dropSet,
            isSubSet: true
        )

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[1]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: message
        )
        let first = controller.lastAnnouncement

        controller.record(
            snapshots: AppSetDeletionUndo.snapshots(for: [sets[2]], in: workoutExercise),
            workoutExercise: workoutExercise,
            message: "deleted",
            announcement: message
        )
        let second = controller.lastAnnouncement

        #expect(first?.message == second?.message)
        // Identity differs, so `onChange` fires and the second delete is
        // actually announced.
        #expect(first != second)
        #expect(first?.id != second?.id)
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
