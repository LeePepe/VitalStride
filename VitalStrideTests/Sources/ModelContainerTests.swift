import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ModelContainer Tests")
struct ModelContainerTests {
    @Test("Test container initializes successfully")
    func testContainerInitialization() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        #expect(container.schema.entities.count > 0)
    }

    @Test("Test container schema contains all model types")
    func testContainerSchemaContainsAllModels() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let entityNames = container.schema.entities.map(\.name)

        #expect(entityNames.contains("Workout"))
        #expect(entityNames.contains("WorkoutExercise"))
        #expect(entityNames.contains("ExerciseSet"))
        #expect(entityNames.contains("Exercise"))
        #expect(entityNames.contains("WorkoutTemplate"))
        #expect(entityNames.contains("TemplateExercise"))
    }

    @Test("Test container supports CRUD operations")
    func testContainerCRUD() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Deadlift",
            nameZh: "硬拉",
            muscleGroup: .back,
            equipment: .barbell
        )
        context.insert(exercise)
        try context.save()

        let descriptor = FetchDescriptor<Exercise>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.nameEn == "Deadlift")
    }
}
