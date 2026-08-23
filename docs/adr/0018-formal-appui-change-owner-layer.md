# ADR-0018: Formal AppUI Change-Owner Layer

**Status**: Accepted  
**Date**: 2026-08-23  
**Decider**: tianpli

## Context

The repository treated six SPM packages as formal layers while declaring all app targets outside
the layer model. That left production UI such as `ExercisePickerView.swift`, app unit/UI tests,
watch tests, and XcodeGen build configuration without machine-readable ownership. Shared source
entries in `project.yml` also mean target-by-target ownership would assign the same file more than
once.

`Prototype` is a separate SPM package but was likewise absent from the layer index and gates.

## Decision

- Add one cross-platform `AppUI` change-owner layer. Its explicit `paths` cover all app production
  roots, app test roots, `project.yml`, and the generated Xcode project exactly once.
- Shared source consumption by Mac/Watch/Widget remains inside `AppUI`; it does not create duplicate
  target-specific layer ownership.
- `AppUI` depends on the six production package layers. Package `depended_by` mirrors include it.
- Add `Prototype` as an isolated layer depending only on `DesignKit`.
- Gate speed is independent of layer status: `AppUI` is formal even though its full test command is
  CI-only by default. Local pre-push remains fast; the `App target` required check owns full
  `xcodebuild` enforcement.

## Consequences

- Every production/test/build-config path now has a formal change owner.
- AppUI work can be routed and reviewed against layer frontmatter like SPM work.
- The anti-rot checker validates path existence, project package dependencies, and dependency
  mirrors for both directory-backed and logical multi-root layers.
- Current required CI fully covers the iOS scheme. Dedicated macOS and watchOS execution remains a
  separately visible coverage gap rather than a reason to exclude app code from the layer model.

