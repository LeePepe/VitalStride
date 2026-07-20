// swiftlint:disable file_length type_body_length
import HealthKitService
import XCTest

@testable import VitalStrideWatch_Watch_App

// MARK: - WatchWorkoutDisplayStateTests
//
// Focused unit tests for the MY-1290 display-state projection.
// Verifies:
//   * `.initial` snapshot shape (spec §7 "Watch fallback" — never blank).
//   * `pickNextSet(from:)` picks the first not-yet-completed set, honours
//     snapshot index ordering, returns nil for freeform / plan-complete
//     inputs, and flags `isLastSetOfWorkout` when the workout is on its
//     final set.
//   * `with(snapshot:)` maps snapshot progress/elapsed/current exercise/
//     next set fields while preserving unrelated fields (config / hr /
//     avg / peak / connection / saving).
//   * `with(config:)` / `with(hr:)` / `with(connection:)` / `with(saving:)`
//     replace only their named slice.
//   * `withAvgPeak(...)` respects fallback semantics when a nil override
//     is passed.
final class WatchWorkoutDisplayStateTests: XCTestCase {
    // MARK: Fixtures

    private var setAlpha: WorkoutStateSnapshot.PlannedSet!
    private var setBeta: WorkoutStateSnapshot.PlannedSet!
    private var setGamma: WorkoutStateSnapshot.PlannedSet!
    private var snapshot: WorkoutStateSnapshot!

    override func setUp() {
        super.setUp()
        setAlpha = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 0,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: true
        )
        setBeta = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 1,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: false
        )
        setGamma = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 2,
            targetReps: 8,
            targetWeightKg: 60,
            isCompleted: false
        )
        snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Back Squat",
            sets: [setAlpha, setBeta, setGamma],
            elapsedSeconds: 42,
            progress: WorkoutStateSnapshot.Progress(
                completedSetCount: 1,
                totalSetCount: 3
            ),
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    // MARK: .initial fallback

    func test_initial_isSpecSevenFallback_neverBlank() {
        // Spec §7 "Watch fallback": stale/absent config → default
        // (fullInfo + all modules on). Never blank.
        let initial = WatchWorkoutDisplayState.initial
        XCTAssertEqual(initial.config.preset, .fullInfo)
        XCTAssertEqual(initial.config.enabledModules, Set(WatchScreenConfig.Module.allCases))
        XCTAssertEqual(initial.hr, .notConnected)
        XCTAssertNil(initial.elapsedSeconds)
        XCTAssertNil(initial.progress)
        XCTAssertNil(initial.currentExerciseName)
        XCTAssertNil(initial.nextSet)
        XCTAssertNil(initial.averageBPM)
        XCTAssertNil(initial.peakBPM)
        XCTAssertEqual(initial.connection, .unsupported)
        XCTAssertEqual(initial.saving, .idle)
    }

    // MARK: pickNextSet

    func test_pickNextSet_returnsFirstIncomplete_byIndexOrder() {
        // setAlpha completed → next is setBeta (index 1 of 3).
        let picked = WatchWorkoutDisplayState.pickNextSet(from: snapshot)
        XCTAssertEqual(picked?.id, setBeta.id)
        XCTAssertEqual(picked?.index, 2)
        XCTAssertEqual(picked?.total, 3)
        XCTAssertEqual(picked?.exerciseName, "Back Squat")
        XCTAssertEqual(picked?.targetReps, 8)
        XCTAssertEqual(picked?.targetWeightKg, 60)
        XCTAssertFalse(picked?.isLastSetOfWorkout ?? true)
    }

    func test_pickNextSet_returnsNil_forFreeformSnapshot() {
        // Freeform = no sets.
        let freeform = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [],
            elapsedSeconds: 10,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 0, totalSetCount: 0),
            updatedAt: Date()
        )
        XCTAssertNil(WatchWorkoutDisplayState.pickNextSet(from: freeform))
    }

    func test_pickNextSet_returnsNil_whenPlanFullyCompleted() {
        let completedSet = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 0,
            targetReps: 8,
            targetWeightKg: nil,
            isCompleted: true
        )
        let done = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Deadlift",
            sets: [completedSet],
            elapsedSeconds: 300,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 1, totalSetCount: 1),
            updatedAt: Date()
        )
        XCTAssertNil(WatchWorkoutDisplayState.pickNextSet(from: done))
    }

    func test_pickNextSet_returnsNil_whenExerciseNameMissing() {
        // Guard: `currentExerciseName == nil` ⇒ nil (spec §11.2 —
        // watch does not fabricate names).
        let named = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: nil,
            sets: [setBeta, setGamma],
            elapsedSeconds: 10,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 0, totalSetCount: 2),
            updatedAt: Date()
        )
        XCTAssertNil(WatchWorkoutDisplayState.pickNextSet(from: named))
    }

    func test_pickNextSet_sortsUnorderedSetsByIndex() {
        // Even if the transport delivered sets out of order, `pickNextSet`
        // sorts by `index` before searching.
        let s1 = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 3,
            targetReps: 6,
            targetWeightKg: nil,
            isCompleted: false
        )
        let s0 = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 1,
            targetReps: 6,
            targetWeightKg: nil,
            isCompleted: false
        )
        let unordered = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Push Press",
            sets: [s1, s0],
            elapsedSeconds: 5,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 0, totalSetCount: 2),
            updatedAt: Date()
        )
        let picked = WatchWorkoutDisplayState.pickNextSet(from: unordered)
        XCTAssertEqual(picked?.id, s0.id, "lower `index` should sort first")
        // With 2 sets total, s0's position after sort = 1.
        XCTAssertEqual(picked?.index, 1)
        XCTAssertEqual(picked?.total, 2)
    }

    func test_pickNextSet_flagsLastSetOfWorkout_whenPlanIsAtFinalRep() {
        // Two-set plan, first completed; picking set #2 = last of workout.
        let s0 = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 0,
            targetReps: nil,
            targetWeightKg: nil,
            isCompleted: true
        )
        let s1 = WorkoutStateSnapshot.PlannedSet(
            id: UUID(),
            index: 1,
            targetReps: nil,
            targetWeightKg: nil,
            isCompleted: false
        )
        let almostDone = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Row",
            sets: [s0, s1],
            elapsedSeconds: 100,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 1, totalSetCount: 2),
            updatedAt: Date()
        )
        let picked = WatchWorkoutDisplayState.pickNextSet(from: almostDone)
        XCTAssertEqual(picked?.id, s1.id)
        XCTAssertTrue(picked?.isLastSetOfWorkout ?? false)
    }

    // MARK: with(snapshot:)

    func test_withSnapshot_projectsFieldsAndPreservesOthers() {
        // Priming state with non-default fields for HR / avg / connection.
        let seeded = WatchWorkoutDisplayState.initial
            .with(hr: .connected(bpm: 132, zone: 3))
            .with(connection: .reachable)
            .with(saving: .saving)
            .withAvgPeak(bpm: 130, runningMean: 125, peak: 145)
        let projected = seeded.with(snapshot: snapshot)

        // Snapshot-derived slices.
        XCTAssertEqual(projected.elapsedSeconds, 42)
        XCTAssertEqual(projected.progress?.completedSetCount, 1)
        XCTAssertEqual(projected.progress?.totalSetCount, 3)
        XCTAssertEqual(projected.currentExerciseName, "Back Squat")
        XCTAssertEqual(projected.nextSet?.id, setBeta.id)

        // Preserved slices.
        XCTAssertEqual(projected.hr, .connected(bpm: 132, zone: 3))
        XCTAssertEqual(projected.connection, .reachable)
        XCTAssertEqual(projected.saving, .saving)
        XCTAssertEqual(projected.averageBPM, 125)
        XCTAssertEqual(projected.peakBPM, 145)
        XCTAssertEqual(projected.config, WatchScreenConfig.defaultConfig())
    }

    func test_withSnapshot_clampsNegativeElapsedToZero() {
        // Defensive: transport shouldn't send negative elapsed, but if it
        // does the projection must clamp so UI never renders "-0:03".
        let weird = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [],
            elapsedSeconds: -30,
            progress: WorkoutStateSnapshot.Progress(completedSetCount: 0, totalSetCount: 0),
            updatedAt: Date()
        )
        let projected = WatchWorkoutDisplayState.initial.with(snapshot: weird)
        XCTAssertEqual(projected.elapsedSeconds, 0)
    }

    // MARK: with(config:) / with(hr:) / with(connection:) / with(saving:)

    func test_with_replacesConfigAndPreservesRest() {
        let seeded = WatchWorkoutDisplayState.initial
            .with(snapshot: snapshot)
            .with(hr: .connected(bpm: 120, zone: 2))
        let newConfig = WatchScreenConfig(
            preset: .hrFocus,
            enabledModules: [.heartRate, .primaryAction, .clock],
            updatedAt: Date()
        )
        let after = seeded.with(config: newConfig)

        XCTAssertEqual(after.config, newConfig)
        XCTAssertEqual(after.hr, .connected(bpm: 120, zone: 2))
        XCTAssertEqual(after.elapsedSeconds, 42)
        XCTAssertEqual(after.nextSet?.id, setBeta.id)
    }

    func test_with_replacesHRAndPreservesRest() {
        let seeded = WatchWorkoutDisplayState.initial.with(snapshot: snapshot)
        let after = seeded.with(hr: .connectedNoData)
        XCTAssertEqual(after.hr, .connectedNoData)
        // Snapshot slice unchanged.
        XCTAssertEqual(after.elapsedSeconds, 42)
        XCTAssertEqual(after.progress, seeded.progress)
        XCTAssertEqual(after.nextSet, seeded.nextSet)
    }

    func test_with_replacesConnectionAndPreservesRest() {
        let seeded = WatchWorkoutDisplayState.initial
            .with(snapshot: snapshot)
            .with(hr: .connectedNoData)
        let after = seeded.with(connection: .reachable)
        XCTAssertEqual(after.connection, .reachable)
        // HR / snapshot slices unchanged.
        XCTAssertEqual(after.hr, .connectedNoData)
        XCTAssertEqual(after.elapsedSeconds, 42)
    }

    func test_with_replacesSavingAndPreservesRest() {
        let seeded = WatchWorkoutDisplayState.initial.with(snapshot: snapshot)
        let after = seeded.with(saving: .failed(reason: "test"))
        XCTAssertEqual(after.saving, .failed(reason: "test"))
        XCTAssertEqual(after.elapsedSeconds, 42)
    }

    // MARK: withAvgPeak fallback semantics

    func test_withAvgPeak_nilOverrideKeepsExistingValue() {
        let seeded = WatchWorkoutDisplayState.initial
            .withAvgPeak(bpm: 100, runningMean: 100, peak: 100)
        // Pass nil for runningMean / peak → existing values kept.
        let after = seeded.withAvgPeak(bpm: 110, runningMean: nil, peak: nil)
        XCTAssertEqual(after.averageBPM, 100)
        XCTAssertEqual(after.peakBPM, 100)
    }

    func test_withAvgPeak_overridesReplace() {
        let seeded = WatchWorkoutDisplayState.initial
            .withAvgPeak(bpm: 100, runningMean: 100, peak: 100)
        let after = seeded.withAvgPeak(bpm: 130, runningMean: 115, peak: 135)
        XCTAssertEqual(after.averageBPM, 115)
        XCTAssertEqual(after.peakBPM, 135)
    }
}
