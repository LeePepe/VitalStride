import Foundation
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutDeletionController")

/// Observable state machine that owns the "delete a workout" flow for both
/// `WorkoutDetailView` (toolbar delete) and `WorkoutListView` (swipe delete).
///
/// # MY-1094 invariants
///
/// 1. `isDeleting` flips to `true` **synchronously** in `beginDelete`, before
///    any async work runs. Views observe it and stop reading the live
///    `Workout` reference immediately, closing the SwiftData "backing data
///    was detached without resolving faults" trap on `\Workout.type` that
///    fired when a surviving SwiftUI body re-evaluated after
///    `modelContext.save()` in the old inline flow.
///
/// 2. On **successful** delete `isDeleting` remains `true`; the view stays
///    gated across the `onFinished()` → `dismiss()` transition. The detail
///    view MUST NOT rebuild `detailList` (which reads `workout.type` etc.)
///    between `save()` returning and the dismissal animation completing —
///    that is the exact window the old code opened. Callers that reuse the
///    controller for another delete must call `reset()` explicitly.
///
/// 3. On **error** `isDeleting` resets to `false` so the view can re-enable
///    its toolbar and present the failure alert. The workout is still live
///    (the deleter's `rollback()` in `WorkoutDeleter` restores it), so it's
///    safe to render `detailList` again.
@MainActor
@Observable
final class WorkoutDeletionController {
    /// True from the moment `beginDelete` is invoked. Remains `true` after a
    /// successful delete completes (see invariant 2 above); reset by an
    /// error path OR an explicit `reset()`.
    private(set) var isDeleting = false

    /// Non-nil when the last delete attempt failed and the caller should
    /// present an error alert.
    var deleteError: Error?

    /// Snapshot captured at delete time. Non-nil while a delete is in flight
    /// AND for the duration of a successful terminal state (see invariant 2).
    /// Cleared by an error path OR an explicit `reset()`.
    private(set) var inflightSnapshot: WorkoutDeletionSnapshot?

    /// Injected async deleter. Defaults to `WorkoutDeleter.delete`; tests
    /// substitute a controllable variant to observe intermediate state.
    /// `@MainActor` because it operates on a live `ModelContext`.
    typealias Deleter = @MainActor (
        _ snapshot: WorkoutDeletionSnapshot,
        _ context: ModelContext,
        _ healthKitDelete: @Sendable (String) async throws -> Void
    ) async throws -> WorkoutDeletionOutcome

    private let deleter: Deleter

    init(deleter: @escaping Deleter = WorkoutDeleter.delete) {
        self.deleter = deleter
    }

    /// Capture a snapshot, flip `isDeleting = true` synchronously, then run
    /// the delete off the caller's synchronous frame.
    ///
    /// - `onFinished` fires on successful delete while `isDeleting` is STILL
    ///   `true` — the view stays gated across the dismiss handoff. Callers
    ///   that keep the controller alive after success must call `reset()` to
    ///   accept another delete.
    /// - `onError` fires on failure with `isDeleting` already reset to
    ///   `false` and `deleteError` populated.
    ///
    /// Returns the `Task` handle for tests that need to await completion.
    @discardableResult
    func beginDelete(
        workout: Workout,
        in modelContext: ModelContext,
        healthKitDelete: @Sendable @escaping (String) async throws -> Void,
        onFinished: @escaping () -> Void = {},
        onError: @escaping (Error) -> Void = { _ in }
    ) -> Task<Void, Never> {
        if isDeleting {
            // Re-entry guard — a double-tap on the confirm button must not
            // spawn a second delete Task.
            return Task { }
        }

        // Snapshot BEFORE flipping the flag: snapshot reads `.source`,
        // `.healthKitUUID`, `.persistentModelID` on the still-live workout.
        let snapshot = WorkoutDeleter.snapshot(of: workout)
        logger.info("Deleting workout source=\(snapshot.source.rawValue, privacy: .private)")

        // Flip synchronously — views observing `isDeleting` re-render on the
        // next runloop pass and STOP reading `workout.<anything>` immediately.
        inflightSnapshot = snapshot
        isDeleting = true
        deleteError = nil

        let deleter = self.deleter
        return Task { @MainActor in
            do {
                _ = try await deleter(snapshot, modelContext, healthKitDelete)
                // NOTE: do NOT reset isDeleting / inflightSnapshot here.
                // The view is about to be dismissed by onFinished; clearing
                // the gate now reopens the exact stale-reference window
                // MY-1094 fixed (SwiftUI would re-evaluate a body that reads
                // `workout.type` while dismiss is still animating).
                onFinished()
            } catch {
                logger.error("Failed to save after deleting workout: \(error.localizedDescription, privacy: .private)")
                inflightSnapshot = nil
                isDeleting = false
                deleteError = error
                onError(error)
            }
        }
    }

    /// Release the terminal-success state so this controller can accept
    /// another delete. Only callers that stay mounted after `onFinished`
    /// (e.g. `WorkoutListView`, which keeps its controller across multiple
    /// swipe deletes) need to invoke this. Detail-view style callers that
    /// dismiss on success MUST NOT call this — their view is unmounting.
    func reset() {
        isDeleting = false
        inflightSnapshot = nil
        deleteError = nil
    }
}
