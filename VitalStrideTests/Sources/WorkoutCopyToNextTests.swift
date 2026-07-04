import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// MY-1073 — copy-to-next branches for `ActiveExerciseSection.copyToNext`.
///
/// The helper backs the Copy key of `WorkoutNumericKeyboard`. Two branches
/// need coverage per the issue's acceptance list:
///
/// * **Overwrite**: a next set exists → its weight/weightRight/reps/setType/
///   isUnilateral are replaced by the source values.
/// * **Append**: source is the last set → a new main set is inserted at the
///   end using the same `order = count` rule as `ActiveExerciseSection.addSet`.
@Suite("Copy-to-next (MY-1073)")
struct WorkoutCopyToNextTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: overwrite branch

    @Test("Overwrite: copies weight, reps, setType, isUnilateral to existing next set")
    func overwritesNextSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 80, reps: 8, setType: .working, isUnilateral: false, weightRight: nil),
                MakeSet(weight: 0, reps: 0, setType: .working, isUnilateral: false, weightRight: nil)
            ]
        )
        let source = sets[0]
        let target = sets[1]

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        #expect(target.weight == 80)
        #expect(target.reps == 8)
        #expect(target.setType == .working)
        #expect(target.isUnilateral == false)
        #expect(target.weightRight == nil)
        // Set count is unchanged in the overwrite branch.
        #expect((workoutExercise.sets ?? []).count == 2)
    }

    @Test("Overwrite: propagates unilateral weightRight and isUnilateral flag")
    func overwritesUnilateralFields() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 40, reps: 10, setType: .working, isUnilateral: true, weightRight: 42),
                MakeSet(weight: 0, reps: 0, setType: .warmup, isUnilateral: false, weightRight: nil)
            ]
        )
        let source = sets[0]
        let target = sets[1]

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        #expect(target.isUnilateral == true)
        #expect(target.weight == 40)
        #expect(target.weightRight == 42)
        #expect(target.reps == 10)
        #expect(target.setType == .working)
    }

    @Test("Overwrite: preserves target's isCompleted flag")
    func preservesCompletedFlag() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 60, reps: 6, setType: .working, isUnilateral: false, weightRight: nil),
                MakeSet(weight: 0, reps: 0, setType: .working, isUnilateral: false, weightRight: nil)
            ]
        )
        let source = sets[0]
        let target = sets[1]
        target.isCompleted = true
        try context.save()

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        #expect(target.isCompleted == true) // untouched
        #expect(target.weight == 60)
    }

    // MARK: append branch

    @Test("Append: creates a new main set at end when no next set exists")
    func appendsWhenLast() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 100, reps: 5, setType: .working, isUnilateral: false, weightRight: nil)
            ]
        )
        let source = sets[0]

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 2)
        #expect(remaining[0].persistentModelID == source.persistentModelID)
        let newSet = remaining[1]
        #expect(newSet.order == 1)
        #expect(newSet.weight == 100)
        #expect(newSet.reps == 5)
        #expect(newSet.setType == .working)
        #expect(newSet.isUnilateral == false)
        #expect(newSet.weightRight == nil)
    }

    @Test("Append: new set inherits unilateral state and weightRight")
    func appendsUnilateralSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 30, reps: 12, setType: .working, isUnilateral: true, weightRight: 32.5)
            ]
        )
        let source = sets[0]

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        let remaining = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(remaining.count == 2)
        let appended = remaining[1]
        #expect(appended.isUnilateral == true)
        #expect(appended.weight == 30)
        #expect(appended.weightRight == 32.5)
        #expect(appended.reps == 12)
    }

    @Test("Overwrite covers a sub-set target too (matches issue spec)")
    func overwriteWorksAcrossSubSetBoundary() throws {
        // "next set" per the spec is defined as strictly the next entry
        // (main or sub). Overwriting a sub-set's fields is fine — its
        // setType is replaced by the source's.
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [
                MakeSet(weight: 80, reps: 8, setType: .working, isUnilateral: false, weightRight: nil),
                MakeSet(weight: 68, reps: 8, setType: .dropSet, isUnilateral: false, weightRight: nil),
                MakeSet(weight: 0, reps: 0, setType: .working, isUnilateral: false, weightRight: nil)
            ]
        )
        let source = sets[0]
        let subSet = sets[1]

        ActiveExerciseSection.copyToNext(from: source, in: workoutExercise, using: context)
        try context.save()

        #expect(subSet.weight == 80)
        #expect(subSet.reps == 8)
        #expect(subSet.setType == .working) // overwritten
        // Set count is unchanged (overwrite branch, not append).
        #expect((workoutExercise.sets ?? []).count == 3)
    }

    // MARK: - Helpers

    private struct MakeSet {
        let weight: Double
        let reps: Int
        let setType: SetType
        let isUnilateral: Bool
        let weightRight: Double?
    }

    private func makeExercise(
        context: ModelContext,
        sets: [MakeSet]
    ) -> (WorkoutExercise, [ExerciseSet]) {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let exerciseSets: [ExerciseSet] = sets.enumerated().map { idx, item in
            let set = ExerciseSet(
                order: idx,
                weight: item.weight,
                reps: item.reps,
                setType: item.setType,
                isUnilateral: item.isUnilateral,
                weightRight: item.weightRight
            )
            context.insert(set)
            return set
        }

        let workoutExercise = WorkoutExercise(
            order: 0,
            exercise: exercise,
            sets: exerciseSets
        )
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try? context.save()

        return (workoutExercise, exerciseSets)
    }
}
