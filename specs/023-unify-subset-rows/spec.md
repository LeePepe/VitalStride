# Feature Specification: Unified Editable Sub-Set Rows

**Feature Branch**: 023-unify-subset-rows

**Created**: 2026-08-25

**Status**: Planning candidate for MY-1478

**Input**: Pyramid and drop-set rows must use the standard editable set-row interaction and reliably delete through the existing delete/undo policy.

**Constitution references**: Principles II, III, VI and VII; Development Workflow / Planning Review; Cross-Cutting Quality Bars A, G, H, I and K.

## User Scenarios & Testing

### User Story 1 - Edit and reliably remove a sub-set (Priority: P1)

During an active workout, a user can edit a pyramid or drop-set row with the same weight, reps, completion and action-menu controls used by a normal set. Deleting from either the menu or trailing swipe removes only the chosen sub-set and offers the existing undo snackbar.

**Why this priority**: A sub-set that cannot be corrected or removed leaves the active workout in a state the user cannot repair without deleting its parent and losing valid data.

**Independent Test**: Create one main set followed by one pyramid and one drop-set row. Edit each sub-set, delete each once through the production request path, verify its parent and sibling remain, then undo and verify the row returns with its values and order intact.

**Acceptance Scenarios**:

1. **Given** a main set followed by a pyramid sub-set and another surviving row, **When** the pyramid row's menu delete action reaches the testable section request seam used by ActiveExerciseSection.requestDelete, **Then** that seam performs policy dispatch and production execution, only the pyramid row is removed, the undo snackbar is armed, and undo restores its values and original relative position.
2. **Given** a main set followed by a drop-set sub-set and another surviving row, **When** the drop-set row is deleted through trailing full swipe, **Then** the swipe invokes the same requestDelete entry and request-level policy/execution seam as the menu, only that drop-set row is removed, and undo restores it.
3. **Given** a pyramid or drop-set row, **When** the user edits weight or reps, changes completion, or opens its action menu, **Then** the controls, alignment, input behavior and menu ordering match a standard set row; only the leading parent-index/type identity differs.
4. **Given** a parent main set with consecutive sub-sets, **When** the parent is deleted, **Then** the existing count-aware cascade confirmation remains and the package-owned deletion manager remains the single source of the cascade and minimum-one-row rules.

#### Accessibility and visual acceptance

A user can distinguish a sub-set from its parent without receiving a visually or behaviorally different row, and can discover and activate deletion with touch or VoiceOver in normal and Large Mode.

The same slice is incomplete if the hierarchy becomes ambiguous, controls clip, or destructive actions cannot be identified by assistive technology. On iPhone 16 Simulator, compare normal and sub-set rows in light/dark and normal/Large Mode, measure the delete target, and inspect VoiceOver output for parent number, sub-set type and delete intent.

**Acceptance Scenarios**:

1. **Given** a pyramid or drop-set row, **When** VoiceOver focuses its delete entry, **Then** the spoken label identifies the parent main-set number, the current sub-set type and the delete action.
2. **Given** any normal or sub-set row, **When** its delete entry is laid out, **Then** its rendered hit target is at least 44 by 44 points and does not overlap an adjacent row.
3. **Given** light/dark appearance and normal/Large Mode, **When** a normal row and both sub-set types are rendered together on iPhone 16 Simulator, **Then** weight, reps, menu and completion columns align and the leading identity is the only hierarchy-specific visual treatment.

### Edge Cases

- Deleting the first of several consecutive sub-sets must not remove later sub-sets or the parent.
- Deleting the last sub-set must leave no dangling hierarchy marker.
- Given an only remaining set, a delete request through the production request-level seam must reach WorkoutSetManager refusal, leave the row intact, and produce no pending undo, success announcement or deletion callback.
- Two consecutive deletions with identical copy must each replace the pending undo and produce a distinct VoiceOver announcement.
- Changing a sub-set's values or completion state must not change SetType persistence semantics or the generation algorithm.
- Compact-width Large Mode must keep the trailing menu and completion controls visible.

## Requirements

### Functional Requirements

- **FR-001**: Standard and sub-set rows MUST share one editable row composition for weight, reps, completion and action-menu layout.
- **FR-002**: A sub-set row MUST express identity through a leading parent main-set number plus its existing pyramid/drop-set type; it MUST NOT use the former read-only tree-line/text control tree.
- **FR-003**: Both menu deletion and trailing full swipe MUST call ActiveExerciseSection.requestDelete, which MUST delegate to one app-internal request-level seam covering SetDeletionPolicy dispatch and production execution.
- **FR-004**: The request-level seam MUST resolve confirmation through SetDeletionPolicy, execute eligible deletion through WorkoutSetManager.deleteSet, and arm the existing SetDeletionUndoController only after a successful deletion; manager refusal MUST produce no pending undo, success announcement or deletion callback.
- **FR-005**: Deleting a sub-set MUST remove only the selected row; deleting a parent MUST retain the existing consecutive-child cascade confirmation and package-owned cascade behavior.
- **FR-006**: Each delete entry MUST render a hit target of at least 44 by 44 points and expose its localized VoiceOver identity. When one standard, one pyramid and one drop-set production row are hosted adjacently, all three hit/accessibility frames MUST meet the size floor and each neighboring pair MUST be disjoint; sub-set labels MUST contain parent number, current type and delete intent.
- **FR-007**: Existing normal-row input behavior, custom numeric keyboard layout/safe area, smart-progression behavior, previous-set hints, add-sub-set generation and copy semantics MUST NOT regress.
- **FR-008**: Verification MUST cover pyramid and drop-set request-level policy/execution, manager-refusal side effects, undo restoration, sibling/parent isolation, parent cascade regression, menu/swipe convergence, shared row configuration, adjacent non-overlapping hit targets, VoiceOver copy and four iPhone 16 Simulator appearance/mode combinations.
- **FR-009**: The feature MUST add no public API and MUST not modify SetType storage/schema or WorkoutSetManager.

### Key Entities

- **ExerciseSet**: Existing set record whose SetType determines normal versus pyramid/drop-set identity.
- **Row identity/configuration**: App-internal presentation metadata that supplies the displayed main-set number and, for a sub-set, its existing type to the shared row composition.
- **Delete request**: Existing app-layer orchestration that chooses immediate versus confirmed deletion, invokes the package manager, and records undo.
- **DeletedSetSnapshot**: Existing undo payload used to restore deleted rows with their values and relative order.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Automated tests independently delete and undo one pyramid and one drop-set through the request-level policy/execution seam used by ActiveExerciseSection.requestDelete, with zero parent or sibling loss; a manager-refused request produces zero undo, announcement or deletion-callback side effects.
- **SC-002**: The shared row composition renders identical weight, reps, action-menu and completion columns for normal, pyramid and drop-set rows; all four iPhone 16 Simulator comparison screenshots pass review.
- **SC-003**: The standard, pyramid and drop-set delete affordances each measure at least 44 by 44 points, both neighboring production-row target-frame pairs have an empty intersection, and every sub-set delete accessibility label includes parent number, sub-set type and delete intent.
- **SC-004**: The repository AppUI test gate passes without changes under Packages/, project.yml, generated Xcode project files, the numeric keyboard layout/safe-area implementation, exercise reorder or the add-exercise FAB.

## Assumptions

- The issue's accepted product decision supersedes MY-875's former read-only sub-set presentation.
- Existing SetRow input controls and WorkoutNumericKeyboard behavior are reused, not redesigned.
- The existing SetType values and WorkoutSetManager deletion rules are correct and remain unchanged.
- Screenshot evidence is attached to the implementation PR; it is not stored as a new product asset.

## Non-Goals

- No SetType enum or SwiftData schema change.
- No change to pyramid/drop-set generation calculations.
- No numeric keyboard layout, safe-area, reorder or add-exercise FAB change.
- No new package or public interface.
- No watchOS- or macOS-specific feature work.
