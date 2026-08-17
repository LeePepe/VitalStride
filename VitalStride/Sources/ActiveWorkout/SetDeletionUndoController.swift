// swiftlint:disable no_hardcoded_chinese
// Undo-after-delete controller + bottom-snackbar arbitration (MY-1420 / MY-1422).
//
// Deletion is immediate and real (see `DeletedSetSnapshot` for why a deferred
// delete is not an option). This controller holds the snapshot that makes it
// reversible for `SetUndoTiming.window`, and decides which of the two bottom
// snackbars — undo vs rest timer — is on screen, since only one may be.
//
// The expiry timer lives here rather than in `SnackbarModifier`'s
// `.autoDismiss` mode on purpose: consecutive deletes must *replace* the
// pending undo and restart the full window. `.autoDismiss` only (re)schedules
// when `isPresented` or `mode` changes, and neither changes when one pending
// delete replaces another, so the second undo would inherit the remainder of
// the first one's countdown.

import Foundation
import SwiftData
import SwiftUI
import VitalModels

/// A delete that is still reversible.
struct PendingSetDeletion: Identifiable {
    let id = UUID()
    let snapshots: [DeletedSetSnapshot]
    let workoutExercise: WorkoutExercise
    /// Snackbar body, e.g. "已删除第 2 组递减".
    let message: String
}

/// Which bottom snackbar wins when both want the slot.
///
/// Undo outranks rest: it is the only one with a deadline the user cannot
/// recover from, and deleting a stray sub-set during rest is exactly when the
/// two collide. Rest is not cancelled — it stays live underneath and comes
/// back once the undo window closes (a resting countdown is wall-clock, so it
/// resumes showing the real remaining time, never a stale one).
enum BottomSnackbarSlot: Equatable {
    case none
    case undo
    case rest

    static func resolve(hasPendingUndo: Bool, restPhase: RestPhase) -> BottomSnackbarSlot {
        if hasPendingUndo { return .undo }
        return restPhase == .idle ? .none : .rest
    }
}

@MainActor
@Observable
final class SetDeletionUndoController {
    private(set) var pending: PendingSetDeletion?
    /// Posted for VoiceOver after a delete; the deleted row took focus with it
    /// and the snackbar is deliberately non-modal, so the announcement is the
    /// only channel that tells a screen-reader user undo exists.
    private(set) var lastAnnouncement: String?

    private let window: TimeInterval
    private var expiryTask: Task<Void, Never>?

    init(window: TimeInterval = SetUndoTiming.window) {
        self.window = window
    }

    var hasPendingUndo: Bool { pending != nil }

    func slot(restPhase: RestPhase) -> BottomSnackbarSlot {
        BottomSnackbarSlot.resolve(hasPendingUndo: hasPendingUndo, restPhase: restPhase)
    }

    /// Registers a completed deletion as undoable. Replaces any still-pending
    /// undo — the earlier delete becomes final — and restarts the window.
    func record(
        snapshots: [DeletedSetSnapshot],
        workoutExercise: WorkoutExercise,
        message: String,
        announcement: String
    ) {
        guard !snapshots.isEmpty else { return }
        pending = PendingSetDeletion(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: message
        )
        lastAnnouncement = announcement
        startExpiry()
    }

    /// Re-inserts the pending snapshot. Returns false when nothing is pending
    /// (double-tap, or the window closed between render and touch).
    @discardableResult
    func undo(using modelContext: ModelContext) -> Bool {
        guard let pending else { return false }
        SetDeletionUndo.restore(
            pending.snapshots,
            into: pending.workoutExercise,
            using: modelContext
        )
        clear()
        return true
    }

    /// Closes the window without restoring — expiry, manual dismissal, or the
    /// workout ending.
    func clear() {
        expiryTask?.cancel()
        expiryTask = nil
        pending = nil
        lastAnnouncement = nil
    }

    /// Binding for `.snackbar(isPresented:)`. Setting it false (swipe / auto
    /// dismiss) finalizes the delete.
    var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.hasPendingUndo ?? false },
            set: { [weak self] newValue in
                guard !newValue else { return }
                self?.clear()
            }
        )
    }

    private func startExpiry() {
        expiryTask?.cancel()
        let duration = window
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.expiryTask = nil
            self?.pending = nil
            self?.lastAnnouncement = nil
        }
    }
}
