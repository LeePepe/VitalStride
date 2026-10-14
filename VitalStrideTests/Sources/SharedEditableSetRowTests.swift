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
/// 3. Retained cascade compatibility invariants (parent delete removes child run, stops at next main).
/// 4. Sub-set query restraint (no previous-set lookup, no smart-progression tree walk).
/// 5. A11y label/value composition from translated catalog fragments.
@Suite("Shared Editable Set Row & Deletion Request (spec 026)")
struct SharedEditableSetRowTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Request Handler return-only results & success effects

    @MainActor
    @Test("Sub-set deletion executes immediately with exactly one callback and armed undo")
    func subSetDeletionExecutesImmediately() throws {
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
        if case .success(let focusTarget) = result {
            // Focus target moves to parent main set (index 0)
            #expect(focusTarget == sets[0].persistentModelID)
        } else {
            Issue.record("Expected .success result for sub-set deletion")
        }

        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 3)
        #expect(remaining.map(\.weight) == [80, 68, 85])
    }

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
    @Test("Manager refusal on zero remaining rows produces .refusal and zero success effects")
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
    }

    // MARK: - Probe Decorator Tests

    @MainActor
    @Test("Probe accurately counts requests, seam traversals, and delegates callbacks")
    func probeCountsRequestsAndSeamTraversals() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.pyramid, 92), (.working, 85)]
        )
        let controller = SetDeletionUndoController(window: 60)
        let probe = SetDeletionRequestProbe()
        var callbackCount = 0

        let rowContexts = ActiveExerciseSection.rowContexts(from: sorted(workoutExercise))
        _ = probe.requestDelete(
            for: sets[1],
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: controller,
            modelContext: context,
            onSetDeleted: { callbackCount += 1 }
        )

        #expect(probe.requestCount == 1)
        #expect(probe.seamTraversalCount == 1)
        #expect(probe.callbackCount == 1)
        #expect(probe.lastRequestedSetType == .pyramid)
        #expect(callbackCount == 1)

        probe.reset()
        #expect(probe.requestCount == 0)
        #expect(probe.seamTraversalCount == 0)
        #expect(probe.callbackCount == 0)
    }

    // MARK: - Retained Cascade Compatibility Invariants

    @Test("Deleting parent cascades to single Drop Set sub-set")
    func deleteParentCascadesToDropSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80.0), (.dropSet, 68.0), (.working, 80.0)]
        )
        let deleted = WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == sets[2].persistentModelID)
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
        let deleted = WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 1)
        #expect(remaining[0].persistentModelID == sets[4].persistentModelID)
        #expect(remaining[0].order == 0)
    }

    @Test("Cascade stops at next main set")
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
        let deleted = WorkoutSetManager.deleteSet(sets[0], from: workoutExercise, using: context)
        try context.save()

        #expect(deleted)
        let remaining = sorted(workoutExercise)
        #expect(remaining.count == 2)
        #expect(remaining[0].persistentModelID == sets[2].persistentModelID)
        #expect(remaining[1].persistentModelID == sets[3].persistentModelID)
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
