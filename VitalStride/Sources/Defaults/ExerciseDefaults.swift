import Foundation
import VitalModels

/// Rep-range bucket used by the three preset keys on the right side of the
/// custom workout keyboard.
///
/// Each bucket has a fixed integer range (inclusive). Tapping the same bucket
/// in succession rotates through the range in ascending order and wraps back
/// to the start.
enum PresetRepBucket: String, CaseIterable, Sendable, Equatable {
    case high  // hypertrophy / endurance: 15-20
    case mid   // hypertrophy: 8-12
    case low   // strength: 4-6

    var range: ClosedRange<Int> {
        switch self {
        case .high: 15...20
        case .mid: 8...12
        case .low: 4...6
        }
    }
}

/// Pure-function preset resolver for the workout keyboard's right-side keys.
///
/// Rules (see MY-1072 spec):
/// * `weight` is resolved from a priority chain:
///     1. `exercise.defaultWeightHigh/Mid/Low` (non-nil, > 0) — Stage 1 seeded values
///     2. Most recent same-exercise set in the current workout
///     3. `nil` (caller preserves existing input; no overwrite)
/// * `reps` uses the bucket range and cycles on repeat taps.
///
/// The returned `weight` is always **in kilograms** — VitalModels stores weight
/// in kg. Callers converting to a display unit (lb) do so at the boundary.
enum ExerciseDefaults {
    /// Resolve the preset value for a given bucket.
    ///
    /// - Parameters:
    ///   - bucket: Which preset key was pressed.
    ///   - exercise: The exercise whose defaults to consult. Optional so the
    ///     keyboard can render before an exercise is bound.
    ///   - recentWeightKg: Most recent same-exercise weight in the current
    ///     workout (kg), if any. Passed in by the caller — this function does
    ///     not touch SwiftData.
    ///   - previousReps: Reps currently on the tapped preset for cycling; if
    ///     nil, returns the low end of the range.
    /// - Returns: `(weightKg, reps)` — `weightKg` is nil when the priority
    ///   chain yields no value; caller MUST NOT overwrite the input in that
    ///   case.
    static func resolvePreset(
        bucket: PresetRepBucket,
        exercise: Exercise?,
        recentWeightKg: Double?,
        previousReps: Int?
    ) -> (weightKg: Double?, reps: Int) {
        let weight = resolveWeightKg(
            bucket: bucket,
            exercise: exercise,
            recentWeightKg: recentWeightKg
        )
        let reps = nextReps(in: bucket.range, previous: previousReps)
        return (weight, reps)
    }

    /// Priority-chained weight lookup — see doc comment on `resolvePreset`.
    /// Exposed for isolated testing.
    static func resolveWeightKg(
        bucket: PresetRepBucket,
        exercise: Exercise?,
        recentWeightKg: Double?
    ) -> Double? {
        if let exercise, let seeded = seededWeightKg(bucket: bucket, exercise: exercise) {
            return seeded
        }
        if let recent = recentWeightKg, recent > 0 {
            return recent
        }
        return nil
    }

    /// Cycle to the next reps value within a bucket range.
    ///
    /// * If `previous` is nil or outside the current cycle, returns the low
    ///   end of the cycle.
    /// * Otherwise returns the next value in the fixed cycle and wraps back
    ///   to the start after the top. Concrete cycles (per spec):
    ///     * high (15-20): 15 → 18 → 20 → 15 …
    ///     * mid (8-12):    8 → 10 → 12 → 8 …
    ///     * low (4-6):     4 → 5 → 6 → 4 …
    /// Exposed for isolated testing.
    static func nextReps(in range: ClosedRange<Int>, previous: Int?) -> Int {
        let cycle = cycleValues(for: range)
        guard let previous, let idx = cycle.firstIndex(of: previous) else {
            return cycle[0]
        }
        let nextIdx = (idx + 1) % cycle.count
        return cycle[nextIdx]
    }

    // MARK: - Internals

    private static func seededWeightKg(
        bucket: PresetRepBucket,
        exercise: Exercise
    ) -> Double? {
        let raw: Double?
        switch bucket {
        case .high: raw = exercise.defaultWeightHigh
        case .mid: raw = exercise.defaultWeightMid
        case .low: raw = exercise.defaultWeightLow
        }
        guard let raw, raw > 0 else { return nil }
        return raw
    }

    /// Materialise the exact cycle for a bucket range. Kept as a small pure
    /// helper so tests can assert against it directly.
    static func cycleValues(for range: ClosedRange<Int>) -> [Int] {
        switch range {
        case 15...20: [15, 18, 20]
        case 8...12: [8, 10, 12]
        case 4...6: [4, 5, 6]
        default:
            // Generic fallback: start, midpoint, end. Ensures three distinct
            // touch points and always ends on the upper bound.
            fallbackCycle(for: range)
        }
    }

    private static func fallbackCycle(for range: ClosedRange<Int>) -> [Int] {
        let lo = range.lowerBound
        let hi = range.upperBound
        if lo == hi { return [lo] }
        let mid = lo + (hi - lo) / 2
        if mid == lo || mid == hi { return [lo, hi] }
        return [lo, mid, hi]
    }
}

// MARK: - Unit conversion helpers

extension ExerciseDefaults {
    /// Convert a canonical kg weight to a display unit value.
    ///
    /// * `.kg` returns the value as-is.
    /// * `.lb` uses the standard 1 kg = 2.20462 lb factor (matches the
    ///   conversion used throughout `ActiveWorkoutView`).
    static func displayWeight(fromKg weightKg: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: weightKg
        case .lb: weightKg * 2.20462
        }
    }

    /// Convert a display-unit value back to canonical kg.
    static func canonicalWeight(fromDisplay display: Double, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: display
        case .lb: display / 2.20462
        }
    }
}
