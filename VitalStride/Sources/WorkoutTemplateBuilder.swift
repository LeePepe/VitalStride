import Foundation
import SwiftData
import VitalModels

@MainActor
enum WorkoutTemplateBuilder {
    @discardableResult
    static func saveAsTemplate(
        from workout: Workout,
        name: String,
        context: ModelContext
    ) throws -> WorkoutTemplate {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = WorkoutTemplate(name: trimmedName)
        context.insert(template)

        let sortedExercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
        for (index, workoutExercise) in sortedExercises.enumerated() {
            guard let exercise = workoutExercise.exercise else { continue }

            let workingSets = (workoutExercise.sets ?? []).filter { $0.setType != .warmup }
            let targetSets = workingSets.count
            let targetWeight: Double? = workingSets.isEmpty
                ? nil
                : workingSets.map(\.weight).reduce(0, +) / Double(workingSets.count)

            let templateExercise = TemplateExercise(
                exercise: exercise,
                targetSets: targetSets,
                targetWeight: targetWeight,
                order: index
            )
            templateExercise.template = template
            context.insert(templateExercise)
        }

        try context.save()
        return template
    }

    static func defaultTemplateName(from workout: Workout, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: workout.startDate)
        let suffix = String(
            localized: "workout_template_default_name_suffix",
            defaultValue: "Workout",
            comment: "Suffix appended to the workout date to form the default template name, for example: date + suffix"
        )
        return "\(dateString) \(suffix)"
    }
}
