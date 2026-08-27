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
    let onCopyToNext: () -> Void

    var body: some View {
        let rowIndex = max(parentSetNumber - 1, 0)

        return SetRow(
            index: rowIndex,
            exerciseSet: exerciseSet,
            weightUnit: weightUnit,
            canDelete: true,
            exercise: nil,
            recentWeightKg: nil,
            previousSet: nil,
            rowIdentity: SetRowIdentity(
                displayedMainSetNumber: parentSetNumber,
                currentSetType: exerciseSet.setType,
                isSubSet: true
            ),
            onToggleCompleted: onToggleCompleted,
            onDelete: onDelete,
            onAddSubSet: { _ in },
            onCopyToNext: onCopyToNext
        )
    }
}
