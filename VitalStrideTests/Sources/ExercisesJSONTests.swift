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

@Suite("Exercises JSON")
struct ExercisesJSONTests {
    let exercises: [PresetExercise]

    init() throws {
        let url = Bundle.main.url(forResource: "exercises", withExtension: "json")!
        let data = try Data(contentsOf: url)
        exercises = try JSONDecoder().decode([PresetExercise].self, from: data)
    }

    @Test("JSON parses into valid exercise array")
    func jsonParsesSuccessfully() {
        #expect(!exercises.isEmpty)
    }

    @Test("Contains between 50 and 80 exercises")
    func totalCountInRange() {
        #expect(exercises.count >= 50, "Expected at least 50 exercises, got \(exercises.count)")
        #expect(exercises.count <= 80, "Expected at most 80 exercises, got \(exercises.count)")
    }

    @Test("All MuscleGroup enum values are covered with at least 5 exercises each")
    func allMuscleGroupsCovered() {
        let requiredGroups = ["chest", "back", "shoulders", "legs", "arms", "core", "fullBody"]
        var counts: [String: Int] = [:]
        for exercise in exercises {
            counts[exercise.muscleGroup, default: 0] += 1
        }
        for group in requiredGroups {
            let count = counts[group] ?? 0
            #expect(count >= 5, "MuscleGroup '\(group)' has only \(count) exercises, expected >= 5")
        }
    }

    @Test("All Equipment enum values are covered")
    func allEquipmentCovered() {
        let requiredEquipment = ["barbell", "dumbbell", "machine", "bodyweight", "cable"]
        let usedEquipment = Set(exercises.map(\.equipment))
        for eq in requiredEquipment {
            #expect(usedEquipment.contains(eq), "Equipment '\(eq)' not found in exercises")
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
        for exercise in exercises {
            #expect(validGroups.contains(exercise.muscleGroup), "\(exercise.nameEn) has invalid muscleGroup: \(exercise.muscleGroup)")
        }
    }

    @Test("Equipment values are valid enum values")
    func validEquipmentValues() {
        let validEquipment: Set<String> = ["barbell", "dumbbell", "machine", "bodyweight", "cable"]
        for exercise in exercises {
            #expect(validEquipment.contains(exercise.equipment), "\(exercise.nameEn) has invalid equipment: \(exercise.equipment)")
        }
    }
}
