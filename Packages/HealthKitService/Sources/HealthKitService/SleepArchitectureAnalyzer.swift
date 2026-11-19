import Foundation
import VitalModels

public struct SleepArchitectureAnalyzer: Sendable {
    public init() {}

    public func analyze(points: [HealthDataPoint], targetSleepDuration: TimeInterval = 8 * 60 * 60) -> SleepArchitectureSnapshot? {
        let sleepPoints = points.filter { $0.sampleType == .sleepAnalysis }
        guard !sleepPoints.isEmpty else { return nil }
        var deep = 0.0
        var rem = 0.0
        var core = 0.0
        var awake = 0.0
        var inBed = 0.0
        for point in sleepPoints {
            let duration = max(0, point.endDate.timeIntervalSince(point.startDate))
            switch point.sleepStage {
            case .asleepDeep: deep += duration
            case .asleepREM: rem += duration
            case .asleepCore, .asleepUnspecified: core += duration
            case .awake: awake += duration
            case .inBed, .none: inBed += duration
            }
        }
        let totalSleep = deep + rem + core
        let occupied = max(inBed, totalSleep + awake)
        let efficiency = occupied > 0 ? totalSleep / occupied : (targetSleepDuration > 0 ? totalSleep / targetSleepDuration : 0)
        return SleepArchitectureSnapshot(
            deepDuration: deep,
            remDuration: rem,
            coreDuration: core,
            awakeDuration: awake,
            totalSleepDuration: totalSleep,
            sleepEfficiency: efficiency,
            periodStart: sleepPoints.map(\.startDate).min(),
            periodEnd: sleepPoints.map(\.endDate).max()
        )
    }

    public func debtSummary(nights: [SleepArchitectureSnapshot], targetSleepDuration: TimeInterval) -> SleepDebtSummary {
        let target = max(0, targetSleepDuration)
        let seven = nights.suffix(7).reduce(0) { $0 + max(0, target - $1.totalSleepDuration) }
        let fourteen = nights.suffix(14).reduce(0) { $0 + max(0, target - $1.totalSleepDuration) }
        let baseline = nights.isEmpty ? 0 : nights.reduce(0) { $0 + $1.totalSleepDuration } / Double(nights.count)
        return SleepDebtSummary(
            sevenDayDebt: seven,
            fourteenDayDebt: fourteen,
            baselineSleepDuration: baseline,
            targetSleepDuration: target
        )
    }

    public func debtSummary(points: [HealthDataPoint], targetSleepDuration: TimeInterval) -> SleepDebtSummary? {
        guard let snapshot = analyze(points: points, targetSleepDuration: targetSleepDuration) else { return nil }
        return debtSummary(nights: [snapshot], targetSleepDuration: targetSleepDuration)
    }
}
