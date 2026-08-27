import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Subset row parity (MY-1484)")
struct SubSetRowParityTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Sub-set rows keep the parent main-set numbering contract")
    func subsetRowsShareParentMainSetNumbering() throws {
        let sets = makeSets([
            (80, .working),
            (68, .dropSet),
            (58, .dropSet),
            (90, .working)
        ])

        let contexts = ActiveExerciseSection.rowContexts(from: sets)

        #expect(contexts.map(\.mainSetNumber) == [0, 1, 1, 1])
        #expect(contexts.map(\.isLastSubSet) == [false, false, true, false])
    }

    @Test("Sub-set deletion remains immediate by policy while preserving the shared row contract")
    func subsetDeletionStaysImmediate() throws {
        let context = ModelContext(container)
        let (workoutExercise, sets) = makeExercise(
            context: context,
            sets: [(.working, 80), (.dropSet, 68), (.working, 90)]
        )

        #expect(SetDeletionPolicy.intent(for: sets[1], in: workoutExercise) == .immediate)
    }

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

    private func makeSets(_ items: [(Double, SetType)]) -> [ExerciseSet] {
        let context = ModelContext(container)
        return items.enumerated().map { index, item in
            let set = ExerciseSet(
                order: index,
                weight: item.0,
                reps: 8,
                setType: item.1,
                isUnilateral: false,
                weightRight: nil
            )
            context.insert(set)
            return set
        }
    }
}
