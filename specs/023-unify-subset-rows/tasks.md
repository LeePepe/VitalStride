# Tasks: Unified Editable Sub-Set Rows

**Input**: Design documents from specs/023-unify-subset-rows/

**Prerequisites**: spec.md, plan.md, research.md, data-model.md, contracts/row-and-deletion-contract.md and quickstart.md

**Parent issue**: MY-1478

**Constitution references**: Principles II, III, VI and VII; Development Workflow / Planning Review; Cross-Cutting Quality Bars A, G, H, I and K.

**Organization**: One vertical slice with one RED/GREEN AppUI implementation task and one blocked AppUI verification task. No task changes a package layer.

## Phase 1: User Story 1 — Edit, identify and reliably remove a sub-set (P1)

**Goal**: Pyramid and drop-set rows use the standard editable row composition, delete through the existing production policy/manager/undo route, and remain accessible and aligned across supported visual modes.

**Independent Test**: Create a parent, pyramid, drop-set and survivor; edit both sub-sets; delete each through the production request handler; verify isolation and undo restoration; measure the delete target and review four iPhone 16 Simulator states.

- [ ] T001 [US1] Add RED tests then implement the shared editable sub-set adapter and production deletion route across VitalStride/Sources/ActiveWorkout/SetRow.swift, VitalStride/Sources/ActiveWorkout/SubSetRow.swift, VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift, VitalStrideTests/Sources/SubSetDeletionUndoTests.swift, VitalStrideTests/Sources/SubSetReadOnlyTests.swift, VitalStrideTests/Sources/SubSetRowParityTests.swift, VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift, VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift and specs/023-unify-subset-rows/**
- [ ] T002 [US1] Execute the focused and full AppUI gates, inspect the allowlisted diff, and attach four iPhone 16 Simulator row-alignment comparisons using specs/023-unify-subset-rows/quickstart.md

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer / context | AppUI — VitalStride/CONTEXT.md |
| Slice | US1 |
| Files in scope | VitalStride/Sources/ActiveWorkout/SetRow.swift; VitalStride/Sources/ActiveWorkout/SubSetRow.swift; VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift; VitalStrideTests/Sources/SubSetDeletionUndoTests.swift; VitalStrideTests/Sources/SubSetReadOnlyTests.swift (rename source and remove obsolete suite content); VitalStrideTests/Sources/SubSetRowParityTests.swift (rename target and replacement suite); VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift; VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift; specs/023-unify-subset-rows/** |
| Files excluded | VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift; Packages/** including SetType and WorkoutSetManager; VitalStride/Sources/WorkoutNumericKeyboard.swift; VitalStride/Sources/ActiveWorkoutView.swift; VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift; VitalStride/Resources/Localizable.xcstrings; project.yml; VitalStride.xcodeproj/**; VitalStrideMac/**; VitalStrideWatch Watch App/**; VitalStrideWidgets/** |
| Interface / contract | No public API. Add immutable app-internal row identity/configuration. SetRow remains the only weight/reps/menu/completion composition; SubSetRow remains a thin adapter. Add one app-internal request-level seam that starts before SetDeletionPolicy dispatch, enters production execution, and is delegated to by ActiveExerciseSection.requestDelete and invoked by tests. The seam records undo/announcement and invokes the deletion callback only after manager success, then returns presentation state such as the focus target; the view does not apply those success effects. Reuse existing cataloged sub-set identity and delete strings. |
| Blocking edges | None |
| Task-local acceptance | Capture RED before production edits. GREEN proves: (1) pyramid and drop-set cases enter the request-level seam used by requestDelete, including SetDeletionPolicy dispatch and production execution, remove only the selected row, arm pending undo and restore values/order without parent/sibling loss; (2) the production-configured menu-delete and full-swipe callbacks each forward the selected set exactly once through requestDelete to that seam; (3) an only-remaining-set request reaches WorkoutSetManager refusal, leaves the row intact, leaves a fresh undo controller's pending and announcement state nil, and keeps a deletion-callback spy at zero; (4) normal, pyramid and drop-set identities select the shared editable field/menu/completion model; (5) the old read-only/tree-line implementation and tests are removed; (6) adjacent hosted standard, pyramid and drop-set production rows each expose a delete hit/accessibility frame at least 44 by 44 points and both neighboring pairs have an empty intersection; (7) sub-set delete copy includes parent number, current type and delete intent; (8) existing parent confirmation, announcement identity, dead-parent undo, main-row keyboard behavior and compact Large layout remain green; (9) the existing four ActiveExerciseSection preview states each seed a normal, pyramid and drop-set row for visual capture. |
| Exact verification | Run the focused iPhone 16 command below from repository root. |

~~~bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SubSetRowParityTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests
~~~

### T002 Metadata

| Field | Contract |
|---|---|
| Owning layer / context | AppUI integration/verification — VitalStride/CONTEXT.md |
| Slice | US1 |
| Files in scope | Verification of the T001 allowlist and PR attachments only; follow specs/023-unify-subset-rows/quickstart.md. No repository source file is owned by this task. |
| Files excluded | Any implementation repair or scope expansion; failures return to T001. T002 changes no repository file. |
| Interface / contract | Verify the assembled AppUI behavior and evidence. Do not create another row or deletion path. |
| Blocking edges | Depends on T001 |
| Task-local acceptance | Focused iPhone 16 suites pass, including request-level pyramid/drop-set success, manager-refusal side effects, exactly-once menu/swipe callback convergence and three-row adjacent disjoint-frame assertions; the issue-declared unfiltered iPhone 16 suite passes; the formal AppUI iPhone 17 suite passes; diff contains only declared source/test/spec paths; four iPhone 16 screenshots show aligned standard/pyramid/drop-set rows in normal-light, normal-dark, Large-light and Large-dark; PR evidence records menu delete, full swipe, undo and parent-cascade results. |
| Exact verification | Run all commands and the manual checklist below from repository root. |

~~~bash
# Focused issue acceptance
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SubSetRowParityTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests

# Issue-declared full gate
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# Formal AppUI layer gate
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation

# Scope allowlist
git diff --name-only origin/main...HEAD
~~~

Manual evidence:

- iPhone 16 Simulator normal/light: standard + pyramid + drop-set rows aligned.
- iPhone 16 Simulator normal/dark: same.
- iPhone 16 Simulator Large/light: same, no clipped menu/completion controls.
- iPhone 16 Simulator Large/dark: same.
- Menu-delete pyramid → only pyramid removed → undo restores.
- Full-swipe drop-set → only drop-set removed → undo restores.
- Parent delete → existing child-count confirmation and cascade behavior preserved.
- VoiceOver delete entry states parent number, type and delete action.

**US1 checkpoint**: The unified interaction is editable, reliably deletable, undoable, accessible, visually aligned and fully verified.

---

## Dependencies & Execution Order

~~~text
US1 / T001 RED-GREEN AppUI implementation
        ↓
US1 / T002 assembled AppUI verification
~~~

- T001 owns every source/test edit and records RED before GREEN.
- T002 is verification-only and cannot repair failures; it returns them to T001.
- The graph is acyclic and contains no false parallel marker.

## Acceptance Traceability

| Spec requirement / acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| FR-003, FR-004, FR-005: pyramid menu deletion crosses request-level policy/execution, removes only selected row and undo restores | US1 | T001, T002 | SubSetDeletionUndoTests; production menu-callback exactly-once test; manual menu path |
| FR-003, FR-004, FR-005: drop-set swipe deletion crosses request-level policy/execution, removes only selected row and undo restores | US1 | T001, T002 | SubSetDeletionUndoTests; production swipe-callback exactly-once test; manual full swipe |
| FR-004, FR-008: manager refusal emits no undo, announcement or deletion callback | US1 | T001, T002 | SubSetDeletionUndoTests only-remaining-set negative case |
| FR-001, FR-002, FR-007: shared editable weight/reps/completion/menu composition and identity | US1 | T001, T002 | SubSetRowParityTests; implementation reuse; screenshots |
| FR-004, FR-005: parent cascade confirmation and package rule remain | US1 | T001, T002 | SubSetDeletionUndoTests; manual parent delete |
| FR-006: 44-point delete targets, disjoint adjacent frames and explicit VoiceOver identity | US1 | T001, T002 | ActiveWorkoutHitTargetTests standard+pyramid+drop-set geometry and both neighboring intersections; SubSetRowParityTests; VoiceOver check |
| FR-008: light/dark × normal/Large alignment and full verification | US1 | T001, T002 | ActiveExerciseSection previews; focused/full tests; four iPhone 16 screenshots |
| FR-009: no public API/package/schema/keyboard/reorder/FAB change | US1 | T001, T002 | Diff allowlist and full AppUI gates |

## Global Scope Contract

### Files in scope

- VitalStride/Sources/ActiveWorkout/SetRow.swift
- VitalStride/Sources/ActiveWorkout/SubSetRow.swift
- VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift
- VitalStrideTests/Sources/SubSetDeletionUndoTests.swift
- VitalStrideTests/Sources/SubSetReadOnlyTests.swift
- VitalStrideTests/Sources/SubSetRowParityTests.swift
- VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift
- VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift
- specs/023-unify-subset-rows/**

### Files not to touch

- VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift
- Packages/VitalModels/** and every other Packages/** path
- VitalStride/Sources/WorkoutNumericKeyboard.swift
- VitalStride/Sources/ActiveWorkoutView.swift
- VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift
- VitalStride/Resources/Localizable.xcstrings
- project.yml and VitalStride.xcodeproj/**
- companion targets

### Public signatures

None. App-internal immutable row configuration and a testable request-level deletion seam covering policy dispatch plus production execution are permitted. No public type, method or package API is added.

## Implementation Strategy

1. Complete T001 with captured RED then GREEN evidence and demonstrate the complete user slice.
2. Complete T002 only after fresh verification; return any failure to T001 instead of expanding T002.
3. Do not run speckit implement. Team Lead dispatches implementation only after exact-revision AI Reviewer and Team Lead approval.
