import HealthKitService
import SwiftUI
import os

private let signposter = OSSignposter(
    subsystem: "com.vitalstride", category: "HKWorkoutDetail"
)

struct HealthKitWorkoutDetailView: View {
    let record: HealthWorkoutRecord

    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .km

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
                    let formatted = Self.formattedEnergy(energy, unit: energyUnit)
                    LabeledContent(String(localized: "消耗热量", comment: "Calories burned label")) {
                        Text(formatted)
                    }
                    .accessibilityLabel(
                        Text(String(
                            localized: "消耗热量 \(formatted)",
                            comment: "Calories a11y label"
                        ))
                    )
                }

                if let distance = record.totalDistance, distance > 0 {
                    let formatted = Self.formattedDistance(distance, unit: distanceUnit)
                    LabeledContent(String(localized: "距离", comment: "Distance label")) {
                        Text(formatted)
                    }
                    .accessibilityLabel(
                        Text(String(
                            localized: "距离 \(formatted)",
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

    static func formattedEnergy(_ kcal: Double, unit: EnergyUnit) -> String {
        let converted = Int(unit.convert(fromKcal: kcal).rounded())
        return "\(converted) \(unit.abbreviation)"
    }

    static func formattedDistance(_ meters: Double, unit: DistanceUnit) -> String {
        let converted = unit.convert(fromMeters: meters)
        let formatted = converted.formatted(.number.precision(.fractionLength(1)))
        return "\(formatted) \(unit.abbreviation)"
    }
}
