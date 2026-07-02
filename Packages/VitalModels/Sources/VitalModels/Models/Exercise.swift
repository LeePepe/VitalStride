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
    public var presetId: String?

    public var defaultWeightLow: Double?
    public var defaultWeightMid: Double?
    public var defaultWeightHigh: Double?
    public var defaultRepsLow: Int = 5
    public var defaultRepsMid: Int = 10
    public var defaultRepsHigh: Int = 15

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
        isCustom: Bool = false,
        presetId: String? = nil,
        defaultWeightLow: Double? = nil,
        defaultWeightMid: Double? = nil,
        defaultWeightHigh: Double? = nil,
        defaultRepsLow: Int = 5,
        defaultRepsMid: Int = 10,
        defaultRepsHigh: Int = 15
    ) {
        self.nameEn = nameEn
        self.nameZh = nameZh
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.isCustom = isCustom
        self.presetId = presetId
        self.defaultWeightLow = defaultWeightLow
        self.defaultWeightMid = defaultWeightMid
        self.defaultWeightHigh = defaultWeightHigh
        self.defaultRepsLow = defaultRepsLow
        self.defaultRepsMid = defaultRepsMid
        self.defaultRepsHigh = defaultRepsHigh
    }
}
