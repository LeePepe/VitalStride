// swiftlint:disable no_hardcoded_chinese
// Set deletion request module (spec 026 / AC-001–AC-005).
//
// Owns policy dispatch, production deletion execution via WorkoutSetManager.deleteSet,
// success-only undo recording and announcement, success-only deletion callback invocation,
// and calculation of the VoiceOver focus target. Returns presentation-only results to the view.

import Foundation
import Observation
import SwiftData
import VitalModels

/// A main-set delete parked behind cascade confirmation, carrying the resolved
/// child count and kind so the confirmation dialog names the actual consequence.
struct CascadeDeletionRequest: Identifiable, Equatable {
    let exerciseSet: ExerciseSet
    let setNumber: Int
    let childCount: Int
    let childKind: SubSetChildKind

    var id: PersistentIdentifier { exerciseSet.persistentModelID }
}

/// Return-only presentation result indicating confirmation requirement,
/// successful deletion with optional focus target, or refusal/no-op.
enum SetDeletionResult: Equatable {
    case confirmationRequired(CascadeDeletionRequest)
    case success(focusTarget: PersistentIdentifier?)
    case refusal
}

@MainActor
protocol SetDeletionRequesting: AnyObject {
    func requestDelete(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult

    func confirmCascadeDelete(
        _ request: CascadeDeletionRequest,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult
}

@MainActor
final class SetDeletionRequestHandler: SetDeletionRequesting {
    static let shared = SetDeletionRequestHandler()

    func requestDelete(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult {
        switch SetDeletionPolicy.intent(for: exerciseSet, in: workoutExercise) {
        case .confirm(let childCount, let kind):
            let setNumber = Self.displaySetNumber(of: exerciseSet, in: rowContexts)
            let cascadeRequest = CascadeDeletionRequest(
                exerciseSet: exerciseSet,
                setNumber: setNumber,
                childCount: childCount,
                childKind: kind
            )
            return .confirmationRequired(cascadeRequest)
        case .immediate:
            return executeDelete(
                for: exerciseSet,
                in: workoutExercise,
                rowContexts: rowContexts,
                undoController: undoController,
                modelContext: modelContext,
                onSetDeleted: onSetDeleted
            )
        }
    }

    func confirmCascadeDelete(
        _ request: CascadeDeletionRequest,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult {
        return executeDelete(
            for: request.exerciseSet,
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: undoController,
            modelContext: modelContext,
            onSetDeleted: onSetDeleted
        )
    }

    private func executeDelete(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult {
        let targets = WorkoutSetTree.deletionTargets(for: exerciseSet, in: workoutExercise)
        let targetIDs = Set(targets.map(\.persistentModelID))
        let snapshots = SetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        let isSubSet = exerciseSet.setType.isSubSet
        let setNumber = Self.displaySetNumber(of: exerciseSet, in: rowContexts)
        let setType = exerciseSet.setType

        let deletedIndices = Set(rowContexts.indices.filter {
            targetIDs.contains(rowContexts[$0].exerciseSet.persistentModelID)
        })
        let focusTarget = SetDeletionFocusTarget.focusIndexAfterDeletion(
            deleting: deletedIndices,
            isSubSet: rowContexts.map { $0.exerciseSet.setType.isSubSet }
        ).map { rowContexts[$0].exerciseSet.persistentModelID }

        let didDelete = WorkoutSetManager.deleteSet(exerciseSet, from: workoutExercise, using: modelContext)
        guard didDelete else {
            return .refusal
        }

        undoController.record(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: SetDeletionPolicy.undoMessage(
                setNumber: setNumber,
                setType: setType,
                isSubSet: isSubSet
            ),
            announcement: SetDeletionPolicy.deletionAnnouncement(
                setNumber: setNumber,
                setType: setType,
                isSubSet: isSubSet
            )
        )

        onSetDeleted()
        return .success(focusTarget: focusTarget)
    }

    nonisolated static func displaySetNumber(
        of exerciseSet: ExerciseSet,
        in rowContexts: [ActiveExerciseSection.RowContext]
    ) -> Int {
        guard let ctx = rowContexts.first(where: {
            $0.exerciseSet.persistentModelID == exerciseSet.persistentModelID
        }) else { return 1 }
        return exerciseSet.setType.isSubSet ? ctx.mainSetNumber : ctx.mainSetNumber + 1
    }
}

#if DEBUG
@MainActor
@Observable
final class SetDeletionRequestProbe: SetDeletionRequesting {
    let underlying: any SetDeletionRequesting
    private(set) var requestCount: Int = 0
    private(set) var seamTraversalCount: Int = 0
    private(set) var callbackCount: Int = 0
    private(set) var lastRequestedSetID: PersistentIdentifier?
    private(set) var lastRequestedSetType: SetType?

    init(underlying: any SetDeletionRequesting = SetDeletionRequestHandler.shared) {
        self.underlying = underlying
    }

    func requestDelete(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult {
        requestCount += 1
        seamTraversalCount += 1
        lastRequestedSetID = exerciseSet.persistentModelID
        lastRequestedSetType = exerciseSet.setType
        return underlying.requestDelete(
            for: exerciseSet,
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: undoController,
            modelContext: modelContext,
            onSetDeleted: { [weak self] in
                self?.callbackCount += 1
                onSetDeleted()
            }
        )
    }

    func confirmCascadeDelete(
        _ request: CascadeDeletionRequest,
        in workoutExercise: WorkoutExercise,
        rowContexts: [ActiveExerciseSection.RowContext],
        undoController: SetDeletionUndoController,
        modelContext: ModelContext,
        onSetDeleted: () -> Void
    ) -> SetDeletionResult {
        requestCount += 1
        seamTraversalCount += 1
        lastRequestedSetID = request.exerciseSet.persistentModelID
        lastRequestedSetType = request.exerciseSet.setType
        return underlying.confirmCascadeDelete(
            request,
            in: workoutExercise,
            rowContexts: rowContexts,
            undoController: undoController,
            modelContext: modelContext,
            onSetDeleted: { [weak self] in
                self?.callbackCount += 1
                onSetDeleted()
            }
        )
    }

    func reset() {
        requestCount = 0
        seamTraversalCount = 0
        callbackCount = 0
        lastRequestedSetID = nil
        lastRequestedSetType = nil
    }
}
#endif
