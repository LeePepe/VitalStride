import Foundation
import SwiftData
import VitalModels

enum WorkoutCopier {
    static func copyExercises(
        from sourceWorkout: Workout,
        to targetWorkout: Workout,
        using modelContext: ModelContext
    ) {
        let sourceExercises: [WorkoutExercise]

        let sourceID = sourceWorkout.persistentModelID
        var exerciseDescriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate<WorkoutExercise> { $0.workout?.persistentModelID == sourceID },
            sortBy: [SortDescriptor(\.order)]
        )
        exerciseDescriptor.relationshipKeyPathsForPrefetching = [\.sets, \.exercise]

        do {
            sourceExercises = try modelContext.fetch(exerciseDescriptor)
        } catch {
            sourceExercises = (sourceWorkout.exercises ?? []).sorted { $0.order < $1.order }
        }

        for (index, srcExercise) in sourceExercises.enumerated() {
            let workoutExercise = WorkoutExercise(order: index, exercise: srcExercise.exercise)
            workoutExercise.workout = targetWorkout
            modelContext.insert(workoutExercise)

            let srcSets = (srcExercise.sets ?? []).sorted { $0.order < $1.order }
            if srcSets.isEmpty {
                let defaultSet = ExerciseSet(order: 0, weight: 0, reps: 0, setType: .working)
                defaultSet.workoutExercise = workoutExercise
                modelContext.insert(defaultSet)
            } else {
                for (setIndex, srcSet) in srcSets.enumerated() {
                    let newSet = ExerciseSet(
                        order: setIndex,
                        weight: srcSet.weight,
                        reps: srcSet.reps,
                        setType: srcSet.setType,
                        isUnilateral: srcSet.isUnilateral
                    )
                    newSet.workoutExercise = workoutExercise
                    modelContext.insert(newSet)
                }
            }
        }
    }
}
