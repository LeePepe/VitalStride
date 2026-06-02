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
