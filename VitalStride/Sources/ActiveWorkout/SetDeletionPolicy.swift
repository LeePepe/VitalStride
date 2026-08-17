// swiftlint:disable no_hardcoded_chinese
// Set-deletion policy + copy (MY-1420 / MY-1422).
//
// Decides *whether a delete needs confirmation* and *what the user is told*,
// with no SwiftUI involved, so both are unit-testable without rendering a row.
//
// Confirmation is deliberately narrow. Single-set deletion is a high-frequency
// move during a workout — rest between sets is 60-90s — so gating it behind a
// dialog would tax the fast path and cover the numbers just entered. It is
// gated only when the delete reaches **beyond the row the user acted on**:
// deleting a main set silently takes the whole run of sub-sets under it
// (`WorkoutSetManager.deleteSet`), a consequence the user cannot see from the
// row they swiped. Everything else deletes immediately and is protected by the
// undo snackbar instead (see `SetDeletionUndoController`).

import Foundation
import VitalModels

/// The kind of sub-set run hanging under a main set, used to phrase the
/// confirmation. A run of one type names that type; a mixed run falls back to
/// the generic term rather than picking a misleading winner.
enum SubSetChildKind: Equatable {
    case pyramid
    case dropSet
    case mixed

    /// nil when there are no children at all (nothing to describe).
    static func resolve(from types: [SetType]) -> SubSetChildKind? {
        guard !types.isEmpty else { return nil }
        if types.allSatisfy({ $0 == .pyramid }) { return .pyramid }
        if types.allSatisfy({ $0 == .dropSet }) { return .dropSet }
        return .mixed
    }

    var localizedDescription: String {
        switch self {
        case .pyramid:
            String(
                localized: "active_workout.set_delete.child_kind_pyramid",
                defaultValue: "pyramid sub-sets",
                comment: "Noun phrase for a run of pyramid sub-sets in the delete confirmation message (MY-1420)."
            )
        case .dropSet:
            String(
                localized: "active_workout.set_delete.child_kind_drop",
                defaultValue: "drop-set sub-sets",
                comment: "Noun phrase for a run of drop-set sub-sets in the delete confirmation message (MY-1420)."
            )
        case .mixed:
            String(
                localized: "active_workout.set_delete.child_kind_mixed",
                defaultValue: "sub-sets",
                comment: "Generic noun phrase used when a set's sub-set run mixes pyramid and drop-set rows (MY-1420)."
            )
        }
    }
}

/// What the UI should do when the user asks to delete a row.
enum SetDeletionIntent: Equatable {
    /// Deleting this row also removes `childCount` sub-sets the user did not
    /// select — confirm first.
    case confirm(childCount: Int, kind: SubSetChildKind)
    /// Scope is exactly the row acted on — delete now, offer undo.
    case immediate
}

enum SetDeletionPolicy {
    nonisolated static func intent(
        for exerciseSet: ExerciseSet,
        in workoutExercise: WorkoutExercise
    ) -> SetDeletionIntent {
        let children = WorkoutSetTree.subSetChildren(of: exerciseSet, in: workoutExercise)
        guard let kind = SubSetChildKind.resolve(from: children.map(\.setType)) else {
            return .immediate
        }
        return .confirm(childCount: children.count, kind: kind)
    }

    // MARK: - Copy

    /// "删除第 N 组？" — `setNumber` is 1-based, matching the row label.
    static func confirmTitle(setNumber: Int) -> String {
        String(
            localized: "active_workout.set_delete.confirm_title",
            defaultValue: "Delete set \(setNumber)?",
            comment: "Title of the confirmation shown when deleting a main set that owns sub-sets (MY-1420)."
        )
    }

    /// "该组及其下 M 个<类型>子组将一并删除" — spells out the cascade the row
    /// itself cannot show.
    static func confirmMessage(childCount: Int, kind: SubSetChildKind) -> String {
        String(
            localized: "active_workout.set_delete.confirm_message",
            defaultValue: "This set and its \(childCount) \(kind.localizedDescription) will be deleted",
            comment: "Body of the delete confirmation, naming how many sub-sets are removed alongside the set (MY-1420)."
        )
    }

    /// Undo-snackbar text: "已删除第 N 组<类型>" / "…子组" for a sub-set row.
    static func undoMessage(setNumber: Int, setType: SetType, isSubSet: Bool) -> String {
        if isSubSet {
            return String(
                localized: "active_workout.set_delete.undo_message_sub",
                defaultValue: "Deleted \(setType.displayName) sub-set of set \(setNumber)",
                comment: "Undo snackbar text after deleting a sub-set row (MY-1420)."
            )
        }
        return String(
            localized: "active_workout.set_delete.undo_message_main",
            defaultValue: "Deleted set \(setNumber) (\(setType.displayName))",
            comment: "Undo snackbar text after deleting a main set row (MY-1420)."
        )
    }

    /// VoiceOver announcement posted right after a delete, since the row that
    /// held focus is gone and the snackbar is not modal.
    static func deletionAnnouncement(setNumber: Int, setType: SetType, isSubSet: Bool) -> String {
        String(
            localized: "active_workout.set_delete.announcement",
            defaultValue: "\(undoMessage(setNumber: setNumber, setType: setType, isSubSet: isSubSet)), undo available",
            comment: "VoiceOver announcement after a set is deleted, telling the user an undo action is available (MY-1420)."
        )
    }
}
