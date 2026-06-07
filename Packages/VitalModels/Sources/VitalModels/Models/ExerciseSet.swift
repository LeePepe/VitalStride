import Foundation
import SwiftData

@Model
public final class ExerciseSet {
    public var order: Int = 0
    public var weight: Double = 0.0
    public var reps: Int = 0
    public var setType: SetType = SetType.working
    public var restDuration: TimeInterval?
    public var isCompleted: Bool = false
    public var isUnilateral: Bool = false
    public var workoutExercise: WorkoutExercise?

    public init(
        order: Int = 0,
        weight: Double,
        reps: Int,
        setType: SetType = .working,
        restDuration: TimeInterval? = nil,
        isCompleted: Bool = false,
        isUnilateral: Bool = false
    ) {
        self.order = order
        self.weight = weight
        self.reps = reps
        self.setType = setType
        self.restDuration = restDuration
        self.isCompleted = isCompleted
        self.isUnilateral = isUnilateral
    }
}

extension ExerciseSet: Codable {
    enum CodingKeys: String, CodingKey {
        case order, weight, reps, setType, restDuration, isCompleted, isUnilateral
    }

    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let order = try container.decode(Int.self, forKey: .order)
        let weight = try container.decode(Double.self, forKey: .weight)
        let reps = try container.decode(Int.self, forKey: .reps)
        let setType = try container.decode(SetType.self, forKey: .setType)
        let restDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .restDuration)
        let isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        let isUnilateral = try container.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        self.init(order: order, weight: weight, reps: reps, setType: setType, restDuration: restDuration, isCompleted: isCompleted, isUnilateral: isUnilateral)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order, forKey: .order)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
        try container.encode(setType, forKey: .setType)
        try container.encodeIfPresent(restDuration, forKey: .restDuration)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(isUnilateral, forKey: .isUnilateral)
    }
}
