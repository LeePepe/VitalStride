import Foundation
import HealthKitService
import SwiftData
import Testing
import VitalModels
@testable import VitalStride

@Suite("Workout Logging V2")
@MainActor
struct WorkoutLoggingV2Tests {
    @Test("Heart-rate resolver is honest across connection and freshness states")
    func heartRateStates() {
        let now = Date()
        #expect(HeartRateStateResolver.resolve(connection: .notPaired, lastValue: 142, lastTimestamp: now, now: now) == .disconnected)
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: nil, lastTimestamp: nil, now: now) == .awaiting)
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: 142, lastTimestamp: now.addingTimeInterval(-2), now: now) == .value(142))
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: 142, lastTimestamp: now.addingTimeInterval(-21), now: now) == .awaiting)
    }

    @Test("Numeric input replaces selection and rejects decimals for reps")
    func numericInputRules() {
        let replaced = NumericKeypadInputHandler.handleKeyPress(.digit(8), currentText: "65", selection: 0..<2, mode: .decimal)
        #expect(replaced.text == "8")
        #expect(replaced.cursor == 1)
        let integer = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "8", selection: 1..<1, mode: .integer)
        #expect(integer.text == "8")
    }

    @Test("Set tree numbers ignore drop and pyramid children")
    func setTreeNumbering() {
        let sets = [
            ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working),
            ExerciseSet(order: 1, weight: 48, reps: 8, setType: .dropSet),
            ExerciseSet(order: 2, weight: 65, reps: 8, setType: .working),
            ExerciseSet(order: 3, weight: 55, reps: 8, setType: .pyramid)
        ]
        let contexts = ActiveExerciseSection.rowContexts(from: sets)
        #expect(contexts.map(\.mainSetNumber) == [0, 0, 1, 1])
        #expect(contexts[1].isLastSubSet)
        #expect(contexts[3].isLastSubSet)
    }

    @Test("Delete arbitration gives the single undo slot priority over rest")
    func deletionArbitration() {
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .resting) == .undo)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .resting) == .rest)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle) == .none)
    }

    @Test("History prefill creates a blank working set without history")
    func prefillHistoryCreatesBlankSet() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let exercise = Exercise(nameEn: "Bench", nameZh: "卧推", muscleGroup: .chest, equipment: .barbell)
        let workout = Workout(type: .strength, startDate: Date(), endDate: nil, exercises: [])
        let target = WorkoutExercise(order: 0, exercise: exercise, sets: [])
        target.workout = workout
        context.insert(exercise); context.insert(workout); context.insert(target)
        let sets = ActiveWorkoutView.prefillHistory(in: target, workout: workout, using: context)
        #expect(sets.count == 1)
        #expect(sets[0].weight == 0)
        #expect(sets[0].reps == 0)
        #expect(sets[0].setType == .working)
    }

    @Test("Append and copy preserve set values but not completion")
    func appendAndCopySetValues() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let source = ExerciseSet(order: 0, weight: 65, reps: 8, setType: .working, isCompleted: true, isUnilateral: true, weightRight: 60)
        let exercise = WorkoutExercise(order: 0, exercise: nil, sets: [source])
        context.insert(exercise); context.insert(source)
        let appended = ActiveExerciseSection.insertAppendedMainSet(in: exercise, using: context)
        #expect(appended.weight == 65)
        #expect(appended.reps == 8)
        ActiveExerciseSection.copyToNext(from: source, in: exercise, using: context)
        let copied = (exercise.sets ?? []).sorted { $0.order < $1.order }.last!
        #expect(copied.weight == 65)
        #expect(copied.weightRight == 60)
        #expect(copied.isCompleted == false)
    }

    @Test("Unilateral mode initializes and mirrors the right weight")
    func unilateralModeCopiesLeftWeight() {
        let first = ExerciseSet(weight: 25, reps: 10)
        let second = ExerciseSet(weight: 30, reps: 8, isUnilateral: true, weightRight: 30)
        let exercise = WorkoutExercise(order: 0, exercise: nil, sets: [first, second])
        first.workoutExercise = exercise; second.workoutExercise = exercise
        SetRow.toggleExerciseWeightMode(from: first)
        #expect(first.isUnilateral)
        #expect(first.weightRight == 25)
        SetRow.toggleExerciseWeightMode(from: first)
        #expect(!first.isUnilateral)
    }

    @Test("Cascade snapshots restore through the single undo controller")
    @MainActor
    func cascadeUndoRestoresTree() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let main = ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working)
        let drop = ExerciseSet(order: 1, weight: 48, reps: 8, setType: .dropSet)
        let survivor = ExerciseSet(order: 2, weight: 65, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, exercise: nil, sets: [main, drop, survivor])
        [main, drop, survivor].forEach { $0.workoutExercise = exercise; context.insert($0) }
        context.insert(exercise)
        let snapshots = SetDeletionUndo.snapshots(for: [main, drop], in: exercise)
        #expect(WorkoutSetManager.deleteSet(main, from: exercise, using: context))
        try context.save()
        let controller = SetDeletionUndoController()
        controller.record(snapshots: snapshots, workoutExercise: exercise, message: "deleted", announcement: "deleted")
        #expect(controller.undo(using: context))
        #expect((exercise.sets ?? []).count == 3)
    }

    @Test("Rest completion presenter buffers and dismisses")
    @MainActor
    func restPresenterLifecycle() {
        let presenter = RestCompletedPresenter()
        presenter.captureCompleted()
        #expect(presenter.isBuffered)
        presenter.markVisible()
        presenter.dismiss()
        #expect(!presenter.isBuffered)
    }

    @Test("Heart-rate stream adapter uses payload timestamps and clears on disconnect")
    @MainActor
    func heartRateStreamAdapter() {
        let timestamp = Date(timeIntervalSince1970: 123)
        let payload = LiveHeartRatePayload(bpm: 142, timestamp: timestamp, sourceName: "Watch")
        var value: Double?
        var receivedAt: Date?
        HeartRateStreamAdapter.applyLivePayload(payload, setValue: { value = $0 }, setTimestamp: { receivedAt = $0 })
        #expect(value == 142)
        #expect(receivedAt == timestamp)
        var connection = WatchConnectionState.reachable
        HeartRateStreamAdapter.applyConnectionState(.unreachable, setConnection: { connection = $0 }, setValue: { value = $0 }, setTimestamp: { receivedAt = $0 })
        #expect(connection == .unreachable)
        #expect(value == nil)
        #expect(receivedAt == nil)
    }
}
