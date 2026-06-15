import Foundation
import HealthKitService
import VitalModels

@MainActor
enum UnifiedWorkout: Identifiable {
    case app(Workout)
    case healthKit(HealthWorkoutRecord)

    nonisolated var id: String {
        switch self {
        case .app(let workout):
            "app-\(workout.persistentModelID)"
        case .healthKit(let record):
            "hk-\(record.id.uuidString)"
        }
    }

    var startDate: Date {
        switch self {
        case .app(let workout): workout.startDate
        case .healthKit(let record): record.startDate
        }
    }

    var endDate: Date? {
        switch self {
        case .app(let workout): workout.endDate
        case .healthKit(let record): record.endDate
        }
    }

    var displayTitle: String {
        switch self {
        case .app(let workout):
            let names = (workout.exercises ?? [])
                .sorted { $0.order < $1.order }
                .compactMap { $0.exercise?.localizedName }
            if names.isEmpty {
                return String(localized: "力量训练", comment: "Strength training default title")
            }
            if names.count <= 3 {
                return names.joined(separator: ", ")
            }
            let prefix = names.prefix(3).joined(separator: ", ")
            return String(localized: "\(prefix) 等", comment: "Workout title with more exercises")
        case .healthKit(let record):
            return record.activityType.localizedName
        }
    }

    var displayIcon: String {
        switch self {
        case .app: "dumbbell"
        case .healthKit(let record): record.activityType.systemImage
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .app(let workout):
            guard let end = workout.endDate else { return nil }
            return end.timeIntervalSince(workout.startDate)
        case .healthKit(let record):
            return record.duration
        }
    }

    var source: String {
        switch self {
        case .app:
            String(localized: "本应用", comment: "Workout source label for workouts recorded in this app")
        case .healthKit(let record):
            record.sourceName ?? String(localized: "HealthKit", comment: "Default source name for HealthKit workouts")
        }
    }
}
