import Foundation
import SwiftData

@Model
final class Workout {
    var type: String = "strength"
    var startDate: Date = Date()
    var endDate: Date?
    var source: WorkoutSource = WorkoutSource.recorded

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]?

    init(
        type: String,
        startDate: Date,
        endDate: Date? = nil,
        source: WorkoutSource = .recorded,
        exercises: [WorkoutExercise] = []
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
        self.exercises = exercises
    }
}
