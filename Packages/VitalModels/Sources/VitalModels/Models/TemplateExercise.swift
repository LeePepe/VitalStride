import Foundation
import SwiftData

@Model
public final class TemplateExercise {
    public var exercise: Exercise?
    public var targetSets: Int = 0
    public var targetWeight: Double?
    public var order: Int = 0
    public var template: WorkoutTemplate?

    public init(
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
