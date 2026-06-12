import ActivityKit
import Foundation

enum RestActivityPhase: String, Codable, Hashable, Sendable {
    case resting
    case completed
}

struct RestTimerAttributes: ActivityAttributes {
    let totalDuration: TimeInterval

    struct ContentState: Codable, Hashable {
        let endDate: Date
        let totalDuration: TimeInterval
        let phase: RestActivityPhase
    }
}
