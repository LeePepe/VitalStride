import Foundation

enum WorkoutAggregator {
    static func computeTodaySummary(from workouts: [Workout]) -> TodayActivitySummary {
        let calendar = Calendar.current
        let todayWorkouts = workouts.filter { calendar.isDateInToday($0.startDate) }
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

    static func computeDailyTrendData(from workouts: [Workout], dayCount: Int) -> [DailyWorkoutData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var dailyMap: [Date: Int] = [:]
        for offset in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                dailyMap[date] = 0
            }
        }

        let rangeStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        for workout in workouts {
            let workoutDay = calendar.startOfDay(for: workout.startDate)
            guard workoutDay >= rangeStart, workoutDay <= today else { continue }
            let minutes: Int
            if let endDate = workout.endDate {
                minutes = max(1, Int(endDate.timeIntervalSince(workout.startDate)) / 60)
            } else {
                minutes = 0
            }
            dailyMap[workoutDay, default: 0] += minutes
        }

        return dailyMap
            .map { DailyWorkoutData(date: $0.key, totalMinutes: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func computeAverage(from data: [DailyWorkoutData]) -> Double {
        guard !data.isEmpty else { return 0 }
        let total = data.reduce(0) { $0 + $1.totalMinutes }
        return Double(total) / Double(data.count)
    }
}
