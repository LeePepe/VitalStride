import SwiftUI

// MARK: - Summary Card Container

struct SummaryCardView<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let isLoading: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    content()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Steps Summary

struct StepsSummaryCard: View {
    @State private var todaySteps: Int?
    @State private var isLoading = true

    var body: some View {
        SummaryCardView(
            title: String(localized: "步数", comment: "Steps"),
            systemImage: "figure.walk",
            color: .blue,
            isLoading: isLoading
        ) {
            if let steps = todaySteps {
                Text(steps.formatted(.number))
                    .font(.title3.bold())
                Text(String(localized: "步", comment: "Steps unit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        let interval = TimeRange.day.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")
        do {
            let result = try await service.fetchData(for: .stepCount, dateRange: interval)
            let aggregated = StepsAggregator.aggregateByDay(dataPoints: result.dataPoints, in: interval)
            todaySteps = aggregated.last?.totalSteps
        } catch {}
        isLoading = false
    }
}

// MARK: - Heart Rate Summary

struct HeartRateSummaryCard: View {
    @State private var latestBPM: Int?
    @State private var isLoading = true

    var body: some View {
        SummaryCardView(
            title: String(localized: "心率", comment: "Heart rate"),
            systemImage: "heart.fill",
            color: .red,
            isLoading: isLoading
        ) {
            if let bpm = latestBPM {
                Text(bpm.formatted())
                    .font(.title3.bold())
                Text(String(localized: "BPM", comment: "Beats per minute"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        let interval = TimeRange.day.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")
        do {
            let result = try await service.fetchData(for: .heartRate, dateRange: interval)
            let filtered = HeartRateStats.filtered(result.dataPoints, in: interval)
            if let avg = HeartRateStats.average(of: filtered) {
                latestBPM = Int(avg.rounded())
            }
        } catch {}
        isLoading = false
    }
}

// MARK: - Sleep Summary

struct SleepSummaryCard: View {
    @State private var lastNightSleep: TimeInterval?
    @State private var isLoading = true

    var body: some View {
        SummaryCardView(
            title: String(localized: "睡眠", comment: "Sleep"),
            systemImage: "bed.double.fill",
            color: .indigo,
            isLoading: isLoading
        ) {
            if let sleep = lastNightSleep {
                Text(formatDuration(sleep))
                    .font(.title3.bold())
            } else {
                Text("--")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        let interval = TimeRange.week.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")
        do {
            let result = try await service.fetchData(for: .sleepAnalysis, dateRange: interval)
            let nights = SleepAggregator.aggregateByNight(dataPoints: result.dataPoints, in: interval)
            lastNightSleep = nights.last?.totalSleep
        } catch {}
        isLoading = false
    }
}

// MARK: - Weight Summary

struct WeightSummaryCard: View {
    @State private var latestWeight: Double?
    @State private var isLoading = true

    var body: some View {
        SummaryCardView(
            title: String(localized: "体重", comment: "Body weight"),
            systemImage: "scalemass.fill",
            color: .green,
            isLoading: isLoading
        ) {
            if let weight = latestWeight {
                Text(weight.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.bold())
                Text(String(localized: "kg", comment: "Kilogram"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        let interval = TimeRange.week.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")
        do {
            let result = try await service.fetchData(for: .bodyMass, dateRange: interval)
            let points = WeightAnalyzer.extractWeightPoints(from: result.dataPoints, in: interval)
            latestWeight = points.last?.weight
        } catch {}
        isLoading = false
    }
}
