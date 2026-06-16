import Foundation
import OSLog
import SwiftData
import VitalModels

enum ExerciseSeeder {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "ExerciseSeeder")
    static let seedVersionKey = "com.vitalstride.exerciseSeedVersion"

    struct ExerciseCatalog: Decodable {
        let version: String
        let exercises: [ExerciseDTO]
    }

    struct ExerciseDTO: Decodable {
        let id: String
        let nameEn: String
        let nameZh: String
        let muscleGroup: MuscleGroup
        let equipment: Equipment
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
    }

    static func seedIfNeeded(
        context: ModelContext,
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard let url = bundle.url(forResource: "exercises", withExtension: "json") else {
            logger.error("exercises.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            try seed(context: context, userDefaults: userDefaults, catalogData: data)
        } catch {
            logger.error("Seed failed: \(type(of: error))")
        }
    }

    static func seed(
        context: ModelContext,
        userDefaults: UserDefaults,
        catalogData: Data
    ) throws {
        let catalog = try JSONDecoder().decode(ExerciseCatalog.self, from: catalogData)

        let storedVersion = userDefaults.string(forKey: seedVersionKey)

        if storedVersion == catalog.version {
            let presetDescriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId != nil }
            )
            let presetCount = try context.fetchCount(presetDescriptor)
            if presetCount > 0 {
                logger.debug("Seed skipped: version \(catalog.version) unchanged")
                return
            }
        }

        if storedVersion == nil {
            try migrateExistingPresets(context: context, dtos: catalog.exercises)
        }

        let insertedCount = try insertNewExercises(context: context, dtos: catalog.exercises)

        if insertedCount > 0 {
            try context.save()
        }

        userDefaults.set(catalog.version, forKey: seedVersionKey)

        logger.info("Seed completed: version \(catalog.version), inserted \(insertedCount) exercises")
    }

    private static func migrateExistingPresets(
        context: ModelContext,
        dtos: [ExerciseDTO]
    ) throws {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == false && $0.presetId == nil }
        )
        let existingPresets = try context.fetch(descriptor)
        guard !existingPresets.isEmpty else { return }

        let nameToDTO = Dictionary(
            dtos.map { ($0.nameEn, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for exercise in existingPresets {
            if let dto = nameToDTO[exercise.nameEn] {
                exercise.presetId = dto.id
            }
        }

        try context.save()
    }

    private static func insertNewExercises(
        context: ModelContext,
        dtos: [ExerciseDTO]
    ) throws -> Int {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId != nil }
        )
        let existingPresets = try context.fetch(descriptor)
        let existingIds = Set(existingPresets.compactMap(\.presetId))

        var insertedCount = 0
        for dto in dtos where !existingIds.contains(dto.id) {
            let exercise = Exercise(
                nameEn: dto.nameEn,
                nameZh: dto.nameZh,
                muscleGroup: dto.muscleGroup,
                equipment: dto.equipment,
                primaryMuscles: dto.primaryMuscles,
                secondaryMuscles: dto.secondaryMuscles,
                isCustom: false,
                presetId: dto.id
            )
            context.insert(exercise)
            insertedCount += 1
        }

        return insertedCount
    }
}
