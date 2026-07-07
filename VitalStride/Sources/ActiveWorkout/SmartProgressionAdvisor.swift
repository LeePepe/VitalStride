// Smart Progression Advisor — MY-1197 / T002.
//
// This file introduces the `ProgressionAdvice` enum, the pure-value contract
// returned by the (yet-to-be-implemented) `SmartProgressionAdvisor.suggest`
// engine.  Spec: `specs/006-smart-progression/spec.md` (FR-002, FR-005) and
// plan: `specs/006-smart-progression/plan.md` (Structure Decision).
//
// Scope of this task (T002) is intentionally narrow: define the type only.
// The advisor's `suggest(...)` function lands in a follow-up task (T003) and
// its rule-branch tests in T004.  Keeping the enum and the future engine in
// the same file matches the plan's Structure Decision (advisor stays at the
// app-target layer alongside the 004 `PreviousSetLookup` it consumes).

import Foundation

/// Progression recommendation returned by `SmartProgressionAdvisor` for a
/// single upcoming main set.
///
/// Each case carries the concrete tap-to-fill payload (`weight`, `reps`) so
/// the SetRow chip in User Story 1 can render "建议 {重量} × {次数}" and
/// one-tap fill without re-deriving values from the caller, plus a
/// `reason` string suitable for user-facing display (localized upstream via
/// `String(localized:)` per Constitution VI / FR-007).
///
/// The four cases mirror the FR-002 contract:
///
/// - `maintain`: keep last session's load — either the client is inside the
///   target rep range or the last set slipped below the lower bound while
///   earlier sets held.  No plate change.
/// - `increaseWeight`: every previous main set hit the upper rep bound —
///   ready to progress the load (increment archetype: small muscle groups
///   +2.5 kg, large muscle groups +5 kg — FR-003; the archetype selection
///   itself belongs to T003 and is not encoded in this type).
/// - `increaseReps`: keep load, target more reps within the range.  Reserved
///   for future rule variants; carried here so the enum is closed at the
///   type level and downstream `switch` statements are exhaustive without
///   another migration when the rule lands.
/// - `decreaseWeight`: every previous main set fell below the lower bound —
///   back off the load (archetype increment mirrors `increaseWeight`).
///
/// Equatable is auto-synthesized (all associated values are `Equatable`
/// value types) so `SmartProgressionAdvisorTests` can assert branch outputs
/// directly.  `Sendable` is auto-synthesized on the same basis, so the
/// advice can flow across actor boundaries (e.g. from a background compute
/// hop into the `@MainActor` SetRow) without any concurrency bypasses.
enum ProgressionAdvice: Equatable, Sendable {
    /// Hold the load and the rep target — either the last session is
    /// mid-range or the drop-off is isolated to the final set.
    ///
    /// - Parameters:
    ///   - weight: Suggested next-set weight (kg).  Equal to the prior
    ///     load for a pure hold.
    ///   - reps: Suggested next-set rep count.
    ///   - reason: Short, user-facing rationale (localized upstream).
    case maintain(weight: Double, reps: Int, reason: String)

    /// Progress the load — every prior main set met the upper rep bound.
    ///
    /// - Parameters:
    ///   - weight: Suggested next-set weight (kg) with the muscle-group
    ///     archetype increment already applied by the engine.
    ///   - reps: Suggested next-set rep count (typically the lower bound
    ///     of the target range after a load bump).
    ///   - reason: Short, user-facing rationale (localized upstream).
    case increaseWeight(weight: Double, reps: Int, reason: String)

    /// Hold load and push reps — reserved rule branch for future engine
    /// versions where the last session sat below the upper bound but
    /// above the lower bound and the user prefers volume progression.
    ///
    /// - Parameters:
    ///   - weight: Suggested next-set weight (kg).  Same as prior load.
    ///   - reps: Suggested next-set rep count (higher than last session).
    ///   - reason: Short, user-facing rationale (localized upstream).
    case increaseReps(weight: Double, reps: Int, reason: String)

    /// Back off the load — every prior main set fell below the lower
    /// rep bound.
    ///
    /// - Parameters:
    ///   - weight: Suggested next-set weight (kg) with the muscle-group
    ///     archetype decrement already applied by the engine.
    ///   - reps: Suggested next-set rep count (typically the upper bound
    ///     of the target range after backing off).
    ///   - reason: Short, user-facing rationale (localized upstream).
    case decreaseWeight(weight: Double, reps: Int, reason: String)
}

// MARK: - Uniform payload accessors

extension ProgressionAdvice {
    /// Suggested next-set weight (kg) regardless of advice kind — lets the
    /// SetRow chip render tap-to-fill without switching on the case.
    var suggestedWeight: Double {
        switch self {
        case let .maintain(weight, _, _),
             let .increaseWeight(weight, _, _),
             let .increaseReps(weight, _, _),
             let .decreaseWeight(weight, _, _):
            return weight
        }
    }

    /// Suggested next-set rep count regardless of advice kind.
    var suggestedReps: Int {
        switch self {
        case let .maintain(_, reps, _),
             let .increaseWeight(_, reps, _),
             let .increaseReps(_, reps, _),
             let .decreaseWeight(_, reps, _):
            return reps
        }
    }

    /// User-facing rationale for the advice.  Localization is performed by
    /// the engine (T003) via `String(localized:)` — FR-007 / Constitution
    /// VI — so callers should render this value as-is.
    var reason: String {
        switch self {
        case let .maintain(_, _, reason),
             let .increaseWeight(_, _, reason),
             let .increaseReps(_, _, reason),
             let .decreaseWeight(_, _, reason):
            return reason
        }
    }
}
