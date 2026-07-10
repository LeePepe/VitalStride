import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Overview Tests")
struct OverviewTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - WorkoutAggregator.computeTodaySummary

    @Test("computeTodaySummary with today's workouts")
    func todaySummaryWithWorkouts() throws {
        let context = ModelContext(container)
        let now = todayAnchor()
        let w1 = Workout(
            type: .strength,
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(-1800),
            totalCalories: 150.0
        )
        let w2 = Workout(
            type: .strength,
            startDate: now.addingTimeInterval(-1200),
            endDate: now,
            totalCalories: 100.0
        )
        context.insert(w1)
        context.insert(w2)
        try context.save()

        let summary = WorkoutAggregator.computeTodaySummary(from: [w1, w2])
        #expect(summary.workoutCount == 2)
        #expect(summary.totalDurationMinutes == 50)
        #expect(summary.totalCalories == 250)
    }

    @Test("computeTodaySummary excludes workouts without endDate")
    func todaySummaryExcludesIncomplete() throws {
        let context = ModelContext(container)
        let now = todayAnchor()
        let complete = Workout(
            type: .strength,
            startDate: now.addingTimeInterval(-1800),
            endDate: now,
            totalCalories: 200.0
        )
        let incomplete = Workout(type: .strength, startDate: now.addingTimeInterval(-600))
        context.insert(complete)
        context.insert(incomplete)
        try context.save()

        let summary = WorkoutAggregator.computeTodaySummary(from: [complete, incomplete])
        #expect(summary.workoutCount == 2)
        #expect(summary.totalDurationMinutes == 30)
        #expect(summary.totalCalories == 200)
    }

    @Test("computeTodaySummary returns zeros for empty input")
    func todaySummaryEmpty() {
        let summary = WorkoutAggregator.computeTodaySummary(from: [])
        #expect(summary.workoutCount == 0)
        #expect(summary.totalDurationMinutes == 0)
        #expect(summary.totalCalories == 0)
    }

    @Test("computeTodaySummary excludes yesterday's workouts")
    func todaySummaryExcludesYesterday() throws {
        let context = ModelContext(container)
        let yesterday = Date().addingTimeInterval(-86400)
        let workout = Workout(
            type: .strength,
            startDate: yesterday,
            endDate: yesterday.addingTimeInterval(3600),
            totalCalories: 300.0
        )
        context.insert(workout)
        try context.save()

        let summary = WorkoutAggregator.computeTodaySummary(from: [workout])
        #expect(summary.workoutCount == 0)
        #expect(summary.totalDurationMinutes == 0)
        #expect(summary.totalCalories == 0)
    }

    // MARK: - WorkoutAggregator.computeDailyTrendData

    @Test("computeDailyTrendData returns correct day count")
    func trendDataDayCount() {
        let data = WorkoutAggregator.computeDailyTrendData(from: [], dayCount: 7)
        #expect(data.count == 7)

        let data30 = WorkoutAggregator.computeDailyTrendData(from: [], dayCount: 30)
        #expect(data30.count == 30)
    }

    @Test("computeDailyTrendData aggregates minutes per day")
    func trendDataAggregation() throws {
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let w1 = Workout(
            type: .strength,
            startDate: today.addingTimeInterval(3600),
            endDate: today.addingTimeInterval(5400)
        )
        let w2 = Workout(
            type: .running,
            startDate: today.addingTimeInterval(7200),
            endDate: today.addingTimeInterval(9000)
        )
        context.insert(w1)
        context.insert(w2)
        try context.save()

        let data = WorkoutAggregator.computeDailyTrendData(from: [w1, w2], dayCount: 7)
        let todayEntry = data.first { calendar.isDate($0.date, inSameDayAs: today) }
        #expect(todayEntry?.totalMinutes == 60)
    }

    @Test("computeDailyTrendData sorted by date ascending")
    func trendDataSorted() {
        let data = WorkoutAggregator.computeDailyTrendData(from: [], dayCount: 7)
        let dates = data.map(\.date)
        #expect(dates == dates.sorted())
    }

    // MARK: - WorkoutAggregator.computeAverage

    @Test("computeAverage with data")
    func averageWithData() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let data = [
            DailyWorkoutData(date: today, totalMinutes: 30),
            DailyWorkoutData(
                date: calendar.date(byAdding: .day, value: -1, to: today)!,
                totalMinutes: 60
            ),
            DailyWorkoutData(
                date: calendar.date(byAdding: .day, value: -2, to: today)!,
                totalMinutes: 0
            ),
        ]
        let average = WorkoutAggregator.computeAverage(from: data)
        #expect(average == 30.0)
    }

    @Test("computeAverage returns zero for empty data")
    func averageEmpty() {
        let average = WorkoutAggregator.computeAverage(from: [])
        #expect(average == 0.0)
    }

    // MARK: - TodayActivitySummary

    @Test("TodayActivitySummary equality")
    func todayActivitySummaryEquality() {
        let a = TodayActivitySummary(workoutCount: 1, totalDurationMinutes: 30, totalCalories: 200)
        let b = TodayActivitySummary(workoutCount: 1, totalDurationMinutes: 30, totalCalories: 200)
        let c = TodayActivitySummary(workoutCount: 2, totalDurationMinutes: 30, totalCalories: 200)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - TrendTimeRange

    @Test("TrendTimeRange day counts")
    func trendTimeRangeDayCounts() {
        #expect(TrendTimeRange.week.dayCount == 7)
        #expect(TrendTimeRange.month.dayCount == 30)
    }

    // MARK: - DailyWorkoutData

    @Test("DailyWorkoutData initialization")
    func dailyWorkoutDataInit() {
        let date = Date()
        let data = DailyWorkoutData(date: date, totalMinutes: 45)
        #expect(data.date == date)
        #expect(data.totalMinutes == 45)
        #expect(data.id == date)
    }

    // MARK: - In-memory derivations from single 30-day query (MY-1078)

    @Test("30-day workouts derive today summary via in-memory filter")
    func thirtyDayWorkoutsDeriveTodaySummary() throws {
        let now = todayAnchor()
        let calendar = Calendar.current
        let today = Workout(
            type: .strength,
            startDate: now.addingTimeInterval(-1800),
            endDate: now,
            totalCalories: 200.0
        )
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let earlier = Workout(
            type: .running,
            startDate: twoDaysAgo,
            endDate: twoDaysAgo.addingTimeInterval(3600),
            totalCalories: 300.0
        )
        let thirtyDayWindow = [today, earlier]

        let summary = WorkoutAggregator.computeTodaySummary(from: thirtyDayWindow)
        #expect(summary.workoutCount == 1)
        #expect(summary.totalDurationMinutes == 30)
        #expect(summary.totalCalories == 200)
    }

    @Test("30-day workouts derive recent slice preserving reverse order")
    func thirtyDayWorkoutsDeriveRecentSlice() throws {
        let calendar = Calendar.current
        let now = todayAnchor()
        var workouts: [Workout] = []
        for offset in 0..<8 {
            let start = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            workouts.append(
                Workout(
                    type: .strength,
                    startDate: start,
                    endDate: start.addingTimeInterval(1800),
                    totalCalories: 100.0
                )
            )
        }

        let recentFive = Array(workouts.prefix(5))
        #expect(recentFive.count == 5)
        #expect(recentFive.first?.startDate == workouts[0].startDate)
        let dates = recentFive.map(\.startDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("30-day workouts feed trend chart with full window")
    func thirtyDayWorkoutsFeedTrend() throws {
        let calendar = Calendar.current
        let now = todayAnchor()
        let inWindow = Workout(
            type: .strength,
            startDate: now.addingTimeInterval(-3600),
            endDate: now
        )
        let dayFifteen = calendar.date(byAdding: .day, value: -15, to: now) ?? now
        let alsoInWindow = Workout(
            type: .running,
            startDate: dayFifteen,
            endDate: dayFifteen.addingTimeInterval(1800)
        )
        let trendData = WorkoutAggregator.computeDailyTrendData(
            from: [inWindow, alsoInWindow],
            dayCount: 30
        )
        #expect(trendData.count == 30)
        let totalMinutes = trendData.reduce(0) { $0 + $1.totalMinutes }
        #expect(totalMinutes == 90)
    }
}

/// Returns a stable "now" anchored inside today so subtracting a few hours
/// stays within today's date window. Fixes flake when tests run shortly
/// after midnight — see MY-1159.
private func todayAnchor(calendar: Calendar = .current) -> Date {
    let now = Date()
    let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
    return max(now, noonToday)
}
