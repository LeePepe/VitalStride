import Foundation

/// Top-level offline evaluation entry point. Reads a dataset of shadow pairs
/// and produces one score per pair. Never called from `AIRouter.execute` —
/// this exists to be driven from a CLI tool or CI job.
///
/// The Apple `Evaluations` framework is iOS 26+ / macOS 26+ / watchOS 26+. The
/// SPM package's declared platforms (iOS 18 / macOS 15 / watchOS 11) MUST stay
/// backward-compatible, so:
///
/// 1. The type-level surface here is available on every supported platform.
/// 2. The concrete Apple-Evaluations backend is behind `#if canImport(Evaluations)`
///    AND an OS-version availability gate. When the framework is not present or
///    the OS is too old, callers use `HeuristicAIRoutingGrader` (or a real CI
///    grader) — `isAppleEvaluationsAvailable == false` is the offline pipeline's
///    signal to fall back, not to fail.
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
/// NOTE: current implementation is a placeholder that delegates to
/// `HeuristicAIRoutingGrader` so the plumbing stays exercised while the
/// concrete Evaluations symbol surface stabilizes. The returned score's
/// `notes` field is prefixed with `placeholder:` so anyone reading the eval
/// report can tell it wasn't produced by the real backend yet.
@available(iOS 26, macOS 26, watchOS 26, *)
public struct AppleEvaluationsGrader: AIRoutingGrader {
    public init() {}

    public func grade(_ sample: AIRoutingEvaluationSample) async -> AIRoutingEvaluationScore {
        let heuristic = await HeuristicAIRoutingGrader().grade(sample)
        let notes = "placeholder:" + (heuristic.notes ?? "")
        return AIRoutingEvaluationScore(
            mainScore: heuristic.mainScore,
            candidateScore: heuristic.candidateScore,
            notes: notes
        )
    }
}
#endif
