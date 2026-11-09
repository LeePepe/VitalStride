import SwiftData
import SwiftUI
import VitalModels

/// The two presentation modes for an in-progress workout.
enum WorkoutDisplayMode: String, CaseIterable, Equatable, Sendable {
    case tiled
    case focus

    static func resolveInitialMode(storedRawValue: String?, flightFocusDefault: Bool) -> WorkoutDisplayMode {
        if let storedRawValue, let stored = WorkoutDisplayMode(rawValue: storedRawValue) {
            return stored
        }
        return flightFocusDefault ? .focus : .tiled
    }
}

enum FocusStageMode: Equatable, Sendable {
    case activeSet
    case restRecovery
    case allCompleted
}

struct FocusAtmosphereTheme: Equatable, Sendable {
    let primaryTint: Color
    let secondaryTint: Color
    let badgeIdentifier: String

    static func resolve(muscleGroup: MuscleGroup?, stageMode: FocusStageMode) -> FocusAtmosphereTheme {
        if stageMode == .restRecovery {
            return FocusAtmosphereTheme(primaryTint: .mint, secondaryTint: .teal, badgeIdentifier: "rest_recovery")
        }
        switch muscleGroup {
        case .chest, .core:
            return FocusAtmosphereTheme(primaryTint: .orange, secondaryTint: .red, badgeIdentifier: "chest_push")
        case .back:
            return FocusAtmosphereTheme(primaryTint: .blue, secondaryTint: .indigo, badgeIdentifier: "back_pull")
        case .legs, .fullBody:
            return FocusAtmosphereTheme(primaryTint: .purple, secondaryTint: .pink, badgeIdentifier: "legs_compound")
        case .shoulders, .arms, nil:
            return FocusAtmosphereTheme(primaryTint: .yellow, secondaryTint: .orange, badgeIdentifier: "shoulders_arms")
        }
    }
}

struct FocusStep: Equatable {
    let exercise: WorkoutExercise
    let set: ExerciseSet
    let exerciseIndex: Int
    let setIndexInExercise: Int
    let totalSetsInExercise: Int
    let mainSetNumber: Int
    let subSetOrdinal: Int?

    static func == (lhs: FocusStep, rhs: FocusStep) -> Bool {
        lhs.exercise.persistentModelID == rhs.exercise.persistentModelID && lhs.set.persistentModelID == rhs.set.persistentModelID
    }
}

@MainActor
enum WorkoutDualModeEngine {
    static func orderedExercises(in workout: Workout) -> [WorkoutExercise] {
        (workout.exercises ?? []).sorted { $0.order < $1.order }
    }

    static func orderedSets(in exercise: WorkoutExercise) -> [ExerciseSet] {
        (exercise.sets ?? []).sorted { $0.order < $1.order }
    }

    static func focusSteps(in workout: Workout) -> [FocusStep] {
        orderedExercises(in: workout).enumerated().flatMap { exerciseIndex, exercise in
            focusSteps(for: exercise, exerciseIndex: exerciseIndex)
        }
    }

    static func focusSteps(for exercise: WorkoutExercise, in workout: Workout) -> [FocusStep] {
        let exerciseIndex = orderedExercises(in: workout).firstIndex(where: {
            $0.persistentModelID == exercise.persistentModelID
        }) ?? 0
        return focusSteps(for: exercise, exerciseIndex: exerciseIndex)
    }

    private static func focusSteps(for exercise: WorkoutExercise, exerciseIndex: Int) -> [FocusStep] {
        let sets = orderedSets(in: exercise)
        var mainNumber = -1
        var subOrdinals: [SetType: Int] = [:]
        return sets.enumerated().map { setIndex, set in
            if !set.setType.isSubSet {
                mainNumber += 1
                subOrdinals.removeAll()
            }
            let subOrdinal: Int?
            if set.setType.isSubSet {
                let next = (subOrdinals[set.setType] ?? 0) + 1
                subOrdinals[set.setType] = next
                subOrdinal = next
            } else {
                subOrdinal = nil
            }
            return FocusStep(
                exercise: exercise,
                set: set,
                exerciseIndex: exerciseIndex,
                setIndexInExercise: setIndex,
                totalSetsInExercise: sets.count,
                mainSetNumber: max(0, mainNumber),
                subSetOrdinal: subOrdinal
            )
        }
    }

    static func tactileModuleRowCounts(isUnilateral: Bool) -> [Int] {
        isUnilateral ? [2, 1] : [2]
    }

    static func syncCursor(
        selectedExerciseID: PersistentIdentifier?,
        selectedSetID: PersistentIdentifier?,
        in workout: Workout
    ) -> FocusStep? {
        let steps = focusSteps(in: workout)
        if let selectedExerciseID, let selectedSetID,
           let exact = steps.first(where: { $0.exercise.persistentModelID == selectedExerciseID && $0.set.persistentModelID == selectedSetID }) {
            return exact
        }
        if let selectedExerciseID,
           let selected = steps.first(where: { $0.exercise.persistentModelID == selectedExerciseID && !$0.set.isCompleted }) {
            return selected
        }
        return steps.first(where: { !$0.set.isCompleted }) ?? steps.last
    }

    static func stepBackward(from currentSetID: PersistentIdentifier?, in workout: Workout) -> FocusStep? {
        let steps = focusSteps(in: workout)
        guard let currentSetID, let index = steps.firstIndex(where: { $0.set.persistentModelID == currentSetID }) else { return steps.first }
        return index > 0 ? steps[index - 1] : nil
    }

    static func stepForward(from currentSetID: PersistentIdentifier?, in workout: Workout) -> FocusStep? {
        let steps = focusSteps(in: workout)
        guard let currentSetID, let index = steps.firstIndex(where: { $0.set.persistentModelID == currentSetID }) else { return steps.first }
        return index + 1 < steps.count ? steps[index + 1] : nil
    }

    static func nextIncompleteStep(after currentSetID: PersistentIdentifier?, in workout: Workout) -> FocusStep? {
        let steps = focusSteps(in: workout)
        guard let currentSetID, let index = steps.firstIndex(where: { $0.set.persistentModelID == currentSetID }) else {
            return steps.first(where: { !$0.set.isCompleted })
        }
        return steps[(index + 1)...].first(where: { !$0.set.isCompleted }) ?? steps.first(where: { !$0.set.isCompleted })
    }

    static func activeExerciseIDAfterSetCompletion(
        in currentExercise: WorkoutExercise,
        workout: Workout
    ) -> PersistentIdentifier {
        let sets = currentExercise.sets ?? []
        guard !sets.isEmpty && sets.allSatisfy(\.isCompleted) else {
            return currentExercise.persistentModelID
        }
        if let next = orderedExercises(in: workout)
            .drop(while: { $0.persistentModelID != currentExercise.persistentModelID })
            .dropFirst()
            .first(where: { ($0.sets ?? []).contains(where: { !$0.isCompleted }) }) {
            return next.persistentModelID
        }
        return currentExercise.persistentModelID
    }

    static func applyPreviousSet(_ previous: ExerciseSet, to target: ExerciseSet) {
        target.weight = previous.weight
        target.reps = previous.reps
        if target.isUnilateral {
            target.weightRight = previous.weightRight ?? previous.weight
        }
    }

    static func applyProgressionAdvice(_ advice: ProgressionAdvice, to target: ExerciseSet) {
        target.weight = advice.suggestedWeight
        target.reps = advice.suggestedReps
        if target.isUnilateral {
            target.weightRight = advice.suggestedWeight
        }
    }

    static func computeExerciseProgressionAdvice(for workoutExercise: WorkoutExercise, in workout: Workout, using context: ModelContext) -> ProgressionAdvice? {
        var previous: [ExerciseSet] = []
        var index = 0
        while let set = PreviousSetLookup.previousMainSet(currentWorkout: workout, exercise: workoutExercise.exercise, mainSetIndex: index, in: context) {
            previous.append(set)
            index += 1
        }
        return SmartProgressionAdvisor.suggest(previousMainSets: previous, userPreferredRepRange: 8...12, muscleGroup: workoutExercise.exercise?.muscleGroup)
    }

    static func insertSubSet(after parentSet: ExerciseSet, type: SetType, in workoutExercise: WorkoutExercise, using context: ModelContext) -> ExerciseSet {
        let sets = orderedSets(in: workoutExercise)
        let mainSet = owningMainSet(for: parentSet, in: sets) ?? parentSet
        let mainIndex = sets.firstIndex(where: { $0.persistentModelID == mainSet.persistentModelID }) ?? (sets.count - 1)
        var insertIndex = mainIndex + 1
        while insertIndex < sets.count, sets[insertIndex].setType.isSubSet {
            insertIndex += 1
        }
        let mainWeight = mainSet.weight
        let factor = type == .dropSet ? 0.8 : 1.1
        let rawWeight = mainWeight * factor
        let roundedWeight = rawWeight < 2.5 ? rawWeight : (rawWeight / 2.5).rounded() * 2.5
        let inserted = ExerciseSet(order: insertIndex, weight: roundedWeight, reps: mainSet.reps, setType: type, isUnilateral: mainSet.isUnilateral, weightRight: mainSet.isUnilateral ? (mainSet.weightRight ?? mainWeight) * factor : nil)
        inserted.workoutExercise = workoutExercise
        var updated = sets
        updated.insert(inserted, at: min(insertIndex, updated.count))
        for (index, set) in updated.enumerated() { set.order = index }
        workoutExercise.sets = updated
        context.insert(inserted)
        return inserted
    }

    static func focusTheme(for muscleGroup: MuscleGroup?, stageMode: FocusStageMode) -> FocusAtmosphereTheme {
        FocusAtmosphereTheme.resolve(muscleGroup: muscleGroup, stageMode: stageMode)
    }

    static func displayWeight(_ weightKg: Double, unit: WeightUnit) -> Double {
        unit == .lb ? weightKg * 2.20462 : weightKg
    }

    private static func owningMainSet(for set: ExerciseSet, in sets: [ExerciseSet]) -> ExerciseSet? {
        guard set.setType.isSubSet else { return set }
        return sets.last(where: { !$0.setType.isSubSet && $0.order < set.order })
    }
}

enum FocusSetStepper {
    enum Field { case weight, weightRight, reps }

    static func step(_ field: Field, direction: Int, unit: WeightUnit, set: ExerciseSet) {
        adjust(field, by: direction, unit: unit, set: set)
    }

    static func adjust(_ field: Field, by direction: Int, unit: WeightUnit, set: ExerciseSet) {
        let delta = field == .reps ? 1 : (unit == .kg ? 2.5 : 5.0) / (unit == .kg ? 1 : 2.20462)
        switch field {
        case .weight: set.weight = max(0, set.weight + Double(direction) * delta)
        case .weightRight: set.weightRight = max(0, (set.weightRight ?? set.weight) + Double(direction) * delta)
        case .reps: set.reps = max(0, set.reps + direction)
        }
    }
}
