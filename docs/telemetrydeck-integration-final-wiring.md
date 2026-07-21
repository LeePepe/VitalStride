# TelemetryDeck Integration — Final Wiring (pending App ID)

Status: **architecture complete, SDK not yet connected** (ADR-0012 path B).

Everything except the literal `import TelemetryDeck` call is done and unit-tested
(70 tests in `Packages/TelemetryKit`). This note is the checklist for the last
step, to run once a TelemetryDeck App ID exists.

## What already exists (done)

- `TelemetryDiagnostic` — closed diagnostic type (crash/hang + sanitized frames)
- `DiagnosticSanitizer` — §I chokepoint, adversarially tested (rejects health
  values / PII / non-ASCII whole)
- `DiagnosticBuilder` — assembles a sanitized diagnostic from raw MetricKit primitives
- `TelemetryDeckSignal` + mapping from `TelemetryEvent` / `TelemetryDiagnostic`
- `TelemetryDeckProvider` (implements `TelemetryProvider`) → delegates to a
  `TelemetryDeckSignalSink`
- `TelemetryService.record(_:)` / `recordNonisolated(_:)` — diagnostic entry point
- `MetricKitDiagnosticCollector` (app target) — subscribes to MetricKit, flattens
  call stacks, calls `DiagnosticBuilder` then `TelemetryService.recordNonisolated`
- Collector started in `VitalStrideApp.init()` (DEBUG logs locally, does not send)

## Remaining steps (need App ID)

1. **Create a TelemetryDeck app** at telemetrydeck.com → copy the **App ID** (a UUID).

2. **Add the SPM dependency** in `project.yml` under the app target's packages:
   ```yaml
   packages:
     TelemetryDeck:
       url: https://github.com/TelemetryDeck/SwiftSDK
       from: 5.0.0
   ```
   Then add `TelemetryDeck` to the app target's `dependencies:` and run
   `xcodegen generate`.

3. **Write the real sink adapter** (app target), implementing `TelemetryDeckSignalSink`:
   ```swift
   import TelemetryDeck
   import TelemetryKit

   struct TelemetryDeckSDKSink: TelemetryDeckSignalSink {
       func send(_ signal: TelemetryDeckSignal) {
           TelemetryDeck.signal(signal.signalType, parameters: signal.parameters)
       }
   }
   ```

4. **Initialize + register** in `VitalStrideApp.init()` (replace or complement the
   DEBUG-only Console provider):
   ```swift
   let config = TelemetryDeck.Config(appID: "<YOUR-APP-ID>")
   TelemetryDeck.initialize(config: config)  // TelemetryDeck itself suppresses DEBUG sends
   Task {
       await TelemetryService.shared.register(
           TelemetryDeckProvider(sink: TelemetryDeckSDKSink())
       )
   }
   ```

5. **Verify** with `xcodebuild build` (generic/iOS Simulator). Ship a build; confirm
   events + `diagnostic_hang` / `diagnostic_crash` signals reach the dashboard.

## Symbolication of transported stacks

Frames are sanitized but NOT pre-symbolicated (MetricKit gives addresses on some
OSes). Keep each release's `.xcarchive` dSYM; resolve `frames` offsets against it
with `atos`/`symbolicate`. See `specs/testflight-crash-report-2026-07-21.md`.
