// swiftlint:disable no_hardcoded_chinese
import DesignKit
import HealthKitService
import SwiftUI
import TelemetryKit
import VitalModels

// MARK: - Summary Card Container

struct SummaryCardView<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let isLoading: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Card {
            Label(title, systemImage: systemImage)
                .font(TypeScale.meta)
                .fontWeight(.semibold)
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Steps Summary

struct StepsSummaryCard: View {
    @State private var todaySteps: Int?
    @State private var isLoading: Bool
    private let needsFetch: Bool
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    init() {
        _todaySteps = State(initialValue: nil)
        _isLoading = State(initialValue: true)
        needsFetch = true
    }

    init(preloaded steps: Int?) {
        _todaySteps = State(initialValue: steps)
        _isLoading = State(initialValue: false)
        needsFetch = false
    }

    var body: some View {
        SummaryCardView(
            title: String(localized: "步数", comment: "Steps"),
            systemImage: "figure.walk",
            color: theme.primary.primary,
            isLoading: isLoading
        ) {
            if let steps = todaySteps {
                Text(steps.formatted(.number))
                    .font(TypeScale.display)
                Text(String(localized: "步", comment: "Steps unit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(TypeScale.display)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard needsFetch else { return }
            await loadData()
        }
    }

    private func loadData() async {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .stepCount, in: interval)
            let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            todaySteps = aggregated.last?.totalSteps
        } catch {
            TelemetryService.shared.trackNonisolated(
                .healthSummaryLoadFailed(sampleType: "stepCount")
            )
        }
        isLoading = false
    }
}

// MARK: - Heart Rate Summary

struct HeartRateSummaryCard: View {
    @State private var latestBPM: Int?
    @State private var isLoading: Bool
    private let needsFetch: Bool
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    init() {
        _latestBPM = State(initialValue: nil)
        _isLoading = State(initialValue: true)
        needsFetch = true
    }

    init(preloaded bpm: Int?) {
        _latestBPM = State(initialValue: bpm)
        _isLoading = State(initialValue: false)
        needsFetch = false
    }

    var body: some View {
        SummaryCardView(
            title: String(localized: "心率", comment: "Heart rate"),
            systemImage: "heart.fill",
            color: theme.danger,
            isLoading: isLoading
        ) {
            if let bpm = latestBPM {
                Text(bpm.formatted())
                    .font(TypeScale.display)
                Text(String(localized: "BPM", comment: "Beats per minute"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(TypeScale.display)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard needsFetch else { return }
            await loadData()
        }
    }

    private func loadData() async {
        let interval = TimeRange.day.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .heartRate, in: interval)
            let filtered = HeartRateStats.filtered(dataPoints, in: interval)
            if let avg = HeartRateStats.average(of: filtered) {
                latestBPM = Int(avg.rounded())
            }
        } catch {
            TelemetryService.shared.trackNonisolated(
                .healthSummaryLoadFailed(sampleType: "heartRate")
            )
        }
        isLoading = false
    }
}

// MARK: - Sleep Summary

struct SleepSummaryCard: View {
    @State private var lastNightSleep: TimeInterval?
    @State private var isLoading: Bool
    private let needsFetch: Bool
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    init() {
        _lastNightSleep = State(initialValue: nil)
        _isLoading = State(initialValue: true)
        needsFetch = true
    }

    init(preloaded sleep: TimeInterval?) {
        _lastNightSleep = State(initialValue: sleep)
        _isLoading = State(initialValue: false)
        needsFetch = false
    }

    var body: some View {
        SummaryCardView(
            title: String(localized: "睡眠", comment: "Sleep"),
            systemImage: "bed.double.fill",
            color: theme.primary.primary,
            isLoading: isLoading
        ) {
            if let sleep = lastNightSleep {
                Text(formatDuration(sleep))
                    .font(TypeScale.display)
            } else {
                Text("--")
                    .font(TypeScale.display)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard needsFetch else { return }
            await loadData()
        }
    }

    private func loadData() async {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .sleepAnalysis, in: interval)
            let nights = SleepAggregator.aggregateByNight(dataPoints: dataPoints, in: interval)
            lastNightSleep = nights.last?.totalSleep
        } catch {
            TelemetryService.shared.trackNonisolated(
                .healthSummaryLoadFailed(sampleType: "sleep")
            )
        }
        isLoading = false
    }
}

// MARK: - Weight Summary

struct WeightSummaryCard: View {
    @State private var latestWeight: Double?
    @State private var isLoading: Bool
    private let needsFetch: Bool
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    init() {
        _latestWeight = State(initialValue: nil)
        _isLoading = State(initialValue: true)
        needsFetch = true
    }

    init(preloaded weight: Double?) {
        _latestWeight = State(initialValue: weight)
        _isLoading = State(initialValue: false)
        needsFetch = false
    }

    var body: some View {
        SummaryCardView(
            title: String(localized: "体重", comment: "Body weight"),
            systemImage: "scalemass.fill",
            color: theme.primary.primary,
            isLoading: isLoading
        ) {
            if let weight = latestWeight {
                Text(weight.formatted(.number.precision(.fractionLength(1))))
                    .font(TypeScale.display)
                Text(String(localized: "kg", comment: "Kilogram"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(TypeScale.display)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard needsFetch else { return }
            await loadData()
        }
    }

    private func loadData() async {
        let interval = TimeRange.week.dateInterval()
        do {
            let dataPoints = try await cache.data(for: .bodyMass, in: interval)
            let points = WeightAnalyzer.extractWeightPoints(from: dataPoints, in: interval)
            latestWeight = points.last?.weight
        } catch {
            TelemetryService.shared.trackNonisolated(
                .healthSummaryLoadFailed(sampleType: "bodyMass")
            )
        }
        isLoading = false
    }
}
