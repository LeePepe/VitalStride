import Foundation
import HealthKitService

// MARK: - WatchWorkoutDisplayState
//
// Compact, Equatable display-model that the watch in-workout screen
// (MY-1292) will render. This type intentionally carries only what the
// UI needs to draw a frame: no service references, no closures, no
// non-Sendable/live handles. That keeps SwiftUI diffing cheap and lets
// unit tests assert against value-typed snapshots.
//
// Owned by MY-1290. Preset composition (MY-1292) reads from here.
//
// Privacy §I: the type is display-only. HR values live in `hr` for
// rendering; any log-side of the pipeline stays in `WatchWorkoutViewModel`
// and never emits the bpm.

/// Three watch-side HR presentation states (spec §6a). "connected(_)"
/// is the only state that surfaces a numeric bpm. `notConnected` /
/// `connectedNoData` never render a bare `--` — the module layer
/// converts them into pill + placeholder art.
public enum HRDisplayState: Sendable, Equatable {
    /// No WC session / no HR stream established yet.
    case notConnected
    /// Session active, awaiting first sample.
    case connectedNoData
    /// Live HR sample present.
    /// `zone` is nil until the iPhone starts pushing zone with HR
    /// (post-MY-1290; spec §11.1 assertion). UI hides the zone pill
    /// when nil rather than inventing a default.
    case connected(bpm: Int, zone: Int?)
}

/// Coarse saving/finishing lifecycle of the workout — orthogonal to
/// the running/next-set state. Rendered as a full-screen overlay
/// (spec §6b "Session saving") when non-idle.
public enum WorkoutSavingState: Sendable, Equatable {
    case idle
    case saving
    case finished
    case failed(reason: String)
}

/// (completedSetCount, totalSetCount) mirror of the snapshot progress
/// counters, normalized so consumers don't dip into the transport
/// type.
public struct WatchProgressDisplay: Sendable, Equatable {
    public let completedSetCount: Int
    public let totalSetCount: Int

    public init(completedSetCount: Int, totalSetCount: Int) {
        self.completedSetCount = completedSetCount
        self.totalSetCount = totalSetCount
    }
}

/// Next-set descriptor consumed by the next-set modules (fullInfo /
/// nextFocus / list). Nil ⇒ "自由训练 / no plan"; the module layer
/// switches presentation accordingly.
public struct WatchNextSetDisplay: Sendable, Equatable, Identifiable {
    /// Corresponds to `WorkoutStateSnapshot.PlannedSet.id`.
    public let id: UUID
    /// 1-based ordinal within the current exercise.
    public let index: Int
    /// Total sets for the current exercise.
    public let total: Int
    /// User-facing exercise name (already resolved on iPhone side).
    public let exerciseName: String
    public let targetReps: Int?
    /// iPhone pre-formats the weight (e.g. "60kg") — watch does not
    /// re-derive units (spec §11.2 assertion). Passing the raw kilogram
    /// value here for the module layer to format is acceptable.
    public let targetWeightKg: Double?
    /// True when this is the final set of the final exercise — CTA
    /// flips to "完成训练" (module layer decides that copy).
    public let isLastSetOfWorkout: Bool

    public init(
        id: UUID,
        index: Int,
        total: Int,
        exerciseName: String,
        targetReps: Int?,
        targetWeightKg: Double?,
        isLastSetOfWorkout: Bool
    ) {
        self.id = id
        self.index = index
        self.total = total
        self.exerciseName = exerciseName
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.isLastSetOfWorkout = isLastSetOfWorkout
    }
}

/// The single Equatable snapshot the watch screen renders from. Every
/// field is pure data — SwiftUI can diff two `WatchWorkoutDisplayState`
/// values in O(fields).
public struct WatchWorkoutDisplayState: Sendable, Equatable {
    /// Latest layout config (spec §7 axis A + axis B). Defaults to
    /// `WatchScreenConfig.defaultConfig()` until iPhone pushes a real one.
    public let config: WatchScreenConfig
    /// HR three-state (spec §6a).
    public let hr: HRDisplayState
    /// Elapsed seconds since workout start on the iPhone clock.
    /// Non-negative; nil ⇒ no active workout.
    public let elapsedSeconds: TimeInterval?
    /// Workout-wide progress (setCount → dots + band).
    public let progress: WatchProgressDisplay?
    /// User-facing current exercise name (resolved by iPhone). nil ⇒
    /// no current exercise (either freeform or no active workout).
    public let currentExerciseName: String?
    /// Next set to perform. nil ⇒ freeform / no plan / no active workout.
    public let nextSet: WatchNextSetDisplay?
    /// Session-wide average HR (nil until 1st sample). Renders in the
    /// avg/peak module (spec §5 tier-2 right column).
    public let averageBPM: Int?
    /// Session-wide peak HR (nil until 1st sample).
    public let peakBPM: Int?
    /// WC connection to the paired iPhone. Drives the fallback UX
    /// when the state stream is silent.
    public let connection: WatchConnectionState
    /// Saving overlay lifecycle.
    public let saving: WorkoutSavingState

    public init(
        config: WatchScreenConfig,
        hr: HRDisplayState,
        elapsedSeconds: TimeInterval?,
        progress: WatchProgressDisplay?,
        currentExerciseName: String?,
        nextSet: WatchNextSetDisplay?,
        averageBPM: Int?,
        peakBPM: Int?,
        connection: WatchConnectionState,
        saving: WorkoutSavingState
    ) {
        self.config = config
        self.hr = hr
        self.elapsedSeconds = elapsedSeconds
        self.progress = progress
        self.currentExerciseName = currentExerciseName
        self.nextSet = nextSet
        self.averageBPM = averageBPM
        self.peakBPM = peakBPM
        self.connection = connection
        self.saving = saving
    }

    /// Deterministic initial state used before any stream fires. Config
    /// is the spec §7 "Watch fallback" default (`fullInfo` + all modules
    /// on) so the screen renders immediately without waiting on WC.
    public static let initial = WatchWorkoutDisplayState(
        config: WatchScreenConfig.defaultConfig(),
        hr: .notConnected,
        elapsedSeconds: nil,
        progress: nil,
        currentExerciseName: nil,
        nextSet: nil,
        averageBPM: nil,
        peakBPM: nil,
        connection: .unsupported,
        saving: .idle
    )
}

// MARK: - WorkoutStateSnapshot → display projection
//
// Pure functions (no service dependency, no concurrency) so unit tests
// can exercise them directly. Kept here — next to the display state —
// so the projection contract is obvious to future readers.

extension WatchWorkoutDisplayState {
    /// Return a new state with `config` replaced.
    public func with(config: WatchScreenConfig) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            currentExerciseName: currentExerciseName,
            nextSet: nextSet,
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Return a new state with `hr` replaced.
    public func with(hr: HRDisplayState) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            currentExerciseName: currentExerciseName,
            nextSet: nextSet,
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Return a new state with `connection` replaced.
    public func with(connection: WatchConnectionState) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            currentExerciseName: currentExerciseName,
            nextSet: nextSet,
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Return a new state with `saving` replaced.
    public func with(saving: WorkoutSavingState) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            currentExerciseName: currentExerciseName,
            nextSet: nextSet,
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Return a new state with running avg/peak recomputed from a
    /// freshly-received bpm. Uses simple running-mean semantics; the
    /// count is tracked externally by the view-model.
    public func withAvgPeak(bpm: Int, runningMean: Int?, peak: Int?) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            currentExerciseName: currentExerciseName,
            nextSet: nextSet,
            averageBPM: runningMean ?? averageBPM,
            peakBPM: peak ?? peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Project a `WorkoutStateSnapshot` into the display slice, keeping
    /// unrelated fields (hr / avg / saving) from the previous state.
    public func with(snapshot: WorkoutStateSnapshot) -> WatchWorkoutDisplayState {
        WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: max(0, snapshot.elapsedSeconds),
            progress: WatchProgressDisplay(
                completedSetCount: snapshot.progress.completedSetCount,
                totalSetCount: snapshot.progress.totalSetCount
            ),
            currentExerciseName: snapshot.currentExerciseName,
            nextSet: WatchWorkoutDisplayState.pickNextSet(from: snapshot),
            averageBPM: averageBPM,
            peakBPM: peakBPM,
            connection: connection,
            saving: saving
        )
    }

    /// Pick the first not-yet-completed set as "next", using the
    /// snapshot's plan order. Returns nil for freeform / plan-complete.
    static func pickNextSet(from snapshot: WorkoutStateSnapshot) -> WatchNextSetDisplay? {
        guard !snapshot.sets.isEmpty, let exerciseName = snapshot.currentExerciseName else {
            return nil
        }
        // The snapshot lists sets ordered by `index`; we honor that.
        let ordered = snapshot.sets.sorted { $0.index < $1.index }
        guard let next = ordered.first(where: { !$0.isCompleted }) else {
            return nil
        }
        let position = ordered.firstIndex(where: { $0.id == next.id }).map { $0 + 1 } ?? next.index
        let total = ordered.count
        let isLast = position == total &&
            snapshot.progress.completedSetCount + 1 >= snapshot.progress.totalSetCount
        return WatchNextSetDisplay(
            id: next.id,
            index: position,
            total: total,
            exerciseName: exerciseName,
            targetReps: next.targetReps,
            targetWeightKg: next.targetWeightKg,
            isLastSetOfWorkout: isLast
        )
    }
}
