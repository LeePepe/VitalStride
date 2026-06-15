import Foundation
import OSLog
import SwiftData
import VitalModels

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
            guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
                logger.error("exercises.json not found in bundle")
                return
            }

            let data = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([ExerciseDTO].self, from: data)

            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.isCustom == false }
            )
            let existing = try context.fetch(descriptor)
            let existingNames = Set(existing.map(\.nameEn))

            let newDTOs = dtos.filter { !existingNames.contains($0.nameEn) }
            guard !newDTOs.isEmpty else {
                logger.debug("All \(dtos.count) preset exercises already seeded")
                return
            }

            for dto in newDTOs {
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
            logger.info("Seeded \(newDTOs.count) new preset exercises (total: \(existingNames.count + newDTOs.count))")
        } catch {
            logger.error("Failed to seed exercises: \(error.localizedDescription)")
        }
    }
}
