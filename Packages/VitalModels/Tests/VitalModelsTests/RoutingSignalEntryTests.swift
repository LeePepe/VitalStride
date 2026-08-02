import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("RoutingSignalEntry Tests")
struct RoutingSignalEntryTests {

    // MARK: - Container Registration

    @Test("telemetryModelTypes contains RoutingSignalEntry")
    func telemetryModelTypesContent() {
        let typeNames = ModelContainerConfiguration.telemetryModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("RoutingSignalEntry"))
        #expect(typeNames.count == 1)
    }

    @Test("allModelTypes includes RoutingSignalEntry")
    func allModelTypesIncludesRoutingSignalEntry() {
        let typeNames = ModelContainerConfiguration.allModelTypes.map { String(describing: $0) }
        #expect(typeNames.contains("RoutingSignalEntry"))
    }

    @Test("training / healthCache / aiCache configurations do NOT include RoutingSignalEntry")
    func telemetryIsolatedFromOtherPartitions() {
        let trainingNames = ModelContainerConfiguration.trainingModelTypes.map { String(describing: $0) }
        let healthNames = ModelContainerConfiguration.healthCacheModelTypes.map { String(describing: $0) }
        let aiNames = ModelContainerConfiguration.aiCacheModelTypes.map { String(describing: $0) }

        #expect(!trainingNames.contains("RoutingSignalEntry"))
        #expect(!healthNames.contains("RoutingSignalEntry"))
        #expect(!aiNames.contains("RoutingSignalEntry"))
    }

    @Test("telemetryModelTypes does NOT include any training / health-cache model")
    func telemetryDoesNotLeakTrainingOrHealthModels() {
        let telemetryNames = ModelContainerConfiguration.telemetryModelTypes.map { String(describing: $0) }
        let forbidden: Set<String> = [
            "Workout", "WorkoutExercise", "ExerciseSet", "Exercise",
            "WorkoutTemplate", "TemplateExercise", "UserInterest",
            "HealthCacheEntry", "AvailableTypesEntry",
        ]
        for name in telemetryNames {
            #expect(!forbidden.contains(name), "RoutingSignalEntry configuration must not carry \(name)")
        }
    }

    // MARK: - CloudKit Isolation (constitution I)

    @Test("makeTestContainer succeeds and RoutingSignalEntry ModelConfiguration has cloudKitDatabase == .none")
    func routingSignalEntryConfigurationIsNone() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()

        // Find the ModelConfiguration that hosts RoutingSignalEntry.
        let matching = container.configurations.filter { config in
            (config.schema?.entities ?? []).contains(where: { $0.name == "RoutingSignalEntry" })
        }
        #expect(matching.count == 1, "RoutingSignalEntry must live in exactly one configuration")

        guard let config = matching.first else { return }
        // CloudKitDatabase is not Equatable — compare its rendered description exactly
        // against `String(describing: ModelConfiguration.CloudKitDatabase.none)`.
        // Substring matches like `.contains("none")` would falsely accept `.automatic`
        // and `.private(...)` because every case renders with the `_none` field label.
        let expectedNone = String(describing: ModelConfiguration.CloudKitDatabase.none)
        let dbDescription = String(describing: config.cloudKitDatabase)
        #expect(dbDescription == expectedNone,
                "RoutingSignalEntry configuration must be cloudKitDatabase:.none (宪法 I); got \(dbDescription)")

        // Enforce isolation: this configuration cannot host training / health-cache entities.
        let forbidden: Set<String> = [
            "Workout", "WorkoutExercise", "ExerciseSet", "Exercise",
            "WorkoutTemplate", "TemplateExercise", "UserInterest",
            "HealthCacheEntry", "AvailableTypesEntry",
        ]
        for entity in (config.schema?.entities ?? []) {
            let name: String = entity.name
            #expect(!forbidden.contains(name),
                    "Telemetry configuration leaked entity \(name); .none-partition isolation violated")
        }
    }

    // MARK: - CRUD

    @Test("insert and fetch RoutingSignalEntry with all fields")
    func insertAndFetchAllFields() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let now = Date()
        let entry = RoutingSignalEntry(
            kind: "chat",
            provider: "openai",
            deviceTier: "cloudOnly",
            latencyMs: 1234,
            schemaValid: true,
            accepted: true,
            timestamp: now,
            rawPromptDebug: "prompt",
            rawResponseDebug: "response"
        )
        context.insert(entry)
        try context.save()

        let results = try context.fetch(FetchDescriptor<RoutingSignalEntry>())
        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.kind == "chat")
        #expect(fetched.provider == "openai")
        #expect(fetched.deviceTier == "cloudOnly")
        #expect(fetched.latencyMs == 1234)
        #expect(fetched.schemaValid == true)
        #expect(fetched.accepted == true)
        #expect(fetched.timestamp == now)
        #expect(fetched.rawPromptDebug == "prompt")
        #expect(fetched.rawResponseDebug == "response")
    }

    @Test("insert with nil optional fields round-trips as nil")
    func nilOptionalsRoundTrip() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry = RoutingSignalEntry(
            kind: "trainingAdvice",
            provider: "onDevice",
            deviceTier: "onDeviceCapable",
            latencyMs: 42,
            schemaValid: false,
            accepted: nil,
            timestamp: Date(),
            rawPromptDebug: nil,
            rawResponseDebug: nil
        )
        context.insert(entry)
        try context.save()

        let results = try context.fetch(FetchDescriptor<RoutingSignalEntry>())
        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.accepted == nil)
        #expect(fetched.rawPromptDebug == nil)
        #expect(fetched.rawResponseDebug == nil)
        #expect(fetched.schemaValid == false)
    }

    @Test("multiple entries persist independently")
    func multipleEntriesPersistIndependently() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let kinds = ["chat", "overviewInsights", "trainingAdvice", "dataTrend", "substitute"]
        for (index, kind) in kinds.enumerated() {
            let entry = RoutingSignalEntry(
                kind: kind,
                provider: "openai",
                deviceTier: "cloudOnly",
                latencyMs: index * 100,
                schemaValid: true,
                accepted: (index % 2 == 0),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60))
            )
            context.insert(entry)
        }
        try context.save()

        let results = try context.fetch(FetchDescriptor<RoutingSignalEntry>())
        #expect(results.count == kinds.count)
        #expect(Set(results.map(\.kind)) == Set(kinds))
    }

    @Test("delete RoutingSignalEntry")
    func deleteRoutingSignalEntry() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let entry = RoutingSignalEntry(
            kind: "chat",
            provider: "openai",
            deviceTier: "cloudOnly",
            latencyMs: 100,
            schemaValid: true
        )
        context.insert(entry)
        try context.save()

        var results = try context.fetch(FetchDescriptor<RoutingSignalEntry>())
        #expect(results.count == 1)

        context.delete(results[0])
        try context.save()

        results = try context.fetch(FetchDescriptor<RoutingSignalEntry>())
        #expect(results.isEmpty)
    }

    // MARK: - Field Defaults

    @Test("init with defaults leaves optionals nil")
    func initDefaultsLeaveOptionalsNil() {
        let now = Date()
        let entry = RoutingSignalEntry(
            kind: "chat",
            provider: "openai",
            deviceTier: "cloudOnly",
            latencyMs: 500,
            schemaValid: true,
            timestamp: now
        )
        #expect(entry.accepted == nil)
        #expect(entry.rawPromptDebug == nil)
        #expect(entry.rawResponseDebug == nil)
        #expect(entry.timestamp == now)
    }
}
