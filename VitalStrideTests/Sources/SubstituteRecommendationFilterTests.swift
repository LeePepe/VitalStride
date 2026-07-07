import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("SubstituteRecommendationFilter")
struct SubstituteRecommendationFilterTests {
    private let suiteName = "com.vitalstride.test.SubstituteRecommendationFilter.\(UUID().uuidString)"

    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    private func cleanUp(_ userDefaults: UserDefaults) {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeCatalogData(version: String, exercises: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": version,
            "exercises": exercises,
        ])
    }

    private func makeExerciseJSON(
        id: String,
        nameEn: String,
        muscleGroup: String,
        equipment: String = "barbell"
    ) -> [String: Any] {
        [
            "id": id,
            "nameEn": nameEn,
            "nameZh": "",
            "muscleGroup": muscleGroup,
            "equipment": equipment,
            "primaryMuscles": [] as [String],
            "secondaryMuscles": [] as [String],
        ]
    }

    // MARK: - Pure filter unit tests

    @Test("Accepts a candidate whose muscle group matches the expected group")
    func acceptsSameMuscleGroup() {
        #expect(
            SubstituteRecommendationFilter.acceptsSameMuscleGroup(
                exerciseMuscleGroup: .chest,
                expected: .chest
            )
        )
    }

    @Test("Rejects a candidate whose muscle group differs from the expected group")
    func rejectsDifferentMuscleGroup() {
        #expect(
            SubstituteRecommendationFilter.acceptsSameMuscleGroup(
                exerciseMuscleGroup: .legs,
                expected: .chest
            ) == false
        )
    }

    // MARK: - Integration: valid preset id from the wrong muscle group is filtered

    @Test("A valid preset id from a different muscle group is rejected by the filter — SC-002 blocker fix")
    func validPresetIdFromWrongMuscleGroupIsRejected() throws {
        // Given: a seeded catalog where two presets exist, each in a different muscle group.
        // The AI is asked for chest substitutes; simulate it returning a valid preset id
        // that happens to be a LEG exercise — this is exactly the SC-002 gap the reviewer
        // flagged (prompt-only enforcement lets a valid-but-wrong-muscle candidate through).
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalog = try makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "bench-press", nameEn: "Bench Press", muscleGroup: "chest"),
            makeExerciseJSON(id: "back-squat", nameEn: "Back Squat", muscleGroup: "legs"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        let legExercise = try #require(
            ExerciseSeeder.findByPresetId("back-squat", context: context)
        )
        #expect(legExercise.muscleGroup == .legs)

        // When: the resolved exercise's muscle group is compared against the current
        // exercise's muscle group (chest), the filter must reject it deterministically.
        let accepted = SubstituteRecommendationFilter.acceptsSameMuscleGroup(
            exerciseMuscleGroup: legExercise.muscleGroup,
            expected: .chest
        )

        // Then: rejected — even though the preset id is valid and resolves locally.
        #expect(accepted == false, "SC-002 requires deterministic rejection of wrong-muscle candidates")
    }

    @Test("A resolved candidate in the same muscle group as the current exercise is accepted")
    func validPresetIdInSameMuscleGroupIsAccepted() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalog = try makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "bench-press", nameEn: "Bench Press", muscleGroup: "chest"),
            makeExerciseJSON(id: "incline-db-press", nameEn: "Incline DB Press", muscleGroup: "chest"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        let chestSubstitute = try #require(
            ExerciseSeeder.findByPresetId("incline-db-press", context: context)
        )
        #expect(chestSubstitute.muscleGroup == .chest)

        #expect(
            SubstituteRecommendationFilter.acceptsSameMuscleGroup(
                exerciseMuscleGroup: chestSubstitute.muscleGroup,
                expected: .chest
            )
        )
    }
}
