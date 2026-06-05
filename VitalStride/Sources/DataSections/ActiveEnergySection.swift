import Charts
import SwiftUI
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

    private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveEnergySection")

    private func displayValue(_ kcal: Double) -> Int {
        Int(energyUnit.convert(fromKcal: kcal).rounded())
    }

    var body: some View {
        DataSectionCard(
            title: String(localized: "活动能量", comment: "Active energy section"),
            systemImage: "flame.fill",
            destination: ActiveEnergyDetailView(
                range: range,
                dailyData: dailyData,
                statistics: statistics
            )
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.orange.gradient)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.formatted(.number))
                    .font(.subheadline.weight(.medium))
                Text(energyUnit.abbreviation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        let service = HealthKitService(deviceIdentifier: "ios-display")

        do {
            let result = try await service.fetchData(for: .activeEnergyBurned, dateRange: interval)
            guard !Task.isCancelled else { return }

            let aggregated = EnergyAggregator.aggregateByDay(dataPoints: result.dataPoints, in: interval)
            let stats = EnergyAggregator.computeStatistics(from: aggregated)

            dailyData = aggregated
            statistics = stats

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("render dataPoints=\(result.dataPoints.count) aggregated=\(aggregated.count) ms=\(ms)")
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
    let range: TimeRange
    let dailyData: [DailyEnergyData]
    let statistics: EnergyStatistics

    @AppStorage("energyUnit") private var energyUnit: EnergyUnit = .kcal
    @State private var selectedDate: Date?
    private let logger = Logger(subsystem: "com.vitalstride", category: "ActiveEnergySection")

    private func displayValue(_ kcal: Double) -> Int {
        Int(energyUnit.convert(fromKcal: kcal).rounded())
    }

    var body: some View {
        List {
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

            Section {
                ForEach(dailyData.reversed()) { item in
                    HStack {
                        Text(item.date, format: .dateTime.month().day().weekday())
                        Spacer()
                        Text("\(displayValue(item.totalEnergy).formatted(.number)) \(energyUnit.abbreviation)")
                            .foregroundStyle(.secondary)
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "活动能量", comment: "Active energy detail title"))
        .onAppear {
            logger.info("detail_opened range=\(range.rawValue) days=\(dailyData.count)")
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
                    .foregroundStyle(.orange.gradient)
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
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailBarOpacity(for date: Date) -> Double {
        guard let selectedDate else { return 1.0 }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate) ? 1.0 : 0.5
    }
}

#Preview("ActiveEnergySection") {
    NavigationStack {
        ScrollView {
            ActiveEnergySection(range: .week)
                .padding()
        }
    }
}
