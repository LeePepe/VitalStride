import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable {
    case list
    case calendar
}

/// Minimal placeholder rendered when `WorkoutListView` is in `.calendar` mode.
/// Real month-grid rendering (LazyVGrid + navigation + day selection) is added
/// in the follow-up task T009 per specs/011-workout-calendar/tasks.md.
struct WorkoutCalendarView: View {
    let unifiedWorkouts: [UnifiedWorkout]

    var body: some View {
        ContentUnavailableView(
            // swiftlint:disable:next no_hardcoded_chinese
            String(localized: "日历视图即将上线", comment: "Calendar view placeholder title"),
            systemImage: "calendar"
        )
    }
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
