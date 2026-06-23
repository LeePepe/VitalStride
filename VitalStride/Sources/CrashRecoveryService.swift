import Foundation
import SwiftData
import VitalModels

/// Pure, testable helpers for detecting and handling workouts that were left
/// unfinished by an app crash or termination.
///
/// "Orphan" definition: `endDate == nil && source == .recorded`. SwiftData has
/// already persisted the `Workout` row (it was inserted at start), but
/// `finish()` was never called, so the record never appears in the user-facing
/// training history (which filters `endDate != nil`).
enum CrashRecoveryService {

    // MARK: - Types

    /// A read-only snapshot of an orphan workout's user-visible metadata.
    /// Counts only; never includes weight/reps values (privacy constraint).
    struct Summary: Equatable {
        let workoutID: PersistentIdentifier
        let startDate: Date
        let exerciseCount: Int
        let setCount: Int

        var isEmpty: Bool { exerciseCount == 0 }
    }

    /// The split between the single workout offered for resume (the most
    /// recent orphan) and the remaining orphans that will be auto-finished.
    struct Partition {
        let resumable: Workout?
        let autoFinish: [Workout]
    }

    // MARK: - Detection

    /// Fetches orphan workouts ordered most-recent first.
    ///
    /// The SwiftData `#Predicate` macro only filters by `endDate`. The
    /// `source == .recorded` check is performed in Swift to sidestep the
    /// enum-in-predicate limitation observed in earlier predicate macros.
    static func findOrphans(in context: ModelContext) -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.filter { $0.source == .recorded }
    }

    // MARK: - Partition

    /// Splits the orphan set into the single resumable candidate (most recent
    /// by `startDate`) and the rest, which should be auto-finished so they
    /// stop occupying space outside the history view.
    ///
    /// `orphans` may be in any order; this helper sorts defensively.
    static func partition(_ orphans: [Workout]) -> Partition {
        let sorted = orphans.sorted { $0.startDate > $1.startDate }
        guard let first = sorted.first else {
            return Partition(resumable: nil, autoFinish: [])
        }
        return Partition(
            resumable: first,
            autoFinish: Array(sorted.dropFirst())
        )
    }

    // MARK: - Auto-finish

    /// Marks each workout as finished at `date` so the records become visible
    /// in the training history. Caller is responsible for `context.save()`.
    static func autoFinishOrphans(
        _ workouts: [Workout],
        at date: Date = Date()
    ) {
        for workout in workouts {
            workout.finish(at: date)
        }
    }

    // MARK: - Summary

    /// Builds a privacy-safe `Summary` of the orphan workout.
    /// Counts and the start date only — no weights or reps.
    static func summary(for workout: Workout) -> Summary {
        let exercises = workout.exercises ?? []
        let exerciseCount = exercises.count
        let setCount = exercises.reduce(0) { $0 + ($1.sets?.count ?? 0) }
        return Summary(
            workoutID: workout.persistentModelID,
            startDate: workout.startDate,
            exerciseCount: exerciseCount,
            setCount: setCount
        )
    }

    // MARK: - Resolution actions

    /// The outcome of a save / discard attempt. The caller (the SwiftUI
    /// modifier) uses this to decide whether to dismiss the alert, surface
    /// an error prompt, or re-try.
    enum ResolutionOutcome: Equatable {
        case success
        /// Persistence threw — the caller should surface a retry path. The
        /// underlying error is captured for logging but not surfaced to
        /// the user (privacy: error descriptions can leak data).
        case persistFailed
    }

    /// Finishes the workout at `date` and attempts to persist. On failure
    /// the in-memory `endDate` mutation is *not* rolled back — the caller
    /// is expected to re-try the save (or, on cancel, leave the orphan in
    /// place so the next launch's recovery flow can pick it up again).
    ///
    /// `save` defaults to `context.save()` and is injectable for testing
    /// failure paths without mocking SwiftData internals.
    @discardableResult
    static func saveAndEnd(
        workout: Workout,
        context: ModelContext,
        at date: Date = Date(),
        save: (() throws -> Void)? = nil
    ) -> ResolutionOutcome {
        workout.finish(at: date)
        do {
            try (save ?? { try context.save() })()
            return .success
        } catch {
            return .persistFailed
        }
    }

    /// Deletes the workout and attempts to persist. On failure the delete
    /// is rolled back via `context.rollback()` so the workout remains
    /// available for retry rather than being left in a half-deleted state.
    @discardableResult
    static func discard(
        workout: Workout,
        context: ModelContext,
        save: (() throws -> Void)? = nil
    ) -> ResolutionOutcome {
        context.delete(workout)
        do {
            try (save ?? { try context.save() })()
            return .success
        } catch {
            context.rollback()
            return .persistFailed
        }
    }
}
