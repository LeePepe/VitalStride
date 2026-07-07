// Smart Progression Advisor — MY-1197 (T002 type) + MY-1198 (T003 engine).
//
// This file houses the pure `SmartProgressionAdvisor` engine and the
// `ProgressionAdvice` value it returns.  Spec:
// `specs/006-smart-progression/spec.md` (FR-002, FR-003, FR-005) and plan:
// `specs/006-smart-progression/plan.md` (Structure Decision — advisor lives at
// the app-target layer alongside the 004 `PreviousSetLookup` that supplies its
// history input).
//
// Scope split:
//  * T002 (MY-1197) — introduced the `ProgressionAdvice` enum below.
//  * T003 (MY-1198, this task) — implements the pure `suggest(...)` engine.
//  * T004 (follow-up)          — adds branch-covering unit tests.
//
// The engine is deliberately pure: no SwiftData fetches, no telemetry, no
// logging, no UI — history is collected upstream by repeatedly calling 004's
// `PreviousSetLookup.previousMainSet(...)`.  Callers pass the resulting
// `[ExerciseSet]` in; the advisor returns a `ProgressionAdvice?` and nothing
// else.

import Foundation
import VitalModels

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

// MARK: - SmartProgressionAdvisor engine (T003)

/// Pure rule engine that turns "the same-exercise main-set sequence from the
/// user's last session" into a `ProgressionAdvice` for the next set.
///
/// The engine follows the FR-002 / FR-005 contract exactly:
///
/// 1. **Empty history** (`previousMainSets.isEmpty`) → `nil` — SetRow renders
///    no chip (matches the 004 no-history behavior, FR-004 边界).
/// 2. **All sets hit the upper rep bound** → `.increaseWeight` — bump the
///    load using the muscle-group archetype increment (small +2.5 kg / large
///    +5 kg, FR-003), keep reps at the lower bound of the target range.
/// 3. **Last set fell below the lower bound** (but earlier sets held) →
///    `.maintain` — the drop-off is isolated; give the load another session.
/// 4. **Every set fell below the lower bound** → `.decreaseWeight` — back off
///    the load by the same archetype increment.
/// 5. **Otherwise** (mid-range, or any combination not covered above) →
///    `.maintain` at the last set's weight.
///
/// Notes:
///
/// * Increase / decrease branches key off the **first set's** weight.  It is
///   the anchor working weight; back-off drops later in the session don't
///   move the target load if the algorithm has already decided to progress.
/// * Suggested reps after a load bump default to the range's lower bound and
///   suggested reps after backing off default to the upper bound — both are
///   the classic Fitbod progression heuristic (`plan.md` Summary).
/// * The engine is pure and `Sendable`: it does not read SwiftData, does not
///   log, does not emit telemetry, does not touch UI.  T004 will exercise
///   every branch via `XCTest` without a container.
enum SmartProgressionAdvisor {
    /// Small-muscle-group load increment (kg) — FR-003.
    static let smallMuscleIncrementKg: Double = 2.5

    /// Large-muscle-group load increment (kg) — FR-003.
    static let largeMuscleIncrementKg: Double = 5.0

    /// Muscle groups that get the larger load bump.  The spec calls out
    /// "小肌群 +2.5 / 大肌群 +5"; legs / back / chest / fullBody are the
    /// conventional large groups, shoulders / arms / core the small ones.
    /// Kept private so the archetype table is one source of truth.
    private static let largeMuscleGroups: Set<MuscleGroup> = [
        .legs, .back, .chest, .fullBody,
    ]

    /// Load increment (kg) applied by `.increaseWeight` / `.decreaseWeight`
    /// for the given muscle group.  A `nil` muscle group (e.g. exercise not
    /// yet classified) falls back to the conservative small-group increment.
    static func loadIncrementKg(for muscleGroup: MuscleGroup?) -> Double {
        guard let muscleGroup else { return smallMuscleIncrementKg }
        return largeMuscleGroups.contains(muscleGroup)
            ? largeMuscleIncrementKg
            : smallMuscleIncrementKg
    }

    /// Suggest the next-set progression based on the same exercise's last
    /// main-set sequence and the user's preferred rep range.
    ///
    /// - Parameters:
    ///   - previousMainSets: The sets from the user's most recent session for
    ///     this exercise, ordered as performed (`order` ascending).  Sub-sets
    ///     (drop-set / pyramid) are expected to be filtered out upstream —
    ///     004's `PreviousSetLookup.previousMainSet` already does this; if
    ///     the caller passes them anyway they are treated as main sets, which
    ///     is safe (still `ExerciseSet` weight/reps) but not spec-preferred.
    ///   - userPreferredRepRange: Closed rep range (e.g. `8...12`) driving
    ///     the "hit the upper bound" and "fell below the lower bound"
    ///     comparisons.  Passing a degenerate range like `10...10` is legal
    ///     and treated as "target reps = 10".
    ///   - muscleGroup: The exercise's primary muscle group.  Selects the
    ///     archetype load increment via ``loadIncrementKg(for:)``.  Pass
    ///     `nil` when unknown; the conservative small-group increment is
    ///     applied.
    /// - Returns: A `ProgressionAdvice` describing the recommended next set,
    ///   or `nil` when `previousMainSets` is empty (no history → no chip).
    static func suggest(
        previousMainSets: [ExerciseSet],
        userPreferredRepRange: ClosedRange<Int>,
        muscleGroup: MuscleGroup? = nil
    ) -> ProgressionAdvice? {
        guard let firstSet = previousMainSets.first,
              let lastSet = previousMainSets.last
        else {
            return nil
        }

        let lowerBound = userPreferredRepRange.lowerBound
        let upperBound = userPreferredRepRange.upperBound
        let increment = loadIncrementKg(for: muscleGroup)

        let allHitUpperBound = previousMainSets.allSatisfy { $0.reps >= upperBound }
        let allBelowLowerBound = previousMainSets.allSatisfy { $0.reps < lowerBound }
        let lastBelowLowerBound = lastSet.reps < lowerBound

        if allHitUpperBound {
            let suggestedWeight = max(0, firstSet.weight + increment)
            return .increaseWeight(
                weight: suggestedWeight,
                reps: lowerBound,
                reason: String(
                    localized: "smart_progression.reason.increase_weight",
                    defaultValue: "All sets hit target — increase weight",
                    comment: "SetRow chip reason when every prior main set hit the upper rep bound (translated to zh in xcstrings by T007)"
                )
            )
        }

        if allBelowLowerBound {
            let suggestedWeight = max(0, firstSet.weight - increment)
            return .decreaseWeight(
                weight: suggestedWeight,
                reps: upperBound,
                reason: String(
                    localized: "smart_progression.reason.decrease_weight",
                    defaultValue: "Below lower bound — decrease weight",
                    comment: "SetRow chip reason when every prior main set fell below the lower rep bound (translated to zh in xcstrings by T007)"
                )
            )
        }

        if lastBelowLowerBound {
            return .maintain(
                weight: lastSet.weight,
                reps: lastSet.reps,
                reason: String(
                    localized: "smart_progression.reason.maintain_dropoff",
                    defaultValue: "Last set dropped — maintain",
                    comment: "SetRow chip reason when only the final prior main set fell below the lower rep bound (translated to zh in xcstrings by T007)"
                )
            )
        }

        return .maintain(
            weight: lastSet.weight,
            reps: lastSet.reps,
            reason: String(
                localized: "smart_progression.reason.maintain_inrange",
                defaultValue: "Within range — maintain",
                comment: "SetRow chip reason when the prior main sets sat within the target rep range (translated to zh in xcstrings by T007)"
            )
        )
    }
}
