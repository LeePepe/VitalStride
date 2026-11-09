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
        guard let copied = (exercise.sets ?? []).max(by: { $0.order < $1.order }) else {
            #expect(Bool(false))
            return
        }
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

    @Test("Dual mode resolution prefers a valid stored value and flight fallback")
    func dualModeResolution() {
        #expect(WorkoutDisplayMode.resolveInitialMode(storedRawValue: "focus", flightFocusDefault: false) == .focus)
        #expect(WorkoutDisplayMode.resolveInitialMode(storedRawValue: "invalid", flightFocusDefault: true) == .focus)
        #expect(WorkoutDisplayMode.resolveInitialMode(storedRawValue: nil, flightFocusDefault: false) == .tiled)
    }

    @Test("Focus steppers use unit-aware weight increments and clamp values")
    func focusStepperRules() {
        let set = ExerciseSet(weight: 0, reps: 0, isUnilateral: true, weightRight: 0)
        FocusSetStepper.step(.weight, direction: 1, unit: .kg, set: set)
        FocusSetStepper.step(.weightRight, direction: 1, unit: .lb, set: set)
        FocusSetStepper.step(.reps, direction: 1, unit: .kg, set: set)
        #expect(set.weight == 2.5)
        #expect(set.weightRight == 5 / 2.20462)
        #expect(set.reps == 1)
        FocusSetStepper.step(.weight, direction: -1, unit: .kg, set: set)
        #expect(set.weight == 0)
    }

    @Test("Focus atmosphere reserves mint and teal for recovery")
    func focusAtmosphereThemes() {
        #expect(FocusAtmosphereTheme.resolve(muscleGroup: .chest, stageMode: .activeSet).badgeIdentifier == "chest_push")
        #expect(FocusAtmosphereTheme.resolve(muscleGroup: .chest, stageMode: .restRecovery).badgeIdentifier == "rest_recovery")
        #expect(FocusAtmosphereTheme.resolve(muscleGroup: .legs, stageMode: .activeSet).badgeIdentifier == "legs_compound")
    }

    @Test("Focus sequence orders main and child sets")
    func focusSequenceOrdersSubsets() {
        let main = ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working)
        let drop = ExerciseSet(order: 1, weight: 48, reps: 8, setType: .dropSet)
        let next = ExerciseSet(order: 2, weight: 65, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, sets: [main, drop, next])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [exercise])
        exercise.workout = workout
        let steps = WorkoutDualModeEngine.focusSteps(in: workout)
        #expect(steps.map(\.set.persistentModelID) == [main, drop, next].map(\.persistentModelID))
        #expect(steps[0].mainSetNumber == 0)
        #expect(steps[1].subSetOrdinal == 1)
        #expect(steps[2].mainSetNumber == 1)
    }

    @Test("Previous and progression actions fill incomplete sets without completing them")
    func previousAndProgressionBackfill() {
        let previous = ExerciseSet(weight: 60, reps: 10, isUnilateral: true, weightRight: 55)
        let target = ExerciseSet(weight: 0, reps: 0, isUnilateral: true)
        WorkoutDualModeEngine.applyPreviousSet(previous, to: target)
        #expect(target.weight == 60)
        #expect(target.weightRight == 55)
        #expect(target.reps == 10)
        #expect(!target.isCompleted)
        WorkoutDualModeEngine.applyProgressionAdvice(.increaseWeight(weight: 65, reps: 8, reason: "test"), to: target)
        #expect(target.weight == 65)
        #expect(target.weightRight == 65)
        #expect(target.reps == 8)
        #expect(!target.isCompleted)
    }

    @Test("Inserted drop set is rounded and becomes the next incomplete step")
    func insertDropSetAndNextIncomplete() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let main = ExerciseSet(order: 0, weight: 62.5, reps: 8, setType: .working, isCompleted: true)
        let next = ExerciseSet(order: 1, weight: 70, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, sets: [main, next])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [exercise])
        exercise.workout = workout
        [main, next].forEach { $0.workoutExercise = exercise; context.insert($0) }
        context.insert(exercise)
        context.insert(workout)
        let drop = WorkoutDualModeEngine.insertSubSet(after: main, type: .dropSet, in: exercise, using: context)
        #expect(drop.weight == 50)
        #expect(drop.order == 1)
        let nextStep = WorkoutDualModeEngine.nextIncompleteStep(after: main.persistentModelID, in: workout)
        #expect(nextStep?.set.persistentModelID == drop.persistentModelID)
    }

    @Test("Cursor synchronization preserves the selected step across mode switches")
    func syncCursorAcrossModes() {
        let first = ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working, isCompleted: true)
        let second = ExerciseSet(order: 1, weight: 65, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, sets: [first, second])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [exercise])
        exercise.workout = workout
        let cursor = WorkoutDualModeEngine.syncCursor(selectedExerciseID: exercise.persistentModelID, selectedSetID: second.persistentModelID, in: workout)
        #expect(cursor?.set.persistentModelID == second.persistentModelID)
        #expect(WorkoutDisplayMode.resolveInitialMode(storedRawValue: "focus", flightFocusDefault: false) == .focus)
        #expect(WorkoutDisplayMode.resolveInitialMode(storedRawValue: "tiled", flightFocusDefault: true) == .tiled)
    }

    @Test("Completing a focus set advances to the next incomplete set")
    func focusCompletionAdvancesToNextSet() {
        let first = ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working, isCompleted: true)
        let second = ExerciseSet(order: 1, weight: 62.5, reps: 8, setType: .working)
        let exercise = WorkoutExercise(order: 0, sets: [first, second])
        let workout = Workout(type: .strength, startDate: Date(), exercises: [exercise])
        exercise.workout = workout
        #expect(WorkoutDualModeEngine.nextIncompleteStep(after: first.persistentModelID, in: workout)?.set.persistentModelID == second.persistentModelID)
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

    @Test("Focus progress rail scopes steps strictly to the current exercise")
    func focusProgressRailScopesToCurrentExercise() {
        let exercises = (0..<4).map { exerciseIndex in
            let sets = (0..<4).map { setIndex in
                ExerciseSet(order: setIndex, weight: Double(40 + exerciseIndex * 10), reps: 10, setType: .working)
            }
            return WorkoutExercise(order: exerciseIndex, sets: sets)
        }
        let workout = Workout(type: .strength, startDate: Date(), exercises: exercises)
        for exercise in exercises {
            exercise.workout = workout
        }

        #expect(WorkoutDualModeEngine.focusSteps(in: workout).count == 16)

        let secondExercise = exercises[1]
        let railSteps = WorkoutDualModeEngine.focusSteps(for: secondExercise, in: workout)
        #expect(railSteps.count == 4)
        #expect(railSteps.allSatisfy { $0.exercise.persistentModelID == secondExercise.persistentModelID })
        #expect(railSteps.map(\.exerciseIndex) == [1, 1, 1, 1])
        #expect(railSteps.map(\.mainSetNumber) == [0, 1, 2, 3])
    }

    @Test("Focus tactile module rows follow 2+1 for unilateral and 2 for bilateral")
    func focusTactileModuleRowLayout() {
        #expect(WorkoutDualModeEngine.tactileModuleRowCounts(isUnilateral: true) == [2, 1])
        #expect(WorkoutDualModeEngine.tactileModuleRowCounts(isUnilateral: false) == [2])
    }
}
