import Foundation
import Testing

struct PresetExercise: Decodable {
    let id: String
    let nameEn: String
    let nameZh: String
    let muscleGroup: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
}

/// Envelope shape introduced in MY-850 (PR #97) — `{version, exercises: [...]}`.
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

    @Test("JSON parses into valid exercise array")
    func jsonParsesSuccessfully() {
        #expect(!exercises.isEmpty)
    }

    @Test("Envelope has non-empty version string")
    func versionPresent() {
        #expect(!version.isEmpty, "Envelope version should be non-empty (MY-850 envelope)")
    }

    @Test("Contains between 250 and 350 exercises")
    func totalCountInRange() {
        #expect(exercises.count >= 250, "Expected at least 250 exercises, got \(exercises.count)")
        #expect(exercises.count <= 350, "Expected at most 350 exercises, got \(exercises.count)")
    }

    @Test("All MuscleGroup enum values are covered with at least 30 exercises each")
    func allMuscleGroupsCovered() {
        let requiredGroups = ["chest", "back", "shoulders", "legs", "arms", "core", "fullBody"]
        var counts: [String: Int] = [:]
        for exercise in exercises {
            counts[exercise.muscleGroup, default: 0] += 1
        }
        for group in requiredGroups {
            let count = counts[group] ?? 0
            #expect(count >= 30, "MuscleGroup '\(group)' has only \(count) exercises, expected >= 30")
        }
    }

    @Test("All Equipment enum values are covered with at least 20 exercises each")
    func allEquipmentCovered() {
        let requiredEquipment = ["barbell", "dumbbell", "machine", "bodyweight", "cable", "kettlebell"]
        var counts: [String: Int] = [:]
        for exercise in exercises {
            counts[exercise.equipment, default: 0] += 1
        }
        for equipment in requiredEquipment {
            let count = counts[equipment] ?? 0
            #expect(count >= 20, "Equipment '\(equipment)' has only \(count) exercises, expected >= 20")
        }
    }

    @Test("All exercises have non-empty primaryMuscles and secondaryMuscles")
    func musclesNonEmpty() {
        for exercise in exercises {
            #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.nameEn) has empty primaryMuscles")
            #expect(!exercise.secondaryMuscles.isEmpty, "\(exercise.nameEn) has empty secondaryMuscles")
        }
    }

    @Test("All exercise IDs are unique")
    func uniqueIds() {
        let ids = exercises.map(\.id)
        #expect(ids.count == Set(ids).count, "Duplicate exercise IDs found")
    }

    @Test("All exercises have non-empty names in both languages")
    func namesNonEmpty() {
        for exercise in exercises {
            #expect(!exercise.nameEn.isEmpty, "Exercise \(exercise.id) has empty nameEn")
            #expect(!exercise.nameZh.isEmpty, "Exercise \(exercise.id) has empty nameZh")
        }
    }

    @Test("MuscleGroup values are valid enum values")
    func validMuscleGroupValues() {
        let validGroups: Set<String> = ["chest", "back", "shoulders", "legs", "arms", "core", "fullBody"]
        for exercise in exercises where !validGroups.contains(exercise.muscleGroup) {
            Issue.record("\(exercise.nameEn) has invalid muscleGroup: \(exercise.muscleGroup)")
        }
    }

    @Test("Equipment values are valid enum values")
    func validEquipmentValues() {
        let validEquipment: Set<String> = ["barbell", "dumbbell", "machine", "bodyweight", "cable", "kettlebell"]
        for exercise in exercises where !validEquipment.contains(exercise.equipment) {
            Issue.record("\(exercise.nameEn) has invalid equipment: \(exercise.equipment)")
        }
    }
}
