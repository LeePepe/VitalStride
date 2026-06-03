import Foundation

enum WorkoutSource: String, Codable, CaseIterable {
    case recorded
    case imported
    case healthkit
}
