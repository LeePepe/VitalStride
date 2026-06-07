import Foundation
import SwiftData

@Model
public final class WorkoutExercise {
    public var order: Int = 0
    public var exercise: Exercise?
    public var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workoutExercise)
    public var sets: [ExerciseSet]?

    public init(
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
    public var totalSetsCount: Int {
        sets?.count ?? 0
    }

    public var totalRepsCount: Int {
        let isFinished = workout?.endDate != nil
        return (sets ?? [])
            .filter { isFinished || $0.isCompleted }
            .reduce(0) { $0 + $1.reps }
    }

    public var workingVolume: Double {
        let isFinished = workout?.endDate != nil
        return (sets ?? [])
            .filter { (isFinished || $0.isCompleted) && $0.setType != .warmup }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) * ($1.isUnilateral ? 2.0 : 1.0) }
    }
}
