import HealthKitService
import SwiftUI
import os

private let signposter = OSSignposter(
    subsystem: "com.vitalstride", category: "HKWorkoutDetail"
)

struct HealthKitWorkoutDetailView: View {
    let record: HealthWorkoutRecord

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: record.activityType.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(record.activityType.localizedName)
                        .font(.title2.bold())
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "概要", comment: "Summary section header in HK workout detail")) {
                LabeledContent(String(localized: "时间", comment: "Workout time label")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Self.formattedDate(record.startDate))
                        Text(Self.formattedTimeRange(start: record.startDate, end: record.endDate))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                LabeledContent(String(localized: "时长", comment: "Workout duration label")) {
                    Text(Self.formattedDuration(record.duration))
                }

                if let energy = record.totalEnergyBurned {
                    LabeledContent(String(localized: "消耗热量", comment: "Calories burned label")) {
                        Text(Self.formattedEnergy(energy))
                    }
                    .accessibilityLabel(
                        Text(String(
                            localized: "消耗热量 \(Self.formattedEnergy(energy))",
                            comment: "Calories a11y label"
                        ))
                    )
                }

                if let distance = record.totalDistance, distance > 0 {
                    LabeledContent(String(localized: "距离", comment: "Distance label")) {
                        Text(Self.formattedDistance(distance))
                    }
                    .accessibilityLabel(
                        Text(String(
                            localized: "距离 \(Self.formattedDistance(distance))",
                            comment: "Distance a11y label"
                        ))
                    )
                }

                LabeledContent(String(localized: "来源", comment: "Workout source label")) {
                    Text(record.sourceName ?? String(localized: "HealthKit", comment: "Default HK source name"))
                }
            }
        }
        .navigationTitle(record.activityType.localizedName)
        .onAppear {
            signposter.emitEvent(
                "hk_workout_detail_viewed",
                "activity_type=\(record.activityTypeRawValue)"
            )
        }
    }

    // MARK: - Formatting

    static func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().weekday())
    }

    static func formattedTimeRange(start: Date, end: Date) -> String {
        let startTime = start.formatted(.dateTime.hour().minute())
        let endTime = end.formatted(.dateTime.hour().minute())
        return "\(startTime) - \(endTime)"
    }

    static func formattedDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: duration)
            ?? HealthKitWorkoutRowView.formattedDuration(duration)
    }

    static func formattedEnergy(_ kcal: Double) -> String {
        let measurement = Measurement(value: kcal, unit: UnitEnergy.kilocalories)
        return Self.energyFormatter.string(from: measurement)
    }

    static func formattedDistance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return Self.distanceFormatter.string(from: measurement)
    }

    private static let energyFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let distanceFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()
}
