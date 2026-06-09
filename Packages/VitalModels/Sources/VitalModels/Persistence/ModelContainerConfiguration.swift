import SwiftData

public enum ModelContainerConfiguration {
    public static let trainingModelTypes: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutExercise.self,
        ExerciseSet.self,
        Exercise.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        UserInterest.self,
    ]

    public static let healthCacheModelTypes: [any PersistentModel.Type] = [
        HealthCacheEntry.self,
    ]

    public static let allModelTypes: [any PersistentModel.Type] =
        trainingModelTypes + healthCacheModelTypes

    public static let cloudKitContainerIdentifier = "iCloud.com.leepepe.VitalStride"

    public static func makeContainer() throws -> ModelContainer {
        let trainingSchema = Schema(trainingModelTypes)
        let trainingConfig = ModelConfiguration(
            "Training",
            schema: trainingSchema
        )

        let healthCacheSchema = Schema(healthCacheModelTypes)
        let healthCacheConfig = ModelConfiguration(
            "HealthCache",
            schema: healthCacheSchema,
            cloudKitDatabase: .none
        )

        let fullSchema = Schema(allModelTypes)
        return try ModelContainer(
            for: fullSchema,
            configurations: [trainingConfig, healthCacheConfig]
        )
    }

    public static func makeTestContainer() throws -> ModelContainer {
        let trainingSchema = Schema(trainingModelTypes)
        let trainingConfig = ModelConfiguration(
            "Training",
            schema: trainingSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let healthCacheSchema = Schema(healthCacheModelTypes)
        let healthCacheConfig = ModelConfiguration(
            "HealthCache",
            schema: healthCacheSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let fullSchema = Schema(allModelTypes)
        return try ModelContainer(
            for: fullSchema,
            configurations: [trainingConfig, healthCacheConfig]
        )
    }
}
