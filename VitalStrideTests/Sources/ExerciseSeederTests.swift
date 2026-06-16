import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ExerciseSeeder")
struct ExerciseSeederTests {
    private let suiteName = "com.vitalstride.test.ExerciseSeeder.\(UUID().uuidString)"

    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    private func cleanUp(_ userDefaults: UserDefaults) {
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeCatalogData(version: String, exercises: [[String: Any]]) -> Data {
        let catalog: [String: Any] = ["version": version, "exercises": exercises]
        return try! JSONSerialization.data(withJSONObject: catalog)
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

    // MARK: - Full Bundle Tests

    @Test("Seeds 300 exercises into empty container with presetId")
    func seedsIntoEmptyContainer() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let exercises = try context.fetch(descriptor)
        #expect(exercises.count == 300)

        let withPresetId = exercises.filter { $0.presetId != nil }
        #expect(withPresetId.count == 300)
    }

    @Test("Idempotent — same version does not duplicate")
    func idempotent() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)
        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == 300)
    }

    @Test("Does not affect custom exercises")
    func doesNotAffectCustomExercises() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let custom = Exercise(
            nameEn: "My Custom Exercise",
            nameZh: "自定义动作",
            muscleGroup: .chest,
            equipment: .bodyweight,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let customDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true }
        )
        let customCount = try context.fetchCount(customDescriptor)
        #expect(customCount == 1)

        let presetDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let presetCount = try context.fetchCount(presetDescriptor)
        #expect(presetCount == 300)
    }

    @Test("Seeded data matches JSON source")
    func dataMatchesJSON() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.nameEn == "Barbell Bench Press" }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)

        let benchPress = try #require(results.first)
        #expect(benchPress.nameZh == "杠铃卧推")
        #expect(benchPress.muscleGroup == .chest)
        #expect(benchPress.equipment == .barbell)
        #expect(benchPress.primaryMuscles == ["pectoralis major"])
        #expect(benchPress.secondaryMuscles == ["anterior deltoid", "triceps"])
        #expect(benchPress.isCustom == false)
        #expect(benchPress.presetId == "550e8400-e29b-41d4-a716-446655440001")
    }

    @Test("Stores version after successful seed")
    func storesVersion() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == nil)

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "1")
    }

    // MARK: - Version Skip + Empty DB Recovery

    @Test("Skips seed when version unchanged and presets exist")
    func skipsWhenVersionUnchangedAndPresetsExist() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)
        let countAfterFirst = try context.fetchCount(FetchDescriptor<Exercise>())
        #expect(countAfterFirst == 2)

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)
        let countAfterSecond = try context.fetchCount(FetchDescriptor<Exercise>())
        #expect(countAfterSecond == 2)
    }

    @Test("Seeds into empty DB even when UserDefaults has matching version")
    func seedsEmptyDBDespiteMatchingVersion() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        defaults.set("1", forKey: ExerciseSeeder.seedVersionKey)

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        #expect(count == 2)
    }

    // MARK: - Incremental Seed with Fixtures

    @Test("New version inserts only added exercises")
    func newVersionInsertsOnlyAdded() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
            makeExerciseJSON(id: "ex-3", nameEn: "Exercise C", muscleGroup: "back"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let allDescriptor = FetchDescriptor<Exercise>()
        let all = try context.fetch(allDescriptor)
        #expect(all.count == 3)

        let newExercise = all.first { $0.presetId == "ex-3" }
        #expect(newExercise?.nameEn == "Exercise C")
        #expect(newExercise?.muscleGroup == .back)

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "2")
    }

    @Test("New version does not delete exercises removed from JSON")
    func newVersionDoesNotDeleteRemoved() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
            makeExerciseJSON(id: "ex-3", nameEn: "Exercise C"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 3)

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-3", nameEn: "Exercise C"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 3)

        let removed = all.first { $0.presetId == "ex-2" }
        #expect(removed != nil)
        #expect(removed?.nameEn == "Exercise B")
    }

    @Test("Does not overwrite existing exercises on version upgrade")
    func doesNotOverwriteExisting() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A", nameZh: "动作A"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A Renamed", nameZh: "动作A改名"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 1)
        #expect(all.first?.nameEn == "Exercise A")
        #expect(all.first?.nameZh == "动作A")
    }

    // MARK: - Migration

    @Test("Migration backfills presetId on existing preset exercises")
    func migrationBackfillsPresetId() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let legacy = Exercise(
            nameEn: "Exercise A",
            nameZh: "动作A",
            muscleGroup: .chest,
            equipment: .barbell,
            isCustom: false
        )
        context.insert(legacy)
        try context.save()

        #expect(legacy.presetId == nil)

        let catalog = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        #expect(legacy.presetId == "ex-1")

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)

        let exerciseB = all.first { $0.presetId == "ex-2" }
        #expect(exerciseB?.nameEn == "Exercise B")
    }

    @Test("Custom exercises not affected by migration or incremental seed")
    func customExercisesUnaffectedWithFixtures() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let custom = Exercise(
            nameEn: "My Move",
            nameZh: "自定义",
            muscleGroup: .arms,
            equipment: .bodyweight,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let customDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true }
        )
        let customs = try context.fetch(customDescriptor)
        #expect(customs.count == 1)
        #expect(customs.first?.nameEn == "My Move")
        #expect(customs.first?.presetId == nil)
    }
}
