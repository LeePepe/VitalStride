import Foundation
import SwiftData
import Testing

@testable import VitalModels

@Suite("WorkoutSetTree — tree queries (MY-1432)")
struct WorkoutSetTreeTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - subSetChildren

    @Test("subSetChildren returns consecutive sub-sets after a parent")
    func subSetChildrenReturnsConsecutiveSubSets() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )

        let children = WorkoutSetTree.subSetChildren(of: sets[0], in: workoutExercise)

        #expect(children.count == 2)
        #expect(children[0].persistentModelID == sets[1].persistentModelID)
        #expect(children[1].persistentModelID == sets[2].persistentModelID)
    }

    @Test("subSetChildren stops at the next main set")
    func subSetChildrenStopsAtNextMain() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85), (.dropSet, 70)]
        )

        let children = WorkoutSetTree.subSetChildren(of: sets[0], in: workoutExercise)

        #expect(children.count == 1)
        #expect(children[0].persistentModelID == sets[1].persistentModelID)
    }

    @Test("subSetChildren returns empty for a sub-set input")
    func subSetChildrenReturnsEmptyForSubSet() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )

        let children = WorkoutSetTree.subSetChildren(of: sets[1], in: workoutExercise)

        #expect(children.isEmpty)
    }

    @Test("subSetChildren returns empty for a parent with no children")
    func subSetChildrenEmptyForParentWithoutChildren() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.working, 85)]
        )

        let children = WorkoutSetTree.subSetChildren(of: sets[0], in: workoutExercise)

        #expect(children.isEmpty)
    }

    // MARK: - deletionTargets

    @Test("deletionTargets for a main set includes itself and its children")
    func deletionTargetsForMainSetIncludesChildren() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.dropSet, 58), (.working, 85)]
        )

        let targets = WorkoutSetTree.deletionTargets(for: sets[0], in: workoutExercise)

        #expect(targets.count == 3)
        #expect(targets[0].persistentModelID == sets[0].persistentModelID)
        #expect(targets[1].persistentModelID == sets[1].persistentModelID)
        #expect(targets[2].persistentModelID == sets[2].persistentModelID)
    }

    @Test("deletionTargets for a sub-set is only itself")
    func deletionTargetsForSubSetIsOnlyItself() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 85)]
        )

        let targets = WorkoutSetTree.deletionTargets(for: sets[1], in: workoutExercise)

        #expect(targets.count == 1)
        #expect(targets[0].persistentModelID == sets[1].persistentModelID)
    }

    // MARK: - Helpers

    private func makeExercise(
        context: ModelContext,
        sets: [(SetType, Double)]
    ) -> (WorkoutExercise, [ExerciseSet]) {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let exerciseSets: [ExerciseSet] = sets.enumerated().map { idx, item in
            let set = ExerciseSet(order: idx, weight: item.1, reps: 8, setType: item.0)
            context.insert(set)
            return set
        }

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: exerciseSets)
        context.insert(workoutExercise)

        let workout = Workout(
            type: .strength,
            startDate: Date(),
            source: .recorded,
            exercises: [workoutExercise]
        )
        context.insert(workout)
        try? context.save()

        return (workoutExercise, exerciseSets)
    }
}
