import Foundation
import Testing
import VitalModels
@testable import VitalStride

private let requiredInstructionLanguages: Set<String> = ["en", "es", "fr", "hi", "it", "ko", "pl", "ru", "tr", "zh"]
private let expectedCuratedSourceEquipmentValues: Set<String> = [
    "band",
    "barbell",
    "body weight",
    "cable",
    "dumbbell",
    "ez barbell",
    "leverage machine",
    "medicine ball",
    "resistance band",
    "rope",
    "sled machine",
    "smith machine",
    "stability ball",
    "trap bar",
    "weighted",
    "wheel roller",
]
private let forbiddenCardioAndStretchEquipmentValues: Set<String> = [
    "assisted",
    "bosu_ball",
    "elliptical_machine",
    "hammer",
    "olympic_barbell",
    "roller",
    "skierg_machine",
    "stationary_bike",
    "stepmill_machine",
    "tire",
    "upper_body_ergometer",
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
    private let version: String
    private let exercises: [PresetExercise]

    init() throws {
        let url = try #require(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(ExerciseCatalogTestEnvelope.self, from: data)
        version = catalog.version
        exercises = catalog.exercises
    }

    @Test("Catalog version is v6")
    func catalogVersion() {
        #expect(version == "6")
    }

    @Test("Catalog contains the curated golden row count")
    func exactCatalogCount() {
        #expect(exercises.count == 316)
    }

    @Test("Local calf-raise presets exclude the antagonist tibialis anterior")
    func calfRaiseSecondaryMuscles() throws {
        let ids = [
            "550e8400-e29b-41d4-a716-446655440039",
            "550e8400-e29b-41d4-a716-446655440199",
            "550e8400-e29b-41d4-a716-446655440200",
            "550e8400-e29b-41d4-a716-446655440202",
        ]
        for id in ids {
            let exercise = try #require(exercises.first { $0.id == id })
            #expect(exercise.primaryMuscles == ["calves"])
            #expect(exercise.secondaryMuscles.isEmpty)
        }
    }

    @Test("All exercise IDs are unique")
    func uniqueIds() {
        let ids = exercises.map(\.id)
        #expect(ids.count == Set(ids).count, "Duplicate exercise IDs found")
    }

    @Test("Source split is 82 curated upstream-backed and 234 VitalStride-only")
    func sourceSplit() {
        let upstream = exercises.filter { $0.source == "hasaneyldrm/exercises-dataset" }
        let vitalStrideOnly = exercises.filter { $0.source == "vitalstride" }

        #expect(upstream.count == 82)
        #expect(vitalStrideOnly.count == 234)
        #expect(upstream.allSatisfy { $0.sourceData != nil })
        #expect(vitalStrideOnly.allSatisfy { $0.sourceData == nil })
    }

    @Test("Upstream source IDs are unique and complete")
    func uniqueSourceIDs() {
        let sourceIDs = exercises.compactMap(\.sourceData?.id)
        #expect(sourceIDs.count == 82)
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

    @Test("Curated upstream equipment allowlist excludes cardio machines and stretches")
    func allSourceEquipmentValuesRepresented() {
        let equipmentValues = Set(exercises.compactMap(\.sourceData?.equipment))
        #expect(equipmentValues == expectedCuratedSourceEquipmentValues)
        let appEquipmentValues = Set(exercises.map(\.equipment))
        #expect(appEquipmentValues.isDisjoint(with: forbiddenCardioAndStretchEquipmentValues))
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

    @Test("Lever Front Pulldown keeps lats primary and biceps plus forearms secondary")
    func cablePulldownRegression() throws {
        let frontPulldown = try #require(exercises.first { $0.sourceData?.id == "0579" })
        #expect(frontPulldown.primaryMuscles == ["lats"])
        #expect(frontPulldown.secondaryMuscles.contains("biceps"))
    }

    @Test("Names stay populated for every row")
    func namesNonEmpty() {
        for exercise in exercises {
            #expect(!exercise.nameEn.isEmpty)
            #expect(!exercise.nameZh.isEmpty)
        }
    }

    @Test("Every row in v6 has a translated Chinese name and zero encoding glitches or POV/V2 duplicates")
    func boundedBandPresetTranslations() throws {
        for exercise in exercises {
            #expect(exercise.nameZh != exercise.nameEn, "Untranslated exercise: \(exercise.nameEn)")
            #expect(!exercise.nameEn.contains("в°"))
            #expect(!exercise.nameZh.contains("в°"))
            #expect(!exercise.nameEn.localizedCaseInsensitiveContains("back Pov"))
            #expect(!exercise.nameEn.localizedCaseInsensitiveContains("side Pov"))
            #expect(!exercise.nameEn.contains("V. 2"))
            #expect(!exercise.nameEn.contains("V. 3"))
        }
        let sledLegPress = try #require(exercises.first { $0.sourceData?.id == "0739" })
        #expect(sledLegPress.nameEn == "Sled 45° Leg Press")
        #expect(sledLegPress.nameZh == "45度倒蹬机蹬腿")
    }

    @Test("Full catalog resolves to the final 12-section nonempty aggregation")
    func fullCatalogSectionDistribution() {
        let workouts = exercises.map { exercise in
            let rawEquipment = exercise.sourceData?.equipment ?? exercise.equipment
            return Exercise(
                nameEn: exercise.nameEn,
                nameZh: exercise.nameZh,
                muscleGroup: MuscleGroup(rawValue: exercise.muscleGroup) ?? .fullBody,
                equipment: equipment(fromSourceValue: rawEquipment),
                primaryMuscles: exercise.primaryMuscles,
                secondaryMuscles: exercise.secondaryMuscles
            )
        }

        let grouped = ExercisePickerSectionGrouping.groupedSections(from: workouts)
        let counts = Dictionary(uniqueKeysWithValues: grouped.map { ($0.0, $0.1.count) })

        #expect(grouped.count == 12)
        #expect(grouped.reduce(0) { $0 + $1.1.count } == 316)
        #expect(grouped.map(\.0) == [
            .band,
            .barbell,
            .bodyweight,
            .cable,
            .dumbbell,
            .ezBarbell,
            .kettlebell,
            .leverageMachine,
            .machine,
            .smithMachine,
            .weighted,
            .other
        ])
        #expect(counts == [
            .band: 9,
            .barbell: 55,
            .bodyweight: 38,
            .cable: 41,
            .dumbbell: 54,
            .ezBarbell: 8,
            .kettlebell: 20,
            .leverageMachine: 20,
            .machine: 38,
            .smithMachine: 12,
            .weighted: 8,
            .other: 13
        ])
        #expect(grouped.allSatisfy { section, items in
            !items.isEmpty && items.allSatisfy { $0.section == section }
        })
        #expect(workouts.filter { $0.equipment == .rope }.count == 2)
        #expect(
            workouts
                .filter { [
                    Equipment.bosuBall,
                    .ellipticalMachine,
                    .hammer,
                    .medicineBall,
                    .olympicBarbell,
                    .resistanceBand,
                    .roller,
                    .rope,
                    .skiergMachine,
                    .sledMachine,
                    .stabilityBall,
                    .stationaryBike,
                    .stepmillMachine,
                    .tire,
                    .trapBar,
                    .upperBodyErgometer,
                    .wheelRoller
                ].contains($0.equipment) }
                .count == 13
        )
    }
}

private func equipment(fromSourceValue sourceValue: String) -> Equipment {
    switch sourceValue {
    case "assisted": .assisted
    case "band": .band
    case "barbell": .barbell
    case "body weight": .bodyweight
    case "bodyweight": .bodyweight
    case "bosu ball": .bosuBall
    case "cable": .cable
    case "dumbbell": .dumbbell
    case "elliptical machine": .ellipticalMachine
    case "ez barbell": .ezBarbell
    case "hammer": .hammer
    case "kettlebell": .kettlebell
    case "leverage machine": .leverageMachine
    case "machine": .machine
    case "medicine ball": .medicineBall
    case "olympic barbell": .olympicBarbell
    case "resistance band": .resistanceBand
    case "roller": .roller
    case "rope": .rope
    case "skierg machine": .skiergMachine
    case "sled machine": .sledMachine
    case "smith machine": .smithMachine
    case "stability ball": .stabilityBall
    case "stationary bike": .stationaryBike
    case "stepmill machine": .stepmillMachine
    case "tire": .tire
    case "trap bar": .trapBar
    case "upper body ergometer": .upperBodyErgometer
    case "weighted": .weighted
    case "wheel roller": .wheelRoller
    default:
        preconditionFailure("Unsupported exercise equipment in fixture: \(sourceValue)")
    }
}
