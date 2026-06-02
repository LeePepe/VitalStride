import Foundation
import SwiftData
import Testing

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
        #expect(cases.count == 2)
        #expect(cases.contains(.working))
        #expect(cases.contains(.warmup))
    }

    @Test("SetType raw values match expected strings")
    func setTypeRawValues() {
        #expect(SetType.working.rawValue == "working")
        #expect(SetType.warmup.rawValue == "warmup")
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
        #expect(cases.count == 5)
        #expect(cases.contains(.barbell))
        #expect(cases.contains(.dumbbell))
        #expect(cases.contains(.machine))
        #expect(cases.contains(.bodyweight))
        #expect(cases.contains(.cable))
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

        let muscleGroup = MuscleGroup.chest
        let muscleData = try encoder.encode(muscleGroup)
        let decodedMuscle = try decoder.decode(MuscleGroup.self, from: muscleData)
        #expect(decodedMuscle == muscleGroup)

        let equipment = Equipment.barbell
        let equipData = try encoder.encode(equipment)
        let decodedEquip = try decoder.decode(Equipment.self, from: equipData)
        #expect(decodedEquip == equipment)
    }

    @Test("WorkoutType has all expected cases")
    func workoutTypeCases() {
        let cases = WorkoutType.allCases
        #expect(cases.count == 1)
        #expect(cases.contains(.strength))
    }

    @Test("WorkoutType raw value matches expected string")
    func workoutTypeRawValue() {
        #expect(WorkoutType.strength.rawValue == "strength")
    }
}
