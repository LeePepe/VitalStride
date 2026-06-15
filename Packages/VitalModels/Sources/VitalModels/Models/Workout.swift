import Foundation
import SwiftData

@Model
public final class Workout {
    public var type: WorkoutType = WorkoutType.strength
    public var startDate: Date = Date()
    public var endDate: Date?
    public var totalCalories: Double?
    public var source: WorkoutSource = WorkoutSource.recorded
    public var healthKitUUID: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise]?

    public init(
        type: WorkoutType,
        startDate: Date,
        endDate: Date? = nil,
        totalCalories: Double? = nil,
        source: WorkoutSource = .recorded,
        healthKitUUID: String? = nil,
        exercises: [WorkoutExercise] = []
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.totalCalories = totalCalories
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.exercises = exercises
    }
}

// MARK: - Lifecycle

extension Workout {
    public var isInProgress: Bool {
        endDate == nil && source == .recorded
    }

    public func finish(at date: Date = Date()) {
        for exercise in (exercises ?? []) {
            for set in (exercise.sets ?? []) where !set.isCompleted {
                set.isCompleted = true
            }
        }
        endDate = date
    }
}

// MARK: - Calculation Helpers

extension Workout {
    public var overallWorkingVolume: Double {
        (exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    public var hasWorkingSets: Bool {
        (exercises ?? []).contains { exercise in
            (exercise.sets ?? []).contains { $0.setType == .working }
        }
    }
}
