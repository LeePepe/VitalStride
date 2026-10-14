// swiftlint:disable no_hardcoded_chinese
// Sub-Set Row adapter (spec 026 / FR-001).
// Delegates to the single shared `SetRow` composition with sub-set configuration.

import DesignKit
import SwiftUI
import VitalModels
import VitalUI

struct SubSetRow: View {
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let isLast: Bool
    let parentSetNumber: Int
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    var onCopyToNext: (() -> Void)?
    var stableRowID: String?

    var body: some View {
        SetRow(
            index: parentSetNumber - 1,
            exerciseSet: exerciseSet,
            weightUnit: weightUnit,
            canDelete: true,
            exercise: nil,
            recentWeightKg: nil,
            previousSet: nil,
            isSubSet: true,
            parentSetNumber: parentSetNumber,
            stableRowID: stableRowID,
            onToggleCompleted: onToggleCompleted,
            onDelete: onDelete,
            onAddSubSet: { _ in },
            onCopyToNext: {
                onCopyToNext?()
            }
        )
    }
}
