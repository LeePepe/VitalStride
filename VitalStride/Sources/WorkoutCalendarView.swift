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

/// Renders a calendar month as a 7-column `LazyVGrid` with a weekday header
/// row plus day cells; dates that have workouts are visually highlighted
/// using the T004 `WorkoutCalendarGrouping.groupByDay` result
/// (spec 011-workout-calendar FR-002 / SC-001).
///
/// T010 scope: adds previous/next month navigation controls and a month
/// title that updates as the visible month changes. Day-tap selection and
/// detail navigation (T011), previews (T013), and the accessibility audit
/// pass (T014) land in later tasks.
struct WorkoutCalendarView: View {
    let workouts: [UnifiedWorkout]

    private var calendar: Calendar { Calendar.current }

    /// Anchor date used to derive the visible month. Initialized to the
    /// month containing "now" (preserving T009 initial behavior) and
    /// mutated by the previous/next month navigation controls (T010).
    /// Normalized to the first day of its month so equality/reset stays
    /// stable across arbitrary intra-month anchors.
    @State private var monthAnchor: Date = {
        let calendar = Calendar.current
        let now = Date()
        return calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)
    }()

    private var workoutsByDay: [Date: [UnifiedWorkout]] {
        WorkoutCalendarGrouping.groupByDay(workouts)
    }

    /// Weekday labels for the 7-column header, ordered by the current
    /// locale's `firstWeekday` so the grid header matches the day-cell layout.
    private var orderedWeekdayLabels: [String] {
        // Fixed key order Sun..Sat (index 0..6, matching `Calendar.weekday`
        // where Sunday == 1). We rotate this array by `firstWeekday - 1`
        // so callers see the correct locale-driven order.
        let sundayFirst: [String] = [
            String(localized: "workout_calendar_weekday_sun", comment: "Sunday header"),
            String(localized: "workout_calendar_weekday_mon", comment: "Monday header"),
            String(localized: "workout_calendar_weekday_tue", comment: "Tuesday header"),
            String(localized: "workout_calendar_weekday_wed", comment: "Wednesday header"),
            String(localized: "workout_calendar_weekday_thu", comment: "Thursday header"),
            String(localized: "workout_calendar_weekday_fri", comment: "Friday header"),
            String(localized: "workout_calendar_weekday_sat", comment: "Saturday header")
        ]
        let offset = max(0, calendar.firstWeekday - 1) % 7
        return Array(sundayFirst[offset...]) + Array(sundayFirst[..<offset])
    }

    /// Month title (e.g. "July 2026" / "2026年7月") wrapped in the
    /// `workout_calendar_month_title_format` key so future prefix/suffix
    /// tweaks stay inside the xcstrings catalog (Constitution VI).
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        let localizedMonth = formatter.string(from: monthAnchor)
        return String(
            format: NSLocalizedString(
                "workout_calendar_month_title_format",
                comment: "Month header wrapper for the workout calendar."
            ),
            localizedMonth
        )
    }

    /// Day cells for the visible month, padded at the front with `nil`
    /// leading placeholders so the first-of-month lands under the correct
    /// weekday column. Trailing `nil` padding keeps a rectangular grid.
    private var monthCells: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor)
        else {
            return []
        }
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 0

        let leadingWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (leadingWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth) {
                cells.append(calendar.startOfDay(for: date))
            }
        }
        // Trailing padding so the grid ends on a complete row of 7.
        let trailing = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailing))
        return cells
    }

    private let gridColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    goToAdjacentMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    Text(
                        "workout_calendar_previous_month",
                        comment: "Previous-month button accessibility label."
                    )
                )

                Text(monthTitle)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    goToAdjacentMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    Text(
                        "workout_calendar_next_month",
                        comment: "Next-month button accessibility label."
                    )
                )
            }
            .padding(.horizontal)

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(orderedWeekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .accessibilityHidden(true)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    dayCell(for: day)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private func dayCell(for day: Date?) -> some View {
        if let day {
            let dayNumber = calendar.component(.day, from: day)
            let hasWorkout = workoutsByDay[day] != nil
            Text("\(dayNumber)")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Circle()
                        .fill(hasWorkout ? Color.accentColor.opacity(0.18) : Color.clear)
                        .frame(width: 36, height: 36)
                )
                .foregroundStyle(hasWorkout ? Color.accentColor : .primary)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    /// Shift the visible month by the given number of months. Falls back
    /// to the current anchor if the calendar cannot resolve the offset
    /// (should not happen in Gregorian but keeps the type total).
    private func goToAdjacentMonth(by offset: Int) {
        guard
            let shifted = calendar.date(
                byAdding: .month,
                value: offset,
                to: monthAnchor
            ),
            let normalized = calendar.dateInterval(of: .month, for: shifted)?.start
        else {
            return
        }
        monthAnchor = normalized
    }
}
