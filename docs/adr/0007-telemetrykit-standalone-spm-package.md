# ADR-0007: TelemetryKit as Standalone SPM Package

**Status**: Accepted
**Date**: 2026-06-18 (backfilled)
**Deciders**: tianpli (project owner)

## Context

VitalStride has telemetry needs across many code paths:

- Workout lifecycle events (start, set complete, workout end).
- HealthKit query budgets and failures.
- AI provider chain decisions (which provider served, latency, cache hit/miss).
- Rest timer interactions (start, adjust, skip, complete).
- Crash and recovery surfaces.

Inlining telemetry calls in each subsystem creates two problems:

1. **Provider lock-in** — if every call site references `Firebase.Analytics.logEvent(...)` directly, swapping the provider (console-only for local dev, Mixpanel, no-op for tests) becomes a sprawling find-and-replace.
2. **Health data leakage** — HealthKit values must **never** appear in telemetry per the project's privacy rule (`AGENTS.md` § Key Conventions). Without a chokepoint, this is enforced only by reviewer vigilance, which retros showed degrades under load.

We needed a single abstraction with a single sanitization choke point.

## Decision

Extract telemetry into **`TelemetryKit`**, a standalone SPM package at `Packages/TelemetryKit/`:

### Public API surface (small on purpose)

- `Telemetry.event(_:metadata:)` — discrete events.
- `Telemetry.metric(_:value:tags:)` — numeric metrics.
- `Telemetry.span { ... }` — timed operations.
- `Telemetry.error(_:context:)` — error surfaces.

All inputs go through a sanitization layer that:

- Strips known health-value keys (`heart_rate`, `weight_kg`, `steps`, `sleep_duration`, `bpm`, `kcal`, `distance`, etc.).
- Buckets numeric values flagged as `.sensitive`.
- Asserts (debug) and elides (release) any value whose key matches the health-blocklist.

### Provider routing

Internal `TelemetryProvider` protocol with implementations:

- `ConsoleTelemetryProvider` — default for development, prints to `os_log`.
- (Future) `FirebaseAnalyticsTelemetryProvider` — production provider; pending integration into app target (`AGENTS.md` notes this is "not yet registered to project.yml as of 2026-06-18").

Provider is selected at app startup; tests inject a recording provider for assertions.

### Why standalone, not embedded in `VitalUI` or app target

- Multiple packages need to emit telemetry (AIService records provider decisions, HealthKitService records query budgets). If TelemetryKit lived in the app target, packages would have to take a string-based callback or duplicate the abstraction.
- Standalone means tests for telemetry sanitization run via `swift test Packages/TelemetryKit` in seconds.

## Consequences

### Positive
- Single change point for adding/removing providers.
- Health-value blocklist enforced mechanically.
- All packages (`AIService`, `HealthKitService`, eventually `VitalUI`) can emit telemetry without depending on the app target.
- Open-sourceable in isolation if desired.

### Negative
- Pre-existing inline `print(...)` / `os_log(...)` calls in older code still need to be migrated to `Telemetry.event(...)`. Tracked but not blocking.
- The blocklist is hardcoded — a new health metric added later must be added to the blocklist explicitly, or its values would leak. This is an ongoing maintenance burden.
- Adds a package dependency for any code wanting to emit telemetry; for a one-line `print` during debugging, devs may bypass it.

### Trade-offs accepted
- No automatic schema versioning — events evolve by add-only convention. If we need strict schema later, that's a v2 problem.
- The provider chain is single-provider-at-a-time (no fan-out). Multi-provider routing can be layered later if needed.

## Implementation references

- `Packages/TelemetryKit/Package.swift`
- `Packages/TelemetryKit/Sources/TelemetryKit/`
- `Packages/TelemetryKit/Tests/TelemetryKitTests/`

## Open follow-ups

- App-target registration (`project.yml`) — the package is built but not yet wired into the running app as of this ADR's date. Integration issue exists in the Multica backlog.
- Migrate all existing `print` / `os_log` call sites to `Telemetry.event` / `Telemetry.error`.
- Decide on first real provider (Firebase Analytics is the leading candidate).

## Revisit triggers

- First production provider integrated (re-validate the protocol shape against real provider constraints).
- Health blocklist surprises us (a leak slips through) → tighten sanitization, add fuzz test.
- New analytics requirement (cohort analysis, funnels) that the minimalist API can't express.
