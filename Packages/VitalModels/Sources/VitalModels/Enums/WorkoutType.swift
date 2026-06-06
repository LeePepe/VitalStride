import Foundation

public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case strength
    case running
    case cycling
    case swimming
    case yoga
    case hiking
    case walking
    case rowing
    case elliptical
    case coreTraining
    case flexibility
    case other
}
