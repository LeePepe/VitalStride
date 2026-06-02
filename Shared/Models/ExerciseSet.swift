import Foundation
import SwiftData

@Model
final class ExerciseSet {
    var weight: Double = 0.0
    var reps: Int = 0
    var setType: SetType = SetType.working
    var restDuration: TimeInterval?
    var workoutExercise: WorkoutExercise?

    init(
        weight: Double,
        reps: Int,
        setType: SetType = .working,
        restDuration: TimeInterval? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.setType = setType
        self.restDuration = restDuration
    }
}
