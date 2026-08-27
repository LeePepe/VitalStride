// swiftlint:disable no_hardcoded_chinese
// Sub-Set Row adapter.
// The accepted AppUI contract keeps the shared editable fields, menu and
// completion controls in `SetRow`; sub-sets only supply the row identity that
// differentiates a child row from its parent. This wrapper therefore delegates
// to the same editable composition rather than maintaining a parallel read-only
// tree-line layout.

import DesignKit
import SwiftUI
import VitalModels
import VitalUI

struct SubSetRow: View {
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let parentSetNumber: Int
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        let rowIndex = max(parentSetNumber - 1, 0)
        let deleteLabel = String(localized: "删除", comment: "Delete action")

        return SetRow(
            index: rowIndex,
            exerciseSet: exerciseSet,
            weightUnit: weightUnit,
            canDelete: true,
            exercise: nil,
            recentWeightKg: nil,
            previousSet: nil,
            onToggleCompleted: onToggleCompleted,
            onDelete: onDelete,
            onAddSubSet: { _ in },
            onCopyToNext: {}
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组，\(deleteLabel)",
                comment: "Sub-set row accessibility label"
            )
        )
    }
}
