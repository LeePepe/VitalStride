import Foundation
import SwiftData

@Model
final class TemplateExercise {
    var exercise: Exercise?
    var targetSets: Int = 0
    var targetWeight: Double?
    var order: Int = 0
    var template: WorkoutTemplate?

    init(
        exercise: Exercise? = nil,
        targetSets: Int,
        targetWeight: Double? = nil,
        order: Int
    ) {
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetWeight = targetWeight
        self.order = order
    }
}
