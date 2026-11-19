import Foundation
import SwiftData

@Model
public final class Workout {
    public var type: WorkoutType = WorkoutType.strength
    public var startDate: Date = Date()
    public var endDate: Date?
    public var totalCalories: Double?
    public var source: WorkoutSource = WorkoutSource.recorded
    public var healthKitUUID: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise]?

    public init(
        type: WorkoutType,
        startDate: Date,
        endDate: Date? = nil,
        totalCalories: Double? = nil,
        source: WorkoutSource = .recorded,
        healthKitUUID: String? = nil,
        exercises: [WorkoutExercise] = []
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.totalCalories = totalCalories
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.exercises = exercises
    }
}

// MARK: - Lifecycle

extension Workout {
    public var isInProgress: Bool {
        endDate == nil && source == .recorded
    }

    public func finish(at date: Date = Date()) {
        for exercise in (exercises ?? []) {
            for set in (exercise.sets ?? []) where !set.isCompleted {
                set.isCompleted = true
            }
        }
        endDate = date
    }
}

// MARK: - Calculation Helpers

extension Workout {
    public var overallWorkingVolume: Double {
        (exercises ?? []).reduce(0.0) { $0 + $1.workingVolume }
    }

    public var hasWorkingSets: Bool {
        (exercises ?? []).contains { exercise in
            (exercise.sets ?? []).contains { $0.setType == .working }
        }
    }

    public var completedWorkingSetCount: Int {
        let isFinished = endDate != nil
        return (exercises ?? []).reduce(0) { total, exercise in
            let count = (exercise.sets ?? []).filter { (isFinished || $0.isCompleted) && $0.setType != .warmup }.count
            return total + count
        }
    }

    /// Projects a completed SwiftData `Workout` into an actor-safe `StrengthWorkoutSummaryInput`
    /// value type for training-load and NEAT workout-exclusion calculators without leaking
    /// `@Model` references across concurrency boundaries.
    ///
    /// Returns `nil` when the workout is still in progress (`endDate == nil` or `endDate <= startDate`).
    public func makeStrengthWorkoutSummaryInput(defaultRPE: Double = 7.5) -> StrengthWorkoutSummaryInput? {
        guard let endDate, endDate > startDate else { return nil }
        let workingSets = (exercises ?? []).flatMap { $0.sets ?? [] }.filter { $0.setType != .warmup }
        let rpeValues = workingSets.compactMap(\.rpe).filter { (1...10).contains($0) }
        let resolvedRPE: Double
        if rpeValues.isEmpty {
            resolvedRPE = defaultRPE
        } else {
            resolvedRPE = Double(rpeValues.reduce(0, +)) / Double(rpeValues.count)
        }
        return StrengthWorkoutSummaryInput(
            startDate: startDate,
            endDate: endDate,
            workingVolume: overallWorkingVolume,
            setCount: workingSets.count,
            estimatedRPE: resolvedRPE,
            healthKitUUID: healthKitUUID
        )
    }

    public var strengthSummaryInput: StrengthWorkoutSummaryInput? {
        makeStrengthWorkoutSummaryInput()
    }
}

extension StrengthWorkoutSummaryInput {
    public init?(workout: Workout, defaultRPE: Double = 7.5) {
        guard let projected = workout.makeStrengthWorkoutSummaryInput(defaultRPE: defaultRPE) else {
            return nil
        }
        self = projected
    }
}
