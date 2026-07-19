# ADR-0010: Promote watchOS Live Heart-Rate Workout Session (narrow exception to ADR-0002)

**Status**: Accepted
**Date**: 2026-07-19
**Deciders**: tianpli (project owner)
**Amends**: [ADR-0002](0002-defer-watchos-macos-feature-work.md) — narrow, feature-scoped promotion (does NOT reverse it)
**Related**: Constitution §VII (watchOS/macOS 是 companion), §I (健康数据隐私零妥协)

## Addendum 2026-07-19 — bidirectional workout-state sync + configurable screen

The original decision below specced heart rate flowing **watch → iPhone** only. Product design
(`specs/watch-in-workout-screen.md`) expanded the promoted screen to (a) show the **next set** and
let the user **complete a set on the watch**, and (b) be **user-configurable** (layout preset +
module toggles). Both are still inside this narrow exception (the one in-workout live-HR training
screen); neither reopens general watchOS feature work. This addendum records the widened data flow:

1. **The WatchConnectivity channel is bidirectional and carries workout state, not just HR:**
   - **iPhone → watch**: `WorkoutStateSnapshot` (current exercise, its sets with target
     reps/weight + completion state, elapsed, set totals) + `WatchScreenConfig` (layout preset +
     enabled modules). Pushed on session start and on every iPhone-side change (application-context,
     latest-wins).
   - **watch → iPhone**: live HR samples (as before) + `SetCompletedEvent` when the user taps the
     primary button on the watch.
2. **iPhone remains the source of truth** for workout state; the watch's set-completion is an
   optimistic local advance reconciled by iPhone.
3. **Privacy §I still binds fully.** HR values stay display-only and unlogged. `WorkoutStateSnapshot`
   carries training data (reps/weight/exercise) — training data is CloudKit-syncable per §I, but WC
   payloads are transient transport, not a new persisted store. `WatchScreenConfig` carries no
   health values (it's app config) and may sync as app config; re-verify §I at build time.

Scope unchanged otherwise: still one screen, no complications, no independent watch workout product.

## Context

During an active strength-training session, the iOS app is expected to show the user's
**live heart rate**. In practice it shows `--` almost the entire time. Root-cause
investigation (2026-07-19) established that the live-heart-rate connection **is not
actually implemented**, only stubbed:

1. **iPhone start-workout starts nothing.** `ActiveWorkoutView` calls
   `makeWorkoutSessionManager().startSession()`, but on iOS the factory
   (`HealthKitService.swift:749-750`) returns `NoopWorkoutSessionManager` — a no-op. No
   `HKWorkoutSession` is started and no Watch is engaged.
2. **The real collector is watchOS-only and never called.** `WorkoutSessionManager`
   (`HKWorkoutSession` + `HKLiveWorkoutBuilder`) is compiled only under
   `#if os(watchOS)`. The Watch app (`WatchContentView`) is a placeholder ("力量训练 —
   Coming Soon") that never invokes it.
3. **iPhone HR is a passive read.** `observeHeartRate()` runs an anchored query over the
   iPhone's *local* HealthKit store for HR samples from the last 5 min. At rest the Watch
   writes HR only every few minutes; combined with the 120 s `startDate` discard
   (`ActiveWorkoutView.swift:760`) and the 120 s staleness reset (`:766-774`), the value
   collapses to `nil` → `--` for most of the session.

The standard, only-reliable way to obtain **live** heart rate is a Watch-side
`HKWorkoutSession` + `HKLiveWorkoutBuilder` streaming samples to the iPhone via
`WatchConnectivity`. That is precisely the **"dedicated watchOS training flow"** that
Constitution §VII and [ADR-0002](0002-defer-watchos-macos-feature-work.md) currently
defer ("No new dedicated watchOS feature work"; new watch-UX issues are triaged
out-of-scope "unless explicitly promoted").

ADR-0002 explicitly lists an escape hatch in its *Revisit triggers* / *Mitigations*:

> "If a user reports a watch issue, escalate to active iteration regardless of this ADR."

The project owner (the app's user) has reported exactly this issue. This ADR is that
explicit promotion.

## Decision

**Promote a single, narrowly-scoped watchOS feature: a live-heart-rate workout session
that streams real-time HR to the iOS active-workout screen.** ADR-0002 otherwise stands —
this is a per-feature exception, not a reversal.

In scope (the promoted feature only):
1. **Watch app drives a real workout session.** Replace the "Coming Soon" placeholder
   with a start/stop flow that calls the existing `WorkoutSessionManager`
   (`HKWorkoutSession` + `HKLiveWorkoutBuilder`, `.traditionalStrengthTraining`).
2. **Live HR crosses to iPhone via `WatchConnectivity`** (`WCSession`), so the iOS
   `ActiveWorkoutView` shows real-time BPM sourced from the Watch session rather than a
   passive local-store query.
3. **iPhone-side honest states.** The iOS UI distinguishes *not connected* / *no data
   yet* / *connected+value* instead of a single ambiguous `--`.

Explicitly **out of scope** (still frozen under ADR-0002): watch complications, an
independent watch-only workout product, macOS-specific work, and any watch UX beyond the
live-HR training path above.

## Constitution alignment

- **§VII** amended from "不立项 watchOS 专属 feature" to allow this one promoted
  training-flow feature; the companion-first stance and the ADR-required-to-promote gate
  remain. Constitution version bump: **MINOR** (scope relaxation of one principle, not a
  reversal). §VII text patched to reference this ADR alongside ADR-0002.
- **§I (privacy, NON-NEGOTIABLE) is unchanged and binding.** The live-HR path MUST NOT
  log real health values (BPM). WatchConnectivity payloads carrying HR are transient
  transport, not persistence — they MUST NOT be written to any CloudKit-synced store, and
  any local caching stays `cloudKitDatabase: .none`. Health values may appear only as
  sample-type / count / time-range metadata in logs.

## Consequences

### Good
- The advertised live-HR-during-workout behavior becomes real; `--` stops being the
  steady state when a Watch is present.
- Reuses the already-written `WorkoutSessionManager` skeleton (low net-new watch code).

### Bad / watch
- Reintroduces watch-specific concurrency / lifecycle / WatchConnectivity code paths that
  ADR-0002 warned could bit-rot — now actively maintained for this feature.
- Users **without** an Apple Watch still get no live HR; the iOS UI must degrade honestly
  (the "not connected" state) rather than imply a value.
- Live Multica agent instructions do not change from this ADR; implementation lands via
  the normal pipeline issues that reference it.

## Implementation references
- `Packages/HealthKitService/Sources/HealthKitService/WorkoutSessionManager.swift` — existing session/builder.
- `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift:740-752` — `makeWorkoutSessionManager` factory (iOS returns Noop today).
- `VitalStride/Sources/ActiveWorkoutView.swift:758-778` — iPhone HR observe + staleness.
- `VitalStrideWatch Watch App/Sources/WatchContentView.swift` — placeholder to replace.
- Constitution §VII + §I; [ADR-0002](0002-defer-watchos-macos-feature-work.md).
