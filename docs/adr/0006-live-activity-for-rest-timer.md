# ADR-0006: Live Activity for Rest Timer

**Status**: Accepted
**Date**: 2026-06-18 (backfilled)
**Deciders**: tianpli (project owner)

## Context

The training flow has a rest timer between sets. Default 60 s, user-adjustable in ±10 s steps. The countdown is meaningful for the user — they look at their phone or watch during the rest.

In the original implementation, the timer lived in-app via a `Snackbar` overlay. Two friction points emerged:

1. **Phone in pocket / screen locked** — the user can't see the rest timer. They open the app, lose context, miss the perfect window.
2. **iOS 16+ Dynamic Island / Lock Screen** — the platform now expects timer-style transient UI to surface here. Without it, the app feels behind the times.

A standard local notification at the end of the rest does fire, but only at completion — it does not show the countdown.

## Decision

Use **Live Activity (ActivityKit)** for the rest timer:

- Start a Live Activity when the rest begins; activity content carries `startedAt`, `duration`, and a derived `endsAt`.
- The Lock Screen presentation shows a circular ring + remaining seconds.
- The Dynamic Island presentation (compact + expanded + minimal) mirrors the same data with appropriate density.
- End the activity when the rest completes, when the user manually skips, or when the workout ends.
- A local notification still fires on completion as the audible/haptic signal (Live Activity itself is silent).

### Lifecycle correctness

Live Activity has known pitfalls; the implementation accounts for:

- **Relaunch orphan cleanup** — on app launch, any leftover Live Activity from a crashed prior session is ended explicitly. Otherwise the Lock Screen shows a phantom timer counting up.
- **Race condition on start/end** — start and end are funneled through a single actor (`RestLiveActivityManager`) so the user double-tapping doesn't create or leak activities.
- **Extension API safety** — the activity content stays inside ActivityKit's serializable types; no SwiftUI views are passed across the activity boundary.

### Widget extension target

The Live Activity requires a Widget Extension target (`VitalStrideWidgets`). The extension is added to `project.yml`, signed under the same team, and shares `AppGroups` with the main app.

## Consequences

### Positive
- The user sees the rest countdown without unlocking the phone.
- Apple Watch users on iPhone-paired devices get the Dynamic Island treatment + companion notification.
- Modern iOS feel; users expect this from any fitness app post-iOS 16.

### Negative
- Live Activity has hard limits: max 8 hours, ActivityKit budgets, OS may kill the activity.
- Background-task / push-update story is more complex than a foreground timer.
- Widget Extension target adds build complexity, code-signing surface, and a separate Info.plist.
- Crash recovery / orphan cleanup is a known footgun — must be tested every release.

### Trade-offs accepted
- We don't use push-based ActivityKit updates (no server side). Rest timer durations are short enough that local-only updates suffice.
- We don't try to extend the activity past the rest end into the "next set" UI — that would blur the activity's purpose and risk hitting the 8-hour cap on long workouts.

## Implementation references

- `VitalStride/Sources/RestLiveActivityManager.swift` (activity lifecycle)
- `VitalStrideWidgets/` (widget extension target, if present in current project.yml)
- `project.yml` — widget extension target definition
- Test paths: `VitalStrideTests/Sources/RestTimerCancellationTests.swift` (cancellation surfaces)

## Revisit triggers

- ActivityKit gets push update support that we want for cross-device sync.
- iOS deprecates ActivityKit (unlikely soon).
- User reports phantom-timer or activity-leak bugs (treat as P0).
- Rest timer evolves into something longer or more complex than a simple countdown.
