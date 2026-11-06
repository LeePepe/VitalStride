# ADR-0023: Upgrade Deployment Targets to OS 26

**Status**: Accepted  
**Date**: 2026-11-06  
**Deciders**: project owner

## Context

VitalStride's deployment baseline was iOS 18.0, macOS 15.0, and watchOS 11.0.
The workout logging redesign uses platform capabilities that are first-class on
OS 26, including Liquid Glass (`GlassEffectContainer` and `.glassEffect`),
native `ToolbarSpacer`, and Apple Intelligence integrations aligned with Swift 6.
Maintaining the older minimums would require compatibility branches across the
app, packages, and prototype, while weakening the intended native experience.

## Decision

Raise the minimum deployment targets to:

- iOS 26.0
- macOS 26.0
- watchOS 26.0

The shared XcodeGen source and generated project use these values. All seven
local SPM packages use iOS, macOS, and watchOS 26.0; the macOS/iOS-only
Prototype package uses iOS and macOS 26.0. Swift tools version remains 6.0 for
manifest compatibility with the supported Xcode 26.5 and Xcode 27.0 toolchains.

## Consequences

### Positive

- Liquid Glass, `ToolbarSpacer`, and Swift 6 platform APIs can be used without
  legacy deployment guards.
- App, package, test, and prototype targets share one explicit OS baseline.
- The minimum supported platform set matches the current product direction.

### Negative

- Devices and systems older than OS 26 are no longer supported.
- Package consumers must use a toolchain and platform SDK that understand OS 26.
- Future compatibility work must treat OS 26 as the baseline rather than adding
  lower-version branches.

## Implementation references

- `project.yml`
- `VitalStride.xcodeproj/project.pbxproj`
- `Packages/*/Package.swift`
- `Prototype/Package.swift`
- `.specify/memory/constitution.md`
- `CONTEXT.md`

## Revisit triggers

Reopen this decision if Apple changes the availability or behavior of the
required APIs, if product support expands to older operating systems, or if a
future ADR establishes a different minimum platform baseline.
