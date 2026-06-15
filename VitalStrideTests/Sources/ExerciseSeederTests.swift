import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ExerciseSeeder")
struct ExerciseSeederTests {

    @Test("Seeds 300 exercises into empty container")
    func seedsIntoEmptyContainer() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        ExerciseSeeder.seedIfNeeded(context: context)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == 300)
    }

    @Test("Idempotent - does not duplicate on repeated calls")
    func idempotent() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        ExerciseSeeder.seedIfNeeded(context: context)
        ExerciseSeeder.seedIfNeeded(context: context)

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

        let custom = Exercise(
            nameEn: "My Custom Exercise",
            nameZh: "自定义动作",
            muscleGroup: .chest,
            equipment: .bodyweight,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        ExerciseSeeder.seedIfNeeded(context: context)

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

        ExerciseSeeder.seedIfNeeded(context: context)

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
    }

    @Test("Upgrades existing preset store by adding only missing exercises")
    func upgradesExistingPresets() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let existingNames = ["Barbell Bench Press", "Barbell Back Squat", "Conventional Deadlift"]
        for name in existingNames {
            let exercise = Exercise(
                nameEn: name,
                nameZh: "测试",
                muscleGroup: .chest,
                equipment: .barbell,
                isCustom: false
            )
            context.insert(exercise)
        }
        try context.save()

        ExerciseSeeder.seedIfNeeded(context: context)

        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false }
        )
        let total = try context.fetchCount(descriptor)
        #expect(total == 300, "Expected 300 total presets after upgrade, got \(total)")

        let benchDescriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.nameEn == "Barbell Bench Press" && $0.isCustom == false }
        )
        let benchCount = try context.fetchCount(benchDescriptor)
        #expect(benchCount == 1, "Expected exactly 1 'Barbell Bench Press', got \(benchCount)")
    }
}
