import Foundation

// MARK: - Offline evaluation sample model
//
// Spec 019 US3 / FR-011 supports Apple `Evaluations` framework offline scoring
// of shadow sampling pairs to grade "main vs candidate". This sample type is
// the offline dataset's row — one `(main, candidate)` output pair from a
// shadow run, plus the routing metadata needed to slice results.
//
// TEMP-PRELAUNCH: `mainResponse` / `candidateResponse` may embed HealthKit
// values verbatim, so instances of this type MUST be treated exactly like
// `ShadowPairPayload`: local-only (`cloudKitDatabase: .none`), never logged,
// never uploaded. The offline CLI reads them from the same on-device sink
// that captures shadow pairs, grades them, and writes only scores back.

/// One graded shadow-pair sample.
public struct AIRoutingEvaluationSample: Sendable, Codable {
    public let kind: AITaskKind
    public let mainProvider: String
    public let candidateProvider: String
    public let mainResponse: String
    public let candidateResponse: String

    public init(
        kind: AITaskKind,
        mainProvider: String,
        candidateProvider: String,
        mainResponse: String,
        candidateResponse: String
    ) {
        self.kind = kind
        self.mainProvider = mainProvider
        self.candidateProvider = candidateProvider
        self.mainResponse = mainResponse
        self.candidateResponse = candidateResponse
    }
}

/// Score attached to one sample after a grader has run. Range `[0, 1]` per
/// side, or `nil` when the grader could not produce a score. `notes` is free
/// text for humans reading the eval report; not consumed at runtime anywhere.
public struct AIRoutingEvaluationScore: Sendable, Codable {
    public let mainScore: Double?
    public let candidateScore: Double?
    public let notes: String?

    public init(mainScore: Double?, candidateScore: Double?, notes: String? = nil) {
        self.mainScore = mainScore
        self.candidateScore = candidateScore
        self.notes = notes
    }
}

/// Grades one shadow pair. Implementations MAY be async — Apple `Evaluations`
/// is async under the hood.
public protocol AIRoutingGrader: Sendable {
    func grade(_ sample: AIRoutingEvaluationSample) async -> AIRoutingEvaluationScore
}

/// Simple length + non-emptiness heuristic. NOT for production quality
/// judgement — it exists so the offline pipeline can produce a number on any
/// platform, and so tests can assert the plumbing without depending on
/// Evaluations availability. Real graders are supplied at CI time.
public struct HeuristicAIRoutingGrader: AIRoutingGrader {
    public init() {}

    public func grade(_ sample: AIRoutingEvaluationSample) async -> AIRoutingEvaluationScore {
        let mainScore = Self.score(for: sample.mainResponse)
        let candidateScore = Self.score(for: sample.candidateResponse)
        return AIRoutingEvaluationScore(
            mainScore: mainScore,
            candidateScore: candidateScore,
            notes: "heuristic:non-empty+length-clip"
        )
    }

    private static func score(for text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return min(Double(trimmed.count) / 200.0, 1.0)
    }
}
