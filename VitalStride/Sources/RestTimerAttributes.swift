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

extension RestTimerAttributes.ContentState {
    /// Returns `true` when the widget should render the completed lock screen
    /// instead of the resting timer. Covers three failure modes that would
    /// otherwise produce an invalid `ClosedRange<Date>` (lowerBound > upperBound)
    /// and trap in `_assertionFailure`:
    ///   1. Phase is already `.completed`.
    ///   2. `endDate` is at or before `referenceDate` (timer expired).
    ///   3. `totalDuration <= 0` (invalid duration).
    func isEffectivelyCompleted(referenceDate: Date = .now) -> Bool {
        phase == .completed || endDate <= referenceDate || totalDuration <= 0
    }

    /// Safe `ClosedRange<Date>` for `Text(timerInterval:)` showing the remaining
    /// time. Returns `nil` when the timer is expired or otherwise invalid,
    /// signalling the caller to render the completed view instead.
    func remainingInterval(referenceDate: Date = .now) -> ClosedRange<Date>? {
        guard !isEffectivelyCompleted(referenceDate: referenceDate) else {
            return nil
        }
        // Invariant from isEffectivelyCompleted: referenceDate < endDate.
        return referenceDate...endDate
    }

    /// Safe `ClosedRange<Date>` for `ProgressView(timerInterval:)` showing the
    /// full rest window. Returns `nil` when the range would be invalid.
    func progressInterval(referenceDate: Date = .now) -> ClosedRange<Date>? {
        guard !isEffectivelyCompleted(referenceDate: referenceDate) else {
            return nil
        }
        let startDate = endDate.addingTimeInterval(-totalDuration)
        // Defence-in-depth: even after the completeness guard, refuse to
        // construct a range whose bounds are inverted.
        guard startDate <= endDate else { return nil }
        return startDate...endDate
    }
}
