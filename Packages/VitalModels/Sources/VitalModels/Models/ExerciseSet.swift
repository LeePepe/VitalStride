import Foundation
import SwiftData

@Model
public final class ExerciseSet {
    public var order: Int = 0
    public var weight: Double = 0.0
    public var reps: Int = 0
    public var setType: SetType = SetType.working
    public var restDuration: TimeInterval?
    public var completedAt: Date?
    public var workoutExercise: WorkoutExercise?

    public var isCompleted: Bool {
        completedAt != nil
    }

    public init(
        order: Int = 0,
        weight: Double,
        reps: Int,
        setType: SetType = .working,
        restDuration: TimeInterval? = nil,
        completedAt: Date? = nil
    ) {
        self.order = order
        self.weight = weight
        self.reps = reps
        self.setType = setType
        self.restDuration = restDuration
        self.completedAt = completedAt
    }
}
