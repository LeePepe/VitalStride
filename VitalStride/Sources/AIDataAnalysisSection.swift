import AIService
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIDataAnalysisSection")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "AIDataAnalysisSection")

// MARK: - AIDataAnalysisSection

struct AIDataAnalysisSection: View {
    let sampleType: HealthSampleType

    @State private var state: AnalysisState = .idle
    @AppStorage(aiPrivacyConsentKey) private var privacyConsented = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthDataCache) private var healthDataCache

    private let keychainHelper = KeychainHelper()
    private let apiKeyService = AISettingsSection.apiKeyKeychainService

    var body: some View {
        Group {
            if !privacyConsented {
                EmptyView()
            } else {
                switch state {
                case .idle, .loading:
                    loadingView
                case .loaded(let analysis, let generatedAt, let source):
                    resultView(analysis: analysis, generatedAt: generatedAt, source: source)
                case .failed:
                    EmptyView()
                }
            }
        }
        .task {
            guard privacyConsented else { return }
            await loadAnalysis(forceRefresh: false)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "正在分析数据", comment: "AI analysis loading"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityValue(String(localized: "正在分析数据", comment: "AI analysis loading a11y"))
        } header: {
            sectionHeader
        }
    }

    // MARK: - Result View

    private func resultView(analysis: DataAnalysis, generatedAt: Date, source: AnalysisSource) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                trendRow(analysis: analysis)
                if let suggestion = analysis.suggestion, !suggestion.isEmpty {
                    suggestionRow(suggestion: suggestion)
                }
                footerRow(generatedAt: generatedAt, source: source)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader
        }
        .onAppear {
            emitShownTelemetry(source: source)
        }
    }

    private func trendRow(analysis: DataAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(String(localized: "趋势分析", comment: "Trend analysis label"))
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: trendIcon(analysis.trend))
                    .foregroundStyle(trendColor(analysis.trend))
            }
            Text(analysis.summary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func suggestionRow(suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(String(localized: "建议", comment: "AI suggestion label"))
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
            }
            Text(suggestion)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func footerRow(generatedAt: Date, source: AnalysisSource) -> some View {
        HStack {
            if source == .cache {
                Text(
                    String(
                        localized: "更新于 \(generatedAt, format: .relative(presentation: .named))",
                        comment: "Cache update time"
                    )
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await loadAnalysis(forceRefresh: true) }
            } label: {
                Label(
                    String(localized: "刷新", comment: "Refresh button"),
                    systemImage: "arrow.clockwise"
                )
                .font(.caption)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "刷新 AI 分析", comment: "Refresh AI analysis a11y"))
        }
    }

    private var sectionHeader: some View {
        Label(
            String(localized: "AI 分析", comment: "AI analysis section header"),
            systemImage: "sparkles"
        )
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Data Loading

    private func loadAnalysis(forceRefresh: Bool) async {
        let sampleTypeRaw = sampleType.rawValue

        if forceRefresh {
            emitRefreshTelemetry()
        }

        state = .loading

        let container = modelContext.container

        if !forceRefresh {
            if let (analysis, generatedAt) = loadFallbackFromCache(container: container) {
                let cacheEntry = loadCacheEntry(sampleType: sampleTypeRaw, in: container)
                if let entry = cacheEntry, !entry.isExpired {
                    state = .loaded(analysis, generatedAt, .cache)
                    return
                }
            }
        }

        let start = ContinuousClock.now

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let service = AIAnalysisService(
                modelContainer: container,
                provider: provider
            )

            let context = await buildDataContext()

            let isTopInterest = checkIsTopInterest()
            if !isTopInterest {
                emitOnDemandTelemetry()
            }

            let analysis = try await service.analyzeDataTrend(
                context: context,
                forceRefresh: forceRefresh
            )

            guard !Task.isCancelled else { return }

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            emitRequestDurationTelemetry(durationMs: ms, success: true)

            let cacheEntry = loadCacheEntry(sampleType: sampleTypeRaw, in: container)
            let generatedAt = cacheEntry?.generatedAt ?? Date()
            let source: AnalysisSource = (cacheEntry != nil && !forceRefresh) ? .cache : .fresh

            state = .loaded(analysis, generatedAt, source)
        } catch {
            guard !Task.isCancelled else { return }

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            emitRequestDurationTelemetry(durationMs: ms, success: false)

            let fallback = loadFallbackFromCache(container: container)
            if let (analysis, generatedAt) = fallback {
                state = .loaded(analysis, generatedAt, .cache)
            } else {
                emitDegradedTelemetry()
                state = .failed
            }
        }
    }

    // MARK: - Context Building

    private func buildDataContext() async -> DataContext {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let recentInterval = DateInterval(start: sevenDaysAgo, end: tomorrow)
        let previousInterval = DateInterval(start: fourteenDaysAgo, end: sevenDaysAgo)

        let recentPoints = (try? await healthDataCache.data(for: sampleType, in: recentInterval)) ?? []
        let previousPoints = (try? await healthDataCache.data(for: sampleType, in: previousInterval)) ?? []

        let recentStats = computeStats(from: recentPoints)
        let previousStats = computeStats(from: previousPoints)

        let timeRangeDesc = buildTimeRangeDescription(
            recentStats: recentStats,
            previousStats: previousStats
        )

        return DataContext(
            sampleType: sampleType.rawValue,
            dataPointCount: recentPoints.count,
            timeRangeDescription: timeRangeDesc,
            statistics: DataContext.DataStatistics(
                average: recentStats.average,
                minimum: recentStats.minimum,
                maximum: recentStats.maximum,
                latestValue: recentStats.latest,
                unit: sampleType.unitLabel
            )
        )
    }

    private struct SimpleStats {
        let average: Double?
        let minimum: Double?
        let maximum: Double?
        let latest: Double?
        let count: Int
    }

    private func computeStats(from points: [HealthDataPoint]) -> SimpleStats {
        let filtered = points.filter { $0.sampleType == sampleType }
        guard !filtered.isEmpty else {
            return SimpleStats(average: nil, minimum: nil, maximum: nil, latest: nil, count: 0)
        }
        let values = filtered.map(\.value)
        let sum = values.reduce(0, +)
        return SimpleStats(
            average: sum / Double(values.count),
            minimum: values.min(),
            maximum: values.max(),
            latest: filtered.sorted(by: { $0.startDate < $1.startDate }).last?.value,
            count: filtered.count
        )
    }

    private func buildTimeRangeDescription(
        recentStats: SimpleStats,
        previousStats: SimpleStats
    ) -> String {
        var parts: [String] = []
        parts.append("Recent 7 days: \(recentStats.count) data points")
        if let avg = recentStats.average {
            parts.append("avg=\(String(format: "%.1f", avg))")
        }
        if let prevAvg = previousStats.average, let recentAvg = recentStats.average {
            let change = recentAvg - prevAvg
            let pct = prevAvg != 0 ? (change / prevAvg * 100) : 0
            parts.append("vs previous 7 days: \(String(format: "%+.1f", change)) (\(String(format: "%+.0f", pct))%)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Cache Helpers

    private func loadCacheEntry(sampleType: String, in container: ModelContainer) -> DataAnalysisCache? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate<DataAnalysisCache> { $0.sampleType == sampleType }
        )
        return try? context.fetch(descriptor).first
    }

    private func loadFallbackFromCache(container: ModelContainer) -> (DataAnalysis, Date)? {
        let sampleTypeRaw = sampleType.rawValue
        guard let entry = loadCacheEntry(sampleType: sampleTypeRaw, in: container),
              let data = entry.contentJSON.data(using: .utf8),
              let analysis = try? JSONDecoder().decode(DataAnalysis.self, from: data)
        else { return nil }
        return (analysis, entry.generatedAt)
    }

    private func checkIsTopInterest() -> Bool {
        let container = modelContext.container
        let context = ModelContext(container)
        let topTypes = UserInterestTracker.topInterests(limit: 3, in: context)
        return topTypes.contains(sampleType)
    }

    // MARK: - Trend Helpers

    private func trendIcon(_ trend: String) -> String {
        switch trend {
        case "rising": "arrow.up.right"
        case "falling": "arrow.down.right"
        case "stable": "arrow.right"
        default: "chart.line.flattrend.xyaxis"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "rising": .green
        case "falling": .red
        case "stable": .blue
        default: .secondary
        }
    }

    // MARK: - Telemetry

    private func emitShownTelemetry(source: AnalysisSource) {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("ai_data_analysis_shown", id: id,
                             "sampleType=\(sampleType.rawValue) source=\(source.rawValue)")
    }

    private func emitRefreshTelemetry() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("ai_data_analysis_refresh", id: id,
                             "sampleType=\(sampleType.rawValue)")
    }

    private func emitRequestDurationTelemetry(durationMs: Int64, success: Bool) {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("ai_data_analysis_request_duration_ms", id: id,
                             "sampleType=\(sampleType.rawValue) duration_ms=\(durationMs) success=\(success)")
    }

    private func emitDegradedTelemetry() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("ai_data_analysis_degraded", id: id,
                             "sampleType=\(sampleType.rawValue)")
    }

    private func emitOnDemandTelemetry() {
        let id = signposter.makeSignpostID()
        signposter.emitEvent("ai_data_analysis_on_demand", id: id,
                             "sampleType=\(sampleType.rawValue)")
    }
}

// MARK: - State Types

extension AIDataAnalysisSection {
    enum AnalysisState {
        case idle
        case loading
        case loaded(DataAnalysis, Date, AnalysisSource)
        case failed

        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
    }

    enum AnalysisSource: String {
        case cache
        case fresh
    }
}

// MARK: - Pregeneration

enum AIDataAnalysisPreloader {
    private static let logger = Logger(subsystem: "com.vitalstride", category: "AIDataAnalysisPreloader")
    private static let signposter = OSSignposter(subsystem: "com.vitalstride", category: "AIDataAnalysisPreloader")

    static func pregenerateTopInterestsIfConsented(
        modelContainer: ModelContainer,
        healthDataCache: HealthDataCache
    ) {
        let consented = UserDefaults.standard.bool(forKey: aiPrivacyConsentKey)
        guard consented else {
            logger.debug("pregenerate skipped: user has not accepted AI privacy consent")
            return
        }
        pregenerateTopInterests(
            modelContainer: modelContainer,
            healthDataCache: healthDataCache
        )
    }

    static func pregenerateTopInterests(
        modelContainer: ModelContainer,
        healthDataCache: HealthDataCache
    ) {
        let context = ModelContext(modelContainer)
        let topTypes = UserInterestTracker.topInterests(limit: 3, in: context)

        guard !topTypes.isEmpty else { return }

        let keychainHelper = KeychainHelper()
        let apiKeyService = AISettingsSection.apiKeyKeychainService

        guard let apiKey = try? keychainHelper.load(service: apiKeyService) else {
            logger.debug("pregenerate skipped: no API key configured")
            return
        }

        let provider = ZhipuProvider(apiKey: apiKey)

        for sampleType in topTypes {
            nonisolated(unsafe) let sampleType = sampleType
            Task.detached {
                let cacheContext = ModelContext(modelContainer)
                let sampleTypeRaw = sampleType.rawValue
                let descriptor = FetchDescriptor<DataAnalysisCache>(
                    predicate: #Predicate<DataAnalysisCache> { $0.sampleType == sampleTypeRaw }
                )
                if let cached = try? cacheContext.fetch(descriptor).first, !cached.isExpired {
                    logger.debug("pregenerate skipped (cache valid): sampleType=\(sampleType.rawValue)")
                    return
                }

                let signpostID = signposter.makeSignpostID()
                signposter.emitEvent("ai_data_analysis_pregenerate", id: signpostID,
                                     "sampleType=\(sampleType.rawValue)")

                let service = AIAnalysisService(
                    modelContainer: modelContainer,
                    provider: provider
                )

                let dataContext = await buildPregenerateContext(
                    sampleType: sampleType,
                    healthDataCache: healthDataCache
                )

                do {
                    _ = try await service.analyzeDataTrend(context: dataContext)
                    logger.debug("pregenerate success: sampleType=\(sampleType.rawValue)")
                } catch {
                    logger.debug("pregenerate failed: sampleType=\(sampleType.rawValue)")
                }
            }
        }
    }

    private static func buildPregenerateContext(
        sampleType: HealthSampleType,
        healthDataCache: HealthDataCache
    ) async -> DataContext {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let recentInterval = DateInterval(start: sevenDaysAgo, end: tomorrow)
        let previousInterval = DateInterval(start: fourteenDaysAgo, end: sevenDaysAgo)

        let recentPoints = (try? await healthDataCache.data(for: sampleType, in: recentInterval)) ?? []
        let previousPoints = (try? await healthDataCache.data(for: sampleType, in: previousInterval)) ?? []

        let recentFiltered = recentPoints.filter { $0.sampleType == sampleType }
        let previousFiltered = previousPoints.filter { $0.sampleType == sampleType }

        let recentValues = recentFiltered.map(\.value)
        let previousValues = previousFiltered.map(\.value)

        let recentAvg = recentValues.isEmpty ? nil : recentValues.reduce(0, +) / Double(recentValues.count)
        let previousAvg = previousValues.isEmpty ? nil : previousValues.reduce(0, +) / Double(previousValues.count)

        var descParts: [String] = ["Recent 7 days: \(recentFiltered.count) data points"]
        if let avg = recentAvg {
            descParts.append("avg=\(String(format: "%.1f", avg))")
        }
        if let prevAvg = previousAvg, let recAvg = recentAvg {
            let change = recAvg - prevAvg
            let pct = prevAvg != 0 ? (change / prevAvg * 100) : 0
            descParts.append("vs previous 7 days: \(String(format: "%+.1f", change)) (\(String(format: "%+.0f", pct))%)")
        }

        return DataContext(
            sampleType: sampleType.rawValue,
            dataPointCount: recentFiltered.count,
            timeRangeDescription: descParts.joined(separator: ", "),
            statistics: DataContext.DataStatistics(
                average: recentAvg,
                minimum: recentValues.min(),
                maximum: recentValues.max(),
                latestValue: recentFiltered.sorted(by: { $0.startDate < $1.startDate }).last?.value,
                unit: sampleType.unitLabel
            )
        )
    }
}
