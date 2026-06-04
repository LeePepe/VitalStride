import SwiftData
import SwiftUI

struct OverviewView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    OverviewTodaySummary()
                    OverviewRecentWorkouts()
                    OverviewTrendSection()
                }
                .padding()
            }
            .navigationTitle("概览")
        }
    }
}

private struct OverviewTodaySummary: View {
    @Query private var todayWorkouts: [Workout]

    init() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        _todayWorkouts = Query(
            filter: #Predicate<Workout> { workout in
                workout.startDate >= startOfDay && workout.endDate != nil
            },
            sort: \Workout.startDate
        )
    }

    var body: some View {
        ActivitySummaryCard(
            summary: WorkoutAggregator.computeTodaySummary(from: todayWorkouts)
        )
    }
}

private struct OverviewRecentWorkouts: View {
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var recentWorkouts: [Workout]

    var body: some View {
        RecentWorkoutsSection(workouts: Array(recentWorkouts.prefix(5)))
    }
}

private struct OverviewTrendSection: View {
    @Query private var trendWorkouts: [Workout]

    init() {
        let calendar = Calendar.current
        let rangeStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        _trendWorkouts = Query(
            filter: #Predicate<Workout> { workout in
                workout.startDate >= rangeStart && workout.endDate != nil
            },
            sort: \Workout.startDate
        )
    }

    var body: some View {
        WorkoutTrendChart(workouts: trendWorkouts)
    }
}

#Preview {
    OverviewView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
