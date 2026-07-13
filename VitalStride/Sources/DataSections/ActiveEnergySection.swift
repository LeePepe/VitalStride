import Charts
import DesignKit
import HealthKitService
import SwiftUI
import VitalModels
import os

// MARK: - Models

struct DailyEnergyData: Identifiable, Equatable, Sendable {
    let date: Date
    let totalEnergy: Double
    var id: Date { date }
}

struct EnergyStatistics: Equatable, Sendable {
    let dailyAverage: Double
    let maxSingleDay: Double
    let totalEnergy: Double

    static let empty = EnergyStatistics(dailyAverage: 0, maxSingleDay: 0, totalEnergy: 0)
}

// MARK: - Energy Aggregator

enum EnergyAggregator {
    static func aggregateByDay(
        dataPoints: [HealthDataPoint],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DailyEnergyData] {
        var dailyMap: [Date: Double] = [:]
        var current = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        while current < end {
            dailyMap[current] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        for point in dataPoints where point.sampleType == .activeEnergyBurned {
            let contributions = splitAcrossDays(point: point, calendar: calendar)
            for (day, value) in contributions {
                guard dailyMap[day] != nil else { continue }
                dailyMap[day]! += value
            }
        }

        return dailyMap
            .map { DailyEnergyData(date: $0.key, totalEnergy: $0.value) }
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

    static func computeStatistics(from data: [DailyEnergyData]) -> EnergyStatistics {
        guard !data.isEmpty else { return .empty }
        let total = data.reduce(0.0) { $0 + $1.totalEnergy }
        let maxDay = data.map(\.totalEnergy).max() ?? 0
        return EnergyStatistics(
            dailyAverage: total / Double(data.count),
            maxSingleDay: maxDay,
            totalEnergy: total
        )
    }
}

// MARK: - ActiveEnergySection

struct ActiveEnergySection: View {
    let range: TimeRange

    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal
    @State private var dailyData: [DailyEnergyData] = []
    @State private var statistics: EnergyStatistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme

    private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveEnergySection")

    private func displayValue(_ kcal: Double) -> Int {
        Int(energyUnit.convert(fromKcal: kcal).rounded())
    }

    var body: some View {
        DataSectionCard(
            title: String(localized: "活动能量", comment: "Active energy section"),
            systemImage: "flame.fill",
            destination: ActiveEnergyDetailView()
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
                .foregroundStyle(theme.neutrals.text2)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                selectedDayInfo
                energyChart
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
                    .foregroundStyle(theme.neutrals.text2)
                Spacer()
                Text("\(displayValue(day.totalEnergy).formatted(.number)) \(energyUnit.abbreviation)")
                    .font(.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var energyChart: some View {
        Chart {
            ForEach(dailyData) { item in
                BarMark(
                    x: .value(
                        String(localized: "日期", comment: "Date axis"),
                        item.date,
                        unit: .day
                    ),
                    y: .value(
                        String(localized: "能量", comment: "Energy axis"),
                        energyUnit.convert(fromKcal: item.totalEnergy)
                    )
                )
                .foregroundStyle(theme.chart(0).gradient)
                .opacity(barOpacity(for: item.date))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis { xAxisMarks }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(v.formatted(.number.notation(.compactName)))
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 120)
        .accessibilityLabel(String(localized: "每日活动能量图", comment: "Energy chart a11y label"))
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
                value: displayValue(statistics.dailyAverage)
            )
            Spacer()
            statisticItem(
                label: String(localized: "最高", comment: "Maximum single day"),
                value: displayValue(statistics.maxSingleDay)
            )
            Spacer()
            statisticItem(
                label: String(localized: "总计", comment: "Total energy"),
                value: displayValue(statistics.totalEnergy)
            )
        }
    }

    private func statisticItem(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.formatted(.number))
                    .font(TypeScale.title)
                Text(energyUnit.abbreviation)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chartAccessibilityValue: String {
        let unitName = energyUnit.accessibilityName
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            let formatted = displayValue(day.totalEnergy).formatted(.number)
            return String(
                localized: "\(day.date.formatted(.dateTime.month().day())) \(formatted) \(unitName)",
                comment: "Selected day a11y value"
            )
        }
        let avg = displayValue(statistics.dailyAverage).formatted(.number)
        let max = displayValue(statistics.maxSingleDay).formatted(.number)
        let total = displayValue(statistics.totalEnergy).formatted(.number)
        return String(
            localized: "日均 \(avg) \(unitName)，最高 \(max) \(unitName)，总计 \(total) \(unitName)",
            comment: "Energy stats a11y summary"
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
            let dataPoints = try await cache.data(for: .activeEnergyBurned, in: interval)
            guard !Task.isCancelled else { return }

            let aggregated = EnergyAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            let stats = EnergyAggregator.computeStatistics(from: aggregated)

            dailyData = aggregated
            statistics = stats

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("render dataPoints=\(dataPoints.count) aggregated=\(aggregated.count) ms=\(ms)")
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            errorMessage = String(localized: "无法加载活动能量数据", comment: "Energy load error")
            dailyData = []
            statistics = .empty
        }

        isLoading = false
    }
}

// MARK: - ActiveEnergyDetailView

struct ActiveEnergyDetailView: View {
    @State private var selectedRange: TimeRange = .week
    @State private var dailyData: [DailyEnergyData] = []
    @State private var statistics: EnergyStatistics = .empty
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal
    @Environment(\.healthDataCache) private var cache
    @Environment(\.theme) private var theme
    private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveEnergySection")

    private func displayValue(_ kcal: Double) -> Int {
        Int(energyUnit.convert(fromKcal: kcal).rounded())
    }

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
                        .foregroundStyle(theme.neutrals.text2)
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
                        value: displayValue(statistics.dailyAverage),
                        image: "chart.bar"
                    )
                    statisticRow(
                        label: String(localized: "最高", comment: "Maximum single day"),
                        value: displayValue(statistics.maxSingleDay),
                        image: "arrow.up"
                    )
                    statisticRow(
                        label: String(localized: "总计", comment: "Total energy"),
                        value: displayValue(statistics.totalEnergy),
                        image: "sum"
                    )
                }

                AIDataAnalysisSection(sampleType: .activeEnergyBurned)

                Section {
                    ForEach(dailyData.reversed()) { item in
                        HStack {
                            Text(item.date, format: .dateTime.month().day().weekday())
                            Spacer()
                            Text("\(displayValue(item.totalEnergy).formatted(.number)) \(energyUnit.abbreviation)")
                                .foregroundStyle(theme.neutrals.text2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(item.date.formatted(.dateTime.month().day())) \(displayValue(item.totalEnergy).formatted(.number)) \(energyUnit.accessibilityName)"
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
        .navigationTitle(String(localized: "活动能量", comment: "Active energy detail title"))
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
                        .foregroundStyle(theme.neutrals.text2)
                    Spacer()
                    Text("\(displayValue(day.totalEnergy).formatted(.number)) \(energyUnit.abbreviation)")
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
                            String(localized: "能量", comment: "Energy axis"),
                            energyUnit.convert(fromKcal: item.totalEnergy)
                        )
                    )
                    .foregroundStyle(theme.chart(0).gradient)
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
                        if let v = value.as(Int.self) {
                            Text(v.formatted(.number.notation(.compactName)))
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 250)
            .accessibilityLabel(String(localized: "每日活动能量图", comment: "Energy chart a11y"))
            .accessibilityValue(detailChartAccessibilityValue)
        }
        .padding()
    }

    private var detailChartAccessibilityValue: String {
        let unitName = energyUnit.accessibilityName
        if let selectedDate,
           let day = dailyData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
            let formatted = displayValue(day.totalEnergy).formatted(.number)
            return String(
                localized: "\(day.date.formatted(.dateTime.month().day())) \(formatted) \(unitName)",
                comment: "Detail selected day a11y value"
            )
        }
        let avg = displayValue(statistics.dailyAverage).formatted(.number)
        let max = displayValue(statistics.maxSingleDay).formatted(.number)
        let total = displayValue(statistics.totalEnergy).formatted(.number)
        return String(
            localized: "日均 \(avg) \(unitName)，最高 \(max) \(unitName)，总计 \(total) \(unitName)",
            comment: "Detail energy stats a11y summary"
        )
    }

    private func statisticRow(label: String, value: Int, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text("\(value.formatted(.number)) \(energyUnit.abbreviation)")
                .foregroundStyle(theme.neutrals.text2)
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
            let dataPoints = try await cache.data(for: .activeEnergyBurned, in: interval)
            guard !Task.isCancelled else { return }

            let aggregated = EnergyAggregator.aggregateByDay(dataPoints: dataPoints, in: interval)
            let stats = EnergyAggregator.computeStatistics(from: aggregated)

            dailyData = aggregated
            statistics = stats
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            errorMessage = String(localized: "无法加载活动能量数据", comment: "Energy load error")
            dailyData = []
            statistics = .empty
        }

        isLoading = false
    }
}

#Preview("ActiveEnergySection") {
    NavigationStack {
        ScrollView {
            ActiveEnergySection(range: .week)
                .padding()
        }
    }
    .designThemePreview()
}
