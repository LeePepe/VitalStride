import DesignKit
import HealthKitService
import SwiftUI

struct HealthKitWorkoutRowView: View {
    @Environment(\.theme) private var theme
    let record: HealthWorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.activityType.systemImage)
                .font(.title3)
                .foregroundStyle(theme.primary.primary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.activityType.localizedName)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(Self.formattedDuration(record.duration))
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)

                    Text(record.startDate, format: .dateTime.month().day().weekday())
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)
                }

                HStack(spacing: 8) {
                    WorkoutSourceBadge(
                        kind: record.sourceDeviceKind,
                        sourceName: record.sourceName,
                        isApp: false
                    )
                    if record.averageHeartRate != nil {
                        avgHeartRateChip
                    }
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
                    .foregroundStyle(theme.neutrals.text2)
                }
                if let distance = record.totalDistance, distance > 0 {
                    Text(String(
                        localized: "\(Self.formattedDistance(distance)) km",
                        comment: "Workout distance display"
                    ))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Small heart-icon + bpm chip. Rendered only when `averageHeartRate != nil`
    /// so `nil` records reveal no extra visual noise. The exact numeric value is
    /// intentionally NOT logged anywhere (Constitution §I privacy red line).
    @ViewBuilder
    private var avgHeartRateChip: some View {
        if let hr = record.averageHeartRate {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.danger)
                    .accessibilityHidden(true)
                Text({
                    let fmt = String(
                        localized: "workout_list.row.avg_hr_bpm",
                        defaultValue: "%lld bpm",
                        comment: "Workout row: average heart rate in beats per minute"
                    )
                    return String(format: fmt, hr)
                }())
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text2)
            }
        }
    }

    private var accessibilityDescription: String {
        var parts = [
            record.activityType.localizedName,
            Self.formattedDuration(record.duration),
            record.startDate.formatted(.dateTime.month().day()),
            WorkoutSourceBadge.accessibilityLabel(
                kind: record.sourceDeviceKind,
                sourceName: record.sourceName,
                isApp: false
            ),
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
        if let hr = record.averageHeartRate {
            let fmt = String(
                localized: "workout_list.row.avg_hr_a11y",
                defaultValue: "Average heart rate %lld",
                comment: "VoiceOver: average heart rate value"
            )
            parts.append(String(format: fmt, hr))
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
