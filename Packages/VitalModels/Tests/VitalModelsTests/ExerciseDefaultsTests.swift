import Foundation
import Testing
@testable import VitalModels

@Suite("Exercise defaultWeight / defaultReps")
struct ExerciseDefaultsTests {

    // MARK: - init defaults

    @Test("init defaults: reps = 5/10/15, weights = nil")
    func initDefaults() {
        let exercise = Exercise(
            nameEn: "Push Up",
            nameZh: "俯卧撑",
            muscleGroup: .chest,
            equipment: .bodyweight
        )

        #expect(exercise.defaultRepsLow == 5)
        #expect(exercise.defaultRepsMid == 10)
        #expect(exercise.defaultRepsHigh == 15)
        #expect(exercise.defaultWeightLow == nil)
        #expect(exercise.defaultWeightMid == nil)
        #expect(exercise.defaultWeightHigh == nil)
        #expect(exercise.mediaKey == nil)
    }

    @Test("init accepts mediaKey")
    func initWithMediaKey() {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            mediaKey: "bench-press-001"
        )

        #expect(exercise.mediaKey == "bench-press-001")
    }

    @Test("init accepts custom weight and reps triples")
    func initCustomValues() {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell,
            defaultWeightLow: 80,
            defaultWeightMid: 60,
            defaultWeightHigh: 40,
            defaultRepsLow: 4,
            defaultRepsMid: 8,
            defaultRepsHigh: 20
        )

        #expect(exercise.defaultWeightLow == 80)
        #expect(exercise.defaultWeightMid == 60)
        #expect(exercise.defaultWeightHigh == 40)
        #expect(exercise.defaultRepsLow == 4)
        #expect(exercise.defaultRepsMid == 8)
        #expect(exercise.defaultRepsHigh == 20)
    }

    // MARK: - Decodable DTO (mirror of ExerciseSeeder.ExerciseDTO)

    private struct DecodableFixture: Decodable {
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
    }

    @Test("Decodable JSON with defaultWeight fields present")
    func decodesWithDefaultWeights() throws {
        let json = Data("""
        {
          "id": "abc",
          "nameEn": "Bench Press",
          "nameZh": "卧推",
          "muscleGroup": "chest",
          "equipment": "barbell",
          "primaryMuscles": ["pectoralis"],
          "secondaryMuscles": ["triceps"],
          "defaultWeightLow": 80.0,
          "defaultWeightMid": 60.0,
          "defaultWeightHigh": 40.0
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(DecodableFixture.self, from: json)
        #expect(decoded.defaultWeightLow == 80.0)
        #expect(decoded.defaultWeightMid == 60.0)
        #expect(decoded.defaultWeightHigh == 40.0)
    }

    @Test("Decodable JSON with defaultWeight explicitly null")
    func decodesWithNullDefaultWeights() throws {
        let json = Data("""
        {
          "id": "abc",
          "nameEn": "Plank",
          "nameZh": "平板支撑",
          "muscleGroup": "core",
          "equipment": "bodyweight",
          "primaryMuscles": ["rectus abdominis"],
          "secondaryMuscles": [],
          "defaultWeightLow": null,
          "defaultWeightMid": null,
          "defaultWeightHigh": null
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(DecodableFixture.self, from: json)
        #expect(decoded.defaultWeightLow == nil)
        #expect(decoded.defaultWeightMid == nil)
        #expect(decoded.defaultWeightHigh == nil)
    }

    @Test("Decodable JSON with defaultWeight fields absent still decodes")
    func decodesWithMissingDefaultWeights() throws {
        let json = Data("""
        {
          "id": "abc",
          "nameEn": "Plank",
          "nameZh": "平板支撑",
          "muscleGroup": "core",
          "equipment": "bodyweight",
          "primaryMuscles": ["rectus abdominis"],
          "secondaryMuscles": []
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(DecodableFixture.self, from: json)
        #expect(decoded.defaultWeightLow == nil)
        #expect(decoded.defaultWeightMid == nil)
        #expect(decoded.defaultWeightHigh == nil)
    }
}
