import Foundation
import SwiftData

@Model
public final class WorkoutTemplate {
    public var name: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    public var exercises: [TemplateExercise]?

    public init(
        name: String,
        exercises: [TemplateExercise] = []
    ) {
        self.name = name
        self.exercises = exercises
    }
}
