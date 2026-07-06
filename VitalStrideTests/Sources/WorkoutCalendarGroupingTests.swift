import Foundation
import HealthKitService
import Testing
import VitalModels

@testable import VitalStride

// MARK: - WorkoutCalendarGrouping.groupByDay Tests (MY-1149 / T005)

@Suite("WorkoutCalendarGrouping.groupByDay")
@MainActor
struct WorkoutCalendarGroupingTests {
    private func makeHealthKitWorkout(
        id: UUID = UUID(),
        activityType: WorkoutActivityType = .running,
        startDate: Date,
        duration: TimeInterval = 1800
    ) -> UnifiedWorkout {
        let record = HealthWorkoutRecord(
            id: id,
            activityTypeRawValue: activityType.rawValue,
            duration: duration,
            totalEnergyBurned: 300,
            totalDistance: 5000,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            sourceName: "Apple Watch"
        )
        return UnifiedWorkout.healthKit(record)
    }

    @Test("Empty input produces empty dictionary")
    func emptyInput() {
        let result = WorkoutCalendarGrouping.groupByDay([])

        #expect(result.isEmpty)
    }

    @Test("Single workout produces single bucket keyed by startOfDay")
    func singleWorkout() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedKey = Calendar.current.startOfDay(for: start)
        let workout = makeHealthKitWorkout(startDate: start)

        let result = WorkoutCalendarGrouping.groupByDay([workout])

        #expect(result.count == 1)
        #expect(result[expectedKey]?.count == 1)
        #expect(result[expectedKey]?.first?.id == workout.id)
    }

    @Test("Multiple workouts on the same day group into one bucket preserving input order")
    func multipleWorkoutsSameDay() throws {
        // Anchor fixtures at the start of a real local day so intra-day offsets
        // stay inside that same Calendar.current day in any timezone.
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let morning = dayStart.addingTimeInterval(8 * 3600)   // 08:00 local
        let afternoon = dayStart.addingTimeInterval(13 * 3600) // 13:00 local
        let evening = dayStart.addingTimeInterval(20 * 3600)  // 20:00 local

        // Merger emits newest-first; the helper must preserve that input order.
        let newest = makeHealthKitWorkout(activityType: .running, startDate: evening)
        let middle = makeHealthKitWorkout(activityType: .cycling, startDate: afternoon)
        let oldest = makeHealthKitWorkout(activityType: .yoga, startDate: morning)

        let result = WorkoutCalendarGrouping.groupByDay([newest, middle, oldest])

        #expect(result.count == 1)
        let bucket = try #require(result[dayStart])
        #expect(bucket.count == 3)
        #expect(bucket.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test("Workouts on different days produce separate buckets keyed by startOfDay")
    func workoutsOnDifferentDays() {
        let calendar = Calendar.current
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400) // + 1 day
        let day3 = day1.addingTimeInterval(3 * 86_400) // + 3 days

        let workout1 = makeHealthKitWorkout(startDate: day1)
        let workout2 = makeHealthKitWorkout(startDate: day2)
        let workout3 = makeHealthKitWorkout(startDate: day3)

        let result = WorkoutCalendarGrouping.groupByDay([workout3, workout2, workout1])

        #expect(result.count == 3)

        let key1 = calendar.startOfDay(for: day1)
        let key2 = calendar.startOfDay(for: day2)
        let key3 = calendar.startOfDay(for: day3)

        #expect(result[key1]?.count == 1)
        #expect(result[key2]?.count == 1)
        #expect(result[key3]?.count == 1)
        #expect(result[key1]?.first?.id == workout1.id)
        #expect(result[key2]?.first?.id == workout2.id)
        #expect(result[key3]?.first?.id == workout3.id)
    }

    @Test("Workouts at day boundary bucket by startOfDay, not by absolute time")
    func dayBoundaryBucketing() {
        let calendar = Calendar.current
        // Pick an arbitrary reference day, then materialize 23:59 that day and 00:01 the next.
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        let refStart = calendar.startOfDay(for: ref)
        let lateNight = refStart.addingTimeInterval(23 * 3600 + 59 * 60)
        let nextMorning = refStart.addingTimeInterval(24 * 3600 + 60)

        let lateWorkout = makeHealthKitWorkout(startDate: lateNight)
        let nextWorkout = makeHealthKitWorkout(startDate: nextMorning)

        let result = WorkoutCalendarGrouping.groupByDay([nextWorkout, lateWorkout])

        let dayA = calendar.startOfDay(for: lateNight)
        let dayB = calendar.startOfDay(for: nextMorning)

        #expect(dayA != dayB)
        #expect(result.count == 2)
        #expect(result[dayA]?.count == 1)
        #expect(result[dayB]?.count == 1)
        #expect(result[dayA]?.first?.id == lateWorkout.id)
        #expect(result[dayB]?.first?.id == nextWorkout.id)
    }

    @Test("All bucket keys equal Calendar.current.startOfDay(for: workout.startDate)")
    func keysAreStartOfDay() {
        let calendar = Calendar.current
        let dates: [Date] = [
            Date(timeIntervalSince1970: 1_700_000_000),
            Date(timeIntervalSince1970: 1_700_100_000),
            Date(timeIntervalSince1970: 1_700_500_000),
            Date(timeIntervalSince1970: 1_701_000_000),
        ]
        let workouts = dates.map { makeHealthKitWorkout(startDate: $0) }

        let result = WorkoutCalendarGrouping.groupByDay(workouts)

        for key in result.keys {
            #expect(key == calendar.startOfDay(for: key))
        }
        for workout in workouts {
            let expectedKey = calendar.startOfDay(for: workout.startDate)
            #expect(result[expectedKey]?.contains(where: { $0.id == workout.id }) == true)
        }
    }
}
