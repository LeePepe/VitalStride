# Implementation Plan: Unified Editable Sub-Set Rows

**Branch**: 023-unify-subset-rows | **Date**: 2026-08-25 | **Spec**: specs/023-unify-subset-rows/spec.md

**Input**: MY-1478 and the feature specification in this directory.

## Summary

Replace the independent read-only SubSetRow control tree with an app-internal identity/configuration feeding the existing SetRow composition. ActiveExerciseSection remains the single row assembler and delete entry point. Menu and swipe deletion converge before SetDeletionPolicy; successful execution remains delegated to WorkoutSetManager.deleteSet and the existing undo controller. The work changes only the AppUI layer and its tests.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency

**Primary Dependencies**: SwiftUI, SwiftData, DesignKit, VitalModels, VitalUI

**Storage**: Existing SwiftData ExerciseSet records; no schema or migration

**Testing**: Swift Testing in VitalStrideTests plus UIHostingController layout measurement on UIKit-capable test hosts

**Target Platform**: iOS 18+; iPhone 16 Simulator for requested visual evidence

**Project Type**: XcodeGen-managed multi-target app; this feature is AppUI-only

**Performance Goals**: Preserve ActiveExerciseSection's existing O(n) row-context pass and avoid per-row sorting or tree walks

**Constraints**: No public API; no package edits; 44-point minimum hit targets; localized accessibility; no numeric-keyboard layout/safe-area changes

**Scale/Scope**: SetRow.swift, SubSetRow.swift, ActiveExerciseSection.swift and focused VitalStrideTests sources

## Constitution Check

### Before design

| Gate | Result | Evidence |
|---|---|---|
| Principle II strict concurrency | PASS | No unsafe isolation escape is required; row configuration is immutable app-internal data. |
| Principle III layer ownership | PASS | Production and tests remain within AppUI; package-owned SetType and WorkoutSetManager are read-only dependencies. |
| Principle VI localization | PASS | Accessibility copy composes existing cataloged sub-set identity and delete strings through String(localized:); the catalog does not change. |
| Principle VII scope restraint | PASS | No keyboard redesign, generation algorithm, reorder, FAB, companion-target or schema work. |
| Quality Bar A scope | PASS | Exact source/test allowlist is declared in tasks.md. |
| Quality Bars H/I/K | PASS | Rendered hit-target test, row/deletion tests and iPhone 16 Simulator visual matrix are mandatory. |

### After design

PASS. The design introduces no cross-layer dependency or public contract. Cross-layer behavior is expressed only as the existing AppUI-to-VitalModels call edge; WorkoutSetManager remains unchanged.

## Current Repository Evidence

- VitalStride/Sources/ActiveWorkout/SetRow.swift defines the editable weight/reps fields, completion control, ellipsis menu and shared ActiveWorkoutHitTarget.side token.
- VitalStride/Sources/ActiveWorkout/SubSetRow.swift defines a separate read-only tree-line/text layout and a one-item delete menu.
- VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift branches on SetType.isSubSet, assembles either row type, and routes both menu and swipe callbacks into requestDelete.
- requestDelete resolves SetDeletionPolicy.intent; performDelete snapshots, invokes WorkoutSetManager.deleteSet, records SetDeletionUndoController state, moves accessibility focus and notifies the parent.
- Packages/VitalModels/Sources/VitalModels/Repo/WorkoutSetManager.swift already removes only a selected sub-set, cascades a main set's consecutive children, prevents a zero-row result and reflows order.
- VitalStrideTests/Sources/SubSetReadOnlyTests.swift records the superseded MY-875 read-only contract and must be replaced by parity coverage.
- VitalStrideTests/Sources/SubSetDeletionUndoTests.swift covers policy and undo components but does not currently exercise the production section request/execution seam end to end.

## Design Decisions

### D1 — One row composition, identity supplied as configuration

SetRow remains the sole composition for editable fields, menu chrome and completion. An app-internal immutable row identity/configuration distinguishes a normal row from a sub-set by displayed parent number and current type. SubSetRow remains as a thin adapter to that shared composition; it must not retain a second field/menu/completion tree. The old tree-line terminal-child state is removed because the accepted identity contract is parent index plus type.

This is a source-internal boundary, not a new public API. Existing main-row behavior, smart-progression content, previous-set hint behavior and custom-keyboard component remain intact.

### D2 — Production deletion routing gains a testable app-internal seam

The private SwiftUI event remains requestDelete. Its immediate branch and the confirmed branch must delegate to the same app-internal deletion execution seam used by tests. That seam captures the existing snapshot, calls WorkoutSetManager.deleteSet, records undo only on success, and reports enough outcome for the view to preserve focus and onSetDeleted behavior.

Tests must not duplicate the manager's deletion algorithm or construct a parallel test-only deletion path. No change to WorkoutSetManager is allowed.

### D3 — Menu and swipe converge before policy

Normal, pyramid and drop-set menu callbacks and trailing full-swipe callbacks all invoke requestDelete with the selected ExerciseSet. No affordance may call ModelContext.delete or WorkoutSetManager directly. A parent continues to receive confirmation only when SetDeletionPolicy reports hidden child impact.

### D4 — Preserve hierarchy and keyboard behavior

The shared row uses the current SetType without redefining enum meaning. WorkoutNumericKeyboard.swift is untouched. Its existing rule already disables add-pyramid/add-drop keys unless the current row is a working set; unilateral and copy behavior remain the current SetRow behavior. This feature does not create a second keyboard policy.

### D5 — Accessibility is derived from row identity

The shared delete control receives localized identity copy from the row configuration. A sub-set label includes the parent main-set number, current pyramid/drop-set display name and delete intent. It reuses the existing cataloged composite sub-set identity format and the existing cataloged delete action, so Localizable.xcstrings does not change. The shared 44-point token remains the minimum rendered target, and tests measure the production hit-target container rather than checking the constant alone.

## Project Structure

### Documentation

~~~text
specs/023-unify-subset-rows/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── row-and-deletion-contract.md
├── quickstart.md
└── tasks.md
~~~

### Source Code

~~~text
VitalStride/Sources/ActiveWorkout/
├── SetRow.swift
├── SubSetRow.swift
└── ActiveExerciseSection.swift

VitalStrideTests/Sources/
├── SubSetDeletionUndoTests.swift
├── SubSetReadOnlyTests.swift          # remove/rename superseded contract
├── SubSetRowParityTests.swift         # replacement parity coverage
├── ActiveExerciseRowContextsTests.swift
└── ActiveWorkoutHitTargetTests.swift
~~~

**Structure Decision**: All product and verification work is AppUI-owned per VitalStride/CONTEXT.md. Specs are support artifacts and do not create another schedulable implementation layer.

## Test Strategy

1. RED: Add pyramid and drop-set tests that invoke the same app-internal handler used by requestDelete. Each must observe model removal, pending undo, exact restoration, and parent/sibling survival.
2. GREEN: Extract only the production routing seam needed for those tests; keep policy and package-manager ownership unchanged.
3. In the same implementation task, replace the read-only contract with shared-row configuration/parity tests, then move sub-set rendering onto SetRow composition.
4. Add rendered hit-target and localized identity assertions, remove obsolete tree-line context coverage, and preserve parent-cascade regression coverage.
5. In the verification task, run focused and full tests on the issue-declared iPhone 16 Simulator, then the AppUI layer's full iPhone 17 Simulator command from VitalStride/CONTEXT.md.
6. Capture four iPhone 16 Simulator comparisons: normal/light, normal/dark, Large/light and Large/dark.

## Files in Scope

- VitalStride/Sources/ActiveWorkout/SetRow.swift
- VitalStride/Sources/ActiveWorkout/SubSetRow.swift
- VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift
- VitalStrideTests/Sources/SubSetDeletionUndoTests.swift
- VitalStrideTests/Sources/SubSetReadOnlyTests.swift
- VitalStrideTests/Sources/SubSetRowParityTests.swift
- VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift
- VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift
- specs/023-unify-subset-rows/**

## Files Not to Touch

- Packages/VitalModels/**, including SetType and WorkoutSetManager
- VitalStride/Sources/WorkoutNumericKeyboard.swift
- VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift
- VitalStride/Sources/ActiveWorkoutView.swift
- VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift
- project.yml and VitalStride.xcodeproj/**
- companion targets and all other packages

## Public Interfaces

None. Any row identity/configuration or deletion execution seam is internal to the app target and exists only to deepen the shared composition and make the real production route testable.

## Verification

Focused issue acceptance:

~~~bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SubSetRowParityTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests
~~~

Issue-declared full gate:

~~~bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
~~~

AppUI layer gate from VitalStride/CONTEXT.md:

~~~bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
~~~

Visual evidence: iPhone 16 Simulator, one normal row followed by pyramid and drop-set rows, captured in light/dark and normal/Large Mode. PR evidence must state menu deletion, full swipe and undo results.

## Complexity Tracking

No constitution violation or cross-layer exception is required.
