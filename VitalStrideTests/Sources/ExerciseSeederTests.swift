import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ExerciseSeeder")
struct ExerciseSeederTests {
    private let requiredInstructionLanguages = ["en", "es", "fr", "hi", "it", "ko", "pl", "ru", "tr", "zh"]
    private let suiteName = "com.vitalstride.test.ExerciseSeeder.\(UUID().uuidString)"

    private enum SaveBoundaryError: Error {
        case forced
    }

    private struct ExerciseSnapshot: Equatable {
        let nameEn: String
        let nameZh: String
        let muscleGroup: MuscleGroup
        let equipment: Equipment
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let isCustom: Bool
        let presetId: String?
        let mediaKey: String?
        let defaultWeightLow: Double?
        let defaultWeightMid: Double?
        let defaultWeightHigh: Double?
        let defaultRepsLow: Int
        let defaultRepsMid: Int
        let defaultRepsHigh: Int

        init(_ exercise: Exercise) {
            nameEn = exercise.nameEn
            nameZh = exercise.nameZh
            muscleGroup = exercise.muscleGroup
            equipment = exercise.equipment
            primaryMuscles = exercise.primaryMuscles
            secondaryMuscles = exercise.secondaryMuscles
            isCustom = exercise.isCustom
            presetId = exercise.presetId
            mediaKey = exercise.mediaKey
            defaultWeightLow = exercise.defaultWeightLow
            defaultWeightMid = exercise.defaultWeightMid
            defaultWeightHigh = exercise.defaultWeightHigh
            defaultRepsLow = exercise.defaultRepsLow
            defaultRepsMid = exercise.defaultRepsMid
            defaultRepsHigh = exercise.defaultRepsHigh
        }
    }

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
        equipment: String = "barbell",
        primaryMuscles: [String] = [],
        secondaryMuscles: [String] = [],
        defaultWeightLow: Double? = nil,
        defaultWeightMid: Double? = nil,
        defaultWeightHigh: Double? = nil,
        mediaKey: String? = nil,
        source: String? = nil,
        sourceData: [String: Any]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "id": id,
            "nameEn": nameEn,
            "nameZh": nameZh,
            "muscleGroup": muscleGroup,
            "equipment": equipment,
            "primaryMuscles": primaryMuscles,
            "secondaryMuscles": secondaryMuscles,
        ]
        if let low = defaultWeightLow { payload["defaultWeightLow"] = low }
        if let mid = defaultWeightMid { payload["defaultWeightMid"] = mid }
        if let high = defaultWeightHigh { payload["defaultWeightHigh"] = high }
        if let mediaKey { payload["mediaKey"] = mediaKey }
        if let source { payload["source"] = source }
        if let sourceData { payload["sourceData"] = sourceData }
        return payload
    }

    private func makeInstructionMap(
        base: String,
        omitting omittedLanguages: Set<String> = [],
        emptyLanguages: Set<String> = []
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: requiredInstructionLanguages.compactMap { language in
            guard !omittedLanguages.contains(language) else { return nil }
            if emptyLanguages.contains(language) {
                return (language, "")
            }
            return (language, "\(base)-\(language)")
        })
    }

    private func makeInstructionStepsMap(
        base: String,
        omitting omittedLanguages: Set<String> = [],
        emptyLanguages: Set<String> = []
    ) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: requiredInstructionLanguages.compactMap { language in
            guard !omittedLanguages.contains(language) else { return nil }
            if emptyLanguages.contains(language) {
                return (language, [])
            }
            return (language, ["\(base)-\(language)-step-1", "\(base)-\(language)-step-2"])
        })
    }

    private func makeSourceDataJSON(
        id: String,
        name: String,
        equipment: String = "barbell",
        target: String = "pectoralis major",
        muscleGroup: String = "anterior deltoid",
        secondaryMuscles: [String] = ["anterior deltoid", "triceps"],
        omittingInstructionLanguages: Set<String> = [],
        emptyInstructionLanguages: Set<String> = [],
        omittingInstructionStepLanguages: Set<String> = [],
        emptyInstructionStepLanguages: Set<String> = []
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "category": "strength",
            "body_part": "chest",
            "equipment": equipment,
            "target": target,
            "muscle_group": muscleGroup,
            "secondary_muscles": secondaryMuscles,
            "instructions": makeInstructionMap(
                base: id,
                omitting: omittingInstructionLanguages,
                emptyLanguages: emptyInstructionLanguages
            ),
            "instruction_steps": makeInstructionStepsMap(
                base: id,
                omitting: omittingInstructionStepLanguages,
                emptyLanguages: emptyInstructionStepLanguages
            ),
            "media_id": "media-\(id)",
            "image": "images/\(id).jpg",
            "gif_url": "videos/\(id).gif",
            "attribution": "Source attribution \(id)",
            "created_at": "2026-08-17T00:00:00Z",
        ]
    }

    private func expectSeedError(
        _ expected: ExerciseSeeder.SeedError,
        catalogData: Data,
        context: ModelContext,
        userDefaults: UserDefaults
    ) {
        do {
            try ExerciseSeeder.seed(context: context, userDefaults: userDefaults, catalogData: catalogData)
            Issue.record("Expected seed to throw \(expected)")
        } catch let error as ExerciseSeeder.SeedError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected ExerciseSeeder.SeedError, got \(error)")
        }
    }

    private func fetchExercise(presetId: String, context: ModelContext) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId == presetId }
        )).first
    }

    private struct BundledCatalogEnvelope: Decodable {
        struct BundledExercise: Decodable { let id: String }
        let version: String
        let exercises: [BundledExercise]
    }

    private func loadBundledCatalog() throws -> BundledCatalogEnvelope {
        let url = try #require(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BundledCatalogEnvelope.self, from: data)
    }

    private func bundledCatalogPresetCount() throws -> Int {
        try loadBundledCatalog().exercises.count
    }

    private func bundledCatalogVersion() -> String {
        (try? loadBundledCatalog().version) ?? ""
    }

    // MARK: - Full Bundle Tests

    @Test("Seeds full bundled catalog into empty container with presetId")
    func seedsIntoEmptyContainer() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let expectedCount = try bundledCatalogPresetCount()

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let exercises = try context.fetch(descriptor)
        #expect(exercises.count == expectedCount)

        let withPresetId = exercises.filter { $0.presetId != nil }
        #expect(withPresetId.count == expectedCount)
    }

    @Test("Idempotent — same version does not duplicate")
    func idempotent() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let expectedCount = try bundledCatalogPresetCount()

        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)
        ExerciseSeeder.seedIfNeeded(context: context, userDefaults: defaults)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == expectedCount)
    }

    @Test("Does not affect custom exercises")
    func doesNotAffectCustomExercises() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let expectedCount = try bundledCatalogPresetCount()

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
        #expect(presetCount == expectedCount)
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
        #expect(benchPress.primaryMuscles == ["pectorals"])
        #expect(benchPress.secondaryMuscles == ["triceps", "shoulders"])
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

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == bundledCatalogVersion())
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

    @Test("Catalog v4 backfills nameZh for presets whose Chinese name was never translated")
    func backfillsUntranslatedChineseName() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        // v3: a preset whose nameZh was never translated (equals nameEn), plus
        // one that already has a Chinese name (nameZh differs).
        let catalogV3 = makeCatalogData(version: "3", exercises: [
            makeExerciseJSON(id: "ex-en", nameEn: "Air Bike", nameZh: "Air Bike"),
            makeExerciseJSON(id: "ex-zh", nameEn: "Bench Press", nameZh: "卧推"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV3)

        // v4: the untranslated one now has a Chinese name; the other unchanged.
        let catalogV4 = makeCatalogData(version: "4", exercises: [
            makeExerciseJSON(id: "ex-en", nameEn: "Air Bike", nameZh: "空中蹬车卷腹"),
            makeExerciseJSON(id: "ex-zh", nameEn: "Bench Press", nameZh: "卧推"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV4)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let byId = Dictionary(uniqueKeysWithValues: all.compactMap { ex in ex.presetId.map { ($0, ex) } })
        #expect(byId["ex-en"]?.nameZh == "空中蹬车卷腹")  // untranslated → backfilled
        #expect(byId["ex-zh"]?.nameZh == "卧推")           // already translated → untouched
    }

    @Test("Catalog v4 does not clobber an already-translated preset name")
    func backfillSkipsAlreadyTranslated() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV3 = makeCatalogData(version: "3", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Squat", nameZh: "深蹲"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV3)

        // v4 changes the catalog nameZh — backfill must NOT overwrite, because
        // the stored value was already translated (nameZh != nameEn).
        let catalogV4 = makeCatalogData(version: "4", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Squat", nameZh: "杠铃深蹲"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV4)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.first?.nameZh == "深蹲")  // unchanged
    }

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

    @Test("Migration assigns renamed upstream v5 preset in place from nil-version legacy rows")
    func migrationBackfillsRenamedUpstreamPresetInPlace() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let legacy = Exercise(
            nameEn: "Legacy Bench Press",
            nameZh: "旧卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["pectoralis major"],
            secondaryMuscles: ["triceps"],
            isCustom: false,
            mediaKey: "legacy-media",
            defaultWeightLow: 80,
            defaultWeightMid: 95,
            defaultWeightHigh: 120,
            defaultRepsLow: 6,
            defaultRepsMid: 10,
            defaultRepsHigh: 14
        )
        context.insert(legacy)

        let workout = Workout(
            type: .strength,
            startDate: .now,
            exercises: [WorkoutExercise(order: 0, exercise: legacy)]
        )
        let template = WorkoutTemplate(
            name: "Legacy Push Day",
            exercises: [TemplateExercise(exercise: legacy, targetSets: 4, order: 0)]
        )
        context.insert(workout)
        context.insert(template)
        try context.save()

        let legacyModelID = legacy.persistentModelID

        let catalogV5 = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Canonical Incline Press",
                nameZh: "旧卧推",
                muscleGroup: "shoulders",
                equipment: "dumbbell",
                primaryMuscles: ["upper chest"],
                secondaryMuscles: ["front delts", "triceps"],
                defaultWeightLow: 80,
                defaultWeightMid: 95,
                defaultWeightHigh: 120,
                mediaKey: "legacy-media",
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-0001",
                    name: "canonical incline press",
                    equipment: "dumbbell",
                    target: "upper chest",
                    muscleGroup: "front delts",
                    secondaryMuscles: ["front delts", "triceps"]
                )
            ),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV5)

        let migrated = try #require(try fetchExercise(presetId: "upstream-1", context: context))
        #expect(migrated.persistentModelID == legacyModelID)
        #expect(migrated.nameEn == "Canonical Incline Press")
        #expect(migrated.nameZh == "旧卧推")
        #expect(migrated.muscleGroup == .shoulders)
        #expect(migrated.equipment == .dumbbell)
        #expect(migrated.primaryMuscles == ["upper chest"])
        #expect(migrated.secondaryMuscles == ["front delts", "triceps"])
        #expect(migrated.mediaKey == "legacy-media")
        #expect(migrated.defaultWeightLow == 80)
        #expect(migrated.defaultWeightMid == 95)
        #expect(migrated.defaultWeightHigh == 120)
        #expect(migrated.defaultRepsLow == 6)
        #expect(migrated.defaultRepsMid == 10)
        #expect(migrated.defaultRepsHigh == 14)
        #expect((migrated.workoutExercises ?? []).count == 1)
        #expect((migrated.templateExercises ?? []).count == 1)
        #expect(migrated.workoutExercises?.first?.workout?.persistentModelID == workout.persistentModelID)
        #expect(migrated.templateExercises?.first?.template?.persistentModelID == template.persistentModelID)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.presetId == nil })).isEmpty)
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

    // MARK: - v1 → v2 backfill (defaultWeight)

    @Test("Seeds new exercises with defaultWeight from JSON on fresh install")
    func seedsWithDefaultWeightOnFreshInstall() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalog = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(
                id: "bench",
                nameEn: "Bench Press",
                defaultWeightLow: 80,
                defaultWeightMid: 60,
                defaultWeightHigh: 40
            ),
            makeExerciseJSON(
                id: "plank",
                nameEn: "Plank",
                muscleGroup: "core",
                equipment: "bodyweight"
            ),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalog)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)

        let bench = try #require(all.first { $0.presetId == "bench" })
        #expect(bench.defaultWeightLow == 80)
        #expect(bench.defaultWeightMid == 60)
        #expect(bench.defaultWeightHigh == 40)

        let plank = try #require(all.first { $0.presetId == "plank" })
        #expect(plank.defaultWeightLow == nil)
        #expect(plank.defaultWeightMid == nil)
        #expect(plank.defaultWeightHigh == nil)
    }

    @Test("v1 → v2 upgrade backfills defaultWeight on existing presets")
    func backfillsDefaultsOnV2Upgrade() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        // v1: no defaultWeight fields → presets stored with nil
        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "bench", nameEn: "Bench Press"),
            makeExerciseJSON(id: "plank", nameEn: "Plank",
                             muscleGroup: "core", equipment: "bodyweight"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let benchV1 = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "bench" }
            )).first
        )
        #expect(benchV1.defaultWeightLow == nil)

        // v2: same presets now carry weights → backfill should populate them
        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(
                id: "bench",
                nameEn: "Bench Press",
                defaultWeightLow: 80,
                defaultWeightMid: 60,
                defaultWeightHigh: 40
            ),
            makeExerciseJSON(id: "plank", nameEn: "Plank",
                             muscleGroup: "core", equipment: "bodyweight"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let benchV2 = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "bench" }
            )).first
        )
        #expect(benchV2.defaultWeightLow == 80)
        #expect(benchV2.defaultWeightMid == 60)
        #expect(benchV2.defaultWeightHigh == 40)

        // Plank preset stays nil (core / bodyweight — no baseline)
        let plankV2 = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "plank" }
            )).first
        )
        #expect(plankV2.defaultWeightLow == nil)

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "2")
    }

    @Test("v1 → v2 backfill does not overwrite user-modified weight values")
    func backfillDoesNotOverwriteUserValues() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV1 = makeCatalogData(version: "1", exercises: [
            makeExerciseJSON(id: "bench", nameEn: "Bench Press"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV1)

        let bench = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "bench" }
            )).first
        )
        // Simulate user overriding the low bucket only
        bench.defaultWeightLow = 100
        try context.save()

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(
                id: "bench",
                nameEn: "Bench Press",
                defaultWeightLow: 80,
                defaultWeightMid: 60,
                defaultWeightHigh: 40
            ),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let benchAfter = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "bench" }
            )).first
        )
        // User's Low value preserved; nil Mid/High filled from DTO
        #expect(benchAfter.defaultWeightLow == 100)
        #expect(benchAfter.defaultWeightMid == 60)
        #expect(benchAfter.defaultWeightHigh == 40)
    }

    @Test("Backfill leaves isCustom exercises alone")
    func backfillIgnoresCustomExercises() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let custom = Exercise(
            nameEn: "My Move",
            nameZh: "自定义",
            muscleGroup: .chest,
            equipment: .barbell,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(
                id: "bench",
                nameEn: "Bench Press",
                defaultWeightLow: 80,
                defaultWeightMid: 60,
                defaultWeightHigh: 40
            ),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let customs = try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true }
        ))
        #expect(customs.count == 1)
        #expect(customs.first?.defaultWeightLow == nil)
        #expect(customs.first?.defaultWeightMid == nil)
        #expect(customs.first?.defaultWeightHigh == nil)
    }

    // MARK: - v2 → v3 mediaKey + incremental upsert

    @Test("DTO tolerates JSON without mediaKey (v2 back-compat)")
    func dtoDecodesWithoutMediaKey() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        // Payload without a `mediaKey` field at all — simulates v2 JSON.
        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let bench = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-1" }
            )).first
        )
        #expect(bench.mediaKey == nil)
    }

    @Test("DTO decodes mediaKey when present in v3 JSON")
    func dtoDecodesMediaKeyWhenPresent() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV3 = makeCatalogData(version: "3", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A", mediaKey: "bench-001"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV3)

        let a = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-1" }
            )).first
        )
        #expect(a.mediaKey == "bench-001")

        let b = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-2" }
            )).first
        )
        #expect(b.mediaKey == nil)
    }

    @Test("v2 → v3 upgrade preserves existing presets, inserts new, leaves custom alone")
    func v2ToV3IncrementalUpsert() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        // v2: two presets + one user custom action already in DB.
        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let custom = Exercise(
            nameEn: "My Move",
            nameZh: "自定义",
            muscleGroup: .arms,
            equipment: .bodyweight,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        // Simulate user having edited Exercise A after v2 seeded it — v3
        // must not overwrite user-authored fields.
        let aBefore = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-1" }
            )).first
        )
        aBefore.defaultWeightLow = 999
        try context.save()

        // v3: same two presets (now with mediaKey) + one net-new preset.
        let catalogV3 = makeCatalogData(version: "3", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A", mediaKey: "a-001"),
            makeExerciseJSON(id: "ex-2", nameEn: "Exercise B", mediaKey: "b-001"),
            makeExerciseJSON(id: "ex-3", nameEn: "Exercise C",
                             muscleGroup: "back", mediaKey: "c-001"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV3)

        // Presets: 2 preserved + 1 inserted = 3.
        let presets = try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        ))
        #expect(presets.count == 3)

        // Existing presets preserved (identity + user-authored field kept).
        let aAfter = try #require(presets.first { $0.presetId == "ex-1" })
        #expect(aAfter.nameEn == "Exercise A")
        #expect(aAfter.defaultWeightLow == 999)
        // mediaKey was nil pre-upgrade → backfilled from v3 DTO.
        #expect(aAfter.mediaKey == "a-001")

        let bAfter = try #require(presets.first { $0.presetId == "ex-2" })
        #expect(bAfter.mediaKey == "b-001")

        // Net-new preset inserted with its mediaKey.
        let cAfter = try #require(presets.first { $0.presetId == "ex-3" })
        #expect(cAfter.nameEn == "Exercise C")
        #expect(cAfter.muscleGroup == .back)
        #expect(cAfter.mediaKey == "c-001")

        // Custom untouched.
        let customs = try context.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true }
        ))
        #expect(customs.count == 1)
        #expect(customs.first?.nameEn == "My Move")
        #expect(customs.first?.presetId == nil)
        #expect(customs.first?.mediaKey == nil)

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "3")
    }

    @Test("v2 → v3 backfill does not overwrite user-set mediaKey")
    func v3BackfillPreservesUserMediaKey() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        // v2 seed with no mediaKey.
        let catalogV2 = makeCatalogData(version: "2", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV2)

        let a = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-1" }
            )).first
        )
        // Simulate a user- or migration-set mediaKey before v3.
        a.mediaKey = "user-set"
        try context.save()

        let catalogV3 = makeCatalogData(version: "3", exercises: [
            makeExerciseJSON(id: "ex-1", nameEn: "Exercise A", mediaKey: "catalog-a"),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV3)

        let aAfter = try #require(
            try context.fetch(FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId == "ex-1" }
            )).first
        )
        #expect(aAfter.mediaKey == "user-set")
    }

    @Test("Catalog v5 updates only canonical upstream fields in place")
    func v5UpdatesOnlyCanonicalUpstreamFieldsInPlace() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV4 = makeCatalogData(version: "4", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Legacy Bench Press",
                nameZh: "旧卧推",
                muscleGroup: "chest",
                equipment: "barbell",
                primaryMuscles: ["pectoralis major"],
                secondaryMuscles: ["triceps"],
                defaultWeightLow: 80,
                defaultWeightHigh: 120
            ),
            makeExerciseJSON(
                id: "vital-1",
                nameEn: "Vital Original",
                nameZh: "原生动作",
                muscleGroup: "core",
                equipment: "bodyweight",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                mediaKey: "vital-media"
            ),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV4)

        let upstreamBefore = try #require(try fetchExercise(presetId: "upstream-1", context: context))
        upstreamBefore.defaultWeightMid = nil
        upstreamBefore.defaultRepsLow = 6
        upstreamBefore.defaultRepsMid = 11
        upstreamBefore.defaultRepsHigh = 17
        upstreamBefore.mediaKey = nil

        let workout = Workout(
            type: .strength,
            startDate: .now,
            exercises: [WorkoutExercise(order: 0, exercise: upstreamBefore)]
        )
        let template = WorkoutTemplate(
            name: "Push Day",
            exercises: [TemplateExercise(exercise: upstreamBefore, targetSets: 4, order: 0)]
        )
        let custom = Exercise(
            nameEn: "My Custom Move",
            nameZh: "我的自定义动作",
            muscleGroup: .legs,
            equipment: .bodyweight,
            primaryMuscles: ["quads"],
            secondaryMuscles: ["glutes"],
            isCustom: true,
            mediaKey: "custom-media",
            defaultWeightLow: 25,
            defaultWeightMid: 35,
            defaultWeightHigh: 45,
            defaultRepsLow: 8,
            defaultRepsMid: 12,
            defaultRepsHigh: 16
        )
        context.insert(workout)
        context.insert(template)
        context.insert(custom)
        try context.save()

        let upstreamModelID = upstreamBefore.persistentModelID
        let upstreamSnapshot = ExerciseSnapshot(upstreamBefore)

        let vitalBefore = try #require(try fetchExercise(presetId: "vital-1", context: context))
        let vitalModelID = vitalBefore.persistentModelID
        let vitalSnapshot = ExerciseSnapshot(vitalBefore)

        let customModelID = custom.persistentModelID
        let customSnapshot = ExerciseSnapshot(custom)

        let catalogV5 = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Canonical Incline Press",
                nameZh: "新中文不应覆盖",
                muscleGroup: "shoulders",
                equipment: "dumbbell",
                primaryMuscles: ["upper chest"],
                secondaryMuscles: ["front delts", "triceps"],
                defaultWeightLow: 1,
                defaultWeightMid: 2,
                defaultWeightHigh: 3,
                mediaKey: "catalog-media",
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-0001",
                    name: "canonical incline press",
                    equipment: "dumbbell",
                    target: "upper chest",
                    muscleGroup: "front delts",
                    secondaryMuscles: ["front delts", "triceps"]
                )
            ),
            makeExerciseJSON(
                id: "vital-1",
                nameEn: "Vital Renamed",
                nameZh: "新中文也不应覆盖",
                muscleGroup: "back",
                equipment: "cable",
                primaryMuscles: ["lats"],
                secondaryMuscles: ["biceps"],
                defaultWeightLow: 10,
                defaultWeightMid: 20,
                defaultWeightHigh: 30,
                mediaKey: "catalog-vital-media",
                source: "vitalstride"
            ),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV5)

        let upstreamAfter = try #require(try fetchExercise(presetId: "upstream-1", context: context))
        #expect(upstreamAfter.persistentModelID == upstreamModelID)
        #expect(upstreamAfter.nameEn == "Canonical Incline Press")
        #expect(upstreamAfter.muscleGroup == .shoulders)
        #expect(upstreamAfter.equipment == .dumbbell)
        #expect(upstreamAfter.primaryMuscles == ["upper chest"])
        #expect(upstreamAfter.secondaryMuscles == ["front delts", "triceps"])
        #expect(upstreamAfter.nameZh == upstreamSnapshot.nameZh)
        #expect(upstreamAfter.defaultWeightLow == upstreamSnapshot.defaultWeightLow)
        #expect(upstreamAfter.defaultWeightMid == upstreamSnapshot.defaultWeightMid)
        #expect(upstreamAfter.defaultWeightHigh == upstreamSnapshot.defaultWeightHigh)
        #expect(upstreamAfter.mediaKey == upstreamSnapshot.mediaKey)
        #expect(upstreamAfter.defaultRepsLow == upstreamSnapshot.defaultRepsLow)
        #expect(upstreamAfter.defaultRepsMid == upstreamSnapshot.defaultRepsMid)
        #expect(upstreamAfter.defaultRepsHigh == upstreamSnapshot.defaultRepsHigh)
        #expect((upstreamAfter.workoutExercises ?? []).count == 1)
        #expect((upstreamAfter.templateExercises ?? []).count == 1)
        #expect(upstreamAfter.workoutExercises?.first?.workout?.persistentModelID == workout.persistentModelID)
        #expect(upstreamAfter.templateExercises?.first?.template?.persistentModelID == template.persistentModelID)

        let vitalAfter = try #require(try fetchExercise(presetId: "vital-1", context: context))
        #expect(vitalAfter.persistentModelID == vitalModelID)
        #expect(ExerciseSnapshot(vitalAfter) == vitalSnapshot)

        let customAfter = try #require(
            try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom == true })).first
        )
        #expect(customAfter.persistentModelID == customModelID)
        #expect(ExerciseSnapshot(customAfter) == customSnapshot)
    }

    @Test("Catalog v5 rejects duplicate stable IDs before mutating")
    func v5RejectsDuplicateStableIDs() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "dup-id",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["chest"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "source-1", name: "source one", target: "chest", secondaryMuscles: ["triceps"])
            ),
            makeExerciseJSON(
                id: "dup-id",
                nameEn: "Canonical Two",
                nameZh: "动作二",
                muscleGroup: "back",
                equipment: "cable",
                primaryMuscles: ["lats"],
                secondaryMuscles: ["biceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "source-2", name: "source two", equipment: "cable", target: "lats", muscleGroup: "biceps", secondaryMuscles: ["biceps"])
            ),
        ])

        expectSeedError(.duplicateExerciseID("dup-id"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == nil)
    }

    @Test("Catalog v5 rejects duplicate upstream source IDs before mutating")
    func v5RejectsDuplicateUpstreamSourceIDs() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["chest"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "shared-source", name: "source one", target: "chest", secondaryMuscles: ["triceps"])
            ),
            makeExerciseJSON(
                id: "stable-2",
                nameEn: "Canonical Two",
                nameZh: "动作二",
                muscleGroup: "back",
                equipment: "cable",
                primaryMuscles: ["lats"],
                secondaryMuscles: ["biceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "shared-source", name: "source two", equipment: "cable", target: "lats", muscleGroup: "biceps", secondaryMuscles: ["biceps"])
            ),
        ])

        expectSeedError(.duplicateUpstreamSourceID("shared-source"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects incomplete instruction language maps")
    func v5RejectsIncompleteInstructionLanguageMaps() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-1",
                    name: "source one",
                    equipment: "body weight",
                    target: "abs",
                    muscleGroup: "obliques",
                    secondaryMuscles: ["obliques"],
                    omittingInstructionLanguages: ["fr"]
                )
            ),
        ])

        expectSeedError(.invalidInstructionLanguages("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects upstream rows missing sourceData")
    func v5RejectsMissingSourceData() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["pectoralis major"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset"
            ),
        ])

        expectSeedError(.missingSourceData("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects incomplete instruction step language maps")
    func v5RejectsIncompleteInstructionStepLanguageMaps() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-1",
                    name: "source one",
                    equipment: "body weight",
                    target: "abs",
                    muscleGroup: "obliques",
                    secondaryMuscles: ["obliques"],
                    omittingInstructionStepLanguages: ["fr"]
                )
            ),
        ])

        expectSeedError(.invalidInstructionSteps("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects empty instruction step lists")
    func v5RejectsEmptyInstructionSteps() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-1",
                    name: "source one",
                    equipment: "body weight",
                    target: "abs",
                    muscleGroup: "obliques",
                    secondaryMuscles: ["obliques"],
                    emptyInstructionStepLanguages: ["fr"]
                )
            ),
        ])

        expectSeedError(.emptyInstructionSteps("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects invalid primary muscle mirrors")
    func v5RejectsInvalidPrimaryMuscles() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["triceps"],
                secondaryMuscles: ["obliques"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-1",
                    name: "source one",
                    equipment: "body weight",
                    target: "abs",
                    muscleGroup: "obliques",
                    secondaryMuscles: ["obliques"]
                )
            ),
        ])

        expectSeedError(.invalidPrimaryMuscles("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects invalid secondary muscle mirrors")
    func v5RejectsInvalidSecondaryMuscles() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-1",
                    name: "source one",
                    equipment: "body weight",
                    target: "abs",
                    muscleGroup: "obliques",
                    secondaryMuscles: ["obliques"]
                )
            ),
        ])

        expectSeedError(.invalidSecondaryMuscles("stable-1"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 rejects unknown sources")
    func v5RejectsUnknownSources() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let invalidCatalog = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "stable-1",
                nameEn: "Unknown Source Move",
                nameZh: "未知来源动作",
                source: "third-party-source"
            ),
        ])

        expectSeedError(.unknownSource("third-party-source"), catalogData: invalidCatalog, context: context, userDefaults: defaults)

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test("Catalog v5 same-version recovery inserts missing preset IDs")
    func v5SameVersionRecoveryInsertsMissingPresetIDs() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        defaults.set("5", forKey: ExerciseSeeder.seedVersionKey)

        let existing = Exercise(
            nameEn: "Existing Upstream",
            nameZh: "已存在上游",
            muscleGroup: .chest,
            equipment: .barbell,
            primaryMuscles: ["pectoralis major"],
            secondaryMuscles: ["triceps"],
            isCustom: false,
            presetId: "upstream-1"
        )
        let stale = Exercise(
            nameEn: "Stale Preset",
            nameZh: "陈旧预设",
            muscleGroup: .back,
            equipment: .cable,
            primaryMuscles: ["lats"],
            secondaryMuscles: ["biceps"],
            isCustom: false,
            presetId: "stale-only"
        )
        context.insert(existing)
        context.insert(stale)
        try context.save()

        let catalogV5 = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Recovered Upstream",
                nameZh: "恢复上游",
                primaryMuscles: ["pectoralis major"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "source-1", name: "recovered upstream", target: "pectoralis major", secondaryMuscles: ["triceps"])
            ),
            makeExerciseJSON(
                id: "vital-1",
                nameEn: "Recovered Vital",
                nameZh: "恢复原生",
                muscleGroup: "core",
                equipment: "bodyweight",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "vitalstride"
            ),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV5)

        let presets = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.presetId != nil }))
        #expect(presets.count == 3)
        #expect(presets.contains { $0.presetId == "upstream-1" })
        #expect(presets.contains { $0.presetId == "vital-1" })
        #expect(presets.contains { $0.presetId == "stale-only" })
    }

    @Test("Catalog v5 repeated seed is idempotent once all presets exist")
    func v5RepeatedSeedIsIdempotent() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV5 = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Canonical One",
                nameZh: "动作一",
                primaryMuscles: ["pectoralis major"],
                secondaryMuscles: ["triceps"],
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(id: "source-1", name: "canonical one", target: "pectoralis major", secondaryMuscles: ["triceps"])
            ),
            makeExerciseJSON(
                id: "vital-1",
                nameEn: "Vital One",
                nameZh: "原生动作一",
                muscleGroup: "core",
                equipment: "bodyweight",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "vitalstride"
            ),
        ])

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV5)
        let firstIDs = Set(try context.fetch(FetchDescriptor<Exercise>()).compactMap(\.presetId))

        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV5)

        let all = try context.fetch(FetchDescriptor<Exercise>())
        #expect(all.count == 2)
        #expect(Set(all.compactMap(\.presetId)) == firstIDs)
        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "5")
    }

    @Test("Catalog v5 rolls back mutations and version when save boundary throws")
    func v5RollsBackWhenSaveBoundaryThrows() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let catalogV4 = makeCatalogData(version: "4", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Legacy Bench Press",
                nameZh: "旧卧推",
                muscleGroup: "chest",
                equipment: "barbell",
                primaryMuscles: ["pectoralis major"],
                secondaryMuscles: ["triceps"],
                defaultWeightLow: 80,
                defaultWeightHigh: 120
            ),
        ])
        try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: catalogV4)

        let upstreamBefore = try #require(try fetchExercise(presetId: "upstream-1", context: context))
        upstreamBefore.defaultWeightMid = nil
        upstreamBefore.defaultRepsLow = 7
        upstreamBefore.defaultRepsMid = 12
        upstreamBefore.defaultRepsHigh = 18
        upstreamBefore.mediaKey = nil
        try context.save()

        let modelID = upstreamBefore.persistentModelID
        let snapshot = ExerciseSnapshot(upstreamBefore)

        let catalogV5 = makeCatalogData(version: "5", exercises: [
            makeExerciseJSON(
                id: "upstream-1",
                nameEn: "Canonical Incline Press",
                nameZh: "新中文不应覆盖",
                muscleGroup: "shoulders",
                equipment: "dumbbell",
                primaryMuscles: ["upper chest"],
                secondaryMuscles: ["front delts", "triceps"],
                defaultWeightLow: 1,
                defaultWeightMid: 2,
                defaultWeightHigh: 3,
                mediaKey: "catalog-media",
                source: "hasaneyldrm/exercises-dataset",
                sourceData: makeSourceDataJSON(
                    id: "source-0001",
                    name: "canonical incline press",
                    equipment: "dumbbell",
                    target: "upper chest",
                    muscleGroup: "front delts",
                    secondaryMuscles: ["front delts", "triceps"]
                )
            ),
            makeExerciseJSON(
                id: "vital-1",
                nameEn: "Recovered Vital",
                nameZh: "恢复原生",
                muscleGroup: "core",
                equipment: "bodyweight",
                primaryMuscles: ["abs"],
                secondaryMuscles: ["obliques"],
                source: "vitalstride"
            ),
        ])

        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "4")

        #expect(throws: SaveBoundaryError.self) {
            try ExerciseSeeder.seed(
                context: context,
                userDefaults: defaults,
                catalogData: catalogV5,
                save: { _ in throw SaveBoundaryError.forced }
            )
        }

        let upstreamAfter = try #require(try fetchExercise(presetId: "upstream-1", context: context))
        #expect(upstreamAfter.persistentModelID == modelID)
        #expect(ExerciseSnapshot(upstreamAfter) == snapshot)
        #expect(try fetchExercise(presetId: "vital-1", context: context) == nil)
        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == "4")
    }

    @Test("Pre-mutation decode failure preserves unrelated caller pending changes")
    func preMutationDecodeFailurePreservesUnrelatedPendingChanges() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let defaults = makeUserDefaults()
        defer { cleanUp(defaults) }

        let unrelated = Exercise(
            nameEn: "Caller Exercise",
            nameZh: "调用方动作",
            muscleGroup: .back,
            equipment: .barbell,
            primaryMuscles: ["lats"],
            secondaryMuscles: ["biceps"],
            isCustom: false,
            presetId: "caller-owned"
        )
        context.insert(unrelated)
        try context.save()

        unrelated.nameEn = "Caller Exercise Pending Rename"
        unrelated.defaultWeightMid = 52.5
        unrelated.secondaryMuscles = ["biceps", "rear delts"]
        let pendingSnapshot = ExerciseSnapshot(unrelated)

        let invalidJSON = Data("{".utf8)

        do {
            try ExerciseSeeder.seed(context: context, userDefaults: defaults, catalogData: invalidJSON)
            Issue.record("Expected invalid JSON to throw a DecodingError")
        } catch is DecodingError {
            // Expected: decoding fails before the seeder mutates the context.
        } catch {
            Issue.record("Expected DecodingError, got \(error)")
        }

        let unrelatedAfter = try #require(try fetchExercise(presetId: "caller-owned", context: context))
        #expect(ExerciseSnapshot(unrelatedAfter) == pendingSnapshot)
        #expect(defaults.string(forKey: ExerciseSeeder.seedVersionKey) == nil)
    }
}
