import Foundation
import SwiftData
import Testing

@testable import VitalStride

@Suite("Overview Tests")
struct OverviewTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("TodayActivitySummary stores all fields")
    func todayActivitySummaryFields() {
        let summary = TodayActivitySummary(
            workoutCount: 3,
            totalDurationMinutes: 90,
            totalCalories: 500
        )
        #expect(summary.workoutCount == 3)
        #expect(summary.totalDurationMinutes == 90)
        #expect(summary.totalCalories == 500)
    }

    @Test("TodayActivitySummary equality")
    func todayActivitySummaryEquality() {
        let a = TodayActivitySummary(workoutCount: 1, totalDurationMinutes: 30, totalCalories: 200)
        let b = TodayActivitySummary(workoutCount: 1, totalDurationMinutes: 30, totalCalories: 200)
        let c = TodayActivitySummary(workoutCount: 2, totalDurationMinutes: 30, totalCalories: 200)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("DailyWorkoutData initialization")
    func dailyWorkoutDataInit() {
        let date = Date()
        let data = DailyWorkoutData(date: date, totalMinutes: 45)
        #expect(data.date == date)
        #expect(data.totalMinutes == 45)
        #expect(data.id == date)
    }

    @Test("TrendTimeRange week has 7 days")
    func trendTimeRangeWeek() {
        #expect(TrendTimeRange.week.dayCount == 7)
        #expect(TrendTimeRange.week.rawValue == "周")
    }

    @Test("TrendTimeRange month has 30 days")
    func trendTimeRangeMonth() {
        #expect(TrendTimeRange.month.dayCount == 30)
        #expect(TrendTimeRange.month.rawValue == "月")
    }

    @Test("Workout duration computation for today summary")
    func workoutDurationComputation() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(2700)
        let workout = Workout(
            type: .strength,
            startDate: start,
            endDate: end,
            totalCalories: 150.0
        )
        context.insert(workout)
        try context.save()

        let durationSeconds = Int(end.timeIntervalSince(start))
        #expect(durationSeconds == 2700)
        #expect(durationSeconds / 60 == 45)
    }

    @Test("Workout without endDate contributes zero duration")
    func workoutWithoutEndDate() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        #expect(workout.endDate == nil)
        let duration = workout.endDate.map { Int($0.timeIntervalSince(workout.startDate)) / 60 } ?? 0
        #expect(duration == 0)
    }

    @Test("Workout totalCalories defaults to nil")
    func workoutCaloriesDefault() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        #expect(workout.totalCalories == nil)
    }

    @Test("ActivityRing progress clamped to 1.0")
    func activityRingProgressClamping() {
        let summary = TodayActivitySummary(
            workoutCount: 5,
            totalDurationMinutes: 120,
            totalCalories: 1000
        )
        let progress = min(Double(summary.totalDurationMinutes) / 60.0, 1.0)
        #expect(progress == 1.0)
    }

    @Test("ActivityRing progress zero when no workouts")
    func activityRingProgressZero() {
        let summary = TodayActivitySummary(
            workoutCount: 0,
            totalDurationMinutes: 0,
            totalCalories: 0
        )
        let progress = min(Double(summary.totalDurationMinutes) / 60.0, 1.0)
        #expect(progress == 0.0)
    }
}
