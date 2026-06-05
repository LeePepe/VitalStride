import Foundation
import SwiftData

@Model
final class Workout {
    var type: WorkoutType = WorkoutType.strength
    var startDate: Date = Date()
    var endDate: Date?
    var totalCalories: Double?
    var source: WorkoutSource = WorkoutSource.recorded

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]?

    init(
        type: WorkoutType,
        startDate: Date,
        endDate: Date? = nil,
        totalCalories: Double? = nil,
        source: WorkoutSource = .recorded,
        exercises: [WorkoutExercise] = []
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.totalCalories = totalCalories
        self.source = source
        self.exercises = exercises
    }
}

// MARK: - Calculation Helpers

extension Workout {
    var overallWorkingVolume: Double {
        (exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    var hasWorkingSets: Bool {
        (exercises ?? []).contains { exercise in
            (exercise.sets ?? []).contains { $0.setType == .working }
        }
    }
}
