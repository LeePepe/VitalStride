import Charts
import DesignKit
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

// MARK: - Health Detail Window Helper (testable)

/// Pure helpers for horizontal time-window navigation on the health detail chart.
///
/// The chart's window is anchored to a single reference date (`anchor`). Given a
/// `TimeRange`, the visible interval is `TimeRange.dateInterval(from: anchor)`
/// (an inclusive-of-anchor-day, half-open interval ending at the day after
/// `anchor`). Shifting the window moves `anchor` by the range granularity, and
/// the anchor is clamped so the window never extends beyond today.
enum HealthDetailWindow {

    /// Direction of a shift. `+1` moves forward in time (toward today), `-1` moves back.
    enum Direction: Int, Sendable {
        case backward = -1
        case forward = 1
    }

    /// Shift the anchor by exactly one window worth of the given range.
    ///
    /// Day → ±1 day, Week → ±7 days, Month → ±1 month. `.year` returns `anchor`
    /// unchanged (the year range is intentionally non-scrollable per MY-1248).
    /// The returned anchor is always clamped to `<= today`.
    static func shift(
        anchor: Date,
        by direction: Direction,
        range: TimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let step = direction.rawValue
        let shifted: Date? = {
            switch range {
            case .day:
                return calendar.date(byAdding: .day, value: step, to: anchor)
            case .week:
                return calendar.date(byAdding: .day, value: 7 * step, to: anchor)
            case .month:
                return calendar.date(byAdding: .month, value: step, to: anchor)
            case .year:
                return anchor
            }
        }()
        return clampedAnchor(shifted ?? anchor, now: now, calendar: calendar)
    }

    /// Whether the window can move forward in time from `anchor`.
    ///
    /// Returns `false` when the current window already ends at today (or the
    /// range is `.year`, which is intentionally non-scrollable).
    static func canGoForward(
        anchor: Date,
        range: TimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard range != .year else { return false }
        let today = calendar.startOfDay(for: now)
        return calendar.startOfDay(for: anchor) < today
    }

    /// Whether the window can move backward in time from `anchor`.
    ///
    /// Always `true` for day/week/month; `false` for `.year`.
    static func canGoBackward(anchor _: Date, range: TimeRange) -> Bool {
        range != .year
    }

    /// Clamp the anchor to today's start-of-day (never allow future anchors).
    static func clampedAnchor(_ anchor: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let anchorDay = calendar.startOfDay(for: anchor)
        return anchorDay > today ? today : anchorDay
    }
}

// MARK: - GenericHealthDetailView

struct GenericHealthDetailView: View {
    let sampleType: HealthSampleType

    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .km
    @State private var selectedRange: TimeRange = .week
    @State private var windowAnchor: Date = Date()
    @State private var dailyData: [GenericHealthAggregator.DailyData] = []
    @State private var statistics: GenericHealthAggregator.Statistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    private let logger = Logger(subsystem: "com.vitalstride", category: "GenericHealthDetail")

    private var isDistanceSampleType: Bool {
        sampleType == .distanceWalkingRunning || sampleType == .distanceCycling
    }

    private func convertedValue(_ value: Double) -> Double {
        guard isDistanceSampleType else { return value }
        return distanceUnit.convert(fromKilometers: value)
    }

    private var displayUnitLabel: String {
        guard isDistanceSampleType else { return sampleType.unitLabel }
        return distanceUnit.abbreviation
    }

    var body: some View {
        List {
            timeRangeSection
            if selectedRange != .year {
                windowNavigatorSection
            }
            if isLoading {
                loadingSection
            } else if let errorMessage {
                errorSection(errorMessage)
            } else if dailyData.isEmpty {
                emptySection
            } else {
                chartSection
                statsSection
                AIDataAnalysisSection(sampleType: sampleType)
                dailyBreakdownSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(sampleType.localizedName)
        .task(id: TaskKey(range: selectedRange, anchor: windowAnchor)) {
            await loadData()
        }
        .onChange(of: selectedRange) { _, _ in
            windowAnchor = Date()
        }
    }

    // MARK: - Task key

    private struct TaskKey: Equatable {
        let range: TimeRange
        let anchor: Date
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
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)
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
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)
                Text(String(localized: "暂无数据", comment: "No data available"))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)
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
                    #if os(iOS)
                    .gesture(chartSwipeGesture)
                    #endif
            }
            .padding()
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var windowNavigatorSection: some View {
        Section {
            windowNavigator
                .padding(.horizontal)
                #if os(iOS)
                .contentShape(Rectangle())
                .gesture(chartSwipeGesture)
                #endif
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var windowRangeText: String {
        let interval = windowInterval
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        switch selectedRange {
        case .day:
            return interval.start.formatted(.dateTime.year().month().day())
        case .week, .month:
            return "\(interval.start.formatted(.dateTime.month().day())) – \(lastDay.formatted(.dateTime.month().day()))"
        case .year:
            return "\(interval.start.formatted(.dateTime.year().month())) – \(lastDay.formatted(.dateTime.year().month()))"
        }
    }

    private var windowNavigator: some View {
        let canPrev = HealthDetailWindow.canGoBackward(anchor: windowAnchor, range: selectedRange)
        let canNext = HealthDetailWindow.canGoForward(anchor: windowAnchor, range: selectedRange)
        return HStack {
            Button {
                shiftWindow(.backward)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)
            .accessibilityLabel(String(
                localized: "health_detail.window.previous",
                defaultValue: "Previous window",
                comment: "Health detail: shift chart window one range earlier"
            ))
            Spacer()
            Text(windowRangeText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.neutrals.text1)
                .accessibilityLabel(
                    String(
                        format: String(
                            localized: "health_detail.window.range_a11y %@",
                            defaultValue: "Current range %@",
                            comment: "Health detail: current chart window range (VoiceOver)"
                        ),
                        windowRangeText
                    )
                )
            Spacer()
            Button {
                shiftWindow(.forward)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canNext)
            .accessibilityLabel(String(
                localized: "health_detail.window.next",
                defaultValue: "Next window",
                comment: "Health detail: shift chart window one range later"
            ))
        }
    }

    #if os(iOS)
    private var chartSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard selectedRange != .year else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5 else { return }
                if horizontal < -40 {
                    // Swipe left → move window forward in time (toward today)
                    shiftWindow(.forward)
                } else if horizontal > 40 {
                    // Swipe right → move window backward in time
                    shiftWindow(.backward)
                }
            }
    }
    #endif

    private func shiftWindow(_ direction: HealthDetailWindow.Direction) {
        let next = HealthDetailWindow.shift(anchor: windowAnchor, by: direction, range: selectedRange)
        guard next != windowAnchor else { return }
        selectedDate = nil
        windowAnchor = next
    }

    @ViewBuilder
    private var selectedDayInfo: some View {
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            HStack {
                Text(day.date, format: .dateTime.year().month().day().weekday())
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                Spacer()
                Text("\(formattedValue(convertedValue(day.value))) \(displayUnitLabel)")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(dailyData) { item in
                let displayVal = convertedValue(item.value)
                if sampleType.aggregationMode == .cumulative {
                    BarMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date,
                            unit: .day
                        ),
                        y: .value(sampleType.localizedName, displayVal)
                    )
                    .foregroundStyle(theme.chart(0).gradient)
                    .opacity(barOpacity(for: item.date))
                } else {
                    LineMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date,
                            unit: .day
                        ),
                        y: .value(sampleType.localizedName, displayVal)
                    )
                    .foregroundStyle(theme.chart(0))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(
                            String(localized: "日期", comment: "Date axis"),
                            item.date,
                            unit: .day
                        ),
                        y: .value(sampleType.localizedName, displayVal)
                    )
                    .foregroundStyle(theme.chart(0))
                    .symbolSize(20)
                }
            }
        }
        .chartYScale(domain: chartYDomain)
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
                value: formattedValue(convertedValue(statistics.average)),
                image: "chart.bar"
            )
            statRow(
                label: String(localized: "最高", comment: "Maximum"),
                value: formattedValue(convertedValue(statistics.max)),
                image: "arrow.up"
            )
            statRow(
                label: String(localized: "最低", comment: "Minimum"),
                value: formattedValue(convertedValue(statistics.min)),
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
                    Text("\(formattedValue(convertedValue(item.value))) \(displayUnitLabel)")
                        .foregroundStyle(theme.neutrals.text2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(item.date.formatted(.dateTime.month().day())) \(formattedValue(convertedValue(item.value))) \(displayUnitLabel)"
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
            Text("\(value) \(displayUnitLabel)")
                .foregroundStyle(theme.neutrals.text2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(displayUnitLabel)")
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

    private var chartYDomain: ClosedRange<Double> {
        let values = dailyData.map { convertedValue($0.value) }
        guard let minVal = values.min(), let maxVal = values.max() else {
            return 0...1
        }

        if sampleType.aggregationMode == .discrete {
            if minVal < maxVal {
                let range = maxVal - minVal
                let padding = max(range * 0.15, maxVal * 0.02)
                let lower = max(0, minVal - padding)
                return lower...(maxVal + padding)
            } else {
                let padding = max(minVal * 0.15, 1)
                let lower = max(0, minVal - padding)
                return lower...(minVal + padding)
            }
        } else {
            return 0...max(maxVal, 1)
        }
    }

    private func barOpacity(for date: Date) -> Double {
        guard let selectedDate else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate) ? 1.0 : 0.5
    }

    // MARK: - Data Loading

    private var windowInterval: DateInterval {
        selectedRange.dateInterval(from: windowAnchor)
    }

    private func loadData() async {
        isLoading = true
        selectedDate = nil
        errorMessage = nil

        let interval = windowInterval

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
