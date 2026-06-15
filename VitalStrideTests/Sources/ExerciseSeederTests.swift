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

    @Test("Seeds all exercises into empty container with presetId")
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
        #expect(exercises.count == 100)

        let withPresetId = exercises.filter { $0.presetId != nil }
        #expect(withPresetId.count == 100)
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
        #expect(count == 100)
    }

    @Test("Skips seed when version is unchanged")
    func skipsOnSameVersion() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        defaults.set("1", forKey: "com.vitalstride.exerciseSeedVersion")

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == 0)
    }

    @Test("Incremental seed inserts only missing exercises")
    func incrementalInsert() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let allDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let allExercises = try context.fetch(allDescriptor)
        #expect(allExercises.count == 100)

        let toDelete = Array(allExercises.prefix(3))
        let deletedIds = Set(toDelete.compactMap(\.presetId))
        for exercise in toDelete {
            context.delete(exercise)
        }
        try context.save()

        let afterDelete = try context.fetchCount(allDescriptor)
        #expect(afterDelete == 97)

        defaults.set("0", forKey: "com.vitalstride.exerciseSeedVersion")

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let afterReseed = try context.fetchCount(allDescriptor)
        #expect(afterReseed == 100)

        let reinsertedDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false && $0.presetId != nil }
        )
        let reinserted = try context.fetch(reinsertedDescriptor)
        let reinsertedIds = Set(reinserted.compactMap(\.presetId))
        #expect(deletedIds.isSubset(of: reinsertedIds))
    }

    @Test("Does not delete exercises removed from JSON")
    func doesNotDeleteRemovedExercises() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let extra = Exercise(
            nameEn: "Obsolete Exercise",
            nameZh: "已废弃动作",
            muscleGroup: .chest,
            equipment: .bodyweight,
            isCustom: false,
            presetId: "obsolete-id-not-in-json"
        )
        context.insert(extra)
        try context.save()

        defaults.set("0", forKey: "com.vitalstride.exerciseSeedVersion")

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == 101)

        let obsoleteDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId == "obsolete-id-not-in-json" }
        )
        let obsolete = try context.fetch(obsoleteDescriptor)
        #expect(obsolete.count == 1)
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
        #expect(presetCount == 100)
    }

    @Test("Migration backfills presetId on existing exercises")
    func migrationBackfillsPresetId() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let legacy = Exercise(
            nameEn: "Barbell Bench Press",
            nameZh: "杠铃卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["pectoralis major"],
            secondaryMuscles: ["anterior deltoid", "triceps"],
            isCustom: false
        )
        context.insert(legacy)
        try context.save()

        #expect(legacy.presetId == nil)

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        #expect(legacy.presetId == "550e8400-e29b-41d4-a716-446655440001")

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.nameEn == "Barbell Bench Press" && $0.isCustom == false }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
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

        #expect(defaults.string(forKey: "com.vitalstride.exerciseSeedVersion") == nil)

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        #expect(defaults.string(forKey: "com.vitalstride.exerciseSeedVersion") == "1")
    }
}
