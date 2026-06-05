import SwiftUI
import os

// MARK: - DataView

struct DataView: View {
    @State private var authCompleted = false
    @State private var dataRefreshToken = UUID()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if authCompleted {
                    summarySection
                    activitySection
                    heartSection
                    bodySection
                    sleepSection
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .id(dataRefreshToken)
            .navigationTitle(String(localized: "数据", comment: "Data tab title"))
            .task {
                await ensureAuthorization()
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitAuthorizationChanged)) { _ in
                dataRefreshToken = UUID()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, authCompleted {
                    dataRefreshToken = UUID()
                }
            }
        }
    }

    private func ensureAuthorization() async {
        let service = HealthKitService(deviceIdentifier: "ios-display")
        do {
            try await service.requestAuthorization()
        } catch {}
        authCompleted = true
    }

    private var summarySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StepsSummaryCard()
                HeartRateSummaryCard()
                SleepSummaryCard()
                WeightSummaryCard()
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var activitySection: some View {
        Section {
            NavigationLink {
                StepsDetailView()
            } label: {
                Label(String(localized: "步数", comment: "Steps"), systemImage: "figure.walk")
            }
            NavigationLink {
                ActiveEnergyDetailView()
            } label: {
                Label(String(localized: "活动能量", comment: "Active energy"), systemImage: "flame.fill")
            }
        } header: {
            Text("活动", comment: "Activity section header")
        }
    }

    private var heartSection: some View {
        Section {
            NavigationLink {
                HeartRateDetailView()
            } label: {
                Label(String(localized: "心率", comment: "Heart rate"), systemImage: "heart.fill")
            }
        } header: {
            Text("心脏", comment: "Heart section header")
        }
    }

    private var bodySection: some View {
        Section {
            NavigationLink {
                BodyWeightDetailView()
            } label: {
                Label(String(localized: "体重", comment: "Body weight"), systemImage: "scalemass.fill")
            }
        } header: {
            Text("身体测量", comment: "Body measurements section header")
        }
    }

    private var sleepSection: some View {
        Section {
            NavigationLink {
                SleepDetailView()
            } label: {
                Label(String(localized: "睡眠", comment: "Sleep"), systemImage: "bed.double.fill")
            }
        } header: {
            Text("睡眠", comment: "Sleep section header")
        }
    }
}

// MARK: - Summary Card

private struct SummaryCardView<Content: View>: View {
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

private struct StepsSummaryCard: View {
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

private struct HeartRateSummaryCard: View {
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

private struct SleepSummaryCard: View {
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

private struct WeightSummaryCard: View {
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

// MARK: - Section Card Container

struct DataSectionCard<Destination: View, Content: View>: View {
    let title: String
    let systemImage: String
    let destination: Destination
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "轻点查看详情", comment: "Card navigation a11y hint"))
    }
}

#Preview {
    DataView()
}
