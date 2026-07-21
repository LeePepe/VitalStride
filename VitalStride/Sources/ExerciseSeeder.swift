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
        let defaultWeightLow: Double?
        let defaultWeightMid: Double?
        let defaultWeightHigh: Double?
        let mediaKey: String?
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

        // Backfill defaults for existing preset exercises when advancing to a
        // new catalog version. Nil-only writes so any user-modified value is
        // preserved. Runs both on fresh installs (harmless — no-op) and on
        // upgrades from v1 (or an empty storedVersion with legacy presets).
        if storedVersion != catalog.version {
            try backfillDefaults(context: context, dtos: catalog.exercises)
        }

        if insertedCount > 0 || storedVersion != catalog.version {
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
                presetId: dto.id,
                mediaKey: dto.mediaKey,
                defaultWeightLow: dto.defaultWeightLow,
                defaultWeightMid: dto.defaultWeightMid,
                defaultWeightHigh: dto.defaultWeightHigh
            )
            context.insert(exercise)
            insertedCount += 1
        }

        return insertedCount
    }

    /// Look up a preset `Exercise` by its exact `presetId`. Returns `nil` when
    /// no match exists or when the SwiftData fetch fails, so callers can
    /// gracefully fall back to manual selection without crashing.
    static func findByPresetId(_ presetId: String, context: ModelContext) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId == presetId }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("findByPresetId fetch failed: \(type(of: error))")
            return nil
        }
    }

    /// Backfill preset Exercise fields when advancing to a newer catalog
    /// version. `defaultWeight*` / `mediaKey` are written only when currently
    /// nil (never overwrites user-modified values). `nameZh` is backfilled only
    /// when the stored value was never translated (still equals `nameEn`) —
    /// catalog v4 added Chinese names for ~1135 previously-English presets.
    /// `isCustom` exercises are excluded via the presetId predicate.
    static func backfillDefaults(context: ModelContext, dtos: [ExerciseDTO]) throws {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId != nil }
        )
        let existing = try context.fetch(descriptor)
        guard !existing.isEmpty else { return }

        let idToDTO = Dictionary(
            dtos.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for exercise in existing {
            guard let presetId = exercise.presetId, let dto = idToDTO[presetId] else { continue }
            if exercise.defaultWeightLow == nil {
                exercise.defaultWeightLow = dto.defaultWeightLow
            }
            if exercise.defaultWeightMid == nil {
                exercise.defaultWeightMid = dto.defaultWeightMid
            }
            if exercise.defaultWeightHigh == nil {
                exercise.defaultWeightHigh = dto.defaultWeightHigh
            }
            if exercise.mediaKey == nil {
                exercise.mediaKey = dto.mediaKey
            }
            // Catalog v4: backfill Chinese names for preset exercises whose
            // stored `nameZh` was never translated (still equal to `nameEn`).
            // Guard on that equality so we never clobber a name a user may have
            // customized, nor an already-good translation from a later catalog.
            if exercise.nameZh == exercise.nameEn, dto.nameZh != dto.nameEn {
                exercise.nameZh = dto.nameZh
            }
        }
    }
}
