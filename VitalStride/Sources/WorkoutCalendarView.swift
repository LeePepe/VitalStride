import DesignKit
import Foundation
import HealthKitService
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
/// T011 scope: adds day selection + a below-grid section listing every
/// workout on the selected day, each row wrapped in a `NavigationLink`
/// to `WorkoutDetailView` / `HealthKitWorkoutDetailView` per the
/// `UnifiedWorkout` case (FR-003 / SC-002). Previews (T013) and the
/// accessibility audit pass (T014) land in later tasks.
struct WorkoutCalendarView: View {
    let workouts: [UnifiedWorkout]

    @Environment(\.theme) private var theme

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

    /// Currently selected day (normalized to `startOfDay`). `nil` means no
    /// day is expanded. Only days with at least one workout are selectable
    /// (empty days ignore taps). Cleared when the visible month changes so
    /// stale selections from another month never render below the grid.
    @State private var selectedDay: Date?

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
                        .foregroundStyle(theme.neutrals.text2)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .accessibilityHidden(true)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    dayCell(for: day)
                }
            }
            .padding(.horizontal)

            if let selectedDay,
               let workoutsForDay = workoutsByDay[selectedDay],
               !workoutsForDay.isEmpty {
                selectedDaySection(day: selectedDay, workouts: workoutsForDay)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical)
    }

    @ViewBuilder
    private func dayCell(for day: Date?) -> some View {
        if let day {
            let dayNumber = calendar.component(.day, from: day)
            let workoutCount = workoutsByDay[day]?.count ?? 0
            let hasWorkout = workoutCount > 0
            let isSelected = selectedDay == day
            Button {
                guard hasWorkout else { return }
                selectedDay = (selectedDay == day) ? nil : day
            } label: {
                Text("\(dayNumber)")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        Circle()
                            .fill(dayCellBackground(hasWorkout: hasWorkout, isSelected: isSelected))
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                    )
                    .foregroundStyle(dayCellForeground(hasWorkout: hasWorkout, isSelected: isSelected))
            }
            .buttonStyle(.plain)
            .disabled(!hasWorkout)
            .accessibilityLabel(Text(dayCellAccessibilityLabel(day: day, workoutCount: workoutCount)))
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHidden(true)
        }
    }

    /// Builds the VoiceOver label for a date cell using the shipped
    /// `workout_calendar_date_a11y_format` (with-workout, plural-aware) or
    /// `workout_calendar_date_a11y_no_workout_format` (no-workout) xcstrings
    /// keys so both branches respect the user's locale (Constitution VI /
    /// Bar H).
    private func dayCellAccessibilityLabel(day: Date, workoutCount: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        let localizedDate = formatter.string(from: day)
        if workoutCount > 0 {
            return String(
                format: NSLocalizedString(
                    "workout_calendar_date_a11y_format",
                    comment: "Date-cell accessibility label; %1$@ localized date, %2$lld workout count."
                ),
                localizedDate,
                workoutCount
            )
        }
        return String(
            format: NSLocalizedString(
                "workout_calendar_date_a11y_no_workout_format",
                comment: "Date-cell accessibility label when the day has no workouts."
            ),
            localizedDate
        )
    }

    private func dayCellBackground(hasWorkout: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return theme.primary.primary
        }
        return hasWorkout ? theme.primary.primary.opacity(0.18) : Color.clear
    }

    private func dayCellForeground(hasWorkout: Bool, isSelected: Bool) -> Color {
        if isSelected {
            return theme.primary.onPrimary
        }
        return hasWorkout ? theme.primary.primary : theme.neutrals.text1
    }

    /// Section rendered below the month grid when a workout day is
    /// selected. Lists every `UnifiedWorkout` for that day (preserves
    /// input order — the merger yields startDate-descending, so the newest
    /// workout of the day shows first). Each row is a `NavigationLink`
    /// into the matching detail view for its `UnifiedWorkout` case
    /// (FR-003 / SC-002; Edge Case: multiple workouts in one day).
    @ViewBuilder
    private func selectedDaySection(day: Date, workouts: [UnifiedWorkout]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day, style: .date)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)

            ForEach(workouts) { item in
                switch item {
                case .app(let workout):
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        SelectedDayWorkoutRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                case .healthKit(let record):
                    NavigationLink {
                        HealthKitWorkoutDetailView(record: record)
                    } label: {
                        SelectedDayWorkoutRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }

    /// Shift the visible month by the given number of months. Falls back
    /// to the current anchor if the calendar cannot resolve the offset
    /// (should not happen in Gregorian but keeps the type total).
    /// Clears any currently selected day so a stale selection from the
    /// old month never renders under the new grid (T011).
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
        selectedDay = nil
    }
}

/// Compact row used inside the T011 selected-day section. Kept private
/// to `WorkoutCalendarView`'s file so it doesn't leak into other
/// screens — `WorkoutListView` continues to use its own `WorkoutRowView`
/// / `HealthKitWorkoutRowView` cells for list mode.
private struct SelectedDayWorkoutRow: View {
    @Environment(\.theme) private var theme
    let item: UnifiedWorkout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.displayIcon)
                .font(.title3)
                .foregroundStyle(theme.neutrals.text2)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.startDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)
                    if let duration = item.duration,
                       let durationText = WorkoutCalendarDurationFormatter.string(from: duration) {
                        Text(durationText)
                            .font(.caption)
                            .foregroundStyle(theme.neutrals.text2)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.neutrals.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Locale-aware duration formatter used by the T011 selected-day workout row.
///
/// MY-1221: replaces the previous "\(hours)h \(minutes)m" / "\(minutes)m"
/// hardcoded English units in `SelectedDayWorkoutRow` so the label respects
/// the user's locale (Cross-Cutting Quality Bar G / Principle VI). Returns
/// `nil` when the formatter cannot produce a string, which lets the caller
/// skip the label entirely instead of falling back to hardcoded English.
enum WorkoutCalendarDurationFormatter {
    static func string(from duration: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        let totalMinutes = Int(duration) / 60
        formatter.allowedUnits = totalMinutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: duration)
    }
}

// MARK: - Previews (T013)
//
// Two previews cover Bar I's two required states:
//   1. calendar populated with workout data (exercises month grid, month
//      navigation, day selection + detail list beneath the grid);
//   2. calendar with no workout data (exercises the empty-month rendering
//      and confirms no day is selectable).
//
// Both previews build `UnifiedWorkout` values from `HealthWorkoutRecord`
// so the preview is self-contained (no SwiftData context / no HealthKit
// access required at preview time). The populated preview seeds several
// workouts on distinct days of the current month plus two workouts on a
// single day to exercise the multi-workout-per-day case (spec 011
// Edge Case). Wrapped in `NavigationStack` so the row `NavigationLink`s
// resolve correctly under preview.

private enum WorkoutCalendarPreviewFixtures {
    @MainActor
    static func populatedWorkouts() -> [UnifiedWorkout] {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)

        func date(dayOffset: Int, hour: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) ?? monthStart
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        }

        func record(
            dayOffset: Int,
            hour: Int,
            duration: TimeInterval,
            activityRaw: UInt,
            source: String
        ) -> UnifiedWorkout {
            let start = date(dayOffset: dayOffset, hour: hour)
            let end = start.addingTimeInterval(duration)
            return .healthKit(
                HealthWorkoutRecord(
                    id: UUID(),
                    activityTypeRawValue: activityRaw,
                    duration: duration,
                    totalEnergyBurned: 320,
                    totalDistance: 5_000,
                    startDate: start,
                    endDate: end,
                    sourceName: source
                )
            )
        }

        // Newest-first ordering (matches merger output contract used by
        // `WorkoutCalendarGrouping.groupByDay`).
        var seeded: [UnifiedWorkout] = []
        seeded.append(record(dayOffset: 22, hour: 18, duration: 45 * 60, activityRaw: 37, source: "Apple Watch"))
        seeded.append(record(dayOffset: 22, hour: 8, duration: 30 * 60, activityRaw: 52, source: "Apple Watch"))
        seeded.append(record(dayOffset: 18, hour: 7, duration: 60 * 60, activityRaw: 13, source: "Apple Watch"))
        seeded.append(record(dayOffset: 12, hour: 19, duration: 40 * 60, activityRaw: 50, source: "iPhone"))
        seeded.append(record(dayOffset: 5, hour: 6, duration: 55 * 60, activityRaw: 24, source: "Apple Watch"))
        seeded.append(record(dayOffset: 1, hour: 20, duration: 25 * 60, activityRaw: 54, source: "iPhone"))
        return seeded.sorted { $0.startDate > $1.startDate }
    }
}

#Preview("With Workouts") {
    NavigationStack {
        WorkoutCalendarView(
            workouts: WorkoutCalendarPreviewFixtures.populatedWorkouts()
        )
    }
    .designThemePreview()
}

#Preview("Empty State") {
    NavigationStack {
        WorkoutCalendarView(workouts: [])
    }
    .designThemePreview()
}
