import Foundation

extension WorkoutTemplate {
    /// Estimates the total duration of the workout for this template.
    ///
    /// - Parameter historicalAverage: Optional average duration in seconds from
    ///   past workouts of this template. When present and positive, it is
    ///   returned directly (more accurate than an empirical estimate).
    /// - Returns: Estimated seconds. Empty templates (no exercises or all
    ///   `targetSets == 0`) return 0. Otherwise falls back to
    ///   `totalSets * 90s + 5min` transition overhead.
    public func estimatedDuration(historicalAverage: TimeInterval?) -> TimeInterval {
        let totalSets = (exercises ?? []).reduce(0) { $0 + max(0, $1.targetSets) }
        guard totalSets > 0 else { return 0 }
        if let historicalAverage, historicalAverage > 0 {
            return historicalAverage
        }
        return TimeInterval(totalSets) * 90 + 5 * 60
    }
}
