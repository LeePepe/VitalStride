# ADR-0012: MetricKit Crash/Hang Diagnostics via the TelemetryDeck Channel

**Status**: Accepted
**Date**: 2026-07-21
**Deciders**: tianpli (project owner)

> Extends [ADR-0011](0011-telemetrydeck-first-production-provider.md), which adopted
> TelemetryDeck for **product-analytics events only** and explicitly left crash
> reporting out of scope ("crashes stay on MetricKit / Xcode Organizer"). This ADR
> closes the resulting observability gap: it routes **MetricKit crash + hang
> diagnostics** out through the same single third-party channel, without adding a
> second SDK (Sentry / Crashlytics).

## Context

A TestFlight tester reported the exercise picker "hanging" while scrolling
(2026-07-16 / -19 / -20, iPhone 16 Pro, iOS 26.5). Investigation
(`specs/testflight-crash-report-2026-07-21.md`) established, via the App Store
Connect API, that **no symbolicated stack is obtainable** for these reports:

- The TestFlight manual-feedback `crashLog` relationship is a 404 empty shell;
  `appUptimeInMilliseconds` is `null` — these are hand-typed feedback, not
  auto-captured crashes.
- Xcode Organizer **Crashes** and **Hangs**, and the ASC `perfPowerMetrics`
  aggregates, are **empty for a TestFlight-only app** — those pipelines only
  populate once a version ships on the App Store ("No App Store Versions").

So until the app ships publicly, **every Apple-side automatic diagnostic
pipeline returns nothing.** The team is left guessing at code from a one-line
user comment. The symptom (`uptime = null`, "scrolling") also indicates the
failure is most likely a **hang (main-thread stall), not a crash** — and only
**MetricKit** captures hangs at all.

Two constraints from the existing decision record shape the options:

1. **ADR-0011 §Decision.1 "Typed-event-only"** — the TelemetryDeck provider may
   consume only the closed `TelemetryEvent` enum; it "must NOT introduce any API
   that accepts free-form strings". A crash/hang **call-stack is inherently
   free-form text**, so it cannot travel as a `TelemetryEvent` parameter today.
2. **ADR-0011 §Decision.4 + Consequences** — "Crash reporting is explicitly out
   of scope"; crashes "stay on MetricKit / Xcode Organizer, not this provider".

Both were written before we knew the Apple pipelines are dark for a
TestFlight-only build. That new fact is the revisit trigger ADR-0011 itself
named: *"TelemetryDeck ships mature crash reporting → re-evaluate the MetricKit
split."* We are not relying on TelemetryDeck's own (immature) crash reporting —
we keep **Apple's MetricKit** as the capture engine and use TelemetryDeck purely
as the **transport** for the already-symbolication-ready payload.

### Options considered

| Option | Capture crash | Capture **hang** | New SDK | Symbolication | Verdict |
|---|:---:|:---:|:---:|---|---|
| Do nothing (wait for App Store) | ✅ | ✅ | — | Apple auto | ❌ blocked until public launch; useless for current TestFlight bug |
| Second SDK: Sentry / Crashlytics | ✅ | partial | **yes** | vendor auto | ❌ violates §V posture harder; 2nd third-party runtime dep; Crashlytics = Google/CLOUD-Act (conflicts §I posture per ADR-0011 survey) |
| **MetricKit capture → TelemetryDeck transport** | ✅ | ✅ | no (reuse) | local dSYM (`MXCallStackTree`) | ✅ **chosen** — one channel, Apple-native capture, hang coverage |

## Decision

Adopt a **controlled diagnostic channel** on top of the existing TelemetryDeck
provider. MetricKit is the capture engine; TelemetryDeck is the transport.

1. **MetricKit is the sole capture source.** A `MetricKitDiagnosticCollector`
   subscribes to `MXMetricManager` and receives `MXDiagnosticPayload`s on the
   next app launch. It handles `crashDiagnostics` and `hangDiagnostics` only.
   No swizzling, no signal handlers, no third-party crash interception.

2. **Diagnostics are a distinct, typed channel — not a `TelemetryEvent`.** The
   §V "typed-event-only" rule is narrowed, **not deleted**: a new
   `TelemetryDiagnostic` value type carries a **structured, sanitized** payload
   (diagnostic kind, OS/app-version metadata, and a `frames: [String]` symbol
   list derived from `MXCallStackTree`). Free-form *user* input, HealthKit
   values, and PII remain forbidden. The provider gains exactly one new sink,
   `TelemetryProvider.record(_ diagnostic:)`, whose input is this closed type —
   it still accepts **no** arbitrary strings from call sites.

3. **Stack sanitization is a mandatory chokepoint.** `MXCallStackTree` →
   `[String]` runs through a pure `DiagnosticSanitizer` that keeps only frame
   symbol names + binary offsets and **drops everything else**. Because
   `TelemetryEvent` never carried health values and stacks are symbol/address
   data (not app data), §I is structurally upheld; a fuzz/allow-list test locks
   it. This mirrors the §I chokepoint ADR-0011 placed in `TelemetryService`.

4. **DEBUG does not send** (unchanged from ADR-0011). Diagnostics captured in
   DEBUG are logged locally via `os_log` and dropped before transport.

5. **Still one third-party SDK.** No Sentry/Crashlytics. The §V exception stays
   scoped to **TelemetryDeck only**; this ADR widens *what* may travel that one
   channel (adds the diagnostic type), not *how many* vendors we depend on.

## Consequences

### Positive
- **Hang + crash stacks become obtainable during TestFlight**, before public
  launch — directly unblocks the exercise-picker investigation.
- Apple-native capture (MetricKit) keeps symbolication on our own dSYMs; no
  vendor lock on the crash data itself.
- No second runtime dependency; the privacy surface stays one vendor wide.

### Negative
- The provider protocol grows a second method (`record(_:)`). ADR-0011's
  "zero-intrusion / never change the protocol" property is relaxed — this is the
  explicit cost. Call sites are unaffected (only the collector calls it).
- MetricKit delivers on the **next launch**, not real-time; a user who never
  reopens the app never reports. Acceptable for the diagnostic use case.
- Stacks are symbolication-ready but **not pre-symbolicated**; we resolve them
  with the build's dSYM. A dSYM-retention discipline is now load-bearing.

### Trade-offs accepted
- TelemetryDeck's own crash reporting is still not used (immature, per ADR-0011).
  We deliberately keep MetricKit as the engine and treat TelemetryDeck as a dumb
  pipe for a structured payload.
- Widening the "typed-event-only" rule is a genuine loosening of ADR-0011; it is
  bounded by the closed `TelemetryDiagnostic` type + sanitizer test rather than
  left open-ended.

## Implementation references

- `specs/testflight-crash-report-2026-07-21.md` (evidence the Apple pipelines are dark)
- `Packages/TelemetryKit/Sources/TelemetryKit/TelemetryProvider.swift` (gains `record(_:)`)
- New: `TelemetryDiagnostic` (closed type), `DiagnosticSanitizer` (pure, tested)
- New: `MetricKitDiagnosticCollector` (app-target; MetricKit is iOS/macOS only)
- `Packages/TelemetryKit/.../TelemetryDeckProvider` (adds diagnostic mapping)
- `.specify/memory/constitution.md` §V (2.2.0 → 2.3.0 amendment)

## Revisit triggers

- App ships on the App Store → Organizer/perfPower pipelines light up; re-evaluate
  whether the MetricKit channel is still worth its maintenance.
- A health value or PII is found in a transported stack → tighten the sanitizer,
  expand the fuzz corpus, or pull diagnostics back to local-file-only.
- Need for real-time (not next-launch) crash visibility → reconsider a dedicated
  crash SDK under a new ADR (would re-open the §V single-vendor scope).
