import Foundation

/// Validates the unmodified model wire payload before constructing sanitizing
/// public DTOs. Transport, availability and schema failures use local rules.
public struct FourLayerAdviceEngine: Sendable {
    private let provider: (any AIProvider)?
    private let fallback: DeterministicFourLayerEngine

    public init(provider: (any AIProvider)? = nil, fallback: DeterministicFourLayerEngine = DeterministicFourLayerEngine()) {
        self.provider = provider
        self.fallback = fallback
    }

    /// Source-compatible nonthrowing facade: cancellation returns local advice
    /// immediately. Call `generateCancellable` when cancellation must propagate.
    public func generate(snapshot: PhysiologicalSnapshot, model: String? = nil) async -> HolisticFourLayerReport {
        do { return try await generateCancellable(snapshot: snapshot, model: model) }
        catch { return fallback.makeReport(from: snapshot) }
    }

    public func generateCancellable(snapshot: PhysiologicalSnapshot, model: String? = nil) async throws -> HolisticFourLayerReport {
        try Task.checkCancellation()
        let local = fallback.makeReport(from: snapshot)
        guard let provider else { return local }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let snapshotJSON = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
            let example = String(decoding: try encoder.encode(local), as: UTF8.self)
            let prompt = """
            Return only a JSON HolisticFourLayerReport with exactly the structure of the example below.
            l1: include every example metric exactly once, preserving domain and metric identifiers;
            value is a finite number in the example's units or null/omitted for unknown observations.
            Each insight needs a nonblank message and severity normal|watch|warning|critical.
            l2: exactly sleepTrainingCoupling (sleep + trainingLoad) and stepsBodyCoupling
            (neat + heart or trainingLoad), each with nonblank relationship/message and severity.
            l3: REQUIRED integer readinessScore, autonomicScore, sleepRestorationScore, fatigueBalanceScore
            in 0...100; mesocyclePhase accumulation|intensification|realization|deload;
            recommendedIntensityCap finite 0...1; nonempty contributingInsights of nonblank strings.
            l4: integer northStarScore 0...100, nonblank cohesive directive, 1...3 nonblank prioritizedActions.
            generatedAt: finite seconds since 2001-01-01, using the snapshot's as-of date.
            Never infer normal recovery from missing data or diagnose disease. Intake and body composition
            are not supplied: expenditure alone cannot establish caloric balance or body trends.
            Example (also the conservative baseline for this snapshot):
            \(example)
            """
            let response = try await provider.chat(messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: snapshotJSON),
            ], model: model)
            try Task.checkCancellation()
            let data = Data(response.content.utf8)
            let raw = try JSONDecoder().decode(RawReport.self, from: data)
            guard raw.isValid(relativeTo: local) else { return local }
            return HolisticFourLayerReport(
                l1: raw.l1, l2: raw.l2,
                l3: .init(readinessScore: raw.l3.readinessScore, autonomicScore: raw.l3.autonomicScore,
                          sleepRestorationScore: raw.l3.sleepRestorationScore, fatigueBalanceScore: raw.l3.fatigueBalanceScore,
                          mesocyclePhase: raw.l3.mesocyclePhase, recommendedIntensityCap: raw.l3.recommendedIntensityCap,
                          contributingInsights: raw.l3.contributingInsights),
                l4: .init(northStarScore: raw.l4.northStarScore, directive: raw.l4.directive,
                          prioritizedActions: raw.l4.prioritizedActions),
                generatedAt: raw.generatedAt
            )
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return local
        }
    }

    public func synthesize(snapshot: PhysiologicalSnapshot, model: String? = nil) async -> HolisticFourLayerReport {
        await generate(snapshot: snapshot, model: model)
    }
}

private struct RawReport: Decodable {
    let l1: [L1SingleMetricInsight]
    let l2: [L2CoupledInsight]
    let l3: Readiness
    let l4: NorthStar
    let generatedAt: Date

    struct Readiness: Decodable {
        let readinessScore: Int
        let autonomicScore: Int
        let sleepRestorationScore: Int
        let fatigueBalanceScore: Int
        let mesocyclePhase: MesocyclePhase
        let recommendedIntensityCap: Double
        let contributingInsights: [String]
    }
    struct NorthStar: Decodable {
        let northStarScore: Int
        let directive: String
        let prioritizedActions: [String]
    }

    func isValid(relativeTo local: HolisticFourLayerReport) -> Bool {
        func nonblank(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let scores = [l3.readinessScore, l3.autonomicScore, l3.sleepRestorationScore, l3.fatigueBalanceScore, l4.northStarScore]
        guard scores.allSatisfy({ (0...100).contains($0) }),
              l3.recommendedIntensityCap.isFinite, (0...1).contains(l3.recommendedIntensityCap),
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              generatedAt == local.generatedAt,
              !l3.contributingInsights.isEmpty, l3.contributingInsights.allSatisfy(nonblank),
              nonblank(l4.directive), (1...3).contains(l4.prioritizedActions.count),
              l4.prioritizedActions.allSatisfy(nonblank),
              l1.count == local.l1.count, Set(l1.map(\.metric)).count == l1.count,
              l1.allSatisfy({ item in
                  nonblank(item.message) && (item.value?.isFinite ?? true)
                    && local.l1.contains(where: { expected in
                        expected.metric == item.metric && expected.domain == item.domain
                            && (expected.value == nil ? item.value == nil && item.severity != .normal : item.value != nil)
                    })
              }), l2.count == 2,
              l2.allSatisfy({ nonblank($0.message) && nonblank($0.relationship) }) else { return false }
        let sleep = l2.filter { $0.relationship == "sleepTrainingCoupling" }
        let steps = l2.filter { $0.relationship == "stepsBodyCoupling" }
        return sleep.count == 1 && sleep.first?.primaryDomain == .sleep && sleep.first?.secondaryDomain == .trainingLoad
            && steps.count == 1 && steps.first?.primaryDomain == .neat
            && (steps.first?.secondaryDomain == .heart || steps.first?.secondaryDomain == .trainingLoad)
    }
}
