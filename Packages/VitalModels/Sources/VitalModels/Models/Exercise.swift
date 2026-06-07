import Foundation
import SwiftData

@Model
public final class Exercise {
    public var nameEn: String = ""
    public var nameZh: String = ""
    public var muscleGroup: MuscleGroup = MuscleGroup.chest
    public var equipment: Equipment = Equipment.barbell
    public var primaryMuscles: [String] = []
    public var secondaryMuscles: [String] = []
    public var isCustom: Bool = false

    @Relationship(inverse: \WorkoutExercise.exercise)
    public var workoutExercises: [WorkoutExercise]?

    @Relationship(inverse: \TemplateExercise.exercise)
    public var templateExercises: [TemplateExercise]?

    public var localizedName: String {
        let isZh = Locale.current.language.languageCode?.identifier == "zh"
        return isZh ? (nameZh.isEmpty ? nameEn : nameZh) : (nameEn.isEmpty ? nameZh : nameEn)
    }

    public init(
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
