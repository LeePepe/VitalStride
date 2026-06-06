import Foundation
import OSLog
import SwiftData

enum ExerciseSeeder {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "ExerciseSeeder")

    private struct ExerciseDTO: Decodable {
        let id: String
        let nameEn: String
        let nameZh: String
        let muscleGroup: MuscleGroup
        let equipment: Equipment
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
    }

    static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.isCustom == false }
            )
            let existingCount = try context.fetchCount(descriptor)
            guard existingCount == 0 else {
                logger.debug("Skipping seed: \(existingCount) preset exercises already exist")
                return
            }

            guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
                logger.error("exercises.json not found in bundle")
                return
            }

            let data = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([ExerciseDTO].self, from: data)

            for dto in dtos {
                let exercise = Exercise(
                    nameEn: dto.nameEn,
                    nameZh: dto.nameZh,
                    muscleGroup: dto.muscleGroup,
                    equipment: dto.equipment,
                    primaryMuscles: dto.primaryMuscles,
                    secondaryMuscles: dto.secondaryMuscles,
                    isCustom: false
                )
                context.insert(exercise)
            }

            try context.save()
            logger.info("Seeded \(dtos.count) preset exercises")
        } catch {
            logger.error("Failed to seed exercises: \(error.localizedDescription)")
        }
    }
}
