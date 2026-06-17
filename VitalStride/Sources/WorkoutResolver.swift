import Foundation
import SwiftData
import VitalModels

/// Resolves a `WorkoutStartSource` into a concrete `Workout`.
///
/// For `.resume`, returns the existing workout without inserting anything.
/// For other sources, creates a new `Workout`, inserts it into the context,
/// and optionally copies exercises from a prior workout or template.
enum WorkoutResolver {
    struct Result {
        let workout: Workout
        let startTime: Date
    }

    static func resolve(
        source: WorkoutStartSource,
        startTime: Date,
        using context: ModelContext
    ) -> Result {
        switch source {
        case .resume(let existingWorkout):
            return Result(
                workout: existingWorkout,
                startTime: existingWorkout.startDate
            )

        default:
            let newWorkout = Workout(type: .strength, startDate: startTime)
            context.insert(newWorkout)

            switch source {
            case .blank:
                break
            case .fromWorkout(let sourceWorkout):
                WorkoutCopier.copyExercises(
                    from: sourceWorkout,
                    to: newWorkout,
                    using: context
                )
            case .fromTemplate(let template):
                WorkoutCopier.setupFromTemplate(
                    template,
                    into: newWorkout,
                    using: context
                )
            case .resume:
                break
            }

            return Result(workout: newWorkout, startTime: startTime)
        }
    }
}
