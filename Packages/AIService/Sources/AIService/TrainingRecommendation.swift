import Foundation

public struct TrainingRecommendation: Codable, Sendable, Equatable {
    public let title: String
    public let muscleGroups: [String]
    public let exercises: [String]
    public let reasoning: String

    public init(
        title: String,
        muscleGroups: [String],
        exercises: [String],
        reasoning: String
    ) {
        self.title = title
        self.muscleGroups = muscleGroups
        self.exercises = exercises
        self.reasoning = reasoning
    }
}
