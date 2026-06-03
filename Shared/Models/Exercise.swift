import Foundation
import SwiftData

@Model
final class Exercise {
    var nameEn: String = ""
    var nameZh: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.chest
    var equipment: Equipment = Equipment.barbell
    var primaryMuscles: [String] = []
    var secondaryMuscles: [String] = []
    var isCustom: Bool = false

    @Relationship(inverse: \WorkoutExercise.exercise)
    var workoutExercises: [WorkoutExercise]?

    @Relationship(inverse: \TemplateExercise.exercise)
    var templateExercises: [TemplateExercise]?

    init(
        nameEn: String,
        nameZh: String,
        muscleGroup: MuscleGroup,
        equipment: Equipment,
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        isCustom: Bool = false
    ) {
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.isCustom = isCustom
    }
}
