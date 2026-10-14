# Implementation Plan: Active Workout Exercise Section Reorder Fix

**Branch**: `023-active-workout-section-reorder-fix` | **Date**: 2026-10-14 | **Spec**: `specs/023-active-workout-section-reorder-fix/spec.md`

**Input**: MY-1473, owner Option A approval `eb00fa65-5302-4150-99b4-d742c9b186aa`, resolved AI Reviewer finding `d15d5476-95de-480c-8358-5c96bbb36848`, the feature specification in this directory, and verified current base `main@7fc46752b36d1b2469209b96c50801419315987c`.

## Summary

Repair active-workout reordering inside the formal AppUI layer. `ActiveWorkoutView.exerciseList` currently asks native `List.onMove` to move children whose rendered roots are SwiftUI `Section` containers, so the existing `EditButton` does not yield a reliable whole-section move control. The implementation will first add an owner-authorized DEBUG harness and XCUITest that fail on the unchanged interaction, then make the outer `WorkoutExercise` identity explicitly draggable while edit mode is active. A separate unit invariant will exercise the production reorder/renumber seam through save and fresh-context refetch. Existing section internals remain unchanged.

## Current-Base Semantic Drift

- Compared with the prior implementation reference `f589a917f6f94c98588606fe9b273b5d4767faa4`, only `VitalStride/Sources/ActiveWorkoutView.swift` has changed among the four authorized implementation paths.
- MY-1706 rewrote the header/bottom safe-area and root animation composition in `ActiveWorkoutView.body` around `ActiveWorkoutSnackbarLayout.policy` and `.activeWorkoutRootAnimation(policy:)`.
- The current `EditButton`, `exerciseList`, outer `ForEach`, `.onMove`, and `moveExercises(from:to:)` remain semantically unchanged. The reported reorder defect and the Option A test strategy therefore remain current.
- Implementation may edit reorder-specific regions in the shared source file but must preserve the MY-1706 policy-driven composition and tests. The package introduces no new product or architecture decision.

## Technical Context

**Language/Version**: Swift 6 with strict concurrency

**Primary Dependencies**: SwiftUI, SwiftData, existing `VitalModels` types consumed by AppUI

**Storage**: Existing SwiftData training configuration; no schema or migration change

**Testing**: Swift Testing app unit tests plus XCTest UI through the existing `VitalStride` / `VitalStrideUITests` schemes

**Target Platform**: iOS 18+; interactive acceptance on iPhone 16 Simulator

**Project Type**: Multiplatform Apple app; this change is limited to the iOS active-workout AppUI surface and AppUI tests

**Performance Goals**: Immediate visual response for a completed drag; linear renumbering in exercise count

**Constraints**: No `Packages/**`, section component, set/sub-set UI, template ordering, project configuration, or public API changes; no workout or health values in logs

**Scale/Scope**: One active workout and its in-memory exercise collection; two app source files, one app unit-test file, and one XCUITest file

## Constitution Check

*GATE before and after design: PASS for this candidate.*

| Gate | Planning evidence |
|---|---|
| Principle II — Swift 6 strict concurrency | The work remains MainActor-bound AppUI state and introduces no concurrency escape hatch. |
| Principle III — formal layer ownership | Production and tests are both owned by AppUI per `VitalStride/CONTEXT.md`; no package changes are scheduled. |
| Principle VII — scope restraint | The existing section component and all set/sub-set, template, picker, companion-target, and project configuration behavior are excluded. |
| Quality Bar A — scope discipline | The task metadata contains a closed source/test allowlist and explicit exclusions. |
| Quality Bars C/D/E | No unsafe isolation, forced failure/cast, or Xcode project configuration change is part of the design. |
| Quality Bars G/H/I | No new user-facing literal is required; the control uses existing exercise display text plus system move/adjustable accessibility semantics; the production interaction receives a behavioral XCUITest and the ordering seam receives a separate persistence invariant. |
| Planning Review / DoR | Scope, exclusions, internal-only interface impact, at least three functional acceptance criteria, working directory, and exact verification are present in `tasks.md`. |

## Project Structure

### Documentation (this feature)

```text
specs/023-active-workout-section-reorder-fix/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── exercise-section-reorder.md
└── tasks.md
```

### Source Code (repository root)

```text
VitalStride/Sources/
├── ActiveWorkoutView.swift
└── VitalStrideApp.swift

VitalStrideTests/Sources/
└── ExerciseManagementTests.swift

VitalStrideUITests/Sources/
└── ActiveWorkoutSectionReorderUITests.swift
```

**Structure Decision**: Keep the change in one formal layer. `ActiveWorkoutView.swift` owns the outer list/edit-mode coordination; `VitalStrideApp.swift` owns an opt-in DEBUG-only test host; `ActiveWorkoutSectionReorderUITests.swift` owns the real interaction RED; and `ExerciseManagementTests.swift` owns the production-seam ordering/persistence invariant rather than a copied algorithm. Existing directory-backed test targets require no project configuration change.

**Authorized implementation paths**:

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/VitalStrideApp.swift`
- `VitalStrideTests/Sources/ExerciseManagementTests.swift`
- `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`

## Design

### Section-level interaction

- Retain the existing toolbar edit-mode entry.
- Stop relying on native row movement to infer that a SwiftUI `Section` is one movable row.
- While edit mode is active, attach an explicit drag source and matching drop target to each outer `WorkoutExercise` section from `ActiveWorkoutView.exerciseList`.
- Use the workout-exercise identity for drag/drop routing. Individual `ExerciseSet` and sub-set identities are never drag identities for this feature.
- Keep `ActiveExerciseSection` unchanged. The outer view may decorate the existing section with an edit-only move affordance, but it may not alter section menus, rows, delete behavior, or set editing.
- Preserve MY-1706's policy-driven `ActiveWorkoutView.body` composition, including snackbar/FAB placement, keyboard handling, accessibility focus, `@MainActor` animation policy consumption, and single root animation ownership.
- Use the exercise's existing localized display text and system move/adjustable accessibility semantics. Do not introduce a hard-coded user-facing string or expand the resource-file scope.

### Behavioral RED harness

- Under a dedicated launch argument and only in DEBUG, `VitalStrideApp.swift` selects isolated test storage, suppresses ordinary exercise-catalog seeding, seeds three distinguishable workout exercises, and presents the production `ActiveWorkoutView` through a narrow test host.
- The reorder argument is disjoint from the existing ExercisePicker and snackbar harness arguments. Preserve the existing ExercisePicker test-container/seed path and both existing harness modifiers when extending the shared app entry.
- With the launch argument absent, ordinary Debug behavior is unchanged. The test entry and fixture are absent from Release behavior.
- Stable test selectors identify outer exercises and their move targets without exposing public API or prescribing compiler-level signatures.
- Add the harness and XCUITest before editing reorder behavior. Run the focused XCUITest against the unchanged `ActiveWorkoutView`; RED is the real section drag failing to complete or produce C/A/B, not compilation or fixture setup.
- The XCUITest then remains unchanged in intent while the production source repair makes the same interaction pass and persist across leaving/re-entering the hosted workout.

### Ordering seam

- Consolidate move application and zero-based contiguous renumbering into one app-target internal production seam in `ActiveWorkoutView.swift`.
- Gesture completion and the app unit invariant both call that seam. The unit test may not repeat collection movement or enumerated order assignment; it is not evidence of the pre-fix interaction failure.
- A completed move updates the observed model objects synchronously so the sorted list rerenders immediately.
- Empty, single-item, invalid-target, and no-op moves leave the collection stable and never lose or duplicate an exercise.

### Persistence

- Continue using existing `WorkoutExercise.order` fields; no package model or schema change is allowed.
- The app unit invariant creates three persisted exercises, invokes the production seam, saves, constructs a fresh `ModelContext`, refetches, and asserts identity order plus contiguous values.
- Any explicit production save added by the implementer must handle failure without `try!`, `fatalError`, silent swallowing, or value-bearing logs. The plan does not require an explicit save if existing SwiftData lifecycle persistence proves the acceptance path.

### Verification surfaces

- Behavioral RED/GREEN: focused XCUITest performs the production whole-section C-before-A drag and asserts immediate/re-entered C/A/B.
- Ordering/persistence invariant: app unit test invokes the production seam, asserts contiguous normalization, saves, and refetches through a fresh context.
- AppUI suite: MY-1473's iPhone 16 Simulator command.
- Required CI: repository-declared AppUI gate on iPhone 17 Simulator remains the shipping authority.
- Interactive acceptance: iPhone 16 Simulator, normal mode, Large Mode, and VoiceOver.

## Delivery Slice and Dependency Graph

`US1 / T001` is one independently demonstrable AppUI vertical slice and one schedulable Fullstack task. It owns the behavioral RED harness/test, source repair, unit persistence invariant, and interactive acceptance because splitting a deliberately failing test from its same-layer fix would create a non-mergeable child issue.

```text
T001 [AppUI]
  ├─ RED: DEBUG harness + XCUITest fail on unchanged section interaction
  ├─ GREEN: section drag/drop routes through production reorder seam
  ├─ invariant: contiguous order + save + fresh-context refetch
  └─ acceptance: normal/Large Mode + VoiceOver on iPhone 16 Simulator
```

There are no internal task dependencies or cross-layer contracts. MY-1486 is cancelled, and successor MY-1706 is complete and incorporated into the declared current base; their former source-overlap gate is resolved by preserving the current policy-driven composition. MY-1484 remains `in_review` and is a shared AppUI/Xcode validation-lane gate rather than a source dependency. Before dispatch, Team Lead must make that lane quiescent, provision the authoritative delivery base/workspace from the passing planning revision, and recheck the four-file allowlist for drift after `7fc46752b36d1b2469209b96c50801419315987c`. Tracker reconciliation reuses parked MY-1567 after AI Reviewer passes this exact planning revision and Team Lead accepts it.

## Complexity Tracking

No constitution violation or cross-layer complexity exception is required.
