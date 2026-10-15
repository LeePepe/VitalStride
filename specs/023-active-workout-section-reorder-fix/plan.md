# Implementation Plan: Active Workout Exercise Section Reorder Fix

**Branch**: `023-active-workout-section-reorder-fix` | **Date**: 2026-10-14 | **Spec**: `specs/023-active-workout-section-reorder-fix/spec.md`

**Input**: MY-1473, owner Option A approval `eb00fa65-5302-4150-99b4-d742c9b186aa`, the accepted Spec 023 revision `bb13c2f3fea7067763cfa9966a751cef29a1beba`, PR #448 published head `db43fab774b06ef887add8014b3c2470ff396c8d`, and the exhausted structural-recovery evidence preserved by MY-1812.

## Summary

Complete the remaining active-workout reorder composition repair inside the formal AppUI layer. The successor starts from the published harness, tests, production ordering seam, identifiers, and terminal target at `db43fab…`. It changes only `ActiveWorkoutView.swift`: one title/content-bearing exercise section stays present in edit mode while a distinct move control is attached to that same per-exercise composition. The published fixture/tests, production ordering behavior, and `ActiveExerciseSection.swift` remain fixed.

## Successor Recovery Evidence

- Published `db43fab…` emits an edit-only handle `Section` beside the title/content `ActiveExerciseSection`; runtime evidence shows the handles are absent.
- The preserved dirty candidate switches edit mode to handles-only sections plus a terminal target. Both tests then discover the controls but fail at `ActiveWorkoutSectionReorderUITests.swift:81` and `:215` because `Exercise C` / `Exercise B` resolve as accessibility `Other`, not `StaticText`.
- The accepted authority preserves localized title content, forbids weakening tests, and requires unchanged-intent interaction coverage. Team Lead explicitly freezes both published tests and treats test-identity changes as unapproved evidence only.
- Therefore no Owner choice remains: the successor selects title-preserving composition. Changing tests or title identity would require a separate Team Lead Owner-decision path.

## Accepted Baseline History

- Before PR #448, comparison with implementation reference `f589a917f6f94c98588606fe9b273b5d4767faa4` showed that only `VitalStride/Sources/ActiveWorkoutView.swift` had changed among the original four implementation paths.
- MY-1706 rewrote the header/bottom safe-area and root animation composition in `ActiveWorkoutView.body` around `ActiveWorkoutSnackbarLayout.policy` and `.activeWorkoutRootAnimation(policy:)`.
- That reconciliation established the reported reorder defect and Option A test strategy. PR #448 then published the fixture, tests, production seam, and structural attempts that are now fixed successor inputs.
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

**Scale/Scope**: One active workout and its in-memory exercise collection; one remaining AppUI source file with the published fixture and tests fixed as verification surfaces

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

**Structure Decision**: Keep the change in one formal layer. `ActiveWorkoutView.swift` owns the remaining outer list/edit-mode composition. The published `VitalStrideApp.swift` harness, `ActiveWorkoutSectionReorderUITests.swift`, and `ExerciseManagementTests.swift` remain fixed verification inputs and require no project configuration change.

**Authorized successor implementation path**:

- `VitalStride/Sources/ActiveWorkoutView.swift`

The three published harness/test paths above are read-only verification surfaces for this successor.

## Design

### Section-level interaction

- Retain the existing toolbar edit-mode entry.
- Stop relying on native row movement to infer that a SwiftUI `Section` is one movable row.
- While edit mode is active, attach an explicit drag source and matching drop target to each outer `WorkoutExercise` section from `ActiveWorkoutView.exerciseList`.
- Use the workout-exercise identity for drag/drop routing. Individual `ExerciseSet` and sub-set identities are never drag identities for this feature.
- Keep `ActiveExerciseSection` unchanged. The outer view may decorate the existing section with an edit-only move affordance, but it may not alter section menus, rows, delete behavior, or set editing.
- Preserve MY-1706's policy-driven `ActiveWorkoutView.body` composition, including snackbar/FAB placement, keyboard handling, accessibility focus, `@MainActor` animation policy consumption, and single root animation ownership.
- Use the exercise's existing localized display text and system move/adjustable accessibility semantics. Do not introduce a hard-coded user-facing string or expand the resource-file scope.

### Successor composition contract

- `ActiveWorkoutView.exerciseList` emits one ordered title/content-bearing composition unit per `WorkoutExercise` in both normal and edit modes. The existing `ActiveExerciseSection` remains that content root and stays unchanged.
- `ActiveWorkoutView.swift` attaches one edit-only move control and the before-section drop behavior to the same returned per-exercise composition. It must not emit an additional sibling top-level `Section` for the same exercise and must not replace content with a handles-only branch.
- The localized title `Text` remains independently exposed as `StaticText`; the move control remains a distinct element with identifier `ActiveWorkoutExerciseMoveHandle_<nameEn>`, exact localized exercise label, drag/adjustable semantics, and a target of at least 44×44 points.
- The title, existing set/sub-set content, and move control reorder together by the same `WorkoutExercise` identity. The separate terminal target remains discoverable as `ActiveWorkoutExerciseEndDropTarget` after the last exercise.
- Existing tests are verification clients of this interface: no change to their element type, identifier, label, drag, order, persistence, or Large Mode assertions is permitted.

### Published behavioral harness (fixed input)

- Under a dedicated launch argument and only in DEBUG, the published `VitalStrideApp.swift` selects isolated test storage, suppresses ordinary exercise-catalog seeding, seeds three distinguishable workout exercises, and presents the production `ActiveWorkoutView` through a narrow test host.
- The published reorder argument is disjoint from the existing ExercisePicker and snackbar harness arguments and preserves the existing ExercisePicker test-container/seed path and both existing harness modifiers.
- With the launch argument absent, ordinary Debug behavior is unchanged. The test entry and fixture are absent from Release behavior.
- Stable test selectors identify outer exercises and their move targets without exposing public API or prescribing compiler-level signatures.
- The accepted historical RED is the real section drag failing to complete or produce C/A/B, not compilation or fixture setup. Do not recreate or edit that test surface.
- Both published XCUITests remain byte-for-byte unchanged while the source repair makes their interactions pass and persist across leaving/re-entering the hosted workout.

### Ordering seam

- Preserve the published app-target internal production seam in `ActiveWorkoutView.swift` for move application and zero-based contiguous renumbering.
- Gesture completion and the published app unit invariant call that seam. The unit test is fixed and is not evidence of the pre-fix interaction failure.
- A completed move updates the observed model objects synchronously so the sorted list rerenders immediately.
- Empty, single-item, invalid-target, and no-op moves leave the collection stable and never lose or duplicate an exercise.

### Persistence

- Continue using existing `WorkoutExercise.order` fields; no package model or schema change is allowed.
- The published app unit invariant creates three persisted exercises, invokes the production seam, saves, constructs a fresh `ModelContext`, refetches, and asserts identity order plus contiguous values; it remains unchanged.
- Any explicit production save added by the implementer must handle failure without `try!`, `fatalError`, silent swallowing, or value-bearing logs. The plan does not require an explicit save if existing SwiftData lifecycle persistence proves the acceptance path.

### Verification surfaces

- Unchanged interaction proof: both published XCUITests run together, covering C-before-A immediate/re-entered/Large Mode assertions and A-to-terminal B/C/A.
- Ordering/persistence invariant: the fixed app unit test invokes the production seam, asserts contiguous normalization, saves, and refetches through a fresh context.
- AppUI suite: MY-1473's iPhone 16 Simulator command.
- Required CI: repository-declared AppUI gate on iPhone 17 Simulator remains the shipping authority.
- Interactive acceptance: iPhone 16 Simulator, normal mode, Large Mode, and VoiceOver.

## Delivery Slice and Dependency Graph

`US1 / T001` remains the same independently demonstrable AppUI vertical slice and task identity. The published fixture/tests and production ordering seam are completed inputs; the successor narrows the remaining executable delta to `VitalStride/Sources/ActiveWorkoutView.swift`. Renaming or replanning does not reset the exhausted repair budget.

```text
T001 [AppUI]
  ├─ fixed inputs: published DEBUG harness + unchanged tests + ordering seam
  ├─ remaining delta: title-preserving single-section edit composition
  ├─ automated proof: both existing reorder tests together
  └─ manual proof: normal/Large Mode + VoiceOver title/control coexistence
```

There are no internal task dependencies or cross-layer contracts. MY-1486 is cancelled, and successor MY-1706 is incorporated into the compatibility baseline. MY-1812 already owns the registered Fullstack delivery workspace, published PR, and preserved uncommitted candidate; they must be reused, not replaced, reset, cleaned, or checked out again. This planning revision creates no execution permission. After an exact-revision AI Reviewer PASS, Planner returns readiness to Team Lead. Only a later explicit Team Lead authorization may resume the original Fullstack lifecycle, on the same registered workspace, with the future implementation diff limited to `VitalStride/Sources/ActiveWorkoutView.swift` and both published reorder tests unchanged.

## Complexity Tracking

No constitution violation or cross-layer complexity exception is required.
