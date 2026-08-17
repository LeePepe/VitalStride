import Foundation
import OSLog
import SwiftData
import VitalModels

enum ExerciseSeeder {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "ExerciseSeeder")
    private static let upstreamSource = "hasaneyldrm/exercises-dataset"
    private static let vitalStrideSource = "vitalstride"
    private static let requiredInstructionLanguages: Set<String> = ["en", "es", "fr", "hi", "it", "ko", "pl", "ru", "tr", "zh"]

    static let seedVersionKey = "com.vitalstride.exerciseSeedVersion"

    enum SeedError: Error, Equatable {
        case duplicateExerciseID(String)
        case duplicateUpstreamSourceID(String)
        case missingSource(String)
        case unknownSource(String)
        case missingSourceData(String)
        case invalidInstructionLanguages(String)
        case invalidInstructionSteps(String)
        case emptyInstruction(String)
        case emptyInstructionSteps(String)
        case invalidPrimaryMuscles(String)
        case invalidSecondaryMuscles(String)
    }

    private struct LegacyUpstreamMatchKey: Hashable {
        let nameZh: String
        let mediaKey: String?
        let defaultWeightLow: Double?
        let defaultWeightMid: Double?
        let defaultWeightHigh: Double?
    }

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
        let source: String?
        let sourceData: ExerciseSourceDTO?
    }

    struct ExerciseSourceDTO: Decodable {
        let id: String
        let name: String
        let category: String
        let bodyPart: String
        let equipment: String
        let target: String
        let muscleGroup: String
        let secondaryMuscles: [String]
        let instructions: [String: String]
        let instructionSteps: [String: [String]]
        let mediaID: String
        let image: String
        let gifURL: String
        let attribution: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case category
            case bodyPart = "body_part"
            case equipment
            case target
            case muscleGroup = "muscle_group"
            case secondaryMuscles = "secondary_muscles"
            case instructions
            case instructionSteps = "instruction_steps"
            case mediaID = "media_id"
            case image
            case gifURL = "gif_url"
            case attribution
            case createdAt = "created_at"
        }
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
        try seed(
            context: context,
            userDefaults: userDefaults,
            catalogData: catalogData,
            save: { try $0.save() }
        )
    }

    static func seed(
        context: ModelContext,
        userDefaults: UserDefaults,
        catalogData: Data,
        save: (ModelContext) throws -> Void
    ) throws {
        let storedVersion = userDefaults.string(forKey: seedVersionKey)
        let catalog = try JSONDecoder().decode(ExerciseCatalog.self, from: catalogData)
        try validateCatalogIfNeeded(catalog)
        let catalogIDs = Set(catalog.exercises.map(\.id))

        if storedVersion == catalog.version {
            let presetDescriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.presetId != nil }
            )
            let existingPresets = try context.fetch(presetDescriptor)
            let existingIDs = Set(existingPresets.compactMap(\.presetId))
            if existingPresets.count == catalogIDs.count, existingIDs == catalogIDs {
                logger.debug("Seed skipped: version \(catalog.version) unchanged")
                return
            }
        }

        do {
            if storedVersion == nil {
                try migrateExistingPresets(context: context, dtos: catalog.exercises)
            }

            if catalog.version == "5" {
                try updateExistingUpstreamExercises(context: context, dtos: catalog.exercises)
            }

            let insertedCount = try insertNewExercises(context: context, dtos: catalog.exercises)

            // Legacy catalogs use nil-only backfill semantics on upgrade. V5
            // preserves all non-canonical fields exactly and skips this phase.
            if storedVersion != catalog.version, catalog.version != "5" {
                try backfillDefaults(context: context, dtos: catalog.exercises)
            }

            try save(context)
            userDefaults.set(catalog.version, forKey: seedVersionKey)

            logger.info("Seed completed: version \(catalog.version), inserted \(insertedCount) exercises")
        } catch {
            context.rollback()
            throw error
        }
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

        let dtosByName = Dictionary(
            grouping: dtos,
            by: \ExerciseDTO.nameEn
        )
        let upstreamDTOsByLegacyKey = Dictionary(
            grouping: dtos.filter { $0.source == upstreamSource },
            by: legacyUpstreamMatchKey(for:)
        )
        var remainingDTOsByID = Dictionary(
            uniqueKeysWithValues: dtos.map { ($0.id, $0) }
        )

        for exercise in existingPresets {
            if let dto = uniqueRemainingNameMatch(
                for: exercise,
                dtosByName: dtosByName,
                remainingDTOsByID: remainingDTOsByID
            ) {
                exercise.presetId = dto.id
                remainingDTOsByID.removeValue(forKey: dto.id)
                continue
            }

            let fallbackCandidates = upstreamDTOsByLegacyKey[legacyUpstreamMatchKey(for: exercise)]?
                .filter { remainingDTOsByID[$0.id] != nil }

            if let dto = onlyElement(from: fallbackCandidates) {
                exercise.presetId = dto.id
                remainingDTOsByID.removeValue(forKey: dto.id)
            }
        }
    }

    private static func uniqueRemainingNameMatch(
        for exercise: Exercise,
        dtosByName: [String: [ExerciseDTO]],
        remainingDTOsByID: [String: ExerciseDTO]
    ) -> ExerciseDTO? {
        onlyElement(
            from: dtosByName[exercise.nameEn]?
                .filter { remainingDTOsByID[$0.id] != nil }
        )
    }

    private static func legacyUpstreamMatchKey(for dto: ExerciseDTO) -> LegacyUpstreamMatchKey {
        LegacyUpstreamMatchKey(
            nameZh: dto.nameZh,
            mediaKey: dto.mediaKey,
            defaultWeightLow: dto.defaultWeightLow,
            defaultWeightMid: dto.defaultWeightMid,
            defaultWeightHigh: dto.defaultWeightHigh
        )
    }

    private static func legacyUpstreamMatchKey(for exercise: Exercise) -> LegacyUpstreamMatchKey {
        LegacyUpstreamMatchKey(
            nameZh: exercise.nameZh,
            mediaKey: exercise.mediaKey,
            defaultWeightLow: exercise.defaultWeightLow,
            defaultWeightMid: exercise.defaultWeightMid,
            defaultWeightHigh: exercise.defaultWeightHigh
        )
    }

    private static func onlyElement<T>(from values: [T]?) -> T? {
        guard let values, values.count == 1 else { return nil }
        return values[0]
    }

    private static func updateExistingUpstreamExercises(
        context: ModelContext,
        dtos: [ExerciseDTO]
    ) throws {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId != nil && $0.isCustom == false }
        )
        let existing = try context.fetch(descriptor)
        guard !existing.isEmpty else { return }

        let existingByID = Dictionary(
            existing.compactMap { exercise in
                exercise.presetId.map { ($0, exercise) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        for dto in dtos where dto.source == upstreamSource {
            guard let exercise = existingByID[dto.id] else { continue }
            exercise.nameEn = dto.nameEn
            exercise.muscleGroup = dto.muscleGroup
            exercise.equipment = dto.equipment
            exercise.primaryMuscles = dto.primaryMuscles
            exercise.secondaryMuscles = dto.secondaryMuscles
        }
    }

    private static func insertNewExercises(
        context: ModelContext,
        dtos: [ExerciseDTO]
    ) throws -> Int {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.presetId != nil }
        )
        let existingPresets = try context.fetch(descriptor)
        var existingIDs = Set(existingPresets.compactMap(\.presetId))

        var insertedCount = 0
        for dto in dtos where !existingIDs.contains(dto.id) {
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
            existingIDs.insert(dto.id)
            insertedCount += 1
        }

        return insertedCount
    }

    private static func validateCatalogIfNeeded(_ catalog: ExerciseCatalog) throws {
        guard catalog.version == "5" else { return }

        var seenExerciseIDs = Set<String>()
        var seenSourceIDs = Set<String>()

        for dto in catalog.exercises {
            guard seenExerciseIDs.insert(dto.id).inserted else {
                throw SeedError.duplicateExerciseID(dto.id)
            }

            guard let source = dto.source else {
                throw SeedError.missingSource(dto.id)
            }

            switch source {
            case upstreamSource:
                guard let sourceData = dto.sourceData else {
                    throw SeedError.missingSourceData(dto.id)
                }

                guard seenSourceIDs.insert(sourceData.id).inserted else {
                    throw SeedError.duplicateUpstreamSourceID(sourceData.id)
                }

                guard Set(sourceData.instructions.keys) == requiredInstructionLanguages else {
                    throw SeedError.invalidInstructionLanguages(dto.id)
                }
                guard Set(sourceData.instructionSteps.keys) == requiredInstructionLanguages else {
                    throw SeedError.invalidInstructionSteps(dto.id)
                }

                for language in requiredInstructionLanguages {
                    guard let instruction = sourceData.instructions[language], !instruction.isEmpty else {
                        throw SeedError.emptyInstruction(dto.id)
                    }
                    guard let steps = sourceData.instructionSteps[language], !steps.isEmpty else {
                        throw SeedError.emptyInstructionSteps(dto.id)
                    }
                }

                guard dto.primaryMuscles == [sourceData.target] else {
                    throw SeedError.invalidPrimaryMuscles(dto.id)
                }

                let expectedSecondary = sourceData.secondaryMuscles.filter { $0 != dto.primaryMuscles.first }
                guard dto.secondaryMuscles == expectedSecondary else {
                    throw SeedError.invalidSecondaryMuscles(dto.id)
                }

            case vitalStrideSource:
                break

            default:
                throw SeedError.unknownSource(source)
            }
        }
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
