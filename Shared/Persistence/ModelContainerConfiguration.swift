import SwiftData

enum ModelContainerConfiguration {
    static let allModelTypes: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutExercise.self,
        ExerciseSet.self,
        Exercise.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        HealthSample.self,
        HealthKitAnchor.self,
    ]

    static let cloudKitContainerIdentifier = "iCloud.com.leepepe.VitalStride"

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeTestContainer() throws -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
