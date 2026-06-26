import Foundation
import HealthKitService
import VitalModels

@MainActor
enum WorkoutListMerger {
    static func merge(
        appWorkouts: [Workout],
        healthKitRecords: [HealthWorkoutRecord]
    ) -> (unified: [UnifiedWorkout], dedupCount: Int) {
        let knownHealthKitUUIDs: Set<String> = Set(
            appWorkouts.compactMap { $0.healthKitUUID }
        )

        let dedupedRecords = healthKitRecords.filter { record in
            !knownHealthKitUUIDs.contains(record.id.uuidString)
        }
        let dedupCount = healthKitRecords.count - dedupedRecords.count

        let appItems = appWorkouts.map { UnifiedWorkout.app($0) }
        let hkItems = dedupedRecords.map { UnifiedWorkout.healthKit($0) }

        let merged = (appItems + hkItems).sorted { $0.startDate > $1.startDate }
        return (unified: merged, dedupCount: dedupCount)
    }

    /// Partition a unified list into per-source groups for grouped display.
    ///
    /// Within each group, items keep their original order (the merge sort is
    /// already startDate descending, so each group is also startDate
    /// descending). Items are placed in the group that matches their case.
    static func partitionBySource(
        _ unified: [UnifiedWorkout]
    ) -> (app: [UnifiedWorkout], healthKit: [UnifiedWorkout]) {
        var app: [UnifiedWorkout] = []
        var healthKit: [UnifiedWorkout] = []
        for item in unified {
            switch item {
            case .app: app.append(item)
            case .healthKit: healthKit.append(item)
            }
        }
        return (app: app, healthKit: healthKit)
    }
}
