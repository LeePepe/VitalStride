import HealthKitService
import SwiftUI

struct HealthKitWorkoutRowView: View {
    let record: HealthWorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.activityType.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.activityType.localizedName)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(Self.formattedDuration(record.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(record.startDate, format: .dateTime.month().day().weekday())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let energy = record.totalEnergyBurned {
                    Text(String(
                        localized: "\(Int(energy.rounded())) kcal",
                        comment: "Workout energy burned display"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let distance = record.totalDistance, distance > 0 {
                    Text(String(
                        localized: "\(Self.formattedDistance(distance)) km",
                        comment: "Workout distance display"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [
            record.activityType.localizedName,
            Self.formattedDuration(record.duration),
            record.startDate.formatted(.dateTime.month().day()),
        ]
        if let energy = record.totalEnergyBurned {
            parts.append(String(
                localized: "\(Int(energy.rounded())) 千卡",
                comment: "Workout energy a11y"
            ))
        }
        if let distance = record.totalDistance, distance > 0 {
            parts.append(String(
                localized: "\(Self.formattedDistance(distance)) 公里",
                comment: "Workout distance a11y"
            ))
        }
        return parts.joined(separator: "，")
    }

    nonisolated static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(
                localized: "\(hours) 小时 \(minutes) 分钟",
                comment: "Duration hours and minutes"
            )
        }
        return String(
            localized: "\(minutes) 分钟",
            comment: "Duration minutes only"
        )
    }

    nonisolated static func formattedDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return km.formatted(.number.precision(.fractionLength(1)))
    }
}
