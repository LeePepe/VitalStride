import Foundation
import HealthKitService

struct HeartRateZone: Sendable, Equatable, Identifiable {
    let id: Int
    let localizedName: String
    let range: ClosedRange<Double>
    let percentage: Double
}

struct WorkoutHeartRateStats: Sendable, Equatable {
    let averageHeartRate: Int
    let maxHeartRate: Int
    let zoneDistribution: [HeartRateZone]?

    static func from(dataPoints: [HealthDataPoint]) -> WorkoutHeartRateStats? {
        guard !dataPoints.isEmpty else { return nil }

        let values = dataPoints.map(\.value)
        let avg = values.reduce(0, +) / Double(values.count)
        let max = values.max() ?? 0

        let zones: [HeartRateZone]? = if dataPoints.count >= 5 {
            Self.computeZones(values: values)
        } else {
            nil
        }

        return WorkoutHeartRateStats(
            averageHeartRate: Int(avg.rounded()),
            maxHeartRate: Int(max.rounded()),
            zoneDistribution: zones
        )
    }

    private static func zoneName(for id: Int) -> String {
        switch id {
        case 1: String(localized: "热身", comment: "Heart rate zone 1 name — Warm Up")
        case 2: String(localized: "燃脂", comment: "Heart rate zone 2 name — Fat Burn")
        case 3: String(localized: "有氧", comment: "Heart rate zone 3 name — Cardio")
        case 4: String(localized: "无氧", comment: "Heart rate zone 4 name — Anaerobic")
        case 5: String(localized: "极限", comment: "Heart rate zone 5 name — Maximum")
        default: ""
        }
    }

    private static let zoneRanges: [(id: Int, range: ClosedRange<Double>)] = [
        (1, 0...99),
        (2, 100...119),
        (3, 120...139),
        (4, 140...159),
        (5, 160...300),
    ]

    private static func computeZones(values: [Double]) -> [HeartRateZone] {
        let total = Double(values.count)
        return zoneRanges.compactMap { def -> HeartRateZone? in
            let count = values.filter { def.range.contains($0) }.count
            let pct = Double(count) / total
            guard pct > 0 else { return nil }
            return HeartRateZone(
                id: def.id,
                localizedName: zoneName(for: def.id),
                range: def.range,
                percentage: pct
            )
        }
    }
}
