import Charts
import HealthKit
import SwiftUI
import os

// MARK: - Heart Rate Statistics

enum HeartRateStats {
    static func average(of dataPoints: [HealthDataPoint]) -> Double? {
        guard !dataPoints.isEmpty else { return nil }
        let sum = dataPoints.reduce(0.0) { $0 + $1.value }
        return sum / Double(dataPoints.count)
    }

    static func max(of dataPoints: [HealthDataPoint]) -> Double? {
        dataPoints.map(\.value).max()
    }

    static func min(of dataPoints: [HealthDataPoint]) -> Double? {
        dataPoints.map(\.value).min()
    }

    static func filtered(
        _ dataPoints: [HealthDataPoint],
        in dateInterval: DateInterval
    ) -> [HealthDataPoint] {
        dataPoints.filter { point in
            point.startDate >= dateInterval.start && point.startDate < dateInterval.end
        }
    }

    static func nearest(
        to targetDate: Date,
        in dataPoints: [HealthDataPoint]
    ) -> HealthDataPoint? {
        dataPoints.min { a, b in
            abs(a.startDate.timeIntervalSince(targetDate)) < abs(b.startDate.timeIntervalSince(targetDate))
        }
    }
}

// MARK: - Heart Rate Section

struct HeartRateSection: View {
    let range: TimeRange

    @State private var dataPoints: [HealthDataPoint] = []
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let service: HealthKitService
    private let logger = Logger(subsystem: "com.vitalstride", category: "HeartRateSection")

    init(range: TimeRange) {
        self.range = range
        #if os(iOS)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceID = Host.current().localizedName ?? UUID().uuidString
        #endif
        self.service = HealthKitService(deviceIdentifier: deviceID)
    }

    private var filteredPoints: [HealthDataPoint] {
        let interval = range.dateInterval()
        return HeartRateStats.filtered(dataPoints, in: interval)
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        DataSectionCard(
            title: String(localized: "心率", comment: "Heart rate section"),
            systemImage: "heart.fill",
            destination: HeartRateDetailView(
                range: range,
                dataPoints: filteredPoints
            )
        ) {
            content
        }
        .task(id: range) {
            await fetchData()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(height: 120)
                .frame(maxWidth: .infinity)
        } else if let fetchError {
            errorView(fetchError)
        } else if filteredPoints.isEmpty {
            emptyView
        } else {
            HeartRateChartView(dataPoints: filteredPoints, range: range, compact: true)
                .frame(height: 120)
            statsSummary
        }
    }

    private func errorView(_ error: any Error) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(String(localized: "无法加载心率数据", comment: "Heart rate load error"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.text.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(String(localized: "暂无心率数据", comment: "No heart rate data"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    private var statsSummary: some View {
        HStack {
            if let avg = HeartRateStats.average(of: filteredPoints) {
                StatItem(
                    label: String(localized: "平均", comment: "Average heart rate"),
                    value: Int(avg.rounded()),
                    unit: String(localized: "BPM", comment: "Beats per minute")
                )
            }
            Spacer()
            if let maxVal = HeartRateStats.max(of: filteredPoints) {
                StatItem(
                    label: String(localized: "最高", comment: "Maximum heart rate"),
                    value: Int(maxVal.rounded()),
                    unit: String(localized: "BPM", comment: "Beats per minute")
                )
            }
            Spacer()
            if let minVal = HeartRateStats.min(of: filteredPoints) {
                StatItem(
                    label: String(localized: "最低", comment: "Minimum heart rate"),
                    value: Int(minVal.rounded()),
                    unit: String(localized: "BPM", comment: "Beats per minute")
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    private var statsAccessibilityLabel: String {
        var parts: [String] = []
        if let avg = HeartRateStats.average(of: filteredPoints) {
            parts.append(String(localized: "平均心率 \(Int(avg.rounded())) BPM", comment: "Average HR a11y"))
        }
        if let maxVal = HeartRateStats.max(of: filteredPoints) {
            parts.append(String(localized: "最高心率 \(Int(maxVal.rounded())) BPM", comment: "Max HR a11y"))
        }
        if let minVal = HeartRateStats.min(of: filteredPoints) {
            parts.append(String(localized: "最低心率 \(Int(minVal.rounded())) BPM", comment: "Min HR a11y"))
        }
        return parts.joined(separator: ", ")
    }

    private func fetchData() async {
        isLoading = true
        fetchError = nil
        let start = ContinuousClock.now
        let interval = range.dateInterval()

        do {
            let result = try await service.fetchData(for: .heartRate, dateRange: interval)
            dataPoints = result.dataPoints
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("chart render type=heartRate points=\(dataPoints.count) ms=\(ms) range=\(range.rawValue)")
        } catch {
            fetchError = error
            logger.error("fetch failed type=heartRate error=\(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let label: String
    let value: Int
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.headline)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Heart Rate Chart

struct HeartRateChartView: View {
    let dataPoints: [HealthDataPoint]
    let range: TimeRange
    let compact: Bool

    @State private var selectedDate: Date?

    private var selectedPoint: HealthDataPoint? {
        guard let selectedDate else { return nil }
        return HeartRateStats.nearest(to: selectedDate, in: dataPoints)
    }

    var body: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value(
                        String(localized: "时间", comment: "Chart x-axis time"),
                        point.startDate
                    ),
                    y: .value(
                        String(localized: "心率", comment: "Chart y-axis heart rate"),
                        point.value
                    )
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value(
                        String(localized: "时间", comment: "Chart x-axis time"),
                        point.startDate
                    ),
                    y: .value(
                        String(localized: "心率", comment: "Chart y-axis heart rate"),
                        point.value
                    )
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.red.opacity(0.3), .red.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.startDate))
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
            AxisMarks(values: .automatic(desiredCount: compact ? 4 : 6)) { value in
                AxisValueLabel(format: xAxisFormat)
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)")
                    }
                }
                AxisGridLine()
            }
        }
        .accessibilityLabel(String(localized: "心率趋势图", comment: "Heart rate chart a11y"))
        .accessibilityValue(chartAccessibilityValue)
    }

    private func selectionAnnotation(for point: HealthDataPoint) -> some View {
        VStack(spacing: 2) {
            Text(Int(point.value.rounded()).formatted())
                .font(.caption.bold())
            Text(String(localized: "BPM", comment: "Beats per minute"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(point.startDate.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(
            String(localized: "心率 \(Int(point.value.rounded())) BPM，\(point.startDate.formatted(.dateTime.hour().minute()))", comment: "Selected HR a11y")
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
            return String(localized: "无数据", comment: "No chart data a11y")
        }
        let avg = HeartRateStats.average(of: dataPoints).map { Int($0.rounded()) } ?? 0
        return String(localized: "\(range.localizedLabel)平均心率 \(avg) BPM", comment: "Chart a11y value")
    }
}

// MARK: - Heart Rate Detail View

struct HeartRateDetailView: View {
    let range: TimeRange
    let dataPoints: [HealthDataPoint]

    private let logger = Logger(subsystem: "com.vitalstride", category: "HeartRateDetail")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeartRateChartView(dataPoints: dataPoints, range: range, compact: false)
                    .frame(height: 250)
                    .padding(.horizontal)

                statsCard

                sampleList
            }
            .padding(.vertical)
        }
        .navigationTitle(String(localized: "心率", comment: "Heart rate detail title"))
        .onAppear {
            logger.info("detail opened type=heartRate points=\(dataPoints.count) range=\(range.rawValue)")
        }
    }

    private var statsCard: some View {
        HStack {
            if let avg = HeartRateStats.average(of: dataPoints) {
                detailStat(
                    label: String(localized: "平均", comment: "Average"),
                    value: Int(avg.rounded())
                )
            }
            Spacer()
            if let maxVal = HeartRateStats.max(of: dataPoints) {
                detailStat(
                    label: String(localized: "最高", comment: "Maximum"),
                    value: Int(maxVal.rounded())
                )
            }
            Spacer()
            if let minVal = HeartRateStats.min(of: dataPoints) {
                detailStat(
                    label: String(localized: "最低", comment: "Minimum"),
                    value: Int(minVal.rounded())
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private func detailStat(label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.formatted())
                    .font(.title2.bold())
                Text(String(localized: "BPM", comment: "Beats per minute"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sampleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "心率记录", comment: "Heart rate samples list header"))
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ForEach(dataPoints.reversed()) { point in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.startDate.formatted(.dateTime.month().day().hour().minute()))
                            .font(.subheadline)
                        if let source = point.sourceName {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Int(point.value.rounded()).formatted())
                            .font(.body.monospacedDigit())
                        Text(String(localized: "BPM", comment: "Beats per minute"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityLabel(
                    String(localized: "\(point.startDate.formatted(.dateTime.month().day().hour().minute()))，心率 \(Int(point.value.rounded())) BPM", comment: "Sample row a11y")
                )

                if point.id != dataPoints.first?.id {
                    Divider()
                        .padding(.leading)
                }
            }
        }
    }
}

#Preview("HeartRateSection") {
    NavigationStack {
        ScrollView {
            HeartRateSection(range: .week)
                .padding()
        }
    }
}
