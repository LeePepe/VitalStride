import Foundation
import Testing
@testable import VitalModels

@Suite("ExerciseSet Tests")
struct ExerciseSetTests {
    @Test("isCompleted defaults to false")
    func isCompletedDefaultValue() {
        let set = ExerciseSet(weight: 60.0, reps: 10)
        #expect(set.isCompleted == false)
    }

    @Test("isCompleted can be set to true via init")
    func isCompletedViaInit() {
        let set = ExerciseSet(weight: 80.0, reps: 5, isCompleted: true)
        #expect(set.isCompleted == true)
    }

    @Test("isCompleted can be toggled")
    func isCompletedToggle() {
        let set = ExerciseSet(weight: 100.0, reps: 3)
        #expect(set.isCompleted == false)
        set.isCompleted = true
        #expect(set.isCompleted == true)
        set.isCompleted = false
        #expect(set.isCompleted == false)
    }

    @Test("SetType displayName returns correct Chinese names")
    func setTypeDisplayName() {
        #expect(SetType.working.displayName == "正式")
        #expect(SetType.warmup.displayName == "热身")
    }

    @Test("init preserves all fields")
    func initPreservesFields() {
        let set = ExerciseSet(
            order: 2,
            weight: 50.5,
            reps: 12,
            setType: .warmup,
            restDuration: 90,
            isCompleted: true
        )
        #expect(set.order == 2)
        #expect(set.weight == 50.5)
        #expect(set.reps == 12)
        #expect(set.setType == .warmup)
        #expect(set.restDuration == 90)
        #expect(set.isCompleted == true)
    }

    @Test("default values for optional and defaulted fields")
    func defaultValues() {
        let set = ExerciseSet(weight: 0, reps: 0)
        #expect(set.order == 0)
        #expect(set.weight == 0)
        #expect(set.reps == 0)
        #expect(set.setType == .working)
        #expect(set.restDuration == nil)
        #expect(set.isCompleted == false)
        #expect(set.workoutExercise == nil)
    }

    // MARK: - Codable Tests

    @Test("encode and decode roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let original = ExerciseSet(
            order: 3,
            weight: 80.5,
            reps: 8,
            setType: .warmup,
            restDuration: 120,
            isCompleted: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExerciseSet.self, from: data)
        #expect(decoded.order == 3)
        #expect(decoded.weight == 80.5)
        #expect(decoded.reps == 8)
        #expect(decoded.setType == .warmup)
        #expect(decoded.restDuration == 120)
        #expect(decoded.isCompleted == true)
    }

    @Test("decode old data without isCompleted defaults to false")
    func codableBackwardCompatibility() throws {
        let json = """
        {"order":1,"weight":60.0,"reps":10,"setType":"working"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)
        #expect(decoded.order == 1)
        #expect(decoded.weight == 60.0)
        #expect(decoded.reps == 10)
        #expect(decoded.setType == .working)
        #expect(decoded.restDuration == nil)
        #expect(decoded.isCompleted == false)
    }

    @Test("encode produces expected JSON keys")
    func codableEncodedKeys() throws {
        let set = ExerciseSet(weight: 50, reps: 5, isCompleted: true)
        let data = try JSONEncoder().encode(set)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["isCompleted"] as? Bool == true)
        #expect(json?["weight"] as? Double == 50)
        #expect(json?["reps"] as? Int == 5)
    }
}
