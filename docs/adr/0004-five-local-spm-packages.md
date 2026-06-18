# ADR-0004: Five Local SPM Packages

**Status**: Accepted
**Date**: 2026-06-18 (backfilled)
**Deciders**: tianpli (project owner)

## Context

In the first 16 days of development VitalStride grew from 0 to ~39,500 LOC across ~234 Swift files. Initially everything lived in a single Xcode app target. Two problems surfaced:

1. **Build cost** — `xcodebuild test` is slow even on a clean cache. Every Swift change rebuilt the world, even when the change only touched a domain model.
2. **Implicit coupling** — without module boundaries, an HealthKit detail could leak into UI code, or an AI provider could reach into model internals. Hard to reason about, easy to regress.

We needed module boundaries that were enforced by the compiler, not by convention.

## Decision

Split the codebase into **five local Swift Package Manager packages**, all living under `Packages/`:

| Package | Responsibility | Typical contents |
|---|---|---|
| `VitalModels` | Plain data types and SwiftData models. No I/O, no UI. | `Workout`, `ExerciseSet`, `HealthCacheEntry`, codable JSON envelopes. |
| `HealthKitService` | Everything HealthKit-facing. The only code allowed to `import HealthKit`. | `HealthKitService`, `HealthDataCache` actor, anchor query plumbing. |
| `AIService` | AI provider chain + structured analysis types. | `AIProviderChain`, `AppleIntelligenceProvider`, `ZhipuProvider`, response models. |
| `VitalUI` | Reusable SwiftUI components, modifiers, and presentation helpers. | Snackbar primitives, `HapticManager`, generic error views. |
| `TelemetryKit` | Telemetry abstraction (event/metric API + provider routing). | Console provider, sanitization helpers. |

The main app and platform targets (`VitalStride/`, `VitalStrideMac/`, `VitalStrideWatch Watch App/`) consume these packages and contain only platform glue + assembled UI.

### Project assembly

- `project.yml` (XcodeGen) declares the targets and SPM dependencies; `xcodegen generate` produces `VitalStride.xcodeproj`.
- Each package has its own `Package.swift`, its own `Sources/<Pkg>/` and `Tests/<Pkg>Tests/`.

### Build & test rules

- **Changes only inside `Packages/`** → use `swift build` and `swift test` for the affected package; sub-second to seconds.
- **Changes to app target code** → use `xcodebuild` with `generic/platform=iOS Simulator` + `-skipPackagePluginValidation`, and only when necessary.
- The pre-push hook detects pure-package changes and skips the heavy `xcodebuild test` path.

## Consequences

### Positive
- `swift test` on `Packages/VitalModels` is essentially instant; tests stay tight.
- Compiler-enforced boundaries: app code cannot accidentally `import HealthKit` without going through `HealthKitService`.
- Package-level test coverage data per concern.
- Easier to extract a package as standalone open-source later (TelemetryKit is the obvious candidate).
- New contributors immediately see the architecture from the directory layout.

### Negative
- Five `Package.swift` files to keep in sync (Swift tools version, platform requirements).
- Adding a new file means a deliberate choice: which package? Wrong choice creates awkward cross-package dependencies later.
- `xcodebuild` for the app target still pays the cost of SPM resolution on first build.
- Refactors that span packages cost more because the dependency graph is real.

### Conventions
- One target per package (no multi-product packages here).
- Test files live in `Tests/<PackageName>Tests/`, mirroring the source tree.
- Packages do not import each other except in carefully chosen one-way arrows:
  - `HealthKitService` → `VitalModels`
  - `AIService` → `VitalModels`
  - `VitalUI` → (nothing, framework-only)
  - `TelemetryKit` → (nothing, framework-only)
  - `VitalModels` → (nothing)

## Implementation references

- `Packages/VitalModels/`, `Packages/HealthKitService/`, `Packages/AIService/`, `Packages/VitalUI/`, `Packages/TelemetryKit/`
- `project.yml`
- `AGENTS.md` § Build & Test
- Per-package `CONTEXT.md`

## Revisit triggers

- A sixth package would be needed for cohesion (e.g. dedicated `WorkoutEngine` for active-workout state machine).
- Cross-package coupling becomes painful (consider merging two packages back).
- Build time on `xcodebuild test` grows beyond ~3 min → re-evaluate split granularity.
