import Foundation
import VitalModels

public struct TrainingLoadCalculator: Sendable {
    public init() {}

    public func calculate(
        workouts: [HealthWorkoutRecord],
        strengthWorkouts: [StrengthWorkoutSummaryInput],
        asOf date: Date = Date()
    ) -> TrainingLoadSnapshot {
        let events = workouts.map(trainingStress(for:)) + strengthWorkouts.map(strengthStress(for:))
        guard let earliest = events.map(\.date).min() else {
            return TrainingLoadSnapshot(acuteTrainingLoad: 0, chronicTrainingLoad: 0, trainingStressBalance: 0, acuteChronicWorkloadRatio: nil)
        }
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = calendar.startOfDay(for: earliest)
        let lastDay = calendar.startOfDay(for: max(date, earliest))
        var atl = 0.0
        var ctl = 0.0
        var totalTRIMP = 0.0
        var totalTSS = 0.0
        var day = firstDay
        while day <= lastDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let load = events.filter { $0.date >= day && $0.date < nextDay }.reduce(0) { $0 + $1.load }
            atl = ewma(previous: atl, load: load, period: 7)
            ctl = ewma(previous: ctl, load: load, period: 42)
            totalTRIMP += events.filter { $0.date >= day && $0.date < nextDay && $0.kind == .trimp }.reduce(0) { $0 + $1.load }
            totalTSS += events.filter { $0.date >= day && $0.date < nextDay && $0.kind == .tss }.reduce(0) { $0 + $1.load }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return TrainingLoadSnapshot(
            acuteTrainingLoad: atl,
            chronicTrainingLoad: ctl,
            trainingStressBalance: ctl - atl,
            acuteChronicWorkloadRatio: ctl > 0 ? atl / ctl : nil,
            trimp: totalTRIMP,
            tss: totalTSS
        )
    }

    public func trimp(duration: TimeInterval, averageHeartRate: Double, restingHeartRate: Double = 60, maximumHeartRate: Double = 190) -> Double {
        guard duration > 0, maximumHeartRate > restingHeartRate else { return 0 }
        let intensity = min(max((averageHeartRate - restingHeartRate) / (maximumHeartRate - restingHeartRate), 0), 1)
        return duration / 60 * intensity * (0.64 * exp(1.92 * intensity))
    }

    public func strengthLoad(_ input: StrengthWorkoutSummaryInput) -> Double {
        guard input.endDate > input.startDate else { return 0 }
        return input.workingVolume * max(input.estimatedRPE, 1) / 10 + Double(input.setCount) * input.estimatedRPE
    }

    private func trainingStress(for workout: HealthWorkoutRecord) -> LoadEvent {
        let load: Double
        let kind: LoadKind
        if let averageHeartRate = workout.averageHeartRate {
            load = trimp(duration: workout.duration, averageHeartRate: Double(averageHeartRate))
            kind = .trimp
        } else {
            load = max(0, workout.duration / 60)
            kind = .tss
        }
        return LoadEvent(date: workout.startDate, load: load, kind: kind)
    }

    private func strengthStress(for workout: StrengthWorkoutSummaryInput) -> LoadEvent {
        LoadEvent(date: workout.startDate, load: strengthLoad(workout), kind: .tss)
    }

    private func ewma(previous: Double, load: Double, period: Double) -> Double {
        let alpha = 2 / (period + 1)
        return previous + alpha * (load - previous)
    }

    private struct LoadEvent: Sendable {
        let date: Date
        let load: Double
        let kind: LoadKind
    }

    private enum LoadKind: Sendable {
        case trimp
        case tss
    }
}
