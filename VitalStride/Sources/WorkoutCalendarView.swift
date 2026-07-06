import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable {
    case list
    case calendar
}

@MainActor
enum WorkoutCalendarGrouping {
    /// Group a merged, newest-first `[UnifiedWorkout]` list into per-day buckets.
    ///
    /// Keys are `Calendar.current.startOfDay(for: item.startDate)`. Within each
    /// bucket the input order is preserved (callers pass merger output that is
    /// already startDate-descending, so buckets stay newest-first too).
    static func groupByDay(
        _ workouts: [UnifiedWorkout]
    ) -> [Date: [UnifiedWorkout]] {
        var buckets: [Date: [UnifiedWorkout]] = [:]
        let calendar = Calendar.current
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            buckets[day, default: []].append(workout)
        }
        return buckets
    }
}
