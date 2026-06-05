import Charts
import SwiftUI
import os

// MARK: - Models

struct WeightDataPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let weight: Double
    var id: Date { date }
}

struct WeightStatistics: Equatable, Sendable {
    let latest: Double?
    let change: Double?
    let max: Double?
    let min: Double?
}

// MARK: - Weight Analyzer

enum WeightAnalyzer {
    static func extractWeightPoints(
        from dataPoints: [HealthDataPoint],
        in interval: DateInterval
    ) -> [WeightDataPoint] {
        dataPoints
            .filter { $0.sampleType == .bodyMass && $0.startDate >= interval.start && $0.startDate < interval.end }
            .map { WeightDataPoint(date: $0.startDate, weight: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func computeStatistics(from points: [WeightDataPoint]) -> WeightStatistics {
        guard !points.isEmpty else {
            return WeightStatistics(latest: nil, change: nil, max: nil, min: nil)
        }
        let sorted = points.sorted { $0.date < $1.date }
        let latest = sorted.last?.weight
        let change: Double? = if sorted.count >= 2,
                                 let first = sorted.first?.weight,
                                 let last = sorted.last?.weight {
            last - first
        } else {
            nil
        }
        let maxVal = sorted.map(\.weight).max()
        let minVal = sorted.map(\.weight).min()
        return WeightStatistics(latest: latest, change: change, max: maxVal, min: minVal)
    }

    static func movingAverage(
        of points: [WeightDataPoint],
        windowSize: Int = 7
    ) -> [WeightDataPoint] {
        guard points.count >= 2 else { return points }
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.enumerated().map { index, point in
            let start = Swift.max(0, index - windowSize + 1)
            let window = sorted[start...index]
            let avg = window.reduce(0.0) { $0 + $1.weight } / Double(window.count)
            return WeightDataPoint(date: point.date, weight: avg)
        }
    }

    static func nearest(
        to targetDate: Date,
        in points: [WeightDataPoint]
    ) -> WeightDataPoint? {
        points.min { a, b in
            abs(a.date.timeIntervalSince(targetDate)) < abs(b.date.timeIntervalSince(targetDate))
        }
    }
}

// MARK: - BodyWeightSection

struct BodyWeightSection: View {
    let range: TimeRange

    @State private var dataPoints: [WeightDataPoint] = []
    @State private var trendPoints: [WeightDataPoint] = []
    @State private var statistics: WeightStatistics = WeightStatistics(latest: nil, change: nil, max: nil, min: nil)
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let logger = Logger(subsystem: "com.vitalstride", category: "BodyWeightSection")

    var body: some View {
        DataSectionCard(
            title: String(localized: "体重", comment: "Body weight section"),
            systemImage: "scalemass.fill",
            destination: BodyWeightDetailView(
                range: range,
                dataPoints: dataPoints,
                trendPoints: trendPoints,
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
        } else if fetchError != nil {
            VStack(spacing: 4) {
                Image(systemName: "scalemass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "无法加载体重数据", comment: "Body weight load error"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        } else if dataPoints.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "scalemass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(String(localized: "暂无体重数据", comment: "No body weight data"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        } else {
            BodyWeightChartView(
                dataPoints: dataPoints,
                trendPoints: trendPoints,
                range: range,
                compact: true
            )
            .frame(height: 120)
            statsSummary
        }
    }

    private var statsSummary: some View {
        HStack {
            if let latest = statistics.latest {
                StatItemDouble(
                    label: String(localized: "最新", comment: "Latest weight"),
                    value: latest,
                    unit: String(localized: "kg", comment: "Kilogram unit")
                )
            }
            Spacer()
            if let change = statistics.change {
                StatItemDouble(
                    label: String(localized: "变化", comment: "Weight change"),
                    value: change,
                    unit: String(localized: "kg", comment: "Kilogram unit"),
                    showSign: true
                )
            }
            Spacer()
            if let maxVal = statistics.max {
                StatItemDouble(
                    label: String(localized: "最高", comment: "Maximum weight"),
                    value: maxVal,
                    unit: String(localized: "kg", comment: "Kilogram unit")
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    private var statsAccessibilityLabel: String {
        var parts: [String] = []
        if let latest = statistics.latest {
            parts.append(String(localized: "最新体重 \(formatted(latest)) 公斤", comment: "Latest weight a11y"))
        }
        if let change = statistics.change {
            let sign = change >= 0 ? "+" : ""
            parts.append(String(localized: "变化 \(sign)\(formatted(change)) 公斤", comment: "Weight change a11y"))
        }
        if let maxVal = statistics.max {
            parts.append(String(localized: "最高 \(formatted(maxVal)) 公斤", comment: "Max weight a11y"))
        }
        return parts.joined(separator: ", ")
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func loadData() async {
        isLoading = true
        fetchError = nil
        let start = ContinuousClock.now
        let interval = range.dateInterval()
        let service = HealthKitService(deviceIdentifier: "ios-display")

        do {
            let result = try await service.fetchData(for: .bodyMass, dateRange: interval)
            guard !Task.isCancelled else { return }

            let points = WeightAnalyzer.extractWeightPoints(from: result.dataPoints, in: interval)
            let trend = WeightAnalyzer.movingAverage(of: points)
            let stats = WeightAnalyzer.computeStatistics(from: points)

            dataPoints = points
            trendPoints = trend
            statistics = stats

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("render dataPoints=\(points.count) ms=\(ms) range=\(range.rawValue)")
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("loadData failed: \(error.localizedDescription)")
            fetchError = error
            dataPoints = []
            trendPoints = []
            statistics = WeightStatistics(latest: nil, change: nil, max: nil, min: nil)
        }

        isLoading = false
    }
}

// MARK: - Stat Item (Double)

private struct StatItemDouble: View {
    let label: String
    let value: Double
    let unit: String
    var showSign: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formattedValue)
                .font(.headline)
                .foregroundStyle(showSign ? (value >= 0 ? .red : .green) : .primary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedValue: String {
        let formatted = value.formatted(.number.precision(.fractionLength(1)))
        if showSign && value > 0 {
            return "+\(formatted)"
        }
        return formatted
    }
}

// MARK: - Body Weight Chart

struct BodyWeightChartView: View {
    let dataPoints: [WeightDataPoint]
    let trendPoints: [WeightDataPoint]
    let range: TimeRange
    let compact: Bool

    @State private var selectedDate: Date?

    private var selectedPoint: WeightDataPoint? {
        guard let selectedDate else { return nil }
        return WeightAnalyzer.nearest(to: selectedDate, in: dataPoints)
    }

    var body: some View {
        Chart {
            ForEach(trendPoints) { point in
                LineMark(
                    x: .value(
                        String(localized: "日期", comment: "Date axis"),
                        point.date
                    ),
                    y: .value(
                        String(localized: "趋势", comment: "Trend axis"),
                        point.weight
                    )
                )
                .foregroundStyle(.green.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .symbol(.circle)
            .symbolSize(0)

            ForEach(dataPoints) { point in
                LineMark(
                    x: .value(
                        String(localized: "日期", comment: "Date axis"),
                        point.date
                    ),
                    y: .value(
                        String(localized: "体重", comment: "Weight axis"),
                        point.weight
                    )
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .symbol(.circle)
            .symbolSize(compact ? 20 : 30)

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit, y: .disabled)
                    ) {
                        selectionAnnotation(for: selectedPoint)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 4 : 6)) { _ in
                AxisValueLabel(format: xAxisFormat)
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(kg.formatted(.number.precision(.fractionLength(1))))
                    }
                }
                AxisGridLine()
            }
        }
        .accessibilityLabel(String(localized: "体重变化趋势图", comment: "Weight chart a11y"))
        .accessibilityValue(chartAccessibilityValue)
    }

    private func selectionAnnotation(for point: WeightDataPoint) -> some View {
        VStack(spacing: 2) {
            Text(point.weight.formatted(.number.precision(.fractionLength(1))))
                .font(.caption.bold())
            Text(String(localized: "kg", comment: "Kilogram"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(point.date.formatted(.dateTime.month().day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(
            String(localized: "体重 \(point.weight.formatted(.number.precision(.fractionLength(1)))) 公斤，\(point.date.formatted(.dateTime.month().day()))", comment: "Selected weight a11y")
        )
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
        guard !dataPoints.isEmpty else {
            return String(localized: "无数据", comment: "No data a11y")
        }
        if let latest = dataPoints.last {
            return String(localized: "最新体重 \(latest.weight.formatted(.number.precision(.fractionLength(1)))) 公斤", comment: "Chart weight a11y")
        }
        return ""
    }
}

// MARK: - Body Weight Detail View

struct BodyWeightDetailView: View {
    let range: TimeRange
    let dataPoints: [WeightDataPoint]
    let trendPoints: [WeightDataPoint]
    let statistics: WeightStatistics

    private let logger = Logger(subsystem: "com.vitalstride", category: "BodyWeightDetail")

    var body: some View {
        List {
            Section {
                BodyWeightChartView(
                    dataPoints: dataPoints,
                    trendPoints: trendPoints,
                    range: range,
                    compact: false
                )
                .frame(height: 250)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                if let latest = statistics.latest {
                    detailStatRow(
                        label: String(localized: "最新", comment: "Latest"),
                        value: formatted(latest),
                        image: "scalemass"
                    )
                }
                if let change = statistics.change {
                    detailStatRow(
                        label: String(localized: "变化", comment: "Change"),
                        value: (change >= 0 ? "+" : "") + formatted(change),
                        image: change >= 0 ? "arrow.up" : "arrow.down"
                    )
                }
                if let maxVal = statistics.max {
                    detailStatRow(
                        label: String(localized: "最高", comment: "Maximum"),
                        value: formatted(maxVal),
                        image: "arrow.up"
                    )
                }
                if let minVal = statistics.min {
                    detailStatRow(
                        label: String(localized: "最低", comment: "Minimum"),
                        value: formatted(minVal),
                        image: "arrow.down"
                    )
                }
            }

            Section {
                ForEach(dataPoints.reversed()) { point in
                    HStack {
                        Text(point.date, format: .dateTime.month().day().weekday())
                        Spacer()
                        Text(
                            "\(point.weight.formatted(.number.precision(.fractionLength(1)))) "
                                + String(localized: "kg", comment: "Kilogram")
                        )
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(point.date.formatted(.dateTime.month().day())) \(point.weight.formatted(.number.precision(.fractionLength(1)))) "
                            + String(localized: "公斤", comment: "Kilogram a11y")
                    )
                }
            } header: {
                Text("体重记录", comment: "Weight records header")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "体重", comment: "Body weight detail title"))
        .onAppear {
            logger.info("detail_opened range=\(range.rawValue) points=\(dataPoints.count)")
        }
    }

    private func detailStatRow(label: String, value: String, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text("\(value) " + String(localized: "kg", comment: "Kilogram"))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

#Preview("BodyWeightSection") {
    NavigationStack {
        ScrollView {
            BodyWeightSection(range: .month)
                .padding()
        }
    }
}
