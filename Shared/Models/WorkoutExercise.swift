import Foundation
import SwiftData

@Model
final class WorkoutExercise {
    var order: Int = 0
    var exercise: Exercise?
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workoutExercise)
    var sets: [ExerciseSet]?

    init(
        order: Int,
        exercise: Exercise? = nil,
        sets: [ExerciseSet] = []
    ) {
        self.order = order
        self.exercise = exercise
        self.sets = sets
    }
}
