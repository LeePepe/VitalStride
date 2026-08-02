import Foundation
import Synchronization

/// Deterministic per-kind ratio sampler.
///
/// Semantics: for a configured rate `p` on some kind, the sampler fires
/// approximately `p` fraction of the time over the long run. Concretely it uses
/// an accumulator per kind: each call adds `p`; when the accumulator crosses 1
/// it fires and subtracts 1. Over 100 calls at `p=0.2` this hits exactly 20,
/// well inside the ±2% SC-005 tolerance — and unlike RNG-based sampling it
/// stays deterministic under test.
///
/// Kinds without an entry (or with rate `0`) never fire. Rate is clamped to
/// `[0, 1]` at construction — an out-of-range rate is a config bug, not a
/// runtime one, so the clamp is silent by design (no crash, no log).
///
/// Concurrency: state is protected by Swift 6 `Mutex` from the `Synchronization`
/// module. No `@unchecked Sendable` — the compiler enforces Sendable safety
/// (Constitution II).
public final class RatioShadowSampler: ShadowSampler {
    private let rates: [AITaskKind: Double]
    private let accumulators: Mutex<[AITaskKind: Double]>

    public init(rates: [AITaskKind: Double]) {
        var clamped: [AITaskKind: Double] = [:]
        for (kind, rate) in rates {
            clamped[kind] = min(max(rate, 0), 1)
        }
        self.rates = clamped
        self.accumulators = Mutex([:])
    }

    public func shouldSample(kind: AITaskKind) -> Bool {
        guard let rate = rates[kind], rate > 0 else { return false }

        return accumulators.withLock { accum in
            let current = (accum[kind] ?? 0) + rate
            if current >= 1 {
                accum[kind] = current - 1
                return true
            } else {
                accum[kind] = current
                return false
            }
        }
    }
}
