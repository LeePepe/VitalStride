import Foundation
import SwiftData
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutDeleter")

/// Value-type projection of a `Workout` sufficient to drive deletion without
/// keeping a live SwiftData reference. Callers capture this **before** starting
/// the delete flow. Reading `\Workout.type` (or any other property) on a
/// `Workout` that has been detached from its `ModelContext` traps with
/// "This backing data was detached from a context without resolving attribute
/// faults" — the snapshot lets the deletion driver carry all state forward
/// without touching the model again.
struct WorkoutDeletionSnapshot: Sendable, Equatable {
    let persistentModelID: PersistentIdentifier
    let source: WorkoutSource
    let healthKitUUID: String?
}

enum WorkoutDeletionOutcome: Sendable, Equatable {
    case deleted
    case alreadyGone
}

@MainActor
enum WorkoutDeleter {
    static func snapshot(of workout: Workout) -> WorkoutDeletionSnapshot {
        WorkoutDeletionSnapshot(
            persistentModelID: workout.persistentModelID,
            source: workout.source,
            healthKitUUID: workout.healthKitUUID
        )
    }

    /// Delete the workout identified by `snapshot`. HealthKit removal (for
    /// recorded+mirrored workouts) runs first and is best-effort — failures
    /// are logged and swallowed, keeping local delete responsive (parity with
    /// the prior inline behavior). On SwiftData save failure the context is
    /// rolled back and the error is rethrown.
    static func delete(
        snapshot: WorkoutDeletionSnapshot,
        in modelContext: ModelContext,
        healthKitDelete: @Sendable (String) async throws -> Void
    ) async throws -> WorkoutDeletionOutcome {
        if snapshot.source == .recorded, let hkUUID = snapshot.healthKitUUID {
            do {
                try await healthKitDelete(hkUUID)
            } catch {
                logger.error(
                    "HealthKit delete failed uuid=\(hkUUID, privacy: .private) error=\(error.localizedDescription, privacy: .private)"
                )
            }
        }

        let matches = try modelContext.fetch(FetchDescriptor<Workout>())
        guard let workout = matches.first(where: { $0.persistentModelID == snapshot.persistentModelID }) else {
            return .alreadyGone
        }

        modelContext.delete(workout)
        do {
            try modelContext.save()
            return .deleted
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
