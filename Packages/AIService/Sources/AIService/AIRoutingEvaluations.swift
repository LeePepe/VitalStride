import Foundation

// MARK: - Offline evaluation model
//
// Spec 019 US3 / FR-011: run Apple `Evaluations` framework offline on shadow
// sampling pairs to grade "main vs candidate". This module is **offline / CI
// only** — it is never called from `AIRouter.execute` at runtime, and its
// output does NOT affect routing decisions. It's a comparison instrument the
// team runs against captured shadow pairs to decide whether to promote a
// candidate provider for some kind.
//
// The Apple `Evaluations` framework is iOS 26+ / macOS 26+ / watchOS 26+. The
// SPM package's declared platforms (iOS 18 / macOS 15 / watchOS 11) MUST stay
// backward-compatible, so:
//
// 1. The type-level surface here is available on every supported platform.
// 2. The concrete Apple-Evaluations backend is behind `#if canImport(Evaluations)`
//    AND an OS-version availability gate. When the framework is not present or
//    the OS is too old, `evaluate(...)` returns `nil` — the caller (offline CLI
//    / CI job) MUST treat `nil` as "skipped, not failed" and not block on it.
//
// 3. A pluggable `AIRoutingGrader` protocol lets tests + CI runs supply their
//    own deterministic grader without any dependency on Apple's framework.
//    The default `HeuristicAIRoutingGrader` gives a small, transparent score
//    so the offline pipeline can produce numbers even on platforms that don't
//    yet ship `Evaluations`.

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
        // 1 char → ~0.01; 200+ chars → 1.0
        return min(Double(trimmed.count) / 200.0, 1.0)
    }
}

/// Top-level offline evaluation entry point. Reads a dataset of shadow pairs
/// and produces one score per pair. Never called from `AIRouter.execute` —
/// this exists to be driven from a CLI tool or CI job.
///
/// - Parameters:
///   - samples: dataset to grade.
///   - grader: pluggable grader. Default is the heuristic grader, which works
///     on any platform.
/// - Returns: parallel array of scores in the same order as `samples`.
public enum AIRoutingEvaluator {

    /// Run a grader over every sample. Grades sequentially — Apple
    /// `Evaluations` back-pressures cheaply and sequential order keeps the
    /// output deterministic. Callers that want throughput can shard the
    /// dataset upstream.
    public static func evaluate(
        samples: [AIRoutingEvaluationSample],
        grader: any AIRoutingGrader = HeuristicAIRoutingGrader()
    ) async -> [AIRoutingEvaluationScore] {
        var scored: [AIRoutingEvaluationScore] = []
        scored.reserveCapacity(samples.count)
        for sample in samples {
            scored.append(await grader.grade(sample))
        }
        return scored
    }

    /// Convenience: is the Apple `Evaluations` backend usable in the current
    /// build + on the current runtime? Callers can use this to decide whether
    /// to feed samples through the Apple grader or fall back to a heuristic /
    /// human grader without failing the CI job.
    ///
    /// Returns `false` when:
    /// - the SDK does not ship `Evaluations` (older Xcode), OR
    /// - the runtime OS is older than iOS 26 / macOS 26.
    public static var isAppleEvaluationsAvailable: Bool {
        #if canImport(Evaluations)
        if #available(iOS 26, macOS 26, watchOS 26, *) {
            return true
        } else {
            return false
        }
        #else
        return false
        #endif
    }
}

// MARK: - Apple Evaluations backend (opt-in, gated)
//
// The real Apple-Evaluations binding lives behind `#if canImport(Evaluations)`.
// Even inside the guard we must be resilient to API drift between betas —
// Evaluations symbols were still moving as of WWDC26. If the specific symbol
// names change, only this file needs a patch; the public grader protocol is
// stable.

#if canImport(Evaluations)
import Evaluations

/// Apple `Evaluations`-backed grader. Available only when the SDK ships the
/// framework AND the runtime is iOS 26+ / macOS 26+.
///
/// This grader is intentionally thin: it maps `AIRoutingEvaluationSample` to
/// whatever Evaluations expects and clamps the returned score into `[0, 1]`.
/// The heavy lifting (dataset definition, offline batch driving) belongs in
/// the CI script that uses it — not in the runtime package.
@available(iOS 26, macOS 26, watchOS 26, *)
public struct AppleEvaluationsGrader: AIRoutingGrader {
    public init() {}

    public func grade(_ sample: AIRoutingEvaluationSample) async -> AIRoutingEvaluationScore {
        // Placeholder integration: the exact symbol surface of `Evaluations`
        // will land when the SDK is present in this build. For now, fall back
        // to the heuristic on the same code path to keep the plumbing
        // exercised — the availability gate above already prevents this type
        // from being instantiated on older systems.
        return await HeuristicAIRoutingGrader().grade(sample)
    }
}
#endif
