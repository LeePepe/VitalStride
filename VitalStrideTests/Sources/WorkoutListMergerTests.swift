import Foundation
import HealthKitService
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

// MARK: - WorkoutListMerger Tests

@Suite("WorkoutListMerger")
@MainActor
struct WorkoutListMergerTests {
    private func makeHealthKitRecord(
        id: UUID = UUID(),
        activityType: WorkoutActivityType = .running,
        duration: TimeInterval = 1800,
        startDate: Date,
        endDate: Date? = nil,
        sourceName: String? = "Apple Watch"
    ) -> HealthWorkoutRecord {
        HealthWorkoutRecord(
            id: id,
            activityTypeRawValue: activityType.rawValue,
            duration: duration,
            totalEnergyBurned: 300,
            totalDistance: 5000,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(duration),
            sourceName: sourceName
        )
    }

    @Test("Empty inputs produce empty output")
    func emptyInputs() {
        let result = WorkoutListMerger.merge(appWorkouts: [], healthKitRecords: [])
        #expect(result.unified.isEmpty)
        #expect(result.dedupCount == 0)
    }

    @Test("App workouts only — sorted by startDate descending")
    func appWorkoutsOnly() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let older = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: Date(timeIntervalSince1970: 1_003_600)
        )
        let newer = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 2_000_000),
            endDate: Date(timeIntervalSince1970: 2_003_600)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let result = WorkoutListMerger.merge(
            appWorkouts: [older, newer],
            healthKitRecords: []
        )

        #expect(result.unified.count == 2)
        #expect(result.dedupCount == 0)
        #expect(result.unified[0].startDate > result.unified[1].startDate)
    }

    @Test("HealthKit records only — sorted by startDate descending")
    func healthKitRecordsOnly() {
        let older = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 1_000_000)
        )
        let newer = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 2_000_000)
        )

        let result = WorkoutListMerger.merge(
            appWorkouts: [],
            healthKitRecords: [older, newer]
        )

        #expect(result.unified.count == 2)
        #expect(result.dedupCount == 0)
        #expect(result.unified[0].startDate > result.unified[1].startDate)
    }

    @Test("Mixed sources — interleaved by startDate descending")
    func mixedSourcesSorted() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let appWorkout = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_500_000),
            endDate: Date(timeIntervalSince1970: 1_503_600)
        )
        context.insert(appWorkout)
        try context.save()

        let hkOlder = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 1_000_000)
        )
        let hkNewer = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 2_000_000)
        )

        let result = WorkoutListMerger.merge(
            appWorkouts: [appWorkout],
            healthKitRecords: [hkOlder, hkNewer]
        )

        #expect(result.unified.count == 3)
        #expect(result.unified[0].startDate == Date(timeIntervalSince1970: 2_000_000))
        #expect(result.unified[1].startDate == Date(timeIntervalSince1970: 1_500_000))
        #expect(result.unified[2].startDate == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("Deduplication filters HK records matching healthKitUUID")
    func deduplicationByHealthKitUUID() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let sharedUUID = UUID()
        let appWorkout = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_500_000),
            endDate: Date(timeIntervalSince1970: 1_503_600)
        )
        appWorkout.healthKitUUID = sharedUUID.uuidString
        context.insert(appWorkout)
        try context.save()

        let duplicateRecord = makeHealthKitRecord(
            id: sharedUUID,
            startDate: Date(timeIntervalSince1970: 1_500_000)
        )
        let uniqueRecord = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 2_000_000)
        )

        let result = WorkoutListMerger.merge(
            appWorkouts: [appWorkout],
            healthKitRecords: [duplicateRecord, uniqueRecord]
        )

        #expect(result.unified.count == 2)
        #expect(result.dedupCount == 1)
    }

    @Test("Multiple duplicates are all filtered")
    func multipleDeduplicates() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let uuid1 = UUID()
        let uuid2 = UUID()

        let app1 = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: Date(timeIntervalSince1970: 1_003_600)
        )
        app1.healthKitUUID = uuid1.uuidString

        let app2 = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 2_000_000),
            endDate: Date(timeIntervalSince1970: 2_003_600)
        )
        app2.healthKitUUID = uuid2.uuidString

        context.insert(app1)
        context.insert(app2)
        try context.save()

        let hk1 = makeHealthKitRecord(id: uuid1, startDate: Date(timeIntervalSince1970: 1_000_000))
        let hk2 = makeHealthKitRecord(id: uuid2, startDate: Date(timeIntervalSince1970: 2_000_000))
        let hk3 = makeHealthKitRecord(startDate: Date(timeIntervalSince1970: 3_000_000))

        let result = WorkoutListMerger.merge(
            appWorkouts: [app1, app2],
            healthKitRecords: [hk1, hk2, hk3]
        )

        #expect(result.unified.count == 3)
        #expect(result.dedupCount == 2)
    }

    @Test("App workouts without healthKitUUID don't cause dedup")
    func noHealthKitUUIDNoDedup() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let appWorkout = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_500_000),
            endDate: Date(timeIntervalSince1970: 1_503_600)
        )
        context.insert(appWorkout)
        try context.save()

        let hkRecord = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 1_500_000)
        )

        let result = WorkoutListMerger.merge(
            appWorkouts: [appWorkout],
            healthKitRecords: [hkRecord]
        )

        #expect(result.unified.count == 2)
        #expect(result.dedupCount == 0)
    }

    @Test("HealthKit empty graceful degradation — only app workouts shown")
    func healthKitEmptyGracefulDegradation() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        context.insert(workout)
        try context.save()

        let result = WorkoutListMerger.merge(
            appWorkouts: [workout],
            healthKitRecords: []
        )

        #expect(result.unified.count == 1)
        if case .app = result.unified[0] {
            // expected
        } else {
            Issue.record("Expected app workout")
        }
    }
}

// MARK: - HealthKitWorkoutRowView Formatting Tests

@Suite("HealthKitWorkoutRowView Formatting")
struct HealthKitWorkoutRowViewFormattingTests {
    @Test("Duration formats minutes only")
    func durationMinutesOnly() {
        let result = HealthKitWorkoutRowView.formattedDuration(1800)
        #expect(result.contains("30"))
    }

    @Test("Duration formats hours and minutes")
    func durationHoursAndMinutes() {
        let result = HealthKitWorkoutRowView.formattedDuration(5400)
        #expect(result.contains("1"))
        #expect(result.contains("30"))
    }

    @Test("Distance formats meters to km with one decimal")
    func distanceFormatting() {
        let result = HealthKitWorkoutRowView.formattedDistance(5432)
        #expect(result == "5.4")
    }

    @Test("Distance formats round km")
    func distanceRoundKm() {
        let result = HealthKitWorkoutRowView.formattedDistance(10000)
        #expect(result == "10.0")
    }
}
