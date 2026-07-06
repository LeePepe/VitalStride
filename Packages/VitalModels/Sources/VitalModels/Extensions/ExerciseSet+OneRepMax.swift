import Foundation

extension ExerciseSet {
    public var estimatedOneRepMax: Double {
        weight * (1.0 + Double(reps) / 30.0)
    }

    public var isOneRepMaxCandidate: Bool {
        setType == .working && (1...12).contains(reps) && weight > 0
    }
}
