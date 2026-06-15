import Foundation
import HealthKitService
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

// MARK: - WorkoutActivityType Display Tests

@Suite("WorkoutActivityType Display")
struct WorkoutActivityTypeDisplayTests {
    @Test("All activity types have non-empty localizedName")
    func allLocalizedNamesNonEmpty() {
        for type in WorkoutActivityType.allCases {
            #expect(!type.localizedName.isEmpty, "localizedName is empty for \(type)")
        }
    }

    @Test("All activity types have non-empty systemImage")
    func allSystemImagesNonEmpty() {
        for type in WorkoutActivityType.allCases {
            #expect(!type.systemImage.isEmpty, "systemImage is empty for \(type)")
        }
    }

    @Test("Known activity types have expected localizedName values")
    func knownLocalizedNames() {
        #expect(WorkoutActivityType.running.localizedName == String(localized: "跑步", comment: "Running"))
        #expect(WorkoutActivityType.cycling.localizedName == String(localized: "骑行", comment: "Cycling"))
        #expect(WorkoutActivityType.yoga.localizedName == String(localized: "瑜伽", comment: "Yoga"))
        #expect(WorkoutActivityType.other.localizedName == String(localized: "其他运动", comment: "Other workout"))
    }

    @Test("Known activity types have expected systemImage values")
    func knownSystemImages() {
        #expect(WorkoutActivityType.running.systemImage == "figure.run")
        #expect(WorkoutActivityType.cycling.systemImage == "bicycle")
        #expect(WorkoutActivityType.swimming.systemImage == "figure.pool.swim")
        #expect(WorkoutActivityType.yoga.systemImage == "figure.yoga")
        #expect(WorkoutActivityType.other.systemImage == "figure.mixed.cardio")
    }
}

// MARK: - UnifiedWorkout Tests

@Suite("UnifiedWorkout")
@MainActor
struct UnifiedWorkoutTests {
    @Test("HealthKit workout provides correct startDate")
    func healthKitStartDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 1800,
            totalEnergyBurned: 300,
            totalDistance: 5000,
            startDate: date,
            endDate: date.addingTimeInterval(1800),
            sourceName: "Apple Watch"
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.startDate == date)
    }

    @Test("HealthKit workout provides correct endDate")
    func healthKitEndDate() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.cycling.rawValue,
            duration: 3600,
            totalEnergyBurned: 500,
            totalDistance: 20000,
            startDate: start,
            endDate: end,
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.endDate == end)
    }

    @Test("HealthKit workout displayTitle uses activityType localizedName")
    func healthKitDisplayTitle() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.displayTitle == WorkoutActivityType.running.localizedName)
    }

    @Test("HealthKit workout displayIcon uses activityType systemImage")
    func healthKitDisplayIcon() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.yoga.rawValue,
            duration: 3600,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.displayIcon == "figure.yoga")
    }

    @Test("HealthKit workout duration returns record duration")
    func healthKitDuration() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.swimming.rawValue,
            duration: 2700,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(2700),
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.duration == 2700)
    }

    @Test("HealthKit workout source returns sourceName")
    func healthKitSource() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: "Apple Watch"
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.source == "Apple Watch")
    }

    @Test("HealthKit workout source falls back when sourceName is nil")
    func healthKitSourceFallback() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.source == String(localized: "HealthKit", comment: "Default source name for HealthKit workouts"))
    }

    @Test("HealthKit workout id has hk prefix")
    func healthKitIdPrefix() {
        let uuid = UUID()
        let record = HealthWorkoutRecord(
            id: uuid,
            activityTypeRawValue: WorkoutActivityType.running.rawValue,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: nil
        )
        let unified = UnifiedWorkout.healthKit(record)

        #expect(unified.id.hasPrefix("hk-"))
        #expect(unified.id.contains(uuid.uuidString))
    }

    @Test("App workout provides correct startDate")
    func appWorkoutStartDate() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(type: .strength, startDate: date)
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.startDate == date)
    }

    @Test("App workout endDate is nil when not finished")
    func appWorkoutEndDateNil() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.endDate == nil)
    }

    @Test("App workout duration computed from dates")
    func appWorkoutDuration() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let workout = Workout(type: .strength, startDate: start, endDate: end)
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.duration == 3600)
    }

    @Test("App workout duration is nil when no endDate")
    func appWorkoutDurationNil() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.duration == nil)
    }

    @Test("App workout displayIcon is dumbbell")
    func appWorkoutDisplayIcon() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.displayIcon == "dumbbell")
    }

    @Test("App workout source is localized app label")
    func appWorkoutSource() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.source == String(localized: "本应用", comment: "Workout source label for workouts recorded in this app"))
    }

    @Test("App workout displayTitle shows exercise names")
    func appWorkoutDisplayTitleWithExercises() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let exercise1 = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let exercise2 = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise1)
        context.insert(exercise2)

        let workoutExercise1 = WorkoutExercise(order: 0, exercise: exercise1)
        let workoutExercise2 = WorkoutExercise(order: 1, exercise: exercise2)
        let workout = Workout(
            type: .strength,
            startDate: Date(),
            exercises: [workoutExercise1, workoutExercise2]
        )
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)
        let title = unified.displayTitle

        #expect(title.contains(exercise1.localizedName))
        #expect(title.contains(exercise2.localizedName))
    }

    @Test("App workout displayTitle falls back for empty exercises")
    func appWorkoutDisplayTitleEmpty() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.displayTitle == String(localized: "力量训练", comment: "Strength training default title"))
    }

    @Test("App workout id has app prefix")
    func appWorkoutIdPrefix() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        try context.save()

        let unified = UnifiedWorkout.app(workout)

        #expect(unified.id.hasPrefix("app-"))
    }
}
