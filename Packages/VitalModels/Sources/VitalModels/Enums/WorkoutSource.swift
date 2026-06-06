import Foundation

public enum WorkoutSource: String, Codable, CaseIterable, Sendable {
    case recorded
    case imported
    case healthkit
}
