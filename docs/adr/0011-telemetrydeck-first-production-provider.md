# ADR-0011: TelemetryDeck as First Production Telemetry Provider

**Status**: Accepted
**Date**: 2026-07-20
**Deciders**: tianpli (project owner)

> Answers the "first real provider" open follow-up left by
> [ADR-0007](0007-telemetrykit-standalone-spm-package.md). ADR-0007 named Firebase
> Analytics as the leading candidate; this ADR selects **TelemetryDeck** instead and
> narrows Constitution §V's "no third-party SDK" rule to permit it.

## Context

`TelemetryKit` has shipped its abstraction (`TelemetryEvent` + `TelemetryProvider` +
`actor TelemetryService`) and is wired into all three app targets, but the only provider
is `ConsoleTelemetryProvider` — events are printed to `os_log` and go nowhere else. The
app therefore has **no product analytics**: workout funnels, AI insight latency, onboarding
completion, cache hit rates are all invisible in production.

Two constraints shaped the choice:

1. **Constitution §I (health-privacy, NON-NEGOTIABLE)** — no HealthKit value may reach any
   log or third-party SDK. `TelemetryEvent` is a closed `enum` whose payloads carry only
   counts / durations / `TelemetryIdentifier` (canonical ASCII) — structurally free of raw
   health values. Any provider must consume *only* this typed event, never raw health data.
2. **Constitution §V + TelemetryKit red_line** — currently forbid third-party
   telemetry/analytics SDKs outright ("用 os / 自定义 provider"). This blocks every hosted
   analytics backend, including privacy-first ones.

Provider survey (2026-07, see conversation research): Firebase Crashlytics/Analytics
(Google cloud, US CLOUD Act exposure, conflicts with §I posture), Sentry (crash-oriented,
self-hosted iOS symbolication limited, 16 GB service to run), Aptabase (privacy-first, no
crash), **TelemetryDeck** (Swift-native, EU/German hosting, hashes identifiers before
send, no signals in DEBUG, self-hostable, watchOS support).

## Decision

Adopt **TelemetryDeck** as the first production `TelemetryProvider`, under these bounds:

1. **Typed-event-only.** The new provider consumes `TelemetryEvent` exclusively via the
   existing `TelemetryProvider.track(_:)` seam. It must NOT introduce any API that accepts
   free-form strings or raw health values. The §I health-blocklist chokepoint in
   `TelemetryService` remains the single sanitization point; the provider sits downstream
   of it.
2. **DEBUG builds do not send.** Signals are suppressed in DEBUG (TelemetryDeck default),
   preventing dev/test noise and accidental local-data emission.
3. **Zero-intrusion.** Adding the provider must not change any call site or the
   `TelemetryProvider` protocol. It is registered at app startup alongside / in place of
   `ConsoleTelemetryProvider`.
4. **Narrow §V exception.** §V's "no third-party SDK" is relaxed **only** for a
   privacy-compliant telemetry SDK, **only** TelemetryDeck, **only** consuming
   `TelemetryEvent`. The AI-provider clause of §V (no OpenAI/Anthropic/Google AI SDK) is
   unchanged. Crash reporting is explicitly out of scope here (see MetricKit path).

## Consequences

### Positive
- Existing `TelemetryEvent`s finally reach a dashboard; product decisions get data.
- Privacy posture preserved: EU hosting, identifier hashing, DEBUG-off, typed-event-only,
  §I chokepoint upstream.
- Reversible — swapping TelemetryDeck for a self-hosted backend later is one new provider.

### Negative
- First third-party runtime dependency in the app (SPM: `TelemetryDeck/SwiftSDK`). The
  §V blanket ban existed partly to avoid exactly this; the narrow exception is the cost.
- TelemetryKit's `depends_on: []` gains an external (non-local) package edge for the
  provider target. Kept isolated so the pure abstraction stays dependency-free.

### Trade-offs accepted
- TelemetryDeck's own crash reporting is immature; crashes stay on MetricKit / Xcode
  Organizer, not this provider.
- Single-provider-at-a-time still holds (ADR-0007); no fan-out to Console + TelemetryDeck
  simultaneously unless a later ADR adds multi-provider routing.

## Implementation references

- `Packages/TelemetryKit/Sources/TelemetryKit/TelemetryProvider.swift` (seam)
- New: `TelemetryDeckProvider` (maps `TelemetryEvent` → TelemetryDeck signal)
- App startup provider registration (iOS/macOS/watchOS)

## Revisit triggers

- Health-value leak through a signal → tighten mapping, add fuzz test, or reconsider.
- TelemetryDeck ships mature crash reporting → re-evaluate the MetricKit split.
- Requirement for data-never-leaves-own-infra → migrate to self-hosted backend provider.
