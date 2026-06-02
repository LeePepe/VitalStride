import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise]?

    init(
        name: String,
        exercises: [TemplateExercise] = []
    ) {
        self.name = name
        self.exercises = exercises
    }
}
