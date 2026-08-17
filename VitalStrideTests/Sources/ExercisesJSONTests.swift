import Foundation
import Testing

private let requiredInstructionLanguages: Set<String> = ["en", "es", "fr", "hi", "it", "ko", "pl", "ru", "tr", "zh"]
private let expectedSourceEquipmentValues: Set<String> = [
    "assisted",
    "band",
    "barbell",
    "body weight",
    "bosu ball",
    "cable",
    "dumbbell",
    "elliptical machine",
    "ez barbell",
    "hammer",
    "kettlebell",
    "leverage machine",
    "medicine ball",
    "olympic barbell",
    "resistance band",
    "roller",
    "rope",
    "skierg machine",
    "sled machine",
    "smith machine",
    "stability ball",
    "stationary bike",
    "stepmill machine",
    "tire",
    "trap bar",
    "upper body ergometer",
    "weighted",
    "wheel roller",
]

private struct PresetExerciseSourceData: Decodable {
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

private struct PresetExercise: Decodable {
    let id: String
    let nameEn: String
    let nameZh: String
    let muscleGroup: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let source: String
    let sourceData: PresetExerciseSourceData?
}

private struct ExerciseCatalogTestEnvelope: Decodable {
    let version: String
    let exercises: [PresetExercise]
}

@Suite("Exercises JSON")
struct ExercisesJSONTests {
    let version: String
    let exercises: [PresetExercise]

    init() throws {
        let url = Bundle.main.url(forResource: "exercises", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(ExerciseCatalogTestEnvelope.self, from: data)
        version = catalog.version
        exercises = catalog.exercises
    }

    @Test("Catalog version is v5")
    func catalogVersion() {
        #expect(version == "5")
    }

    @Test("Catalog contains the full reconciled row count")
    func exactCatalogCount() {
        #expect(exercises.count == 1_558)
    }

    @Test("All exercise IDs are unique")
    func uniqueIds() {
        let ids = exercises.map(\.id)
        #expect(ids.count == Set(ids).count, "Duplicate exercise IDs found")
    }

    @Test("Source split is 1,324 upstream-backed and 234 VitalStride-only")
    func sourceSplit() {
        let upstream = exercises.filter { $0.source == "hasaneyldrm/exercises-dataset" }
        let vitalStrideOnly = exercises.filter { $0.source == "vitalstride" }

        #expect(upstream.count == 1_324)
        #expect(vitalStrideOnly.count == 234)
        #expect(upstream.allSatisfy { $0.sourceData != nil })
        #expect(vitalStrideOnly.allSatisfy { $0.sourceData == nil })
    }

    @Test("Upstream source IDs are unique and complete")
    func uniqueSourceIDs() {
        let sourceIDs = exercises.compactMap(\.sourceData?.id)
        #expect(sourceIDs.count == 1_324)
        #expect(sourceIDs.count == Set(sourceIDs).count)
    }

    @Test("Upstream rows preserve all ten instruction languages")
    func allInstructionLanguagesPreserved() {
        for exercise in exercises {
            guard let sourceData = exercise.sourceData else {
                continue
            }
            #expect(Set(sourceData.instructions.keys) == requiredInstructionLanguages)
            #expect(Set(sourceData.instructionSteps.keys) == requiredInstructionLanguages)
            for language in requiredInstructionLanguages {
                #expect(!(sourceData.instructions[language] ?? "").isEmpty)
                #expect(!(sourceData.instructionSteps[language] ?? []).isEmpty)
            }
        }
    }

    @Test("All 28 upstream equipment strings are represented")
    func allSourceEquipmentValuesRepresented() {
        let equipmentValues = Set(exercises.compactMap(\.sourceData?.equipment))
        #expect(equipmentValues == expectedSourceEquipmentValues)
    }

    @Test("App muscle mapping follows upstream target and secondary muscles")
    func sourceMuscleMapping() {
        for exercise in exercises {
            guard let sourceData = exercise.sourceData else {
                continue
            }

            if !sourceData.target.isEmpty {
                #expect(exercise.primaryMuscles == [sourceData.target], "Primary muscles must mirror upstream target for \(sourceData.id)")
            }

            let expectedSecondary = sourceData.secondaryMuscles.filter { $0 != exercise.primaryMuscles.first }
            #expect(exercise.secondaryMuscles == expectedSecondary, "Secondary muscles must preserve upstream order for \(sourceData.id)")
        }
    }

    @Test("Cable Pulldown keeps lats primary and biceps plus forearms secondary")
    func cablePulldownRegression() throws {
        let cablePulldown = try #require(exercises.first { $0.sourceData?.id == "0198" })
        #expect(cablePulldown.primaryMuscles == ["lats"])
        #expect(cablePulldown.secondaryMuscles == ["biceps", "forearms"])
    }

    @Test("Names stay populated for every row")
    func namesNonEmpty() {
        for exercise in exercises {
            #expect(!exercise.nameEn.isEmpty)
            #expect(!exercise.nameZh.isEmpty)
        }
    }
}
