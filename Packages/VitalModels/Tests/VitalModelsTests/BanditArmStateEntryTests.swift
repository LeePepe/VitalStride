import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("BanditArmStateEntry Tests")
struct BanditArmStateEntryTests {

    // MARK: - Container Registration

    @Test("banditModelTypes contains only BanditArmStateEntry")
    func banditModelTypesContent() {
        let typeNames = ModelContainerConfiguration.banditModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("BanditArmStateEntry"))
        #expect(typeNames.count == 1)
    }

    @Test("allModelTypes includes BanditArmStateEntry")
    func allModelTypesIncludesBanditArmStateEntry() {
        let typeNames = ModelContainerConfiguration.allModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("BanditArmStateEntry"))
    }

    @Test("training / healthCache / aiCache / telemetry configurations do NOT include BanditArmStateEntry")
    func banditIsolatedFromOtherPartitions() {
        let trainingNames = ModelContainerConfiguration.trainingModelTypes.map { String(describing: $0) }
        let healthNames = ModelContainerConfiguration.healthCacheModelTypes.map { String(describing: $0) }
        let aiNames = ModelContainerConfiguration.aiCacheModelTypes.map { String(describing: $0) }
        let telemetryNames = ModelContainerConfiguration.telemetryModelTypes.map { String(describing: $0) }

        #expect(!trainingNames.contains("BanditArmStateEntry"))
        #expect(!healthNames.contains("BanditArmStateEntry"))
        #expect(!aiNames.contains("BanditArmStateEntry"))
        #expect(!telemetryNames.contains("BanditArmStateEntry"))
    }

    @Test("banditModelTypes does NOT include any training / health-cache / ai-cache model")
    func banditDoesNotLeakOtherModels() {
        let banditNames = ModelContainerConfiguration.banditModelTypes.map { String(describing: $0) }
        let forbidden: Set<String> = [
            "Workout", "WorkoutExercise", "ExerciseSet", "Exercise",
            "WorkoutTemplate", "TemplateExercise", "UserInterest",
            "HealthCacheEntry", "AvailableTypesEntry",
            "OverviewInsightCache", "TrainingAdviceCache", "DataAnalysisCache",
            "RoutingSignalEntry",
        ]
        for name in banditNames {
            #expect(!forbidden.contains(name), "Bandit configuration must not carry \(name)")
        }
    }

    // MARK: - CloudKit Isolation (constitution I / FR-014)

    @Test("makeTestContainer succeeds and BanditArmStateEntry ModelConfiguration has cloudKitDatabase == .none")
    func banditArmStateEntryConfigurationIsNone() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()

        let matching = container.configurations.filter { config in
            (config.schema?.entities ?? []).contains(where: { $0.name == "BanditArmStateEntry" })
        }
        #expect(matching.count == 1, "BanditArmStateEntry must live in exactly one configuration")

        guard let config = matching.first else { return }
        let expectedNone = String(describing: ModelConfiguration.CloudKitDatabase.none)
        let dbDescription = String(describing: config.cloudKitDatabase)
        #expect(dbDescription == expectedNone,
                "BanditArmStateEntry configuration must be cloudKitDatabase:.none (宪法 I / FR-014); got \(dbDescription)")

        let forbidden: Set<String> = [
            "Workout", "WorkoutExercise", "ExerciseSet", "Exercise",
            "WorkoutTemplate", "TemplateExercise", "UserInterest",
            "HealthCacheEntry", "AvailableTypesEntry",
            "OverviewInsightCache", "TrainingAdviceCache", "DataAnalysisCache",
        ]
        for entity in (config.schema?.entities ?? []) {
            let name: String = entity.name
            #expect(!forbidden.contains(name),
                    "Bandit configuration leaked entity \(name); .none-partition isolation violated")
        }
    }

    // MARK: - Field-set red line (constitution I) — no health data may enter

    @Test("BanditArmStateEntry entity has exactly the 6 declared attributes and no others")
    func banditArmStateEntryFieldSetIsSealed() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let matching = container.configurations.filter { config in
            (config.schema?.entities ?? []).contains(where: { $0.name == "BanditArmStateEntry" })
        }
        let config = try #require(matching.first)
        let entity = try #require((config.schema?.entities ?? []).first(where: { $0.name == "BanditArmStateEntry" }))

        let attributeNames = Set(entity.attributes.map(\.name))
        let expected: Set<String> = [
            "kind", "deviceTier", "provider", "count", "rewardSum", "updatedAt",
        ]
        #expect(attributeNames == expected,
                "BanditArmStateEntry attribute set must be exactly \(expected) (宪法 I 红线); got \(attributeNames)")

        // Explicit forbid-list — any health / training numeric leaks trip this.
        let forbiddenAttributeNames: Set<String> = [
            "weight", "reps", "heartRate", "hrv", "steps", "distance",
            "calories", "workoutId", "exerciseId", "userId", "workout",
            "exercise", "rawPromptDebug", "rawResponseDebug", "prompt",
            "response", "latencyMs", "schemaValid", "accepted",
        ]
        for attr in attributeNames {
            #expect(!forbiddenAttributeNames.contains(attr),
                    "BanditArmStateEntry must not carry attribute \(attr) — health/training data ban (宪法 I)")
        }
    }

    // MARK: - CRUD + reward accumulation semantics

    @Test("insert and fetch BanditArmStateEntry with all fields")
    func insertAndFetchAllFields() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let now = Date()
        let entry = BanditArmStateEntry(
            kind: "chat",
            deviceTier: "cloudOnly",
            provider: "openai",
            count: 3,
            rewardSum: 1.75,
            updatedAt: now
        )
        context.insert(entry)
        try context.save()

        let results = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.kind == "chat")
        #expect(fetched.deviceTier == "cloudOnly")
        #expect(fetched.provider == "openai")
        #expect(fetched.count == 3)
        #expect(fetched.rewardSum == 1.75)
        #expect(fetched.updatedAt == now)
    }

    @Test("count += 1 and rewardSum += reward persist across save/fetch")
    func incrementSemanticsPersist() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry = BanditArmStateEntry(
            kind: "trainingAdvice",
            deviceTier: "onDeviceCapable",
            provider: "onDevice",
            count: 0,
            rewardSum: 0
        )
        context.insert(entry)
        try context.save()

        // Simulate three reward updates.
        let rewards: [Double] = [0.5, 1.0, 0.25]
        for reward in rewards {
            let all = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
            let arm = try #require(all.first)
            arm.count += 1
            arm.rewardSum += reward
            arm.updatedAt = Date()
            try context.save()
        }

        let results = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.count == 3)
        #expect(fetched.rewardSum == 1.75)
    }

    @Test("multiple arms coexist keyed by (kind, deviceTier, provider)")
    func multipleArmsPersistIndependently() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        struct ArmKey: Hashable {
            let kind: String
            let deviceTier: String
            let provider: String
        }
        let keys: [ArmKey] = [
            .init(kind: "chat", deviceTier: "cloudOnly", provider: "openai"),
            .init(kind: "chat", deviceTier: "cloudOnly", provider: "anthropic"),
            .init(kind: "chat", deviceTier: "onDeviceCapable", provider: "onDevice"),
            .init(kind: "trainingAdvice", deviceTier: "cloudOnly", provider: "openai"),
        ]
        for (i, k) in keys.enumerated() {
            let arm = BanditArmStateEntry(
                kind: k.kind,
                deviceTier: k.deviceTier,
                provider: k.provider,
                count: i,
                rewardSum: Double(i) * 0.1
            )
            context.insert(arm)
        }
        try context.save()

        let results = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        #expect(results.count == keys.count)
        let fetchedKeys = Set(results.map { ArmKey(kind: $0.kind, deviceTier: $0.deviceTier, provider: $0.provider) })
        #expect(fetchedKeys == Set(keys))
    }

    @Test("delete BanditArmStateEntry")
    func deleteBanditArmStateEntry() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry = BanditArmStateEntry(
            kind: "chat",
            deviceTier: "cloudOnly",
            provider: "openai"
        )
        context.insert(entry)
        try context.save()

        var results = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        #expect(results.isEmpty)
    }

    // MARK: - Coexistence with training / health-cache models in the shared container

    @Test("BanditArmStateEntry container has no Workout/Exercise/HealthCacheEntry in its own configuration")
    func banditConfigDoesNotShareWithTrainingOrHealthCache() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let banditConfig = try #require(container.configurations.first {
            ($0.schema?.entities ?? []).contains(where: { $0.name == "BanditArmStateEntry" })
        })

        let siblingNames = Set((banditConfig.schema?.entities ?? []).map(\.name))
        let forbidden: Set<String> = [
            "Workout", "WorkoutExercise", "ExerciseSet", "Exercise",
            "WorkoutTemplate", "TemplateExercise", "UserInterest",
            "HealthCacheEntry", "AvailableTypesEntry",
        ]
        #expect(siblingNames.isDisjoint(with: forbidden),
                "BanditArmStateEntry partition must not host training/health-cache entities; got siblings \(siblingNames)")
    }

    // MARK: - Field defaults

    @Test("init with defaults yields count=0, rewardSum=0")
    func initDefaultsAreZero() {
        let entry = BanditArmStateEntry(
            kind: "chat",
            deviceTier: "cloudOnly",
            provider: "openai"
        )
        // swiftlint:disable:next empty_count
        #expect(entry.count == 0)
        #expect(entry.rewardSum == 0)
    }
}
