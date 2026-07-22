# ADR-0013: Self-Hosted GlitchTip via sentry-cocoa for Crash/Hang Reporting

**Status**: Accepted
**Date**: 2026-07-22
**Deciders**: tianpli (project owner)

> Supersedes the **crash/hang transport** decision of
> [ADR-0012](0012-metrickit-diagnostics-via-telemetrydeck.md) (its self-authored
> MetricKit→TelemetryDeck channel). Triggers directly on ADR-0011's own revisit
> hook: *"Requirement for data-never-leaves-own-infra → migrate to a self-hosted
> backend provider."* ADR-0011/0012's product-**analytics** decision
> (`TelemetryEvent` → a hosted provider) is left intact and out of scope here.

## Context

The observability gap that motivated ADR-0012 is real (a TestFlight tester's
"动作选择页面滚动" hang with no obtainable stack — see
`specs/testflight-crash-report-2026-07-21.md`), but two facts surfaced after
ADR-0012 shipped:

1. **TelemetryDeck cannot be self-hosted.** Its GitHub org publishes only client
   SDKs; the ingestion backend is proprietary. ADR-0011 assumed a hosted vendor;
   the project owner now requires **data never leaves infrastructure we control**.
2. **The self-authored MetricKit→TelemetryDeck channel (ADR-0012) is a lot of
   bespoke code** (`MetricKitDiagnosticCollector` JSON-flattening +
   `DiagnosticBuilder` + a hand-rolled sink) to reproduce what a mature crash SDK
   already does — and it still transports to a vendor we can't self-host.

ADR-0011's provider survey rejected **Sentry** for three reasons; each is
re-examined against a **self-hosted GlitchTip** (a lightweight, MIT-licensed,
Sentry-protocol-compatible server), which changes the calculus:

- *"crash-oriented"* → that is now exactly what we want (crash/hang, not product
  analytics — which stays on the separate typed-event path).
- *"self-hosted iOS symbolication limited"* → GlitchTip accepts dSYM uploads
  (`sentry-cli upload-dif`) and symbolicates server-side; we control the dSYMs.
- *"16 GB service to run"* → that was **Sentry's** footprint. GlitchTip runs in
  **256–512 MB RAM** (all-in-one), which fits a minimal Azure Container App.

## Decision

Adopt **self-hosted GlitchTip** as the crash/hang backend, with the official
**sentry-cocoa** SDK on the client (GlitchTip speaks the Sentry protocol).

1. **Server: GlitchTip on Azure, owner-controlled.** Deployed to the project
   owner's Azure subscription (`Visual Studio Enterprise`, East Asia) as Container
   Apps (web + worker) + PostgreSQL Flexible Server + Redis. Data resides on
   infrastructure the owner controls — satisfying the data-residency requirement
   that TelemetryDeck could not. Deployment recorded in
   `docs/glitchtip-azure-deploy.md`; secrets via `az containerapp secret`, never
   in the repo. HTTPS via the built-in `*.azurecontainerapps.io` domain.

2. **Client: sentry-cocoa, MetricKit-native.** `SentrySDK.start` with
   `options.enableMetricKit = true` — the SDK ingests MetricKit crash + hang
   diagnostics and symbolicates against uploaded dSYMs. This **replaces** the
   ADR-0012 hand-rolled crash path (`MetricKitDiagnosticCollector`'s transport,
   `TelemetryDiagnostic`/`DiagnosticBuilder`/`DiagnosticSanitizer` for crashes).

3. **§I is enforced by a `beforeSend` chokepoint.** sentry-cocoa auto-collects
   device/app context; a mandatory `options.beforeSend` hook strips or rejects
   any field that could carry a HealthKit value or PII, allowing through only the
   crash/hang stack + coarse device metadata. The hook's filtering logic is
   extracted as a pure, unit-tested function (mirroring the ADR-0012 sanitizer
   discipline). A health value in a payload is a §I violation and a revisit
   trigger.

4. **DEBUG does not send.** SDK is not started (or `enabled = false`) in DEBUG,
   consistent with ADR-0011/0012.

5. **Scope: crash/hang only.** Product analytics (`TelemetryEvent` via
   `TelemetryService`) is untouched and still has no live remote provider —
   whether/where to send those events is a separate, later decision. This ADR
   does not make sentry-cocoa a general telemetry SDK.

## Consequences

### Positive
- **Data never leaves owner-controlled infra** — the requirement ADR-0011 could
  not meet. Reversible/portable (Sentry protocol; could move to self-hosted
  Sentry or another GlitchTip host).
- **Far less bespoke code** than ADR-0012's channel for the crash path; a mature
  SDK handles capture, batching, retry, symbolication.
- Crash **and** hang coverage with server-side symbolication during TestFlight,
  before App Store launch (Apple's pipelines stay dark until then).

### Negative
- **First third-party runtime SDK in the app after TelemetryDeck**, and it is
  Sentry — which ADR-0011/0012 explicitly forbade. This ADR reverses that, gated
  to self-hosted GlitchTip + `beforeSend`. §V is amended accordingly.
- **First remote SPM dependency** in `project.yml` (all packages were local).
- sentry-cocoa's broad auto-collection means the `beforeSend` §I hook is
  load-bearing; a lax hook could leak. Mitigated by extracting + unit-testing it.
- dSYM upload becomes a release-step dependency (CI `sentry-cli upload-dif`).

### Trade-offs accepted
- ADR-0012's crash channel becomes dead code for crashes. Its **types** may be
  retired or repurposed for the still-pending product-analytics path in a later
  change; this ADR does not delete them, only supersedes their crash role.
- Running our own backend = our ops burden (upgrades, backups, uptime) vs a
  managed vendor. Accepted for data control.

## Implementation references

- `docs/glitchtip-azure-deploy.md` (Azure deploy, DSN)
- `project.yml` — first remote SPM package (`getsentry/sentry-cocoa`)
- New: `VitalStride/Sources/CrashReporting.swift` (`SentrySDK.start` + `beforeSend`)
- `VitalStride/Sources/VitalStrideApp.swift` (start crash reporting; MetricKit
  collector's crash-transport role retired)
- `.specify/memory/constitution.md` §V (2.3.0 → 2.4.0 amendment)
- Supersedes crash channel of `docs/adr/0012-metrickit-diagnostics-via-telemetrydeck.md`

## Revisit triggers

- A health value or PII found in a transported event → tighten `beforeSend`,
  expand the fuzz corpus, or pull crash reporting to local-file-only.
- GlitchTip ops burden proves too high → evaluate a managed self-hostable
  alternative under a new ADR.
- Product analytics needs a live backend → separate ADR (may or may not reuse
  this GlitchTip instance / the TelemetryEvent path).
