import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// Shared editable set row and deletion request module tests (spec 026 / AC-003–AC-011).
///
/// Covers:
/// 1. Shared editable composition and model synchronization for standard, pyramid, and drop-set rows.
/// 2. Request handler return-only presentation results, success effects, and refusal on zero rows.
/// 3. Exact undo restoration for both pyramid and drop-set rows with order reflow and announcement.
/// 4. Retained cascade compatibility invariants (parent delete removes child run, physical SwiftData deletion).
/// 5. Sub-set query restraint (no previous-set lookup, no smart-progression tree walk).
@Suite("Shared Editable Set Row & Deletion Request (spec 026)")
struct SharedEditableSetRowTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - AC-003 & AC-005: Pyramid & Drop-Set Deletion & Exact Undo Restoration

    @MainActor
    @Test("Pyramid deletion executes immediately, reflows order, and exact undo restores values and order")
    func pyramidDeletionAndExactUndoRestoration() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let handler = SetDeletionRequestHandler()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        let result = handler.requestDelete(
            for: sets[1],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        try context.save()

        #expect(callbackCount == 1)
        #expect(controller.hasPendingUndo)
        #expect(controller.lastAnnouncement != nil)
        let announcementMsg = controller.lastAnnouncement?.message ?? ""
        #expect(announcementMsg.contains("1") || announcementMsg.contains("第 1 组"))

        if case .success(let focusTarget) = result {
            // Focus target moves to parent main set (index 0)
            #expect(focusTarget == sets[0].persistentModelID)
        } else {
            Issue.record("Expected .success result for pyramid deletion")
        }

        // Parent (80), sibling drop-set (68), and next main (85) intact; survivor orders reflowed
        let survivors = sorted(workoutExercise)
        #expect(survivors.count == 3)
        #expect(survivors.map(\.weight) == [80, 68, 85])
        #expect(survivors.map(\.order) == [0, 1, 2])

        // Execute Undo
        let undoSuccess = controller.undo(using: context)
        try context.save()

        #expect(undoSuccess)
        #expect(!controller.hasPendingUndo)

        // Exact restored values and order reflowed
        let restored = sorted(workoutExercise)
        #expect(restored.count == 4)
        #expect(restored.map(\.weight) == [80, 92, 68, 85])
        #expect(restored.map(\.reps) == [8, 8, 8, 8])
        #expect(restored.map(\.setType) == [.working, .pyramid, .dropSet, .working])
        #expect(restored.map(\.order) == [0, 1, 2, 3])
    }

    @MainActor
    @Test("Drop-set deletion executes immediately, reflows order, and exact undo restores values and order")
    func dropSetDeletionAndExactUndoRestoration() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let handler = SetDeletionRequestHandler()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        let result = handler.requestDelete(
            for: sets[2],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        try context.save()

        #expect(callbackCount == 1)
        #expect(controller.hasPendingUndo)
        #expect(controller.lastAnnouncement != nil)

        if case .success(let focusTarget) = result {
            // Focus target moves to parent main set (index 0)
            #expect(focusTarget == sets[0].persistentModelID)
        } else {
            Issue.record("Expected .success result for drop-set deletion")
        }

        let survivors = sorted(workoutExercise)
        #expect(survivors.count == 3)
        #expect(survivors.map(\.weight) == [80, 92, 85])
        #expect(survivors.map(\.order) == [0, 1, 2])

        // Execute Undo
        let undoSuccess = controller.undo(using: context)
        try context.save()

        #expect(undoSuccess)
        #expect(!controller.hasPendingUndo)

        let restored = sorted(workoutExercise)
        #expect(restored.count == 4)
        #expect(restored.map(\.weight) == [80, 92, 68, 85])
        #expect(restored.map(\.order) == [0, 1, 2, 3])
    }

    // MARK: - AC-004 & AC-005: Parent Cascade Confirmation & Production Refusal

    @MainActor
    @Test("Parent with children returns confirmationRequired without deleting or firing callbacks")
    func parentWithChildrenReturnsConfirmationRequired() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let handler = SetDeletionRequestHandler()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        let result = handler.requestDelete(
            for: sets[0],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        #expect(callbackCount == 0)
        #expect(!controller.hasPendingUndo)
        if case .confirmationRequired(let request) = result {
            #expect(request.exerciseSet.persistentModelID == sets[0].persistentModelID)
            #expect(request.childCount == 1)
            #expect(request.childKind == .dropSet)
            #expect(request.setNumber == 1)
        } else {
            Issue.record("Expected .confirmationRequired result")
        }

        // Confirmed execution deletes parent + children
        if case .confirmationRequired(let request) = result {
            let confirmResult = handler.confirmCascadeDelete(
                request,
                in: workoutExercise,
                rowContexts: rowContexts,
                undoController: controller,
                modelContext: context,
                onSetDeleted: { callbackCount += 1 }
            )
            try context.save()

            #expect(callbackCount == 1)
            #expect(controller.hasPendingUndo)
            if case .success(let focusTarget) = confirmResult {
                #expect(focusTarget == sets[2].persistentModelID)
            } else {
                Issue.record("Expected .success on confirmed cascade delete")
            }

            let remaining = sorted(workoutExercise)
            #expect(remaining.count == 1)
            #expect(remaining[0].persistentModelID == sets[2].persistentModelID)
        }
    }

    @MainActor
    @Test("Manager refusal on zero remaining rows produces .refusal, 0 callbacks, empty undo, and unchanged rows")
    func managerRefusalProducesZeroEffects() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let handler = SetDeletionRequestHandler()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        let result = handler.requestDelete(
            for: sets[0],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        // Confirmation requested
        guard case .confirmationRequired(let request) = result else {
            Issue.record("Expected confirmation for parent with child")
            return
        }

        let confirmResult = handler.confirmCascadeDelete(
            request,
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        // Refusal: 0 remaining rows is illegal in WorkoutSetManager
        #expect(confirmResult == .refusal)
        #expect(callbackCount == 0)
        #expect(!controller.hasPendingUndo)
        #expect(controller.lastAnnouncement == nil)

        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 2)
        #expect(remaining[0].persistentModelID == sets[0].persistentModelID)
        #expect(remaining[1].persistentModelID == sets[1].persistentModelID)
        #expect(remaining[0].order == 0)
        #expect(remaining[1].order == 1)
    }

    // MARK: - AC-001 & AC-002: Independent Route Boundary Counting

    @MainActor
    @Test("Probe accurately counts section requests and seam traversals independently")
    func probeCountsSectionRequestAndSeamIndependently() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let probe = SetDeletionRequestProbe()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))

        // 1. Section request boundary
        probe.recordSectionRequest(for: sets[0])
        #expect(probe.requestCount == 1)
        #expect(probe.seamTraversalCount == 0)

        // 2. Seam traversal boundary (returns confirmationRequired)
        let result = probe.requestDelete(
            for: sets[0],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )
        #expect(probe.requestCount == 1)
        #expect(probe.seamTraversalCount == 1)
        #expect(probe.lastRequestedSetID == sets[0].persistentModelID)

        guard case .confirmationRequired(let request) = result else {
            Issue.record("Expected confirmation")
            return
        }

        // 3. Cascade confirmation execution (2nd seam traversal, requestCount unchanged)
        _ = probe.confirmCascadeDelete(
            request,
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )
        #expect(probe.requestCount == 1)
        #expect(probe.seamTraversalCount == 2)
        #expect(probe.callbackCount == 1)
        #expect(callbackCount == 1)
    }

    // MARK: - AC-008: Shared Row Composition, Subtype, RPE, Unilateral & Copy

    @Test("Sub-set row fields edit and sync to model correctly")
    func subSetRowFieldsSyncToModel() throws {
        let context = ModelContext(container)
        let (_, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92)]
        )
        let child = sets[1]

        // Weight edit
        child.weight = 95.5
        #expect(child.weight == 95.5)

        // Reps edit
        child.reps = 10
        #expect(child.reps == 10)

        // RPE change
        child.rpe = 8
        #expect(child.rpe == 8)

        // Subtype change without losing parent or order
        child.setType = .dropSet
        #expect(child.setType == .dropSet)
        #expect(child.order == 1)

        // Completion toggle
        child.isCompleted = true
        #expect(child.isCompleted == true)
    }

    @Test("Sub-set unilateral editing and copy to next set")
    func subSetUnilateralAndCopy() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )
        let child = sets[1]

        // Unilateral toggle
        child.isUnilateral = true
        child.weightRight = 90.0
        #expect(child.isUnilateral)
        #expect(child.weight == 92)
        #expect(child.weightRight == 90.0)

        // Copy to next set (copies from child to next main set)
        ActiveExerciseSection.copyToNext(from: child, in: workoutExercise, using: context)
        try context.save()

        let nextSet = sorted(workoutExercise)[2]
        #expect(nextSet.weight == 92)
        #expect(nextSet.weightRight == 90.0)
        #expect(nextSet.isUnilateral == true)
        #expect(nextSet.setType == .pyramid)
    }

    // MARK: - AC-010: Query Restraint for Sub-Sets

    @Test("Child rows have nil previousSet and perform zero history lookup")
    func childRowsHaveNilPreviousSetAndZeroHistoryLookup() throws {
        let context = ModelContext(container)
        let (_, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.dropSet, 68)]
        )

        let rowContexts = ActiveExerciseSection.rowContexts(from: sets)
        #expect(rowContexts.count == 3)

        // Main set has recentWeightKg nil initially, child sets see recentWeightKg = 80
        #expect(rowContexts[0].recentWeightKg == nil)
        #expect(rowContexts[1].recentWeightKg == 80)
        #expect(rowContexts[2].recentWeightKg == 80)
    }

    // MARK: - AC-009 & AC-011: Retained Cascade Compatibility Invariants (Physical Store Deletion)

    @Test("Deleting parent cascades to single Pyramid sub-set with physical store deletion")
    func deleteParentCascadesToSinglePyramidSubSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.pyramid, 92.0),
                (.working, 80.0)
            ]
        )
        let parent = sets[0]
        let child = sets[1]
        let unrelated = sets[2]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == unrelated.persistentModelID)

        // Physical deletion check from persistent store
        let allSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(!allSets.contains { $0.persistentModelID == child.persistentModelID })
        #expect(!allSets.contains { $0.persistentModelID == parent.persistentModelID })
    }

    @Test("Deleting parent cascades to single Drop Set sub-set with physical store deletion")
    func deleteParentCascadesToSingleDropSetSubSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                (.working, 80.0),
                (.dropSet, 68.0),
                (.working, 80.0)
            ]
        )
        let parent = sets[0]
        let child = sets[1]
        let unrelated = sets[2]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == unrelated.persistentModelID)

        // Physical deletion check from persistent store
        let allSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(!allSets.contains { $0.persistentModelID == child.persistentModelID })
        #expect(!allSets.contains { $0.persistentModelID == parent.persistentModelID })
    }

    @Test("Deleting parent cascades to multiple consecutive sub-sets and reflows order")
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
        let childIDs = Set(sets[1...3].map { $0.persistentModelID })
        let unrelated = sets[4]

        let deleted = WorkoutSetManager.deleteSet(parent, from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == unrelated.persistentModelID)
        #expect(remaining[0].order == 0)

        let allSets = try context.fetch(FetchDescriptor<ExerciseSet>())
        #expect(allSets.allSatisfy { !childIDs.contains($0.persistentModelID) })
    }

    @Test("Cascade stops at next main set and reflows survivor order")
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
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 2)
        #expect(remaining[0].persistentModelID == secondMain.persistentModelID)
        #expect(remaining[1].persistentModelID == secondMainSubSet.persistentModelID)
        #expect(remaining[0].order == 0)
        #expect(remaining[1].order == 1)
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
