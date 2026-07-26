# ADR-0015: Self-Hosted Aptabase as Production Analytics Provider

**Status**: Accepted
**Date**: 2026-07-26
**Deciders**: tianpli (project owner)

> Supersedes [ADR-0011](0011-telemetrydeck-first-production-provider.md) (TelemetryDeck as
> first production analytics provider). Fulfils ADR-0011's own revisit trigger:
> *"Requirement for data-never-leaves-own-infra → migrate to self-hosted backend provider."*

## Context

ADR-0011 adopted **TelemetryDeck** (EU-hosted SaaS) as the first real `TelemetryProvider`
so that `TelemetryEvent`s would finally reach a dashboard. In practice **it never sent a
single event**: the `TELEMETRY_DECK_APP_ID` build setting was never wired into CI, so the
SDK was constructed with an empty app id and stayed inert — product analytics remained
invisible, exactly the gap ADR-0011 set out to close.

Two things changed the calculus:

1. **Self-hosted infra now exists.** ADR-0013 already stood up self-hosted **GlitchTip** on
   the owner's Azure for crash/hang diagnostics. Running one more self-hosted analytics
   service alongside it is now marginal, and keeps *all* telemetry on infrastructure the
   owner controls — the "data-never-leaves-own-infra" posture ADR-0011 named as its migration
   trigger.
2. **Aptabase fits the `TelemetryProvider` seam 1:1.** Aptabase is an open-source,
   privacy-first analytics backend purpose-built for native apps (no cookies, no PII, no
   cross-app identifiers), with an official MIT-licensed Swift SDK that supports a custom
   self-hosted `host`. Its `trackEvent(name, props)` shape maps directly onto the existing
   backend-neutral `AnalyticsSignal` (name + flat string params).

Constitution §I (health-privacy) is unchanged and fully binding: `TelemetryEvent` is a
closed `enum` whose payloads carry only counts / durations / `TelemetryIdentifier`
(canonical ASCII), so no raw health value can reach the provider by construction.

## Decision

Adopt **self-hosted Aptabase** as the production analytics provider, replacing TelemetryDeck
entirely, under these bounds:

1. **Typed-event-only (unchanged).** The provider consumes `TelemetryEvent` exclusively via
   `TelemetryProvider.track(_:)`. No API accepting free-form strings or raw health values.
   The §I chokepoint in `TelemetryService` remains the single sanitization point upstream.
2. **Self-hosted host injected, never hard-coded.** `AptabaseAdapter.makeProvider(appKey:host:)`
   passes the self-hosted URL via `InitOptions(host:)`. App key (`SH-` prefixed) and host come
   from Info.plist (`AptabaseAppKey` / `AptabaseHost`), populated by CI build settings
   (`$(APTABASE_APP_KEY)` / `$(APTABASE_HOST)`) from GitHub secrets. Missing values → the app
   skips registration (fail-safe no-op); analytics is not a release gate.
3. **DEBUG builds do not send.** Suppressed in DEBUG (Aptabase default tracking mode + the
   existing `#if DEBUG` console-only branch), preventing dev/test noise.
4. **Zero-intrusion (unchanged).** No call site or protocol change. The backend-neutral
   `AnalyticsSignal` / `AnalyticsProvider` / `AnalyticsSignalSink` types (renamed from the
   TelemetryDeck-specific names, TelemetryDeck now removed) carry the pure mapping; only one
   thin `AptabaseAdapter` product imports the SDK.
5. **Diagnostics stay separate (unchanged).** Crash/hang transport remains exclusive to
   GlitchTip / sentry-cocoa (ADR-0013). `AnalyticsProvider` still does **not** override
   `record(_:)`, so a diagnostic can never leak into the analytics backend.
6. **Narrow §V exception, retargeted.** §V's "no third-party SDK" stays relaxed **only** for
   one privacy-compliant, self-hosted analytics SDK — now Aptabase (`aptabase-swift`) instead
   of TelemetryDeck. The AI-provider clause of §V is unchanged.

## Consequences

### Positive
- Product analytics finally reaches a dashboard the owner controls; **data never leaves
  own infrastructure** — a strictly tighter privacy posture than EU-hosted SaaS.
- Removes the first EU-SaaS runtime dependency; consolidates all telemetry (analytics +
  diagnostics) onto self-hosted Azure alongside GlitchTip.
- Same reversibility ADR-0011 had: the provider is one file behind `TelemetryProvider`.

### Negative
- One more self-hosted service to run (Aptabase app + Postgres + ClickHouse). ClickHouse is
  a heavier component than GlitchTip's Redis; operational cost ~$15-20/mo (within the VS
  Enterprise Azure credit). Deployment notes in `docs/aptabase-azure-deploy.md`.
- MetricKit performance metrics (a follow-up: `MXMetricPayload` → typed perf events on this
  channel) are out of scope here and land in a separate change.

## Revisit triggers
- Aptabase self-hosting becomes a maintenance burden → evaluate a managed Aptabase plan (same
  SDK, drop the `host` override) or another privacy-first provider behind the same seam.
- Analytics needs richer product analysis (funnels/retention/flags Aptabase lacks) → separate
  ADR to evaluate PostHog (heavier stack) behind the same `TelemetryProvider`.
