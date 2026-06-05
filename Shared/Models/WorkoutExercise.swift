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

// MARK: - Calculation Helpers

extension WorkoutExercise {
    var totalSetsCount: Int {
        sets?.count ?? 0
    }

    var totalRepsCount: Int {
        (sets ?? []).reduce(0) { $0 + $1.reps }
    }

    var workingVolume: Double {
        (sets ?? []).filter { $0.setType == .working }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
    }
}
