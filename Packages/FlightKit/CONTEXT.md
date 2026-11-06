---
layer: FlightKit
role: portable feature-flag contracts, persistence, remote fallback, and debug UI
paths: [Packages/FlightKit]
test_paths: [Packages/FlightKit/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/FlightKit
depends_on: []
depended_by: []
red_lines:
  - FlightKit is portable and must not depend on VitalStride app code or another local package
  - Local override precedence is override, remote when enabled and present, then descriptor default
  - Override persistence stays in the injectable FlightKit UserDefaults suite and reset-all clears every local override
  - Swift 6 strict concurrency; public contracts are Sendable and the debug view/store remain UI-isolated
roles:
  Types: [FlightDescriptor, FlightOverrideState, RemoteFlightProviding, FlightReadout]
  Repo: [FlightStore]
  UI: [FlightDebugView]
test: swift test --package-path Packages/FlightKit
owns: [FlightDescriptor, FlightFlag, FlightOverrideState, RemoteFlightProviding,
       DefaultRemoteFlightProvider, FlightReadout, FlightStore, FlightDebugView]
---

# FlightKit Context

## 职责

FlightKit is the portable feature-flag SDK for VitalStride and future consumers. It
owns descriptor contracts, local override persistence, remote fallback composition,
and the reusable SwiftUI debug surface. It has no app-specific dependency.

## 依赖

FlightKit is an independent local package (`depends_on: []`). TK2 may wire it into
AppUI later; this task intentionally leaves `depended_by: []` until that consumer
integration exists.

## Contracts

- `FlightDescriptor`/`FlightFlag` carry stable key, title, summary, category, and default.
- `FlightStore` applies local override, enabled remote value, then descriptor default.
- `DefaultRemoteFlightProvider` supplies a deterministic `false` fallback while the
  store keeps remote use disabled by default.
- `FlightDebugView` groups and searches descriptors and exposes effective state,
  source readouts, override selection, and reset-all.
