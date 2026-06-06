import Charts
import SwiftUI
import os

// MARK: - Models

struct NightSleepData: Identifiable, Equatable, Sendable {
    let date: Date
    let deep: TimeInterval
    let core: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval
    var id: Date { date }

    var totalSleep: TimeInterval { deep + core + rem }
    var totalDuration: TimeInterval { deep + core + rem + awake }
}

struct SleepStatistics: Equatable, Sendable {
    let averageTotalSleep: TimeInterval
    let averageDeep: TimeInterval
    let averageREM: TimeInterval

    static let empty = SleepStatistics(averageTotalSleep: 0, averageDeep: 0, averageREM: 0)
}

// MARK: - Sleep Aggregator

enum SleepAggregator {
    static func aggregateByNight(
        dataPoints: [HealthDataPoint],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [NightSleepData] {
        let sleepPoints = dataPoints.filter { $0.sampleType == .sleepAnalysis }

        var nightGroups: [Date: [HealthDataPoint]] = [:]
        for point in sleepPoints {
            guard let stage = point.sleepStage else { continue }
            if stage == .inBed { continue }

            let nightDate = nightDateFor(point.startDate, calendar: calendar)
            guard nightDate >= calendar.startOfDay(for: interval.start),
                  nightDate < interval.end else { continue }

            let duration = point.endDate.timeIntervalSince(point.startDate)
            guard duration > 0 else { continue }

            nightGroups[nightDate, default: []].append(point)
        }

        return nightGroups
            .map { aggregateNight(date: $0.key, points: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private static func aggregateNight(date: Date, points: [HealthDataPoint]) -> NightSleepData {
        let hasDetailedStages = points.contains {
            guard let s = $0.sleepStage else { return false }
            return s == .asleepCore || s == .asleepDeep || s == .asleepREM
        }

        let effectivePoints = hasDetailedStages
            ? points.filter { $0.sleepStage != .asleepUnspecified }
            : points

        func intervals(for stages: Set<SleepStage>) -> [(start: Date, end: Date)] {
            effectivePoints
                .filter { $0.sleepStage.map { stages.contains($0) } ?? false }
                .map { (start: $0.startDate, end: $0.endDate) }
        }

        return NightSleepData(
            date: date,
            deep: mergedDuration(intervals(for: [.asleepDeep])),
            core: mergedDuration(intervals(for: [.asleepCore, .asleepUnspecified])),
            rem: mergedDuration(intervals(for: [.asleepREM])),
            awake: mergedDuration(intervals(for: [.awake]))
        )
    }

    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var result = [sorted[0]]
        for interval in sorted.dropFirst() {
            let last = result[result.count - 1]
            if interval.start <= last.end {
                result[result.count - 1] = (start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func mergedDuration(_ intervals: [(start: Date, end: Date)]) -> TimeInterval {
        mergeIntervals(intervals).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    static func nightDateFor(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour < 18 {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            return calendar.startOfDay(for: dayBefore)
        }
        return calendar.startOfDay(for: date)
    }

    static func computeStatistics(from nights: [NightSleepData]) -> SleepStatistics {
        guard !nights.isEmpty else { return .empty }
        let count = Double(nights.count)
        let totalSleep = nights.reduce(0.0) { $0 + $1.totalSleep }
        let totalDeep = nights.reduce(0.0) { $0 + $1.deep }
        let totalREM = nights.reduce(0.0) { $0 + $1.rem }
        return SleepStatistics(
            averageTotalSleep: totalSleep / count,
            averageDeep: totalDeep / count,
            averageREM: totalREM / count
        )
    }
}

// MARK: - Sleep Stage Info

enum SleepStageInfo: String, CaseIterable, Identifiable {
    case deep
    case core
    case rem
    case awake

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .deep: String(localized: "深睡", comment: "Deep sleep")
        case .core: String(localized: "浅睡", comment: "Core/light sleep")
        case .rem: String(localized: "REM", comment: "REM sleep")
        case .awake: String(localized: "清醒", comment: "Awake")
        }
    }

    var color: Color {
        switch self {
        case .deep: .indigo
        case .core: .blue.opacity(0.6)
        case .rem: .purple
        case .awake: .gray.opacity(0.5)
        }
    }

    func duration(from night: NightSleepData) -> TimeInterval {
        switch self {
        case .deep: night.deep
        case .core: night.core
        case .rem: night.rem
        case .awake: night.awake
        }
    }
}

// MARK: - SleepSection

struct SleepSection: View {
    let range: TimeRange

    @State private var nights: [NightSleepData] = []
    @State private var statistics: SleepStatistics = .empty
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let logger = Logger(subsystem: "com.vitalstride", category: "SleepSection")

    var body: some View {
        DataSectionCard(
            title: String(localized: "睡眠", comment: "Sleep section"),
            systemImage: "bed.double.fill",
            destination: SleepDetailView()
        ) {
            content
        }
        .task(id: range) {
            await loadData()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(height: 120)
                .frame(maxWidth: .infinity)
        } else if fetchError != nil {
            VStack(spacing: 4) {
                Image(systemName: "bed.double")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "无法加载睡眠数据", comment: "Sleep load error"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        } else if nights.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "bed.double")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "暂无睡眠数据", comment: "No sleep data"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        } else {
            SleepChartView(nights: nights, range: range, compact: true)
                .frame(height: 120)
            statsSummary
        }
    }

    private var statsSummary: some View {
        HStack {
            SleepStatItem(
                label: String(localized: "平均睡眠", comment: "Average sleep"),
                duration: statistics.averageTotalSleep
            )
            Spacer()
            SleepStatItem(
                label: String(localized: "平均深睡", comment: "Average deep sleep"),
                duration: statistics.averageDeep
            )
            Spacer()
            SleepStatItem(
                label: String(localized: "平均REM", comment: "Average REM"),
                duration: statistics.averageREM
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    private var statsAccessibilityLabel: String {
        let parts = [
            String(localized: "平均睡眠 \(formatDuration(statistics.averageTotalSleep))", comment: "Avg sleep a11y"),
            String(localized: "平均深睡 \(formatDuration(statistics.averageDeep))", comment: "Avg deep a11y"),
            String(localized: "平均REM \(formatDuration(statistics.averageREM))", comment: "Avg REM a11y"),
        ]
        return parts.joined(separator: ", ")
    }

    private func loadData() async {
        isLoading = true
        fetchError = nil
        let start = ContinuousClock.now
        let interval = range.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")

        do {
            let result = try await service.fetchData(for: .sleepAnalysis, dateRange: interval)
            guard !Task.isCancelled else { return }

            let aggregated = SleepAggregator.aggregateByNight(dataPoints: result.dataPoints, in: interval)
            let stats = SleepAggregator.computeStatistics(from: aggregated)

            nights = aggregated
            statistics = stats

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("render dataPoints=\(result.dataPoints.count) nights=\(aggregated.count) ms=\(ms)")
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            fetchError = error
            nights = []
            statistics = .empty
        }

        isLoading = false
    }
}

// MARK: - Sleep Stat Item

private struct SleepStatItem: View {
    let label: String
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatDuration(duration))
                .font(.headline)
        }
    }
}

// MARK: - Duration Formatting

func formatDuration(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = Int(interval) % 3600 / 60
    if hours > 0 {
        return String(localized: "\(hours)h \(minutes)m", comment: "Duration format hours minutes")
    }
    return String(localized: "\(minutes)m", comment: "Duration format minutes only")
}

func hoursFrom(_ interval: TimeInterval) -> Double {
    interval / 3600.0
}

// MARK: - Sleep Chart

struct SleepChartView: View {
    let nights: [NightSleepData]
    let range: TimeRange
    let compact: Bool

    @State private var selectedDate: Date?

    private var selectedNight: NightSleepData? {
        guard let selectedDate else { return nil }
        return nights.min { a, b in
            abs(a.date.timeIntervalSince(selectedDate)) < abs(b.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(nights) { night in
                ForEach(SleepStageInfo.allCases) { stage in
                    let hours = hoursFrom(stage.duration(from: night))
                    BarMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            night.date,
                            unit: .day
                        ),
                        y: .value(
                            stage.localizedName,
                            hours
                        )
                    )
                    .foregroundStyle(by: .value(
                        String(localized: "阶段", comment: "Sleep stage"),
                        stage.localizedName
                    ))
                }
            }
        }
        .chartForegroundStyleScale([
            String(localized: "深睡", comment: "Deep"): SleepStageInfo.deep.color,
            String(localized: "浅睡", comment: "Core"): SleepStageInfo.core.color,
            String(localized: "REM", comment: "REM"): SleepStageInfo.rem.color,
            String(localized: "清醒", comment: "Awake"): SleepStageInfo.awake.color,
        ])
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 4 : 7)) { _ in
                AxisValueLabel(format: xAxisFormat)
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(String(localized: "\(Int(h))h", comment: "Hour axis label"))
                    }
                }
                AxisGridLine()
            }
        }
        .chartLegend(compact ? .hidden : .visible)
        .accessibilityLabel(String(localized: "睡眠分析图", comment: "Sleep chart a11y"))
        .accessibilityValue(chartAccessibilityValue)
        .overlay(alignment: .topLeading) {
            if let selectedNight {
                selectionOverlay(for: selectedNight)
                    .padding(4)
            }
        }
    }

    private func selectionOverlay(for night: NightSleepData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(night.date.formatted(.dateTime.month().day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatDuration(night.totalSleep))
                .font(.caption.bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .day:
            .dateTime.hour()
        case .week:
            .dateTime.weekday(.abbreviated)
        case .month:
            .dateTime.month(.abbreviated).day()
        case .year:
            .dateTime.month(.abbreviated)
        }
    }

    private var chartAccessibilityValue: String {
        if let selectedNight {
            let date = selectedNight.date.formatted(.dateTime.month().day())
            let total = formatDuration(selectedNight.totalSleep)
            let deep = formatDuration(selectedNight.deep)
            let core = formatDuration(selectedNight.core)
            let rem = formatDuration(selectedNight.rem)
            let awake = formatDuration(selectedNight.awake)
            return String(
                localized: "选中\(date)，总睡眠\(total)，深睡\(deep)，浅睡\(core)，REM \(rem)，清醒\(awake)",
                comment: "Selected night sleep a11y"
            )
        }
        guard !nights.isEmpty else {
            return String(localized: "无数据", comment: "No data a11y")
        }
        let avgHours = formatDuration(SleepAggregator.computeStatistics(from: nights).averageTotalSleep)
        return String(localized: "\(range.localizedLabel)平均睡眠 \(avgHours)", comment: "Sleep chart a11y value")
    }
}

// MARK: - Sleep Detail View

struct SleepDetailView: View {
    @State private var selectedRange: TimeRange = .week
    @State private var nights: [NightSleepData] = []
    @State private var statistics: SleepStatistics = .empty
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let logger = Logger(subsystem: "com.vitalstride", category: "SleepDetail")

    var body: some View {
        List {
            Section {
                Picker(selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.localizedLabel).tag(range)
                    }
                } label: {
                    Text("时间范围", comment: "Time range picker label")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "选择时间范围", comment: "Time range picker a11y"))
            }
            .listRowBackground(Color.clear)

            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else if fetchError != nil {
                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "bed.double")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "无法加载睡眠数据", comment: "Sleep load error"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    SleepChartView(nights: nights, range: selectedRange, compact: false)
                        .frame(height: 250)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    statRow(
                        label: String(localized: "平均睡眠", comment: "Average sleep"),
                        value: formatDuration(statistics.averageTotalSleep),
                        image: "bed.double"
                    )
                    statRow(
                        label: String(localized: "平均深睡", comment: "Average deep"),
                        value: formatDuration(statistics.averageDeep),
                        image: "moon.zzz"
                    )
                    statRow(
                        label: String(localized: "平均REM", comment: "Average REM"),
                        value: formatDuration(statistics.averageREM),
                        image: "brain.head.profile"
                    )
                }

                Section {
                    ForEach(nights.reversed()) { night in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(night.date, format: .dateTime.month().day().weekday())
                                Spacer()
                                Text(formatDuration(night.totalSleep))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                stageLabel(String(localized: "深睡", comment: "Deep"), duration: night.deep, color: SleepStageInfo.deep.color)
                                stageLabel(String(localized: "浅睡", comment: "Core"), duration: night.core, color: SleepStageInfo.core.color)
                                stageLabel(String(localized: "REM", comment: "REM"), duration: night.rem, color: SleepStageInfo.rem.color)
                            }
                            .font(.caption2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(nightAccessibilityLabel(for: night))
                    }
                } header: {
                    Text("按夜明细", comment: "Nightly breakdown header")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "睡眠", comment: "Sleep detail title"))
        .task(id: selectedRange) {
            await loadData()
        }
        .onAppear {
            logger.info("detail_opened range=\(selectedRange.rawValue)")
        }
    }

    private func statRow(label: String, value: String, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func stageLabel(_ name: String, duration: TimeInterval, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(name) \(formatDuration(duration))")
                .foregroundStyle(.secondary)
        }
    }

    private func nightAccessibilityLabel(for night: NightSleepData) -> String {
        let date = night.date.formatted(.dateTime.month().day())
        let total = formatDuration(night.totalSleep)
        let deep = formatDuration(night.deep)
        let core = formatDuration(night.core)
        let rem = formatDuration(night.rem)
        return String(localized: "\(date)，总睡眠 \(total)，深睡 \(deep)，浅睡 \(core)，REM \(rem)", comment: "Night row a11y")
    }

    private func loadData() async {
        isLoading = true
        fetchError = nil

        let interval = selectedRange.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")

        do {
            let result = try await service.fetchData(for: .sleepAnalysis, dateRange: interval)
            guard !Task.isCancelled else { return }

            let aggregated = SleepAggregator.aggregateByNight(dataPoints: result.dataPoints, in: interval)
            let stats = SleepAggregator.computeStatistics(from: aggregated)

            nights = aggregated
            statistics = stats
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            fetchError = error
            nights = []
            statistics = .empty
        }

        isLoading = false
    }
}

#Preview("SleepSection") {
    NavigationStack {
        ScrollView {
            SleepSection(range: .week)
                .padding()
        }
    }
}
