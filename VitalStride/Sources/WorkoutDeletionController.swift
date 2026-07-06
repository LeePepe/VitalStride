import Foundation
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutDeletionController")

/// Observable state machine that owns the "delete a workout" flow for both
/// `WorkoutDetailView` (toolbar delete) and `WorkoutListView` (swipe delete).
///
/// The controller enforces the invariant that makes MY-1094 unreachable:
/// **`isDeleting` flips to `true` synchronously, before any async work runs**.
/// Views observe `isDeleting` and stop reading the live `Workout` reference
/// the moment the flag is set. That closes the SwiftData "backing data was
/// detached without resolving faults" trap on `\Workout.type` that surfaced
/// when a surviving SwiftUI body (e.g. a parent `@Query`) re-evaluated after
/// `modelContext.save()` in the old inline flow.
@MainActor
@Observable
final class WorkoutDeletionController {
    /// True from the moment `beginDelete` is invoked until the async delete
    /// terminates (successfully or with error). Views MUST observe this and
    /// suppress reads on the target `Workout` while it is true.
    private(set) var isDeleting = false

    /// Non-nil when the last delete attempt failed and the caller should
    /// present an error alert.
    var deleteError: Error?

    /// Snapshot captured at delete time. Non-nil only while a delete is in
    /// flight; exposed for tests to verify view-level state, not for UI use.
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
    /// the delete off the caller's synchronous frame. `onFinished` fires on
    /// successful delete (both views use it to dismiss / clear selection);
    /// `onError` fires on failure with `isDeleting` already reset to false.
    ///
    /// Returns the `Task` handle for tests that need to await completion.
    /// Production callers ignore the return value.
    @discardableResult
    func beginDelete(
        workout: Workout,
        in modelContext: ModelContext,
        healthKitDelete: @Sendable @escaping (String) async throws -> Void,
        onFinished: @escaping () -> Void = {},
        onError: @escaping (Error) -> Void = { _ in }
    ) -> Task<Void, Never> {
        // Guard re-entry — a double-tap on the confirm button must not spawn
        // a second delete Task.
        if isDeleting {
            return Task { }
        }

        // Capture snapshot BEFORE flipping the flag so a rogue Workout-property
        // read here would still work (snapshot itself uses persistentModelID
        // + source + healthKitUUID, all safe to read on a live model).
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
                inflightSnapshot = nil
                isDeleting = false
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
}
