import SwiftData

public enum ModelContainerConfiguration {
    public static let allModelTypes: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutExercise.self,
        ExerciseSet.self,
        Exercise.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
    ]

    public static let cloudKitContainerIdentifier = "iCloud.com.leepepe.VitalStride"

    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration()
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeTestContainer() throws -> ModelContainer {
        let schema = Schema(allModelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
