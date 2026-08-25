# Research: Unified Editable Sub-Set Rows

## Decision 1 — Reuse SetRow composition

**Decision**: SetRow is the single editable row composition. Sub-set identity is passed as app-internal presentation data, and SubSetRow remains as a thin adapter to avoid unnecessary file/call-site churn.

**Evidence**: SetRow already owns editable weight/reps fields, the ellipsis action menu, completion, Large Mode layout and the 44-point target token. SubSetRow duplicates those positions with read-only Text controls and its own menu.

**Alternatives rejected**:

- Restyle the current SubSetRow: preserves two control trees and cannot satisfy shared input behavior.
- Copy SetRow fields into SubSetRow: guarantees future alignment and accessibility drift.
- Move the row to VitalUI: unnecessary cross-layer/public-interface expansion for app-specific active-workout behavior.

## Decision 2 — Keep deletion ownership unchanged

**Decision**: Menu and swipe converge at ActiveExerciseSection.requestDelete; WorkoutSetManager.deleteSet remains the only deletion-rule implementation.

**Evidence**: ActiveExerciseSection already owns confirmation, undo, focus and callbacks. WorkoutSetManager already implements selected-sub-set isolation, main-set cascade, minimum-one-row protection and order reflow.

**Alternatives rejected**:

- Delete from SetRow/SubSetRow: bypasses confirmation and undo orchestration.
- Reimplement the cascade in AppUI: violates the issue and layer contract.
- Change WorkoutSetManager: current package tests already prove its required behavior.

## Decision 3 — Test policy and execution through a request-level seam

**Decision**: Extract one app-internal request-level seam that begins before SetDeletionPolicy dispatch and owns the transition into production execution. ActiveExerciseSection.requestDelete delegates to it, and tests invoke it directly. The seam applies undo/announcement and the deletion callback only after manager success, while the view applies the returned confirmation/focus presentation state.

**Evidence**: Existing tests separately cover policy, manager and undo, but the defect is at the connection between the row affordance and those pieces. Testing only the downstream executor could pass while request-level policy routing or row wiring is broken.

**Alternatives rejected**:

- Test SetDeletionPolicy and WorkoutSetManager separately again: does not prove the UI request route works.
- Test only a downstream execution helper: does not prove request-level policy dispatch.
- Source-text assertions: brittle and do not observe model mutation or undo.
- Add a public coordinator: violates the no-public-API requirement.

The negative matrix includes an only-remaining-set request. WorkoutSetManager refusal must leave the row intact, leave a fresh undo controller's pending/announcement state unchanged, and keep a deletion-callback spy at zero.

## Decision 4 — Preserve numeric-keyboard implementation

**Decision**: Reuse SetRow inputs without editing WorkoutNumericKeyboard.swift.

**Evidence**: The keyboard already receives SetType and disables add-pyramid/add-drop actions unless the row is a working set. Its unilateral and copy actions are existing SetRow behavior.

**Alternatives rejected**:

- Add a sub-set-specific keyboard layout: explicitly out of scope.
- Hide or duplicate left-column actions in a new keyboard: creates a second interaction model.

## Decision 5 — Simulator-based visual acceptance

**Decision**: Use iPhone 16 Simulator for four comparison screenshots and iPhone 17 Simulator for the repository AppUI test gate.

**Evidence**: MY-1478 explicitly requests iPhone 16 light/dark and normal/Large Mode evidence. VitalStride/CONTEXT.md declares iPhone 17 for the full AppUI test command. Constitution Quality Bar K makes simulator evidence the default for visual work.

## Decision 6 — Reuse cataloged accessibility components

**Decision**: Compose the sub-set delete label from the existing cataloged parent/type identity format and existing cataloged delete action. Do not edit Localizable.xcstrings.

**Evidence**: VitalStride/Resources/Localizable.xcstrings already contains the sub-set identity format and the delete action. This meets Constitution VI without expanding the issue's source allowlist.
