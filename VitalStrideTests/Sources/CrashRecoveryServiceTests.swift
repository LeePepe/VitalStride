import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Crash recovery — orphan detection + partitioning")
struct CrashRecoveryServiceTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Helpers

    private func insertWorkout(
        in context: ModelContext,
        startDate: Date,
        endDate: Date? = nil,
        source: WorkoutSource = .recorded,
        exerciseCount: Int = 0,
        setsPerExercise: Int = 0
    ) throws -> Workout {
        let workout = Workout(
            type: .strength,
            startDate: startDate,
            endDate: endDate,
            source: source
        )
        context.insert(workout)

        for exerciseIndex in 0..<exerciseCount {
            let exercise = Exercise(
                nameEn: "Exercise \(exerciseIndex)",
                nameZh: "动作 \(exerciseIndex)",
                muscleGroup: .legs,
                equipment: .barbell
            )
            context.insert(exercise)

            let workoutExercise = WorkoutExercise(order: exerciseIndex, exercise: exercise)
            workoutExercise.workout = workout
            context.insert(workoutExercise)

            for setIndex in 0..<setsPerExercise {
                let exerciseSet = ExerciseSet(
                    order: setIndex,
                    weight: 50,
                    reps: 8,
                    setType: .working
                )
                exerciseSet.workoutExercise = workoutExercise
                context.insert(exerciseSet)
            }
        }
        try context.save()
        return workout
    }

    // MARK: - Detection

    @Test("findOrphans returns workouts with nil endDate and source == .recorded")
    func findsOrphans() throws {
        let context = ModelContext(container)
        let orphan = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )
        _ = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-7000)
        )

        let orphans = CrashRecoveryService.findOrphans(in: context)
        #expect(orphans.count == 1)
        #expect(orphans[0].persistentModelID == orphan.persistentModelID)
    }

    @Test("findOrphans excludes HealthKit-imported workouts even with nil endDate")
    func excludesHealthKitImports() throws {
        let context = ModelContext(container)
        _ = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600),
            source: .healthkit
        )
        _ = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200),
            source: .imported
        )

        let orphans = CrashRecoveryService.findOrphans(in: context)
        #expect(orphans.isEmpty, "Only recorded workouts can be orphans from a crash")
    }

    @Test("findOrphans returns empty list when none exist")
    func returnsEmptyWhenNoOrphans() throws {
        let context = ModelContext(container)
        _ = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-3000)
        )

        let orphans = CrashRecoveryService.findOrphans(in: context)
        #expect(orphans.isEmpty)
    }

    @Test("findOrphans returns recent orphan first")
    func returnsRecentFirst() throws {
        let context = ModelContext(container)
        let older = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200)
        )
        let newer = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )

        let orphans = CrashRecoveryService.findOrphans(in: context)
        #expect(orphans.count == 2)
        #expect(orphans[0].persistentModelID == newer.persistentModelID)
        #expect(orphans[1].persistentModelID == older.persistentModelID)
    }

    // MARK: - Partition

    @Test("partition picks the most-recent workout for resume and shunts the rest")
    func partitionPicksRecent() throws {
        let context = ModelContext(container)
        let older = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200)
        )
        let newer = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )
        let oldest = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-10800)
        )

        let partition = CrashRecoveryService.partition([older, newer, oldest])
        #expect(partition.resumable?.persistentModelID == newer.persistentModelID)
        #expect(partition.autoFinish.count == 2)
        #expect(partition.autoFinish.contains { $0.persistentModelID == older.persistentModelID })
        #expect(partition.autoFinish.contains { $0.persistentModelID == oldest.persistentModelID })
    }

    @Test("partition with empty input returns no resumable and no auto-finish list")
    func partitionEmpty() {
        let partition = CrashRecoveryService.partition([])
        #expect(partition.resumable == nil)
        #expect(partition.autoFinish.isEmpty)
    }

    @Test("partition with a single workout returns it as resumable")
    func partitionSingle() throws {
        let context = ModelContext(container)
        let only = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-1800)
        )

        let partition = CrashRecoveryService.partition([only])
        #expect(partition.resumable?.persistentModelID == only.persistentModelID)
        #expect(partition.autoFinish.isEmpty)
    }

    // MARK: - Auto-finish

    @Test("autoFinishOrphans sets endDate on every workout passed in")
    func autoFinishSetsEndDates() throws {
        let context = ModelContext(container)
        let workout1 = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200)
        )
        let workout2 = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )
        let timestamp = Date(timeIntervalSince1970: 1_900_000_000)

        CrashRecoveryService.autoFinishOrphans([workout1, workout2], at: timestamp)
        try context.save()

        #expect(workout1.endDate == timestamp)
        #expect(workout2.endDate == timestamp)
        #expect(workout1.isInProgress == false)
        #expect(workout2.isInProgress == false)
    }

    @Test("autoFinishOrphans makes the workouts appear in the history query")
    func autoFinishedWorkoutsAppearInHistory() throws {
        let context = ModelContext(container)
        let orphan = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )

        let beforeFilter = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil }
        )
        #expect(try context.fetchCount(beforeFilter) == 0)

        CrashRecoveryService.autoFinishOrphans([orphan])
        try context.save()

        let afterFilter = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil }
        )
        let visible = try context.fetch(afterFilter)
        #expect(visible.count == 1)
        #expect(visible[0].persistentModelID == orphan.persistentModelID)
    }

    @Test("autoFinishOrphans on empty list is a no-op")
    func autoFinishEmptyList() throws {
        let context = ModelContext(container)
        let untouched = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-3600)
        )

        CrashRecoveryService.autoFinishOrphans([])
        try context.save()

        #expect(untouched.endDate == nil)
    }

    // MARK: - Summary

    @Test("summary reports exercise and set counts and the start date")
    func summaryReportsCounts() throws {
        let context = ModelContext(container)
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = try insertWorkout(
            in: context,
            startDate: startDate,
            exerciseCount: 3,
            setsPerExercise: 4
        )

        let summary = CrashRecoveryService.summary(for: workout)
        #expect(summary.startDate == startDate)
        #expect(summary.exerciseCount == 3)
        #expect(summary.setCount == 12)
        #expect(summary.isEmpty == false)
    }

    @Test("summary marks empty workouts (no exercises) as empty")
    func summaryEmptyWorkout() throws {
        let context = ModelContext(container)
        let workout = try insertWorkout(
            in: context,
            startDate: Date()
        )

        let summary = CrashRecoveryService.summary(for: workout)
        #expect(summary.exerciseCount == 0)
        #expect(summary.setCount == 0)
        #expect(summary.isEmpty == true)
    }

}

@Suite("Crash recovery — end-to-end orchestration")
struct CrashRecoveryEndToEndTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    private func insertWorkout(
        in context: ModelContext,
        startDate: Date,
        endDate: Date? = nil,
        source: WorkoutSource = .recorded,
        exerciseCount: Int = 0,
        setsPerExercise: Int = 0
    ) throws -> Workout {
        let workout = Workout(
            type: .strength,
            startDate: startDate,
            endDate: endDate,
            source: source
        )
        context.insert(workout)

        for exerciseIndex in 0..<exerciseCount {
            let exercise = Exercise(
                nameEn: "Exercise \(exerciseIndex)",
                nameZh: "动作 \(exerciseIndex)",
                muscleGroup: .legs,
                equipment: .barbell
            )
            context.insert(exercise)

            let workoutExercise = WorkoutExercise(order: exerciseIndex, exercise: exercise)
            workoutExercise.workout = workout
            context.insert(workoutExercise)

            for setIndex in 0..<setsPerExercise {
                let exerciseSet = ExerciseSet(
                    order: setIndex,
                    weight: 50,
                    reps: 8,
                    setType: .working
                )
                exerciseSet.workoutExercise = workoutExercise
                context.insert(exerciseSet)
            }
        }
        try context.save()
        return workout
    }

    @Test("End-to-end: multiple orphans get resumed (1) + auto-finished (rest)")
    func endToEndOrchestration() throws {
        let context = ModelContext(container)
        let mostRecent = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-1800),
            exerciseCount: 1,
            setsPerExercise: 2
        )
        let middle = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-7200),
            exerciseCount: 2,
            setsPerExercise: 3
        )
        let oldest = try insertWorkout(
            in: context,
            startDate: Date().addingTimeInterval(-10800)
        )

        let orphans = CrashRecoveryService.findOrphans(in: context)
        let partition = CrashRecoveryService.partition(orphans)

        #expect(partition.resumable?.persistentModelID == mostRecent.persistentModelID)
        #expect(partition.autoFinish.count == 2)

        CrashRecoveryService.autoFinishOrphans(partition.autoFinish)
        try context.save()

        // The resumable one should still be in-progress, the others finished.
        #expect(mostRecent.isInProgress == true)
        #expect(middle.isInProgress == false)
        #expect(oldest.isInProgress == false)

        // Subsequent query should find only the still-in-progress one.
        let remainingOrphans = CrashRecoveryService.findOrphans(in: context)
        #expect(remainingOrphans.count == 1)
        #expect(remainingOrphans[0].persistentModelID == mostRecent.persistentModelID)
    }
}
