import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var completedWorkouts: [Workout]

    private var todaySummary: TodayActivitySummary {
        let calendar = Calendar.current
        let todayWorkouts = completedWorkouts.filter {
            calendar.isDateInToday($0.startDate)
        }
        let totalSeconds = todayWorkouts.reduce(0) { total, workout in
            guard let endDate = workout.endDate else { return total }
            return total + Int(endDate.timeIntervalSince(workout.startDate))
        }
        let totalCalories = todayWorkouts.reduce(0.0) { $0 + ($1.totalCalories ?? 0) }
        return TodayActivitySummary(
            workoutCount: todayWorkouts.count,
            totalDurationMinutes: totalSeconds / 60,
            totalCalories: Int(totalCalories)
        )
    }

    private var recentWorkouts: [Workout] {
        Array(completedWorkouts.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ActivitySummaryCard(summary: todaySummary)
                    RecentWorkoutsSection(workouts: recentWorkouts)
                    WorkoutTrendChart(workouts: completedWorkouts)
                }
                .padding()
            }
            .navigationTitle("概览")
        }
    }
}

#Preview {
    OverviewView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
