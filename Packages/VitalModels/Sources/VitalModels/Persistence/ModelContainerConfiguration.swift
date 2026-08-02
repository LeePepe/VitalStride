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
        AvailableTypesEntry.self,
    ]

    public static let aiCacheModelTypes: [any PersistentModel.Type] = [
        OverviewInsightCache.self,
        TrainingAdviceCache.self,
        DataAnalysisCache.self,
    ]

    public static let telemetryModelTypes: [any PersistentModel.Type] = [
        RoutingSignalEntry.self,
    ]

    public static let banditModelTypes: [any PersistentModel.Type] = [
        BanditArmStateEntry.self,
    ]

    public static let allModelTypes: [any PersistentModel.Type] =
        trainingModelTypes + healthCacheModelTypes + aiCacheModelTypes + telemetryModelTypes + banditModelTypes

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

        let aiCacheSchema = Schema(aiCacheModelTypes)
        let aiCacheConfig = ModelConfiguration(
            "AICache",
            schema: aiCacheSchema,
            cloudKitDatabase: .none
        )

        let telemetrySchema = Schema(telemetryModelTypes)
        let telemetryConfig = ModelConfiguration(
            "Telemetry",
            schema: telemetrySchema,
            cloudKitDatabase: .none
        )

        let banditSchema = Schema(banditModelTypes)
        let banditConfig = ModelConfiguration(
            "Bandit",
            schema: banditSchema,
            cloudKitDatabase: .none
        )

        let fullSchema = Schema(allModelTypes)
        return try ModelContainer(
            for: fullSchema,
            configurations: [trainingConfig, healthCacheConfig, aiCacheConfig, telemetryConfig, banditConfig]
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

        let aiCacheSchema = Schema(aiCacheModelTypes)
        let aiCacheConfig = ModelConfiguration(
            "AICache",
            schema: aiCacheSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let telemetrySchema = Schema(telemetryModelTypes)
        let telemetryConfig = ModelConfiguration(
            "Telemetry",
            schema: telemetrySchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let banditSchema = Schema(banditModelTypes)
        let banditConfig = ModelConfiguration(
            "Bandit",
            schema: banditSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let fullSchema = Schema(allModelTypes)
        return try ModelContainer(
            for: fullSchema,
            configurations: [trainingConfig, healthCacheConfig, aiCacheConfig, telemetryConfig, banditConfig]
        )
    }
}
