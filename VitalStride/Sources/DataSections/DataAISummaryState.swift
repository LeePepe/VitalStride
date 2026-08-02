import AIService
import Foundation
import HealthKitService
import os
import SwiftData
import VitalModels

private let logger = Logger(subsystem: "com.vitalstride", category: "DataAISummaryState")

@Observable
@MainActor
final class DataAISummaryState {

    enum Phase: Sendable {
        case idle
        case loading
        case done
        case failed
    }

    struct TypeResult: Sendable {
        let sampleType: HealthSampleType
        let trend: String
        let summary: String
        let suggestion: String?
        let generatedAt: Date
    }

    private(set) var phase: Phase = .idle
    private(set) var results: [TypeResult] = []
    private(set) var earliestGeneratedAt: Date?

    static let summaryTypes: [HealthSampleType] = [
        .stepCount, .heartRate, .sleepAnalysis, .bodyMass, .activeEnergyBurned,
    ]

    func loadIfNeeded(
        availableTypes: Set<HealthSampleType>,
        modelContainer: ModelContainer,
        healthDataCache: HealthDataCache
    ) async {
        guard phase == .idle else { return }
        await load(
            availableTypes: availableTypes,
            modelContainer: modelContainer,
            healthDataCache: healthDataCache
        )
    }

    private static let maxConcurrentAnalyses = 3

    func load(
        availableTypes: Set<HealthSampleType>,
        modelContainer: ModelContainer,
        healthDataCache: HealthDataCache
    ) async {
        let targetTypes = Self.summaryTypes.filter { availableTypes.contains($0) }
        guard !targetTypes.isEmpty else {
            phase = .failed
            return
        }

        phase = .loading
        logger.info("Starting parallel analysis for \(targetTypes.count) types")

        let start = ContinuousClock.now

        let keychainHelper = KeychainHelper()
        let apiKeyService = AISettingsSection.apiKeyKeychainService
        guard let apiKey = try? keychainHelper.load(service: apiKeyService) else {
            logger.debug("AI summary skipped: no API key configured")
            let cacheResults = loadAllFromCache(
                types: targetTypes,
                container: modelContainer
            )
            if !cacheResults.isEmpty {
                results = cacheResults
                earliestGeneratedAt = cacheResults.map(\.generatedAt).min()
                phase = .done
            } else {
                phase = .failed
            }
            return
        }

        let router = AIRouter.makeDefault(zhipuAPIKey: apiKey)
        let provider = RouterBackedProvider(router: router, kind: .dataTrend)

        var cacheHitCount = 0
        var collectedResults: [TypeResult] = []

        let allCached = loadAllFromCache(types: targetTypes, container: modelContainer)
        let allCachedValid = allCached.count == targetTypes.count
            && allCached.allSatisfy { result in
                let entry = loadCacheEntry(
                    sampleType: result.sampleType.rawValue,
                    container: modelContainer
                )
                return entry != nil && !entry!.isExpired
            }

        if allCachedValid {
            cacheHitCount = allCached.count
            collectedResults = allCached
            logger.debug("All \(allCached.count) types served from cache")
        } else {
            collectedResults = await withTaskGroup(
                of: TypeResult?.self,
                returning: [TypeResult].self
            ) { group in
                var pending = targetTypes.makeIterator()
                var accumulated: [TypeResult] = []

                for _ in 0..<Self.maxConcurrentAnalyses {
                    guard let nextType = pending.next() else { break }
                    nonisolated(unsafe) let sampleType = nextType
                    group.addTask { @Sendable in
                        await Self.analyzeType(
                            sampleType,
                            provider: provider,
                            modelContainer: modelContainer,
                            healthDataCache: healthDataCache
                        )
                    }
                }

                for await result in group {
                    if let result { accumulated.append(result) }
                    if let nextType = pending.next() {
                        nonisolated(unsafe) let sampleType = nextType
                        group.addTask { @Sendable in
                            await Self.analyzeType(
                                sampleType,
                                provider: provider,
                                modelContainer: modelContainer,
                                healthDataCache: healthDataCache
                            )
                        }
                    }
                }
                return accumulated
            }

            for result in collectedResults {
                let entry = loadCacheEntry(
                    sampleType: result.sampleType.rawValue,
                    container: modelContainer
                )
                if let entry, !entry.isExpired {
                    cacheHitCount += 1
                }
            }
        }

        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000

        logger.info("Parallel analysis complete: \(collectedResults.count)/\(targetTypes.count) succeeded, cache hits: \(cacheHitCount)/\(targetTypes.count), duration: \(ms)ms")

        emitTelemetry(
            typesCount: targetTypes.count,
            durationMs: ms,
            cacheHitCount: cacheHitCount
        )

        if collectedResults.isEmpty {
            phase = .failed
        } else {
            let sorted = Self.summaryTypes.compactMap { type in
                collectedResults.first { $0.sampleType == type }
            }
            results = sorted
            earliestGeneratedAt = sorted.map(\.generatedAt).min()
            phase = .done
        }
    }

    var focusSuggestion: String? {
        let needsAttention = results.first {
            $0.trend == "falling" || $0.trend == "insufficient"
        }
        return (needsAttention ?? results.first)?.suggestion
    }

    // MARK: - Per-Type Analysis

    private static func analyzeType(
        _ sampleType: HealthSampleType,
        provider: some AIProvider,
        modelContainer: ModelContainer,
        healthDataCache: HealthDataCache
    ) async -> TypeResult? {
        let service = AIAnalysisService(
            modelContainer: modelContainer,
            provider: provider
        )

        let context = await buildDataContext(
            sampleType: sampleType,
            healthDataCache: healthDataCache
        )

        do {
            let analysis = try await service.analyzeDataTrend(context: context)

            let cacheContext = ModelContext(modelContainer)
            let sampleTypeRaw = sampleType.rawValue
            let descriptor = FetchDescriptor<DataAnalysisCache>(
                predicate: #Predicate<DataAnalysisCache> { $0.sampleType == sampleTypeRaw }
            )
            let generatedAt = (try? cacheContext.fetch(descriptor).first)?.generatedAt ?? Date()

            logger.debug("Analysis succeeded for \(sampleType.rawValue)")
            return TypeResult(
                sampleType: sampleType,
                trend: analysis.trend,
                summary: analysis.summary,
                suggestion: analysis.suggestion,
                generatedAt: generatedAt
            )
        } catch {
            logger.debug("Analysis failed for \(sampleType.rawValue)")
            return nil
        }
    }

    private static func buildDataContext(
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

    // MARK: - Cache Helpers

    private func loadAllFromCache(
        types: [HealthSampleType],
        container: ModelContainer
    ) -> [TypeResult] {
        types.compactMap { type in
            guard let entry = loadCacheEntry(sampleType: type.rawValue, container: container),
                  let data = entry.contentJSON.data(using: .utf8),
                  let analysis = try? JSONDecoder().decode(DataAnalysis.self, from: data)
            else { return nil }

            return TypeResult(
                sampleType: type,
                trend: analysis.trend,
                summary: analysis.summary,
                suggestion: analysis.suggestion,
                generatedAt: entry.generatedAt
            )
        }
    }

    private func loadCacheEntry(
        sampleType: String,
        container: ModelContainer
    ) -> DataAnalysisCache? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate<DataAnalysisCache> { $0.sampleType == sampleType }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: - Telemetry

    private static let signposter = OSSignposter(
        subsystem: "com.vitalstride",
        category: "DataAISummaryCard"
    )

    private func emitTelemetry(
        typesCount: Int,
        durationMs: Int64,
        cacheHitCount: Int
    ) {
        let signposter = Self.signposter
        let id = signposter.makeSignpostID()
        signposter.emitEvent(
            "ai_summary_card_shown",
            id: id,
            "types_count=\(typesCount)"
        )

        let durationId = signposter.makeSignpostID()
        signposter.emitEvent(
            "ai_summary_parallel_duration_ms",
            id: durationId,
            "duration_ms=\(durationMs)"
        )

        let cacheId = signposter.makeSignpostID()
        signposter.emitEvent(
            "ai_summary_cache_hit_count",
            id: cacheId,
            "\(cacheHitCount)/\(typesCount)"
        )
    }
}
