# ADR-0022: Portable FlightKit Feature-Flag Package

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** VitalStride maintainers

## Context

Workout navigation experiments need a stable feature-flag contract before AppUI
integration. The contract must also be portable to a future `LeePepe/shared-flight`
package without importing VitalStride business models or app composition.

## Decision

Add `Packages/FlightKit` as an independent Swift 6 local SPM package. It owns:

- Sendable descriptors and override states;
- an injectable `UserDefaults`-backed override store;
- explicit local, remote, and default precedence;
- a deterministic disabled remote provider fallback; and
- a reusable SwiftUI debug view for searching, grouping, reading, and resetting flags.

The package has no local package dependencies. AppUI integration, XcodeGen package
registration, CI matrix changes, and production flag registry wiring are deferred
to TK2 so this package can be reviewed and built independently.

## Consequences

Consumers receive a narrow, portable API and can inject both persistence and remote
values in tests. Local overrides remain device-local and can be reset without
touching remote configuration.

The package must remain UI-capable because the debug surface is shared, so the
portable extraction boundary includes SwiftUI. App integration requires a later
task to register the package in XcodeGen and update the AppUI dependency graph.

## Implementation references

- `Packages/FlightKit/Package.swift`
- `Packages/FlightKit/Sources/FlightKit`
- `Packages/FlightKit/Tests/FlightKitTests`
- `Packages/FlightKit/CONTEXT.md`

## Revisit triggers

Revisit when FlightKit is extracted to `LeePepe/shared-flight`, when remote
configuration becomes asynchronous, or when the debug surface is replaced by a
host-specific UI.
