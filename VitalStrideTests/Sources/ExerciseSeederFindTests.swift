import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ExerciseSeeder.findByPresetId")
struct ExerciseSeederFindTests {
    private let suiteName = "com.vitalstride.test.ExerciseSeederFind.\(UUID().uuidString)"

    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    private func cleanUp(_ userDefaults: UserDefaults) {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeCatalogData(version: String, exercises: [[String: Any]]) throws -> Data {
        let catalog: [String: Any] = ["version": version, "exercises": exercises]
        return try JSONSerialization.data(withJSONObject: catalog)
    }

    private func makeExerciseJSON(
        id: String,
        nameEn: String,
        nameZh: String = "",
        muscleGroup: String = "chest",
        equipment: String = "barbell"
    ) -> [String: Any] {
        [
            "id": id,
            "nameEn": nameEn,
            "nameZh": nameZh,
            "muscleGroup": muscleGroup,
            "equipment": equipment,
            "primaryMuscles": [] as [String],
            "secondaryMuscles": [] as [String],
        ]
    }

    @Test("Returns matching Exercise for a seeded presetId")
    func returnsMatchingExerciseForSeededPresetId() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalog = try makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A", nameZh: "动作A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B", muscleGroup: "back"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        let result = ExerciseSeeder.findByPresetId("ex-1", context: context)

        let exercise = try #require(result)
        #expect(exercise.presetId == "ex-1")
        #expect(exercise.nameEn == "Exercise A")
        #expect(exercise.nameZh == "动作A")
        #expect(exercise.muscleGroup == .chest)
        #expect(exercise.isCustom == false)
    }

    @Test("Returns nil for an unknown presetId")
    func returnsNilForUnknownPresetId() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalog = try makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        let result = ExerciseSeeder.findByPresetId("does-not-exist", context: context)

        #expect(result == nil)
    }
}
