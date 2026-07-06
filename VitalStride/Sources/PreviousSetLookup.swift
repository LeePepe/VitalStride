import Foundation
import SwiftData
import VitalModels

/// Look up the same-index main set for a given exercise from the most recent
/// previously completed workout. Powers the training-screen "上次 …" hint on
/// `SetRow` (spec 004-previous-set-hint FR-002/003/005/007) and is designed to
/// be reused by MY-1041 Smart Progression.
///
/// The lookup is unit-agnostic: it returns the canonical `ExerciseSet` from the
/// prior workout; downstream UI is responsible for `WeightUnit` conversion and
/// formatting.
@MainActor
enum PreviousSetLookup {
    /// Maximum number of historical workouts scanned per lookup. Bounds the
    /// fetch so history growth cannot degrade active-workout scroll perf
    /// (FR-005; echoes MY-1077's unbounded `@Query` mitigation).
    static let historyFetchLimit = 50

    /// Returns the same-index main set (i.e. non–sub-set) for `exercise` from
    /// the most recent completed workout preceding `currentWorkout`, or `nil`
    /// when there is no prior workout for that exercise or the prior main-set
    /// count is smaller than `mainSetIndex`.
    ///
    /// - Parameters:
    ///   - currentWorkout: The in-progress workout to exclude from the search.
    ///   - exercise: The target exercise. Matched by SwiftData identity — no
    ///     `presetId`/`nameEn` string comparison, so custom + preset exercises
    ///     behave identically and renamed presets stay linked.
    ///   - mainSetIndex: 0-based ordinal among the prior workout's main sets
    ///     (sub-sets like drop-set / pyramid are skipped), matching the
    ///     current view's `mainSetNumber(upTo:)` semantics.
    ///   - modelContext: SwiftData context to fetch from.
    /// - Returns: The prior main `ExerciseSet` at the same index, or `nil`.
    static func previousMainSet(
        currentWorkout: Workout,
        exercise: Exercise?,
        mainSetIndex: Int,
        in modelContext: ModelContext
    ) -> ExerciseSet? {
        guard mainSetIndex >= 0, let exercise else { return nil }

        let currentID = currentWorkout.persistentModelID
        let currentStart = currentWorkout.startDate
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.endDate != nil
                    && workout.persistentModelID != currentID
                    && workout.startDate < currentStart
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = historyFetchLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        let workouts: [Workout]
        do {
            workouts = try modelContext.fetch(descriptor)
        } catch {
            return nil
        }

        let targetID = exercise.persistentModelID
        for workout in workouts {
            guard let workoutExercise = (workout.exercises ?? []).first(where: {
                $0.exercise?.persistentModelID == targetID
            }) else { continue }

            let mainSets = (workoutExercise.sets ?? [])
                .sorted { $0.order < $1.order }
                .filter { !$0.setType.isSubSet }

            guard mainSetIndex < mainSets.count else { return nil }
            return mainSets[mainSetIndex]
        }

        return nil
    }
}
