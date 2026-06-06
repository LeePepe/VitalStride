import Charts
import HealthKit
import HealthKitService
import SwiftUI
import VitalModels
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

    static func downsample(
        _ dataPoints: [HealthDataPoint],
        for range: TimeRange,
        calendar: Calendar = .current
    ) -> [HealthDataPoint] {
        switch range {
        case .day, .week:
            return dataPoints
        case .month:
            return aggregateByComponent(dataPoints, component: .hour, calendar: calendar)
        case .year:
            return aggregateByComponent(dataPoints, component: .day, calendar: calendar)
        }
    }

    private static func aggregateByComponent(
        _ dataPoints: [HealthDataPoint],
        component: Calendar.Component,
        calendar: Calendar
    ) -> [HealthDataPoint] {
        guard !dataPoints.isEmpty else { return [] }

        let grouped = Dictionary(grouping: dataPoints) { point in
            calendar.dateInterval(of: component, for: point.startDate)?.start ?? point.startDate
        }

        return grouped.compactMap { (bucketStart, points) -> HealthDataPoint? in
            guard !points.isEmpty else { return nil }
            let avg = points.reduce(0.0) { $0 + $1.value } / Double(points.count)
            return HealthDataPoint(
                id: points[0].id,
                sampleType: .heartRate,
                startDate: bucketStart,
                endDate: points.last?.endDate ?? bucketStart,
                value: avg,
                unit: "bpm",
                sleepStage: nil,
                sourceName: nil
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - Heart Rate Section

struct HeartRateSection: View {
    let range: TimeRange

    @State private var dataPoints: [HealthDataPoint] = []
    @State private var filteredPoints: [HealthDataPoint] = []
    @State private var chartPoints: [HealthDataPoint] = []
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let service: HealthKitService
    private let logger = Logger(subsystem: "com.vitalstride", category: "HeartRateSection")

    init(range: TimeRange) {
        self.range = range
        #if os(iOS)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceID = Self.stableMacDeviceIdentifier()
        #endif
        self.service = HealthKitService(deviceIdentifier: deviceID)
    }

    #if os(macOS)
    fileprivate static let macDeviceIDKey = "com.vitalstride.macDeviceIdentifier"
    fileprivate static func stableMacDeviceIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: macDeviceIDKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: macDeviceIDKey)
        return generated
    }
    #endif

    var body: some View {
        DataSectionCard(
            title: String(localized: "心率", comment: "Heart rate section"),
            systemImage: "heart.fill",
            destination: HeartRateDetailView()
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
            HeartRateChartView(dataPoints: chartPoints, range: range, compact: true)
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
            filteredPoints = HeartRateStats.filtered(result.dataPoints, in: interval)
                .sorted { $0.startDate < $1.startDate }
            chartPoints = HeartRateStats.downsample(filteredPoints, for: range)
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("chart render type=heartRate points=\(filteredPoints.count) ms=\(ms) range=\(range.rawValue)")
        } catch {
            fetchError = error
            filteredPoints = []
            chartPoints = []
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
        if let selectedPoint {
            let bpm = Int(selectedPoint.value.rounded())
            let time = selectedPoint.startDate.formatted(.dateTime.hour().minute())
            return String(localized: "选中心率 \(bpm) BPM，\(time)", comment: "Selected chart point a11y")
        }
        guard !dataPoints.isEmpty else {
            return String(localized: "无数据", comment: "No chart data a11y")
        }
        let avg = HeartRateStats.average(of: dataPoints).map { Int($0.rounded()) } ?? 0
        return String(localized: "\(range.localizedLabel)平均心率 \(avg) BPM", comment: "Chart a11y value")
    }
}

// MARK: - Heart Rate Detail View

struct HeartRateDetailView: View {
    @State private var selectedRange: TimeRange = .week
    @State private var dataPoints: [HealthDataPoint] = []
    @State private var chartPoints: [HealthDataPoint] = []
    @State private var isLoading = true
    @State private var fetchError: (any Error)?

    private let logger = Logger(subsystem: "com.vitalstride", category: "HeartRateDetail")

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
                        Image(systemName: "heart.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "无法加载心率数据", comment: "Heart rate load error"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    HeartRateChartView(dataPoints: chartPoints, range: selectedRange, compact: false)
                        .frame(height: 250)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                statsSection

                Section {
                    let displayLimit = 200
                    let recentPoints = Array(dataPoints.suffix(displayLimit).reversed())
                    ForEach(recentPoints) { point in
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
                        .accessibilityLabel(
                            String(localized: "\(point.startDate.formatted(.dateTime.month().day().hour().minute()))，心率 \(Int(point.value.rounded())) BPM", comment: "Sample row a11y")
                        )
                    }
                    if dataPoints.count > displayLimit {
                        Text(String(localized: "显示最近 \(displayLimit) 条记录（共 \(dataPoints.count) 条）", comment: "Heart rate row cap note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("心率记录", comment: "Heart rate samples list header")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(String(localized: "心率", comment: "Heart rate detail title"))
        .task(id: selectedRange) {
            await loadData()
        }
        .onAppear {
            logger.info("detail opened type=heartRate range=\(selectedRange.rawValue)")
        }
    }

    private var statsSection: some View {
        Section {
            if let avg = HeartRateStats.average(of: dataPoints) {
                detailStatRow(
                    label: String(localized: "平均", comment: "Average"),
                    value: Int(avg.rounded()),
                    image: "heart"
                )
            }
            if let maxVal = HeartRateStats.max(of: dataPoints) {
                detailStatRow(
                    label: String(localized: "最高", comment: "Maximum"),
                    value: Int(maxVal.rounded()),
                    image: "arrow.up"
                )
            }
            if let minVal = HeartRateStats.min(of: dataPoints) {
                detailStatRow(
                    label: String(localized: "最低", comment: "Minimum"),
                    value: Int(minVal.rounded()),
                    image: "arrow.down"
                )
            }
        }
    }

    private func detailStatRow(label: String, value: Int, image: String) -> some View {
        HStack {
            Label(label, systemImage: image)
            Spacer()
            Text("\(value.formatted()) " + String(localized: "BPM", comment: "Beats per minute"))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadData() async {
        isLoading = true
        fetchError = nil

        let interval = selectedRange.dateInterval()
        #if os(iOS)
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceID = HeartRateSection.stableMacDeviceIdentifier()
        #endif
        let service = HealthKitService(deviceIdentifier: deviceID)

        do {
            let result = try await service.fetchData(for: .heartRate, dateRange: interval)
            guard !Task.isCancelled else { return }

            let filtered = HeartRateStats.filtered(result.dataPoints, in: interval)
                .sorted { $0.startDate < $1.startDate }
            dataPoints = filtered
            chartPoints = HeartRateStats.downsample(filtered, for: selectedRange)
        } catch {
            guard !Task.isCancelled else { return }
            fetchError = error
            dataPoints = []
            chartPoints = []
            logger.error("fetch failed type=heartRate error=\(error.localizedDescription)")
        }

        isLoading = false
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
