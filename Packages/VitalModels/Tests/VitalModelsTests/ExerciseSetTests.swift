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
        #expect(SetType.dropSet.displayName == "递减")
        #expect(SetType.pyramid.displayName == "递增")
    }

    @Test("SetType isSubSet identifies sub-set types")
    func setTypeIsSubSet() {
        #expect(SetType.working.isSubSet == false)
        #expect(SetType.warmup.isSubSet == false)
        #expect(SetType.dropSet.isSubSet == true)
        #expect(SetType.pyramid.isSubSet == true)
    }

    @Test("SetType rawValues for new types")
    func setTypeNewRawValues() {
        #expect(SetType.dropSet.rawValue == "dropSet")
        #expect(SetType.pyramid.rawValue == "pyramid")
    }

    @Test("SetType has four cases")
    func setTypeCaseCount() {
        #expect(SetType.allCases.count == 4)
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

    @Test("init preserves dropSet type")
    func initDropSetType() {
        let set = ExerciseSet(order: 1, weight: 40.0, reps: 10, setType: .dropSet)
        #expect(set.setType == .dropSet)
    }

    @Test("init preserves pyramid type")
    func initPyramidType() {
        let set = ExerciseSet(order: 1, weight: 70.0, reps: 8, setType: .pyramid)
        #expect(set.setType == .pyramid)
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

    @Test("encode and decode roundtrip for dropSet type")
    func codableRoundtripDropSet() throws {
        let original = ExerciseSet(order: 1, weight: 50.0, reps: 10, setType: .dropSet)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)
        #expect(decoded.setType == .dropSet)
        #expect(decoded.weight == 50.0)
    }

    @Test("encode and decode roundtrip for pyramid type")
    func codableRoundtripPyramid() throws {
        let original = ExerciseSet(order: 1, weight: 70.0, reps: 8, setType: .pyramid)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)
        #expect(decoded.setType == .pyramid)
        #expect(decoded.weight == 70.0)
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

    @Test("decode dropSet from JSON string")
    func codableDecodeDropSet() throws {
        let json = """
        {"order":2,"weight":50.0,"reps":10,"setType":"dropSet","isCompleted":false}
        """
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(decoded.setType == .dropSet)
    }

    @Test("decode pyramid from JSON string")
    func codableDecodePyramid() throws {
        let json = """
        {"order":3,"weight":70.0,"reps":8,"setType":"pyramid","isCompleted":true}
        """
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(decoded.setType == .pyramid)
        #expect(decoded.isCompleted == true)
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

    @Test("encode and decode roundtrip preserves isUnilateral true")
    func codableRoundtripUnilateral() throws {
        let original = ExerciseSet(
            order: 1,
            weight: 25.0,
            reps: 10,
            setType: .working,
            isUnilateral: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)
        #expect(decoded.isUnilateral == true)
        #expect(decoded.weight == 25.0)
        #expect(decoded.reps == 10)
    }

    @Test("decode legacy JSON without isUnilateral defaults to false")
    func codableLegacyWithoutUnilateral() throws {
        let json = """
        {"order":0,"weight":80.0,"reps":8,"setType":"working"}
        """
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(decoded.isUnilateral == false)
    }

    // MARK: - weightRight Tests

    @Test("weightRight defaults to nil")
    func weightRightDefaultValue() {
        let set = ExerciseSet(weight: 60.0, reps: 10)
        #expect(set.weightRight == nil)
    }

    @Test("init preserves weightRight value")
    func initPreservesWeightRight() {
        let set = ExerciseSet(
            order: 1,
            weight: 25.0,
            reps: 10,
            setType: .working,
            isUnilateral: true,
            weightRight: 22.5
        )
        #expect(set.weight == 25.0)
        #expect(set.weightRight == 22.5)
        #expect(set.isUnilateral == true)
    }

    @Test("encode and decode roundtrip preserves weightRight")
    func codableRoundtripWeightRight() throws {
        let original = ExerciseSet(
            order: 1,
            weight: 25.0,
            reps: 10,
            setType: .working,
            isUnilateral: true,
            weightRight: 22.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: data)
        #expect(decoded.weight == 25.0)
        #expect(decoded.weightRight == 22.5)
        #expect(decoded.isUnilateral == true)
    }

    @Test("encode omits weightRight when nil")
    func codableEncodesNilWeightRight() throws {
        let set = ExerciseSet(weight: 50.0, reps: 8)
        let data = try JSONEncoder().encode(set)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["weightRight"] == nil)
    }

    @Test("decode legacy JSON without weightRight defaults to nil")
    func codableLegacyWithoutWeightRight() throws {
        let json = """
        {"order":0,"weight":80.0,"reps":8,"setType":"working","isUnilateral":true}
        """
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(decoded.weightRight == nil)
        #expect(decoded.isUnilateral == true)
        #expect(decoded.weight == 80.0)
    }

    @Test("decode JSON with weightRight present")
    func codableDecodeWithWeightRight() throws {
        // swiftlint:disable line_length
        let json = """
        {"order":1,"weight":25.0,"reps":10,"setType":"working","isUnilateral":true,"weightRight":22.5,"isCompleted":false}
        """
        // swiftlint:enable line_length
        let decoded = try JSONDecoder().decode(ExerciseSet.self, from: Data(json.utf8))
        #expect(decoded.weight == 25.0)
        #expect(decoded.weightRight == 22.5)
    }

    // MARK: - MY-876 — toggling isUnilateral must not clear stored values

    @Test("toggling isUnilateral off preserves weight, weightRight, and reps")
    func toggleUnilateralOffPreservesValues() {
        let set = ExerciseSet(
            weight: 25.0,
            reps: 10,
            isUnilateral: true,
            weightRight: 22.5
        )
        set.isUnilateral = false
        #expect(set.weight == 25.0)
        #expect(set.weightRight == 22.5)
        #expect(set.reps == 10)
    }

    @Test("toggling isUnilateral on preserves weight and reps")
    func toggleUnilateralOnPreservesValues() {
        let set = ExerciseSet(weight: 60.0, reps: 8)
        #expect(set.isUnilateral == false)
        #expect(set.weightRight == nil)
        set.isUnilateral = true
        #expect(set.weight == 60.0)
        #expect(set.reps == 8)
        // weightRight stays nil until the user fills it in
        #expect(set.weightRight == nil)
    }

    @Test("multiple isUnilateral toggles do not corrupt stored values")
    func toggleUnilateralRoundTripPreservesValues() {
        let set = ExerciseSet(
            weight: 40.0,
            reps: 12,
            isUnilateral: true,
            weightRight: 37.5
        )
        set.isUnilateral = false
        set.isUnilateral = true
        set.isUnilateral = false
        #expect(set.weight == 40.0)
        #expect(set.weightRight == 37.5)
        #expect(set.reps == 12)
    }
}
