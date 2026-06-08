import Charts
import HealthKitService
import SwiftUI
import VitalModels
import os

// MARK: - Generic Aggregator

enum GenericHealthAggregator {

    struct DailyData: Identifiable, Equatable, Sendable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    struct Statistics: Equatable, Sendable {
        let average: Double
        let max: Double
        let min: Double
        let total: Double

        static let empty = Statistics(average: 0, max: 0, min: 0, total: 0)
    }

    static func aggregateCumulative(
        dataPoints: [HealthDataPoint],
        sampleType: HealthSampleType,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyData] {
        var dailyMap: [Date: Double] = [:]
        var current = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        while current < end {
            dailyMap[current] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        for point in dataPoints where point.sampleType == sampleType {
            let startDay = calendar.startOfDay(for: point.startDate)
            let endDay = calendar.startOfDay(for: point.endDate)

            if startDay == endDay || point.startDate == point.endDate {
                guard dailyMap[startDay] != nil else { continue }
                dailyMap[startDay]! += point.value
            } else {
                let totalDuration = point.endDate.timeIntervalSince(point.startDate)
                guard totalDuration > 0 else { continue }
                var dayStart = startDay
                while dayStart <= endDay {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                    let segStart = max(point.startDate, dayStart)
                    let segEnd = min(point.endDate, nextDay)
                    let segDuration = segEnd.timeIntervalSince(segStart)
                    if segDuration > 0, dailyMap[dayStart] != nil {
                        dailyMap[dayStart]! += point.value * (segDuration / totalDuration)
                    }
                    dayStart = nextDay
                }
            }
        }

        return dailyMap
            .map { DailyData(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func aggregateDiscrete(
        dataPoints: [HealthDataPoint],
        sampleType: HealthSampleType,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyData] {
        let filtered = dataPoints.filter {
            $0.sampleType == sampleType && $0.startDate >= interval.start && $0.startDate < interval.end
        }

        let grouped = Dictionary(grouping: filtered) {
            calendar.startOfDay(for: $0.startDate)
        }

        return grouped.map { (day, points) in
            let avg = points.reduce(0.0) { $0 + $1.value } / Double(points.count)
            return DailyData(date: day, value: avg)
        }
        .sorted { $0.date < $1.date }
    }

    static func computeStatistics(from data: [DailyData]) -> Statistics {
        guard !data.isEmpty else { return .empty }
        let values = data.map(\.value)
        let total = values.reduce(0, +)
        return Statistics(
            average: total / Double(data.count),
            max: values.max() ?? 0,
            min: values.min() ?? 0,
            total: total
        )
    }
}

// MARK: - GenericHealthDetailView

struct GenericHealthDetailView: View {
    let sampleType: HealthSampleType

    @State private var selectedRange: TimeRange = .week
    @State private var dailyData: [GenericHealthAggregator.DailyData] = []
    @State private var statistics: GenericHealthAggregator.Statistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache

    private let logger = Logger(subsystem: "com.vitalstride", category: "GenericHealthDetail")

    var body: some View {
        List {
            timeRangeSection
            if isLoading {
                loadingSection
            } else if let errorMessage {
                errorSection(errorMessage)
            } else if dailyData.isEmpty {
                emptySection
            } else {
                chartSection
                statsSection
                dailyBreakdownSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(sampleType.localizedName)
        .task(id: selectedRange) {
            await loadData()
        }
    }

    // MARK: - Sections

    private var timeRangeSection: some View {
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
    }

    private var loadingSection: some View {
        Section {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
        }
        .listRowBackground(Color.clear)
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        }
        .listRowBackground(Color.clear)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 4) {
                Image(systemName: sampleType.systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(String(localized: "暂无数据", comment: "No data available"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        }
        .listRowBackground(Color.clear)
    }

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                selectedDayInfo
                chart
            }
            .padding()
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var selectedDayInfo: some View {
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            HStack {
                Text(day.date, format: .dateTime.year().month().day().weekday())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formattedValue(day.value)) \(sampleType.unitLabel)")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(dailyData) { item in
                if sampleType.aggregationMode == .cumulative {
                    BarMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date,
                            unit: .day
                        ),
                        y: .value(sampleType.localizedName, item.value)
                    )
                    .foregroundStyle(sampleType.chartColor.gradient)
                    .opacity(barOpacity(for: item.date))
                } else {
                    LineMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date
                        ),
                        y: .value(sampleType.localizedName, item.value)
                    )
                    .foregroundStyle(sampleType.chartColor)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date
                        ),
                        y: .value(sampleType.localizedName, item.value)
                    )
                    .foregroundStyle(sampleType.chartColor)
                    .symbolSize(20)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisValueLabel(format: xAxisFormat)
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formattedValue(v))
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 250)
        .accessibilityLabel(
            String(localized: "\(sampleType.localizedName)，\(selectedRange.localizedLabel)趋势图",
                   comment: "Chart a11y label")
        )
    }

    private var statsSection: some View {
        Section {
            statRow(
                label: String(localized: "平均", comment: "Average"),
                value: formattedValue(statistics.average),
                image: "chart.bar"
            )
            statRow(
                label: String(localized: "最高", comment: "Maximum"),
                value: formattedValue(statistics.max),
                image: "arrow.up"
            )
            statRow(
                label: String(localized: "最低", comment: "Minimum"),
                value: formattedValue(statistics.min),
                image: "arrow.down"
            )
        }
    }

    private var dailyBreakdownSection: some View {
        Section {
            ForEach(dailyData.reversed()) { item in
                HStack {
                    Text(item.date, format: .dateTime.month().day().weekday())
                    Spacer()
                    Text("\(formattedValue(item.value)) \(sampleType.unitLabel)")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(item.date.formatted(.dateTime.month().day())) \(formattedValue(item.value)) \(sampleType.unitLabel)"
                )
            }
        } header: {
            Text("按日明细", comment: "Daily breakdown section header")
        }
    }

    // MARK: - Helpers

    private func statRow(label: String, value: String, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text("\(value) \(sampleType.unitLabel)")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(sampleType.unitLabel)")
    }

    private func formattedValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(sampleType.fractionDigits)))
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated)
        }
    }

    private func barOpacity(for date: Date) -> Double {
        guard let selectedDate else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate) ? 1.0 : 0.5
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        selectedDate = nil
        errorMessage = nil

        let interval = selectedRange.dateInterval()

        do {
            let dataPoints = try await cache.data(for: sampleType, in: interval)
            guard !Task.isCancelled else { return }

            let aggregated: [GenericHealthAggregator.DailyData]
            switch sampleType.aggregationMode {
            case .cumulative:
                aggregated = GenericHealthAggregator.aggregateCumulative(
                    dataPoints: dataPoints, sampleType: sampleType, in: interval
                )
            case .discrete:
                aggregated = GenericHealthAggregator.aggregateDiscrete(
                    dataPoints: dataPoints, sampleType: sampleType, in: interval
                )
            }

            let stats = GenericHealthAggregator.computeStatistics(from: aggregated)
            dailyData = aggregated
            statistics = stats
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("load failed type=\(sampleType.rawValue) error=\(error.localizedDescription)")
            errorMessage = String(
                localized: "无法加载\(sampleType.localizedName)数据",
                comment: "Generic data load error"
            )
            dailyData = []
            statistics = .empty
        }

        isLoading = false
    }
}
