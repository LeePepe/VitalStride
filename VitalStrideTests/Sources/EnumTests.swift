import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Enum Tests")
struct EnumTests {
    @Test("WorkoutSource has all expected cases")
    func workoutSourceCases() {
        let cases = WorkoutSource.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.recorded))
        #expect(cases.contains(.imported))
        #expect(cases.contains(.healthkit))
    }

    @Test("WorkoutSource raw values match expected strings")
    func workoutSourceRawValues() {
        #expect(WorkoutSource.recorded.rawValue == "recorded")
        #expect(WorkoutSource.imported.rawValue == "imported")
        #expect(WorkoutSource.healthkit.rawValue == "healthkit")
    }

    @Test("SetType has all expected cases")
    func setTypeCases() {
        let cases = SetType.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.working))
        #expect(cases.contains(.warmup))
        #expect(cases.contains(.dropSet))
        #expect(cases.contains(.pyramid))
    }

    @Test("SetType raw values match expected strings")
    func setTypeRawValues() {
        #expect(SetType.working.rawValue == "working")
        #expect(SetType.warmup.rawValue == "warmup")
        #expect(SetType.dropSet.rawValue == "dropSet")
        #expect(SetType.pyramid.rawValue == "pyramid")
    }

    @Test("SetType isSubSet identifies sub-set types correctly")
    func setTypeIsSubSet() {
        #expect(SetType.working.isSubSet == false)
        #expect(SetType.warmup.isSubSet == false)
        #expect(SetType.dropSet.isSubSet == true)
        #expect(SetType.pyramid.isSubSet == true)
    }

    @Test("SetType displayName is non-empty and unique across all cases")
    func setTypeDisplayNames() {
        // `SetType.displayName` is resolved via `String(localized:bundle: .module)`
        // in VitalModels, so its value depends on the host's runtime locale
        // (e.g. English on CI vs Chinese on a zh-Hans dev machine). Assert on
        // invariants that hold in every locale:
        //   1) every case has a non-empty displayName
        //   2) all four cases produce distinct values
        // The zh-Hans catalog spec strings are asserted in
        // `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSetTests.swift`,
        // which can reach `Bundle.module` directly.
        let displayNames = SetType.allCases.map(\.displayName)
        for (setType, value) in zip(SetType.allCases, displayNames) {
            #expect(!value.isEmpty, "SetType.\(setType) has empty displayName")
        }
        #expect(Set(displayNames).count == SetType.allCases.count, "SetType displayNames are not unique")
    }

    @Test("MuscleGroup has all expected cases")
    func muscleGroupCases() {
        let cases = MuscleGroup.allCases
        #expect(cases.count == 7)
        #expect(cases.contains(.chest))
        #expect(cases.contains(.back))
        #expect(cases.contains(.shoulders))
        #expect(cases.contains(.legs))
        #expect(cases.contains(.arms))
        #expect(cases.contains(.core))
        #expect(cases.contains(.fullBody))
    }

    @Test("Equipment has all expected cases")
    func equipmentCases() {
        let cases = Equipment.allCases
        let expectedRawValues: Set<String> = [
            "assisted", "band", "barbell", "bodyweight", "bosu_ball", "cable",
            "dumbbell", "elliptical_machine", "ez_barbell", "hammer", "kettlebell",
            "leverage_machine", "machine", "medicine_ball", "olympic_barbell",
            "resistance_band", "roller", "rope", "skierg_machine", "sled_machine",
            "smith_machine", "stability_ball", "stationary_bike", "stepmill_machine",
            "tire", "trap_bar", "upper_body_ergometer", "weighted", "wheel_roller",
        ]

        #expect(cases.count == 29)
        #expect(Set(cases.map(\.rawValue)) == expectedRawValues)
        #expect(cases.contains(.barbell))
        #expect(cases.contains(.dumbbell))
        #expect(cases.contains(.machine))
        #expect(cases.contains(.bodyweight))
        #expect(cases.contains(.cable))
        #expect(cases.contains(.kettlebell))
    }

    @Test("Enums are Codable")
    func enumsCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let source = WorkoutSource.recorded
        let sourceData = try encoder.encode(source)
        let decodedSource = try decoder.decode(WorkoutSource.self, from: sourceData)
        #expect(decodedSource == source)

        let setType = SetType.warmup
        let setTypeData = try encoder.encode(setType)
        let decodedSetType = try decoder.decode(SetType.self, from: setTypeData)
        #expect(decodedSetType == setType)

        let dropSet = SetType.dropSet
        let dropSetData = try encoder.encode(dropSet)
        let decodedDropSet = try decoder.decode(SetType.self, from: dropSetData)
        #expect(decodedDropSet == dropSet)

        let pyramid = SetType.pyramid
        let pyramidData = try encoder.encode(pyramid)
        let decodedPyramid = try decoder.decode(SetType.self, from: pyramidData)
        #expect(decodedPyramid == pyramid)

        let muscleGroup = MuscleGroup.chest
        let muscleData = try encoder.encode(muscleGroup)
        let decodedMuscle = try decoder.decode(MuscleGroup.self, from: muscleData)
        #expect(decodedMuscle == muscleGroup)

        for equipment in Equipment.allCases {
            let equipData = try encoder.encode(equipment)
            let decodedEquip = try decoder.decode(Equipment.self, from: equipData)
            #expect(decodedEquip == equipment)
        }
    }

    @Test("WorkoutType has all expected cases")
    func workoutTypeCases() {
        let cases = WorkoutType.allCases
        #expect(cases.count == 12)
        #expect(cases.contains(.strength))
        #expect(cases.contains(.running))
        #expect(cases.contains(.cycling))
        #expect(cases.contains(.swimming))
        #expect(cases.contains(.yoga))
        #expect(cases.contains(.hiking))
        #expect(cases.contains(.walking))
        #expect(cases.contains(.other))
    }

    @Test("WorkoutType raw values match expected strings")
    func workoutTypeRawValues() {
        #expect(WorkoutType.strength.rawValue == "strength")
        #expect(WorkoutType.running.rawValue == "running")
        #expect(WorkoutType.other.rawValue == "other")
    }
}
