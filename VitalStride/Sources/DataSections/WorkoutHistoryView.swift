import HealthKitService
import SwiftUI
import VitalModels
import os

struct WorkoutHistoryView: View {
    @State private var workouts: [HealthWorkoutRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache

    private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutHistory")

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage {
                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else if workouts.isEmpty {
                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "figure.run")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(String(localized: "暂无运动记录", comment: "No workout records"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(workouts) { workout in
                    workoutRow(workout)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "运动记录", comment: "Workout history title"))
        .task {
            await loadData()
        }
    }

    private func workoutRow(_ workout: HealthWorkoutRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activityType.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activityType.localizedName)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(formattedDuration(workout.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(workout.startDate, format: .dateTime.month().day().weekday())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let energy = workout.totalEnergyBurned {
                    Text(String(
                        localized: "\(Int(energy.rounded())) kcal",
                        comment: "Workout energy"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let distance = workout.totalDistance, distance > 0 {
                    Text(String(
                        localized: "\(formattedDistance(distance)) km",
                        comment: "Workout distance"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(workoutAccessibilityLabel(workout))
    }

    private func workoutAccessibilityLabel(_ workout: HealthWorkoutRecord) -> String {
        var parts = [
            workout.activityType.localizedName,
            formattedDuration(workout.duration),
            workout.startDate.formatted(.dateTime.month().day()),
        ]
        if let energy = workout.totalEnergyBurned {
            parts.append(String(
                localized: "\(Int(energy.rounded())) 千卡",
                comment: "Workout energy a11y"
            ))
        }
        if let distance = workout.totalDistance, distance > 0 {
            parts.append(String(
                localized: "\(formattedDistance(distance)) 公里",
                comment: "Workout distance a11y"
            ))
        }
        return parts.joined(separator: "，")
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(
                localized: "\(hours) 小时 \(minutes) 分钟",
                comment: "Duration hours minutes"
            )
        }
        return String(
            localized: "\(minutes) 分钟",
            comment: "Duration minutes"
        )
    }

    private func formattedDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return km.formatted(.number.precision(.fractionLength(1)))
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let now = Date()
            let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
            let dateRange = DateInterval(start: ninetyDaysAgo, end: now)
            let records = try await cache.workoutData(in: dateRange)
            guard !Task.isCancelled else { return }
            workouts = records.sorted { $0.startDate > $1.startDate }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("workout load failed: \(error.localizedDescription)")
            errorMessage = String(localized: "无法加载运动记录", comment: "Workout load error")
            workouts = []
        }

        isLoading = false
    }
}
