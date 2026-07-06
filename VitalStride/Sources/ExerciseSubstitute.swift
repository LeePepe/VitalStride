import Foundation
import VitalModels

struct SubstituteRequest: Sendable, Equatable {
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
}

struct SubstituteSuggestion: Sendable, Codable, Equatable {
    let exerciseId: String
    let reason: String
}
