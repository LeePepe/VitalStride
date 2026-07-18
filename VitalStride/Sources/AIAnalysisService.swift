// swiftlint:disable no_hardcoded_chinese
// MY-1269: Chinese string values are xcstrings source keys resolved via
// String(localized:). Rule silenced at file scope pending ASCII-key migration.
import AIService
import Foundation
import OSLog
import SwiftData
import TelemetryKit
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIAnalysisService")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "AIAnalysisService")

private enum AICacheOperation {
    static let decode: TelemetryIdentifier = "decode"
    static let encode: TelemetryIdentifier = "encode"
    static let fetch: TelemetryIdentifier = "fetch"
    static let save: TelemetryIdentifier = "save"
    static let clear: TelemetryIdentifier = "clear"
}

actor AIAnalysisService: ModelActor {
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    private nonisolated let provider: any AIProvider
    private nonisolated let cacheTTL: TimeInterval
    private var activeRefreshKeys: Set<String> = []

    init(
        modelContainer: ModelContainer,
        provider: any AIProvider,
        cacheTTL: TimeInterval = 3600
    ) {
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.provider = provider
        self.cacheTTL = cacheTTL
    }

    // MARK: - Public API

    func clearAllCaches() {
        deleteAll(OverviewInsightCache.self)
        deleteAll(TrainingAdviceCache.self)
        deleteAll(DataAnalysisCache.self)
        do {
            try modelContext.save()
            logger.info("AI analysis caches cleared")
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache clear save failed: method=clearAllCaches error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.clear, error: error)
        }
    }

    func generateInsights(
        context: OverviewContext,
        forceRefresh: Bool = false,
        skipCache: Bool = false
    ) async throws -> AIAnalysisResponse {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_analysis_e2e", id: signpostID, "method=generateInsights")
        defer { signposter.endInterval("ai_analysis_e2e", state) }

        let start = ContinuousClock.now

        if !forceRefresh, let cached = loadInsightsCache() {
            if !cached.isExpired {
                let age = Date().timeIntervalSince(cached.generatedAt)
                logger.debug("cache hit: method=generateInsights age=\(Int(age))s")
                if let response = decodeAnalysisResponse(cached.contentJSON) {
                    return response
                }
            } else {
                logger.debug("cache miss: method=generateInsights reason=expired")
                if let staleResponse = decodeAnalysisResponse(cached.contentJSON) {
                    scheduleBackgroundRefresh(key: "generateInsights") { service in
                        try await service.refreshInsights(context: context)
                    }
                    return staleResponse
                }
            }
        } else if !forceRefresh {
            logger.debug("cache miss: method=generateInsights reason=notFound")
        } else {
            logger.debug("cache miss: method=generateInsights reason=forceRefresh")
        }

        let result = try await fetchInsights(context: context, skipCache: skipCache)
        logSuccess(method: "generateInsights", start: start)
        return result
    }

    func generateTrainingAdvice(
        context: TrainingContext,
        forceRefresh: Bool = false
    ) async throws -> TrainingRecommendation {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_analysis_e2e", id: signpostID, "method=generateTrainingAdvice")
        defer { signposter.endInterval("ai_analysis_e2e", state) }

        let start = ContinuousClock.now

        if !forceRefresh, let cached = loadTrainingCache() {
            if !cached.isExpired {
                let age = Date().timeIntervalSince(cached.generatedAt)
                logger.debug("cache hit: method=generateTrainingAdvice age=\(Int(age))s")
                if let advice = decodeTrainingAdvice(cached.contentJSON) {
                    return advice
                }
            } else {
                logger.debug("cache miss: method=generateTrainingAdvice reason=expired")
                if let staleAdvice = decodeTrainingAdvice(cached.contentJSON) {
                    scheduleBackgroundRefresh(key: "generateTrainingAdvice") { service in
                        try await service.refreshTrainingAdvice(context: context)
                    }
                    return staleAdvice
                }
            }
        } else if !forceRefresh {
            logger.debug("cache miss: method=generateTrainingAdvice reason=notFound")
        } else {
            logger.debug("cache miss: method=generateTrainingAdvice reason=forceRefresh")
        }

        let result = try await fetchTrainingAdvice(context: context)
        logSuccess(method: "generateTrainingAdvice", start: start)
        return result
    }

    func analyzeDataTrend(
        context: DataContext,
        forceRefresh: Bool = false
    ) async throws -> DataAnalysis {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_analysis_e2e", id: signpostID, "method=analyzeDataTrend")
        defer { signposter.endInterval("ai_analysis_e2e", state) }

        let start = ContinuousClock.now

        if !forceRefresh, let cached = loadDataAnalysisCache(sampleType: context.sampleType) {
            if !cached.isExpired {
                let age = Date().timeIntervalSince(cached.generatedAt)
                logger.debug("cache hit: method=analyzeDataTrend sampleType=\(context.sampleType) age=\(Int(age))s")
                if let analysis = decodeDataAnalysis(cached.contentJSON) {
                    return analysis
                }
            } else {
                logger.debug("cache miss: method=analyzeDataTrend sampleType=\(context.sampleType) reason=expired")
                if let staleAnalysis = decodeDataAnalysis(cached.contentJSON) {
                    scheduleBackgroundRefresh(key: "analyzeDataTrend:\(context.sampleType)") { service in
                        try await service.refreshDataTrend(context: context)
                    }
                    return staleAnalysis
                }
            }
        } else if !forceRefresh {
            logger.debug("cache miss: method=analyzeDataTrend sampleType=\(context.sampleType) reason=notFound")
        } else {
            logger.debug("cache miss: method=analyzeDataTrend sampleType=\(context.sampleType) reason=forceRefresh")
        }

        let result = try await fetchDataAnalysis(context: context)
        logSuccess(method: "analyzeDataTrend", start: start)
        return result
    }

    // MARK: - Fetch + Parse + Cache

    private func fetchInsights(context: OverviewContext, skipCache: Bool = false) async throws -> AIAnalysisResponse {
        let previousInsights = loadInsightsCache().flatMap { decodeAnalysisResponse($0.contentJSON)?.insights }

        let messages = buildPromptWithSignpost("generateInsights") {
            AIAnalysisPrompts.buildInsightsMessages(context: context, previousInsights: previousInsights)
        }

        let response: ChatResponse
        do {
            response = try await callProvider(method: "generateInsights", messages: messages)
        } catch let error as AIServiceError where error.isNoProvider {
            if let cached = loadInsightsCache(), let cachedResponse = decodeAnalysisResponse(cached.contentJSON) {
                logger.info("noProviderAvailable: method=generateInsights returning cached data")
                return cachedResponse
            }
            throw error
        }

        let json = AIAnalysisPrompts.extractJSON(from: response.content)

        if let analysisResponse = parseWithSignpost("generateInsights", { decodeAnalysisResponse(json) }) {
            if !skipCache {
                saveInsightsCache(response: analysisResponse)
            }
            return analysisResponse
        }

        logger.log("JSON parse failed: method=generateInsights retry=1")
        let retryResponse = try await callProvider(method: "generateInsights", messages: messages)
        let retryJSON = AIAnalysisPrompts.extractJSON(from: retryResponse.content)

        if let analysisResponse = parseWithSignpost("generateInsights", { decodeAnalysisResponse(retryJSON) }) {
            logger.log("JSON parse: method=generateInsights result=retrySuccess")
            if !skipCache {
                saveInsightsCache(response: analysisResponse)
            }
            return analysisResponse
        }

        logger.log("JSON parse: method=generateInsights retry=2 result=decodeFailed")
        throw AIServiceError.responseParsingFailed
    }

    private func fetchTrainingAdvice(context: TrainingContext) async throws -> TrainingRecommendation {
        let messages = buildPromptWithSignpost("generateTrainingAdvice") {
            AIAnalysisPrompts.buildTrainingAdviceMessages(context: context)
        }

        let response: ChatResponse
        do {
            response = try await callProvider(method: "generateTrainingAdvice", messages: messages)
        } catch let error as AIServiceError where error.isNoProvider {
            if let cached = loadTrainingCache(), let advice = decodeTrainingAdvice(cached.contentJSON) {
                logger.info("noProviderAvailable: method=generateTrainingAdvice returning cached data")
                return advice
            }
            throw error
        }

        let json = AIAnalysisPrompts.extractJSON(from: response.content)

        if let advice = parseWithSignpost("generateTrainingAdvice", { decodeTrainingAdvice(json) }) {
            saveTrainingCache(json: json)
            return advice
        }

        logger.log("JSON parse failed: method=generateTrainingAdvice retry=1")
        let retryResponse = try await callProvider(method: "generateTrainingAdvice", messages: messages)
        let retryJSON = AIAnalysisPrompts.extractJSON(from: retryResponse.content)

        if let advice = parseWithSignpost("generateTrainingAdvice", { decodeTrainingAdvice(retryJSON) }) {
            logger.log("JSON parse: method=generateTrainingAdvice result=retrySuccess")
            saveTrainingCache(json: retryJSON)
            return advice
        }

        logger.log("JSON parse: method=generateTrainingAdvice retry=2 result=fallback")
        return TrainingRecommendation(
            title: String(localized: "训练建议", comment: "Fallback training advice title"),
            muscleGroups: [],
            exercises: [],
            reasoning: String(
                localized: "暂时无法生成训练建议，请稍后重试。",
                comment: "Fallback training advice reasoning"
            )
        )
    }

    private func fetchDataAnalysis(context: DataContext) async throws -> DataAnalysis {
        let isCategoryPrompt = AIAnalysisPrompts.isCategorySampleType(context.sampleType)
        let messages = buildPromptWithSignpost("analyzeDataTrend") {
            AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: context.sampleType, context: context)
        }
        if isCategoryPrompt {
            logger.debug("Using category prompt for \(context.sampleType)")
        } else {
            logger.debug("Fallback to generic prompt for \(context.sampleType)")
        }

        let response: ChatResponse
        do {
            response = try await callProvider(method: "analyzeDataTrend", messages: messages)
        } catch let error as AIServiceError where error.isNoProvider {
            if let cached = loadDataAnalysisCache(sampleType: context.sampleType),
               let analysis = decodeDataAnalysis(cached.contentJSON)
            {
                logger.info("noProviderAvailable: method=analyzeDataTrend returning cached data")
                return analysis
            }
            throw error
        }

        let json = AIAnalysisPrompts.extractJSON(from: response.content)

        if let analysis = parseWithSignpost("analyzeDataTrend", { decodeDataAnalysis(json) }) {
            saveDataAnalysisCache(sampleType: context.sampleType, json: json)
            return analysis
        }

        logger.log("JSON parse failed: method=analyzeDataTrend retry=1")
        let retryResponse = try await callProvider(method: "analyzeDataTrend", messages: messages)
        let retryJSON = AIAnalysisPrompts.extractJSON(from: retryResponse.content)

        if let analysis = parseWithSignpost("analyzeDataTrend", { decodeDataAnalysis(retryJSON) }) {
            logger.log("JSON parse: method=analyzeDataTrend result=retrySuccess")
            saveDataAnalysisCache(sampleType: context.sampleType, json: retryJSON)
            return analysis
        }

        logger.log("JSON parse: method=analyzeDataTrend retry=2 result=fallback")
        return DataAnalysis(
            sampleType: context.sampleType,
            summary: String(
                localized: "暂时无法分析数据趋势，请稍后重试。",
                comment: "Fallback data trend analysis summary"
            ),
            trend: "insufficient"
        )
    }

    // MARK: - Background Refresh

    private func refreshInsights(context: OverviewContext) async throws {
        let previousInsights = loadInsightsCache().flatMap { decodeAnalysisResponse($0.contentJSON)?.insights }
        let messages = AIAnalysisPrompts.buildInsightsMessages(context: context, previousInsights: previousInsights)
        let response = try await callProvider(method: "generateInsights", messages: messages)
        let json = AIAnalysisPrompts.extractJSON(from: response.content)
        guard let analysisResponse = decodeAnalysisResponse(json) else {
            throw AIServiceError.responseParsingFailed
        }
        saveInsightsCache(response: analysisResponse)
    }

    private func refreshTrainingAdvice(context: TrainingContext) async throws {
        let messages = AIAnalysisPrompts.buildTrainingAdviceMessages(context: context)
        let response = try await callProvider(method: "generateTrainingAdvice", messages: messages)
        let json = AIAnalysisPrompts.extractJSON(from: response.content)
        if decodeTrainingAdvice(json) != nil {
            saveTrainingCache(json: json)
        }
    }

    private func refreshDataTrend(context: DataContext) async throws {
        let messages = AIAnalysisPrompts.buildCategoryTrendMessages(sampleType: context.sampleType, context: context)
        logger.debug("Background refresh: sampleType=\(context.sampleType) categoryPrompt=\(AIAnalysisPrompts.isCategorySampleType(context.sampleType))")
        let response = try await callProvider(method: "analyzeDataTrend", messages: messages)
        let json = AIAnalysisPrompts.extractJSON(from: response.content)
        if decodeDataAnalysis(json) != nil {
            saveDataAnalysisCache(sampleType: context.sampleType, json: json)
        }
    }

    private func scheduleBackgroundRefresh(
        key: String,
        _ work: @escaping @Sendable (isolated AIAnalysisService) async throws -> Void
    ) {
        guard !activeRefreshKeys.contains(key) else { return }
        activeRefreshKeys.insert(key)
        Task { [self] in
            defer { self.activeRefreshKeys.remove(key) }
            do {
                try await work(self)
            } catch {
                let errorType = describeErrorType(error)
                logger.error("background refresh failed: key=\(key) error=\(errorType)")
            }
        }
    }

    // MARK: - AI Provider Call

    private func callProvider(
        method: String,
        messages: [ChatMessage]
    ) async throws -> ChatResponse {
        do {
            return try await provider.chat(messages: messages, model: nil)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("AI call failed: method=\(method) error=\(errorType)")
            throw error
        }
    }

    // MARK: - Decoding

    private func decodeAnalysisResponse(_ json: String) -> AIAnalysisResponse? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(AIAnalysisResponse.self, from: data)
        } catch let primaryError {
            do {
                let insights = try JSONDecoder().decode([OverviewInsight].self, from: data)
                return AIAnalysisResponse(headline: nil, insights: insights)
            } catch let fallbackError {
                let errorType = describeErrorType(fallbackError)
                logger.error("cache decode failed: method=decodeAnalysisResponse type=AIAnalysisResponse error=\(errorType)")
                trackCacheFailure(operation: AICacheOperation.decode, error: primaryError)
                return nil
            }
        }
    }

    private func decodeTrainingAdvice(_ json: String) -> TrainingRecommendation? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(TrainingRecommendation.self, from: data)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache decode failed: method=decodeTrainingAdvice type=TrainingRecommendation error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.decode, error: error)
            return nil
        }
    }

    private func decodeDataAnalysis(_ json: String) -> DataAnalysis? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(DataAnalysis.self, from: data)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache decode failed: method=decodeDataAnalysis type=DataAnalysis error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.decode, error: error)
            return nil
        }
    }

    // MARK: - Cache Read

    private func loadInsightsCache() -> OverviewInsightCache? {
        let descriptor = FetchDescriptor<OverviewInsightCache>()
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache fetch failed: method=loadInsightsCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.fetch, error: error)
            return nil
        }
    }

    private func loadTrainingCache() -> TrainingAdviceCache? {
        let descriptor = FetchDescriptor<TrainingAdviceCache>()
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache fetch failed: method=loadTrainingCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.fetch, error: error)
            return nil
        }
    }

    private func loadDataAnalysisCache(sampleType: String) -> DataAnalysisCache? {
        let descriptor = FetchDescriptor<DataAnalysisCache>(
            predicate: #Predicate<DataAnalysisCache> { $0.sampleType == sampleType }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache fetch failed: method=loadDataAnalysisCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.fetch, error: error)
            return nil
        }
    }

    // MARK: - Cache Write

    private func saveInsightsCache(response: AIAnalysisResponse) {
        let json: String
        do {
            let data = try JSONEncoder().encode(response)
            guard let encoded = String(data: data, encoding: .utf8) else {
                logger.error("cache encode failed: method=saveInsightsCache error=utf8Conversion")
                trackCacheFailure(operation: AICacheOperation.encode, errorType: "utf8_conversion")
                return
            }
            json = encoded
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache encode failed: method=saveInsightsCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.encode, error: error)
            return
        }

        let now = Date()
        let expiry = now.addingTimeInterval(cacheTTL)

        if let existing = loadInsightsCache() {
            existing.contentJSON = json
            existing.generatedAt = now
            existing.expiresAt = expiry
        } else {
            let entry = OverviewInsightCache(contentJSON: json, generatedAt: now, expiresAt: expiry)
            modelContext.insert(entry)
        }
        do {
            try modelContext.save()
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache save failed: method=saveInsightsCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.save, error: error)
        }
    }

    private func saveTrainingCache(json: String) {
        let now = Date()
        let expiry = now.addingTimeInterval(cacheTTL)

        if let existing = loadTrainingCache() {
            existing.contentJSON = json
            existing.generatedAt = now
            existing.expiresAt = expiry
        } else {
            let entry = TrainingAdviceCache(contentJSON: json, generatedAt: now, expiresAt: expiry)
            modelContext.insert(entry)
        }
        do {
            try modelContext.save()
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache save failed: method=saveTrainingCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.save, error: error)
        }
    }

    private func saveDataAnalysisCache(sampleType: String, json: String) {
        let now = Date()
        let expiry = now.addingTimeInterval(cacheTTL)

        if let existing = loadDataAnalysisCache(sampleType: sampleType) {
            existing.contentJSON = json
            existing.generatedAt = now
            existing.expiresAt = expiry
        } else {
            let entry = DataAnalysisCache(
                sampleType: sampleType,
                contentJSON: json,
                generatedAt: now,
                expiresAt: expiry
            )
            modelContext.insert(entry)
        }
        do {
            try modelContext.save()
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache save failed: method=saveDataAnalysisCache error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.save, error: error)
        }
    }

    // MARK: - Signpost Helpers

    private func buildPromptWithSignpost(
        _ method: String,
        _ build: () -> [ChatMessage]
    ) -> [ChatMessage] {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_analysis_prompt_build", id: signpostID, "method=\(method)")
        let result = build()
        signposter.endInterval("ai_analysis_prompt_build", state)
        return result
    }

    private func parseWithSignpost<T>(
        _ method: String,
        _ parse: () -> T?
    ) -> T? {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("ai_analysis_parse", id: signpostID, "method=\(method)")
        let result = parse()
        signposter.endInterval("ai_analysis_parse", state)
        return result
    }

    // MARK: - Logging Helpers

    private nonisolated func logSuccess(method: String, start: ContinuousClock.Instant) {
        let elapsed = ContinuousClock.now - start
        let ms = elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
        logger.info("AI call success: method=\(method) duration=\(ms)ms")
    }

    private nonisolated func describeErrorType(_ error: Error) -> String {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let code): return "httpError(\(code))"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is DecodingError {
            return "decodingError"
        }
        if error is EncodingError {
            return "encodingError"
        }
        return "unknown"
    }

    private nonisolated func telemetryErrorType(_ error: Error) -> TelemetryIdentifier {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "no_provider_available"
            case .networkError: return "network_error"
            case .httpError(let code):
                return TelemetryIdentifier(validating: "http_error_\(code)") ?? "http_error"
            case .missingAPIKey: return "missing_api_key"
            case .responseParsingFailed: return "response_parsing_failed"
            case .streamingInterrupted: return "streaming_interrupted"
            }
        }
        if error is DecodingError {
            return "decode_error"
        }
        if error is EncodingError {
            return "encode_error"
        }
        return "unknown"
    }

    private nonisolated func trackCacheFailure(
        operation: TelemetryIdentifier,
        error: Error
    ) {
        TelemetryService.shared.trackNonisolated(
            .aiCacheFailure(operation: operation, errorType: telemetryErrorType(error))
        )
    }

    private nonisolated func trackCacheFailure(
        operation: TelemetryIdentifier,
        errorType: TelemetryIdentifier
    ) {
        TelemetryService.shared.trackNonisolated(
            .aiCacheFailure(operation: operation, errorType: errorType)
        )
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let descriptor = FetchDescriptor<T>()
        let items: [T]
        do {
            items = try modelContext.fetch(descriptor)
        } catch {
            let errorType = describeErrorType(error)
            logger.error("cache fetch failed: method=deleteAll type=\(String(describing: T.self)) error=\(errorType)")
            trackCacheFailure(operation: AICacheOperation.fetch, error: error)
            return
        }
        for item in items {
            modelContext.delete(item)
        }
    }
}

// MARK: - AIServiceError Extension

private extension AIServiceError {
    var isNoProvider: Bool {
        if case .noProviderAvailable = self { return true }
        return false
    }
}
