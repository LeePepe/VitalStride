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
}
