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
    @Environment(\.healthKitService) private var healthKitService
    @State private var heartRateStats: WorkoutHeartRateStats?

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

            if let stats = heartRateStats {
                Section {
                    LabeledContent(String(localized: "workout_detail_avg_heart_rate", defaultValue: "Average Heart Rate", comment: "Average heart rate label in workout summary")) {
                        Text(String(localized: "\(stats.averageHeartRate) bpm", comment: "Heart rate value with unit, e.g. 142 bpm"))
                    }
                    .accessibilityLabel(
                        Text(String(localized: "workout_detail_avg_heart_rate_a11y", defaultValue: "Average heart rate \(stats.averageHeartRate) beats per minute", comment: "Average heart rate a11y"))
                    )
                    LabeledContent(String(localized: "workout_detail_max_heart_rate", defaultValue: "Max Heart Rate", comment: "Max heart rate label in workout summary")) {
                        Text(String(localized: "\(stats.maxHeartRate) bpm", comment: "Heart rate value with unit, e.g. 155 bpm"))
                    }
                    .accessibilityLabel(
                        Text(String(localized: "workout_detail_max_heart_rate_a11y", defaultValue: "Max heart rate \(stats.maxHeartRate) beats per minute", comment: "Max heart rate a11y"))
                    )
                    if let hrr = stats.heartRateRecovery1Min {
                        LabeledContent(String(localized: "workout_detail_hrr_1min", defaultValue: "1-min HRR", comment: "1-minute heart rate recovery (HRR) label in workout summary")) {
                            Text(String(localized: "\(hrr) bpm", comment: "Heart rate value with unit, e.g. 24 bpm"))
                        }
                        .accessibilityLabel(
                            Text(String(localized: "workout_detail_hrr_1min_a11y", defaultValue: "1-minute heart rate recovery \(hrr) beats per minute", comment: "1-minute heart rate recovery a11y"))
                        )
                    }
                    if let zones = stats.zoneDistribution, !zones.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HeartRateZoneStackedBar(zones: zones)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(zones) { zone in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(HeartRateZoneStackedBar.color(forZoneId: zone.id))
                                            .frame(width: 8, height: 8)
                                        Text(zone.localizedName)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(zone.percentage * 100))%")
                                            .font(.footnote.bold())
                                    }
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            Text(String(
                                localized: "workout_detail_heart_rate_zones_a11y",
                                defaultValue: "Heart rate zones: \(zones.map { "\($0.localizedName) \(Int($0.percentage * 100))%" }.joined(separator: ", "))",
                                comment: "Heart rate zone distribution a11y"
                            ))
                        )
                    }
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
        .task {
            await loadHeartRateStats()
        }
    }

    private func loadHeartRateStats() async {
        heartRateStats = await WorkoutHeartRateStats.load(
            startDate: record.startDate,
            endDate: record.endDate,
            fetchHeartRate: { dateRange in
                try await healthKitService.fetchData(for: .heartRate, dateRange: dateRange).dataPoints
            },
            fetchPostWorkoutHeartRate: { dateRange in
                try await healthKitService.fetchData(for: .heartRate, dateRange: dateRange).dataPoints
            }
        )
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

    nonisolated static func formattedDuration(_ duration: TimeInterval) -> String {
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

    nonisolated static func formattedDistance(_ meters: Double, unit: DistanceUnit) -> String {
        let converted = unit.convert(fromMeters: meters)
        let formatted = converted.formatted(.number.precision(.fractionLength(1)))
        return "\(formatted) \(unit.abbreviation)"
    }
}
