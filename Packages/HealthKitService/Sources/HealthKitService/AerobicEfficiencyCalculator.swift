import Foundation
import VitalModels

public struct AerobicEfficiencyCalculator: Sendable {
    public init() {}

    public func calculate(from points: [HealthDataPoint]) -> AerobicEfficiencySnapshot? {
        let distances = points.filter { $0.sampleType == .distanceWalkingRunning }
        let heartRates = points.filter { $0.sampleType == .heartRate }
        let vo2 = points.filter { $0.sampleType == .vo2Max }.sorted { $0.startDate < $1.startDate }
        guard !distances.isEmpty, !heartRates.isEmpty else {
            let trend = vo2.count >= 2 ? (vo2.last?.value ?? 0) - (vo2.first?.value ?? 0) : nil
            return vo2.isEmpty ? nil : AerobicEfficiencySnapshot(vo2Max: vo2.last?.value, vo2MaxTrend: trend, sampleCount: vo2.count)
        }
        let totalDistance = distances.reduce(0) { $0 + max(0, $1.value) }
        let start = distances.map(\.startDate).min() ?? Date()
        let end = distances.map(\.endDate).max() ?? start
        let duration = max(end.timeIntervalSince(start), 1)
        let speedKilometersPerHour = totalDistance / 1000 * 3600 / duration
        let averageHeartRate = heartRates.reduce(0) { $0 + $1.value } / Double(heartRates.count)
        let firstHalf = heartRates.filter { $0.startDate.timeIntervalSince(start) <= duration / 2 }
        let secondHalf = heartRates.filter { $0.startDate.timeIntervalSince(start) > duration / 2 }
        let firstHR = firstHalf.isEmpty ? averageHeartRate : firstHalf.reduce(0) { $0 + $1.value } / Double(firstHalf.count)
        let secondHR = secondHalf.isEmpty ? averageHeartRate : secondHalf.reduce(0) { $0 + $1.value } / Double(secondHalf.count)
        let firstEfficiency = speedKilometersPerHour / max(firstHR, 1)
        let secondEfficiency = speedKilometersPerHour / max(secondHR, 1)
        let decoupling = firstEfficiency > 0 ? (firstEfficiency - secondEfficiency) / firstEfficiency * 100 : nil
        let trend = vo2.count >= 2 ? (vo2.last?.value ?? 0) - (vo2.first?.value ?? 0) : nil
        return AerobicEfficiencySnapshot(
            efficiencyFactor: speedKilometersPerHour / max(averageHeartRate, 1),
            aerobicDecouplingPercentage: decoupling,
            vo2Max: vo2.last?.value,
            vo2MaxTrend: trend,
            sampleCount: distances.count + vo2.count
        )
    }

    public func efficiencyFactor(distanceMeters: Double, duration: TimeInterval, averageHeartRate: Double) -> Double? {
        guard distanceMeters >= 0, duration > 0, averageHeartRate > 0 else { return nil }
        return distanceMeters / 1000 * 3600 / duration / averageHeartRate
    }

    public func aerobicDecoupling(firstEfficiency: Double, secondEfficiency: Double) -> Double? {
        guard firstEfficiency > 0 else { return nil }
        return (firstEfficiency - secondEfficiency) / firstEfficiency * 100
    }
}
