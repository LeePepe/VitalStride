// VoiceOver focus target after set deletion (MY-1433).
//
// Extracted from `WorkoutSetTree` (which moved to VitalModels in MY-1432).
// This logic is UI-specific — it decides where screen-reader focus should
// land after a delete — so it stays in the app target.

import Foundation

enum SetDeletionFocusTarget {
    /// Index (into the *pre-deletion* row array) of the row that should take
    /// VoiceOver focus once `deletedIndices` are gone.
    ///
    /// Deleting a focused row silently drops VoiceOver focus or drifts it to an
    /// unrelated element, so the caller must move it explicitly. A sub-set
    /// hands focus back to its parent main set — that is the row the user was
    /// working within. Anything else (or a parent that is itself being
    /// deleted) falls through to the next surviving row, then the previous one.
    /// Returns nil only when nothing survives.
    ///
    /// `isSubSet` is indexed in the same order as the rendered rows.
    nonisolated static func focusIndexAfterDeletion(
        deleting deletedIndices: Set<Int>,
        isSubSet: [Bool]
    ) -> Int? {
        guard let first = deletedIndices.min(), let last = deletedIndices.max() else { return nil }

        if first < isSubSet.count && isSubSet[first] {
            var index = first - 1
            while index >= 0 {
                if !deletedIndices.contains(index) && !isSubSet[index] { return index }
                index -= 1
            }
        }

        var forward = last + 1
        while forward < isSubSet.count {
            if !deletedIndices.contains(forward) { return forward }
            forward += 1
        }

        var backward = first - 1
        while backward >= 0 {
            if !deletedIndices.contains(backward) { return backward }
            backward -= 1
        }
        return nil
    }
}
