import Charts
import HealthKitService
import SwiftUI
import VitalModels
import os

// MARK: - Models

struct DailyStepData: Identifiable, Equatable, Sendable {
    let date: Date
    let totalSteps: Int
    var id: Date { date }
}

struct StepsStatistics: Equatable, Sendable {
    let dailyAverage: Int
    let maxSingleDay: Int
    let totalSteps: Int

    static let empty = StepsStatistics(dailyAverage: 0, maxSingleDay: 0, totalSteps: 0)
}

// MARK: - Aggregator

enum StepsAggregator {
    static func aggregateByDay(
        dataPoints: [HealthDataPoint],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyStepData] {
        var dailyMap: [Date: Double] = [:]
        var current = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        while current < end {
            dailyMap[current] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        for point in dataPoints where point.sampleType == .stepCount {
            let contributions = splitAcrossDays(point: point, calendar: calendar)
            for (day, value) in contributions {
                guard dailyMap[day] != nil else { continue }
                dailyMap[day]! += value
            }
        }

        return dailyMap
            .map { DailyStepData(date: $0.key, totalSteps: Int($0.value.rounded())) }
            .sorted { $0.date < $1.date }
    }

    static func splitAcrossDays(
        point: HealthDataPoint,
        calendar: Calendar
    ) -> [(day: Date, value: Double)] {
        let startDay = calendar.startOfDay(for: point.startDate)
        let endDay = calendar.startOfDay(for: point.endDate)

        if startDay == endDay || point.startDate == point.endDate {
            return [(startDay, point.value)]
        }

        let totalDuration = point.endDate.timeIntervalSince(point.startDate)
        guard totalDuration > 0 else { return [(startDay, point.value)] }

        var results: [(day: Date, value: Double)] = []
        var dayStart = startDay

        while dayStart <= endDay {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentStart = max(point.startDate, dayStart)
            let segmentEnd = min(point.endDate, nextDay)
            let segmentDuration = segmentEnd.timeIntervalSince(segmentStart)
            if segmentDuration > 0 {
                let fraction = segmentDuration / totalDuration
                results.append((dayStart, point.value * fraction))
            }
            dayStart = nextDay
        }

        return results
    }

    static func computeStatistics(from data: [DailyStepData]) -> StepsStatistics {
        guard !data.isEmpty else { return .empty }
        let total = data.reduce(0) { $0 + $1.totalSteps }
        let maxDay = data.map(\.totalSteps).max() ?? 0
        return StepsStatistics(
            dailyAverage: total / data.count,
            maxSingleDay: maxDay,
            totalSteps: total
        )
    }
}

// MARK: - StepsSection

struct StepsSection: View {
    let range: TimeRange

    @State private var dailyData: [DailyStepData] = []
    @State private var statistics: StepsStatistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache

    private let logger = Logger(subsystem: "com.vitalstride", category: "StepsSection")

    var body: some View {
        DataSectionCard(
            title: String(localized: "步数", comment: "Steps section"),
            systemImage: "figure.walk",
            destination: StepsDetailView()
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
        } else if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                selectedDayInfo
                stepsChart
                statisticsSummary
            }
        }
    }

    @ViewBuilder
    private var selectedDayInfo: some View {
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            HStack {
                Text(day.date, format: .dateTime.month().day().weekday())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    "\(day.totalSteps.formatted(.number)) "
                        + String(localized: "步", comment: "Steps unit suffix")
                )
                .font(.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var stepsChart: some View {
        Chart {
            ForEach(dailyData) { item in
                BarMark(
                    x: .value(
                        String(localized: "日期", comment: "Date axis"),
                        item.date,
                        unit: .day
                    ),
                    y: .value(
                        String(localized: "步数", comment: "Steps axis"),
                        item.totalSteps
                    )
                )
                .foregroundStyle(.blue.gradient)
                .opacity(barOpacity(for: item.date))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis { xAxisMarks }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let steps = value.as(Int.self) {
                        Text(steps.formatted(.number.notation(.compactName)))
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 120)
        .accessibilityLabel(String(localized: "每日步数图", comment: "Steps chart a11y label"))
        .accessibilityValue(chartAccessibilityValue)
    }

    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        switch range {
        case .day:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                AxisGridLine()
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                AxisGridLine()
            }
        case .month:
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.day())
                AxisGridLine()
            }
        case .year:
            AxisMarks(values: .automatic(desiredCount: 12)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                AxisGridLine()
            }
        }
    }

    private var statisticsSummary: some View {
        HStack(spacing: 0) {
            statisticItem(
                label: String(localized: "日均", comment: "Daily average"),
                value: statistics.dailyAverage
            )
            Spacer()
            statisticItem(
                label: String(localized: "最高", comment: "Maximum single day"),
                value: statistics.maxSingleDay
            )
            Spacer()
            statisticItem(
                label: String(localized: "总计", comment: "Total steps"),
                value: statistics.totalSteps
            )
        }
    }

    private func statisticItem(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted(.number))
                .font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }

    private var chartAccessibilityValue: String {
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            return String(
                localized: "\(day.date.formatted(.dateTime.month().day())) \(day.totalSteps.formatted(.number)) 步",
                comment: "Selected day a11y value"
            )
        }
        return String(
            localized: "日均 \(statistics.dailyAverage.formatted(.number)) 步，最高 \(statistics.maxSingleDay.formatted(.number)) 步，总计 \(statistics.totalSteps.formatted(.number)) 步",
            comment: "Steps stats a11y summary"
        )
    }

    private func barOpacity(for date: Date) -> Double {
        guard let selectedDate else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate) ? 1.0 : 0.5
    }

    private func loadData() async {
        isLoading = true
        selectedDate = nil
        errorMessage = nil

        let start = ContinuousClock.now
        let interval = range.dateInterval()

        do {
            let dataPoints = try await cache.data(for: .stepCount, in: interval)
            guard !Task.isCancelled else { return }

            let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            let stats = StepsAggregator.computeStatistics(from: aggregated)

            dailyData = aggregated
            statistics = stats

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info(
                "render dataPoints=\(dataPoints.count) aggregated=\(aggregated.count) ms=\(ms)"
            )
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            errorMessage = String(localized: "无法加载步数数据", comment: "Steps load error")
            dailyData = []
            statistics = .empty
        }

        isLoading = false
    }
}

// MARK: - StepsDetailView

struct StepsDetailView: View {
    @State private var selectedRange: TimeRange = .week
    @State private var dailyData: [DailyStepData] = []
    @State private var statistics: StepsStatistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache

    private let logger = Logger(subsystem: "com.vitalstride", category: "StepsSection")

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
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    detailChart
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    statisticRow(
                        label: String(localized: "日均", comment: "Daily average"),
                        value: statistics.dailyAverage,
                        image: "chart.bar"
                    )
                    statisticRow(
                        label: String(localized: "最高", comment: "Maximum single day"),
                        value: statistics.maxSingleDay,
                        image: "arrow.up"
                    )
                    statisticRow(
                        label: String(localized: "总计", comment: "Total steps"),
                        value: statistics.totalSteps,
                        image: "sum"
                    )
                }

                AIDataAnalysisSection(sampleType: .stepCount)

                Section {
                    ForEach(dailyData.reversed()) { item in
                        HStack {
                            Text(item.date, format: .dateTime.month().day().weekday())
                            Spacer()
                            Text(
                                "\(item.totalSteps.formatted(.number)) "
                                    + String(localized: "步", comment: "Steps unit")
                            )
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(item.date.formatted(.dateTime.month().day())) \(item.totalSteps.formatted(.number)) "
                                + String(localized: "步", comment: "Steps unit")
                        )
                    }
                } header: {
                    Text("按日明细", comment: "Daily breakdown section header")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "步数", comment: "Steps detail title"))
        .task(id: selectedRange) {
            await loadData()
        }
        .onAppear {
            logger.info("detail_opened range=\(selectedRange.rawValue)")
        }
    }

    private var detailChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedDate,
               let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                HStack {
                    Text(day.date, format: .dateTime.year().month().day().weekday())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "\(day.totalSteps.formatted(.number)) "
                            + String(localized: "步", comment: "Steps unit")
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }

            Chart {
                ForEach(dailyData) { item in
                    BarMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date,
                            unit: .day
                        ),
                        y: .value(
                            String(localized: "步数", comment: "Steps axis"),
                            item.totalSteps
                        )
                    )
                    .foregroundStyle(.blue.gradient)
                    .opacity(detailBarOpacity(for: item.date))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let steps = value.as(Int.self) {
                            Text(steps.formatted(.number.notation(.compactName)))
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 250)
            .accessibilityLabel(String(localized: "每日步数图", comment: "Steps chart a11y"))
            .accessibilityValue(detailChartAccessibilityValue)
        }
        .padding()
    }

    private var detailChartAccessibilityValue: String {
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            return String(
                localized: "\(day.date.formatted(.dateTime.month().day())) \(day.totalSteps.formatted(.number)) 步",
                comment: "Selected day a11y value"
            )
        }
        return String(
            localized: "日均 \(statistics.dailyAverage.formatted(.number)) 步，最高 \(statistics.maxSingleDay.formatted(.number)) 步",
            comment: "Steps detail chart a11y summary"
        )
    }

    private func statisticRow(label: String, value: Int, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text(value.formatted(.number))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailBarOpacity(for date: Date) -> Double {
        guard let selectedDate else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate) ? 1.0 : 0.5
    }

    private func loadData() async {
        isLoading = true
        selectedDate = nil
        errorMessage = nil

        let interval = selectedRange.dateInterval()

        do {
            let dataPoints = try await cache.data(for: .stepCount, in: interval)
            guard !Task.isCancelled else { return }

            let aggregated = StepsAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            let stats = StepsAggregator.computeStatistics(from: aggregated)

            dailyData = aggregated
            statistics = stats
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            errorMessage = String(localized: "无法加载步数数据", comment: "Steps load error")
            dailyData = []
            statistics = .empty
        }

        isLoading = false
    }
}
