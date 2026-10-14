# Feature Specification: Reliable Editable Sub-Set Rows

**Feature Branch**: `026-reliable-editable-subset-rows`

**Created**: 2026-10-14

**Status**: Ready for planning review

**Input**: Owner-delegated decision `01a138db-f9f3-7bb0-b4da-f8820e91559d` stops MY-1484 and requires one new version from `main` `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`. The stopped MY-1484 candidate and Draft PR #422 are failure evidence only, not this feature's base.

**Constitution references**: Principles II, III, IV, VI and VII; Development Workflow / Planning Review; Cross-Cutting Quality Bars A, G, H, I and K.

## Existing Behavior

At the pinned base revision:

- A standard set row provides editable weight and reps, the complete action menu, completion, custom numeric-keyboard actions, smart-progression content and previous-set hints.
- Pyramid and drop-set rows use a separate compact, read-only tree-line presentation. They expose read-only weight/reps text, a delete-only menu, completion and a trailing full-swipe delete.
- Both row kinds call the section's delete request entry, but the section itself selects policy, performs deletion, owns undo/announcement/callback effects and mutates confirmation/focus presentation state.
- Package-owned deletion rules already remove only a selected sub-set, cascade a parent over its consecutive sub-sets, refuse a zero-row result and reflow order.
- Existing tests cover policy, package deletion, undo and a shared 44-point constant. They do not prove that the actual production menu/full-swipe actions traverse the production request route, that adjacent production delete frames are disjoint, or that all three row kinds render the same editable composition.

## User Scenarios & Testing

### User Story 1 - Edit and reliably remove any active-workout set row (Priority: P1)

During an active workout, a user edits a standard, pyramid or drop-set row through the same weight, reps, menu, copy and completion interaction. Deleting through either the menu or a committed trailing full swipe follows one reliable production route, removes only the intended row, reports the result accessibly and remains undoable.

**Why this priority**: A sub-set that cannot be corrected or reliably removed leaves the active workout in a state the user cannot repair without losing valid parent or sibling data.

**Independent Test**: Launch the production-hosted acceptance scenario containing adjacent standard, pyramid and drop-set rows. Verify the same editable controls on all three, exercise the actual pyramid menu-delete and actual drop-set committed full swipe, observe one request and one real-seam traversal for each action, verify the expected success/undo effects, and measure the actual delete accessibility frames in their shared coordinate space.

#### Functional acceptance

- **AC-001 — Actual menu route**: Activating the destructive item from a production-configured pyramid row menu MUST call the section delete request entry once and the real request seam once for the selected row. Evidence MUST activate the hosted menu and its item; directly invoking a captured or stored closure is not acceptance evidence.
- **AC-002 — Actual full-swipe route**: Committing a trailing full swipe on a production-configured drop-set row MUST call the same section delete request entry once and the same real request seam once for the selected row. Evidence MUST perform the hosted swipe gesture far enough to commit the full-swipe action; invoking a stored action or tapping a synthesized stand-in is not acceptance evidence.
- **AC-003 — Successful deletion and undo**: Through the real request seam, pyramid and drop-set success cases MUST each remove only the selected sub-set, call the deletion callback once, create one pending undo with one success announcement, and restore the deleted row's values and relative order without parent or sibling loss.
- **AC-004 — Manager refusal has no success effects**: A request to delete the only remaining set MUST reach the package-owned manager refusal, keep the row and order unchanged, leave a fresh undo controller's pending and announcement state empty, call the deletion callback zero times and return no focus target.
- **AC-005 — Confirmation and focus ownership**: A parent request with hidden sub-set impact MUST return confirmation data without deletion or success effects. After confirmation, the request seam alone owns production execution plus undo, announcement and deletion-callback effects; it returns confirmation/focus presentation results for the view to apply exactly once and never accepts presentation-state setter callbacks.
- **AC-006 — Actual adjacent geometry**: One production-hosted standard row followed immediately by a pyramid row and a drop-set row MUST expose the actual delete hit/accessibility frame for each row in one shared coordinate space. Every frame MUST be at least 44 by 44 points, the standard/pyramid intersection MUST be empty, and the pyramid/drop-set intersection MUST be empty. Separately hosted rows, whole-row size proxies and synthesized sequential rectangles are not evidence.
- **AC-007 — Cataloged delete identity**: The actual standard, pyramid and drop-set destructive entries MUST use cataloged label composition. A sub-set entry MUST communicate displayed parent number, current pyramid/drop-set type and delete intent. Uncataloged interpolated keys, wrapper-only labels and helper-string assertions detached from the production entry are not evidence.
- **AC-008 — Shared editable composition**: Production standard, pyramid and drop-set rows MUST expose the same actual weight field, reps field, action-menu and completion-control composition. Pyramid and drop-set fields MUST be editable; completion MUST update the selected row; the action menu MUST retain the standard production actions; and the existing custom-keyboard copy action MUST remain wired for a sub-set and update the next row through the production section route.
- **AC-009 — Existing deletion compatibility**: Parent cascade confirmation, selected-sub-set isolation, minimum-one-row refusal, order reflow, distinct consecutive-delete announcements, dead-parent undo protection and existing undo copy MUST remain green without changing package-owned deletion rules.
- **AC-010 — Existing row compatibility**: Standard-row smart progression, previous-set hints, bilateral/unilateral editing, add-pyramid/add-drop generation, custom numeric keyboard layout/safe area, compact Large Mode and existing four ActiveExerciseSection preview variants MUST remain available. Each preview variant MUST seed adjacent standard, pyramid and drop-set rows for visual acceptance.
- **AC-011 — Scope and interface**: The version MUST add no public interface, persistence/schema change, SetType semantic change, package edit, localization-catalog edit, numeric-keyboard edit, reorder change, add-exercise change, or companion-only feature.

#### Visual acceptance

On iPhone 17 Simulator, capture the same production-hosted standard/pyramid/drop-set stack in normal-light, normal-dark, Large-light and Large-dark. In every capture the weight, reps, menu and completion columns align, controls do not clip, the leading identity is the only hierarchy-specific treatment, and no read-only tree-line presentation remains.

### Edge Cases

- Deleting the first of consecutive sub-sets leaves later sub-sets and the parent intact; undo restores the original ordering.
- Deleting the final sub-set leaves no obsolete tree-line or terminal-child state because that presentation is removed.
- Repeated requests for an already removed row do not produce a second success callback, undo or announcement.
- A parent request that requires confirmation has no mutation until confirmation is accepted.
- A mixed pyramid/drop-set child run retains the existing parent confirmation semantics.
- Copying from the final sub-set retains the existing append behavior; copying when a next row exists updates that row using the current production copy contract.
- Compact and Large Mode preserve visible, non-overlapping menu and completion controls.

## Requirements

### Functional Requirements

- **FR-001**: Standard, pyramid and drop-set rows MUST use one production editable-row composition for weight, reps, action menu, custom-keyboard actions and completion.
- **FR-002**: Sub-set identity MUST be immutable app-internal presentation data derived from the displayed parent number and current SetType; it MUST NOT own a second field/menu/completion tree.
- **FR-003**: Production menu-delete and trailing full-swipe actions MUST converge at the section delete request entry and then traverse one app-internal request seam beginning before policy dispatch.
- **FR-004**: The request seam MUST own policy dispatch, production deletion execution and success-only undo/announcement/deletion-callback effects. It MUST return confirmation/focus presentation results without accepting or mutating presentation setters.
- **FR-005**: Package-owned deletion rules MUST remain the only source of selected-sub-set isolation, parent cascade, minimum-one-row refusal and order reflow.
- **FR-006**: Actual production UI activation MUST prove AC-001 and AC-002 with request/seam/callback counts and selected-row identity; direct stored-closure substitution is forbidden.
- **FR-007**: Actual production controls and frames MUST prove AC-006 through AC-008; string helpers, context flags, shared constants, whole-row measurements and synthetic rectangles are insufficient substitutes.
- **FR-008**: All changed user-visible labels MUST be composed from existing cataloged strings; the localization catalog remains unchanged.
- **FR-009**: No public interface, storage migration or package implementation change is permitted.

### Key Entities

- **Exercise set row**: The production active-workout presentation of an existing set record.
- **Row identity/configuration**: Immutable app-internal presentation data distinguishing a standard row from a pyramid/drop-set row while feeding one shared composition.
- **Delete request result**: Return-only presentation information indicating confirmation, focus-after-success or refusal/no change.
- **Delete request seam**: The app-internal interface shared by the production section and its focused tests; it owns policy/execution and success effects.
- **Deleted-set snapshot**: Existing undo data used to restore values and relative order.

## Compatibility

- Existing SetType values, persistence and pyramid/drop-set generation calculations remain unchanged.
- The package-owned manager remains authoritative for deletion and order reflow; package sources and tests are read-only dependencies.
- Standard-row editing, menus, custom keyboard, copy behavior, smart progression, previous-set hints and completion behavior remain available.
- Parent cascade confirmation, undo snackbar arbitration, announcement identity, dead-parent protection and focus recovery remain available.
- Existing app-target build/test gates remain authoritative; this version adds focused UI and request-seam proof rather than weakening existing tests.
- iOS is the implementation surface. No macOS/watchOS-specific behavior is added.

## Removed Behavior

Authority: Owner-delegated decision `01a138db-f9f3-7bb0-b4da-f8820e91559d`, recorded 2026-10-14, requires the shared editable pyramid/drop-set row successor and supersedes the stopped MY-1484 delivery.

- Remove the separate read-only pyramid/drop-set weight/reps control tree.
- Remove the decorative tree-line and terminal-child presentation state from the row contract.
- Remove the sub-set-specific bare-ellipsis, delete-only menu contract; sub-sets use the standard production action-menu composition.
- Delete or replace assertions whose sole purpose is to enforce read-only fields, absent standard menu actions, absent editable composition, tree-line rendering or `isLastSubSet` presentation behavior.
- No other existing test may be deleted or weakened. Any changed test must be replaced by stronger acceptance evidence mapped to AC-001 through AC-011.

## Success Criteria

- **SC-001**: Hosted UI tests activate the actual menu and committed full swipe; each reports exactly one section request and one real-seam traversal for the intended row without invoking stored closures.
- **SC-002**: Focused seam tests prove pyramid/drop-set success, exact undo restoration, return-only confirmation/focus behavior and zero success effects on manager refusal.
- **SC-003**: Hosted standard/pyramid/drop-set rows expose identical production control categories, editable sub-set fields, working completion/menu/copy behavior and cataloged delete identities.
- **SC-004**: Actual adjacent delete frames are each at least 44 by 44 points and both neighboring intersections are empty.
- **SC-005**: Focused acceptance, complete AppUI and required CI gates pass with changes limited to the reviewed AppUI/test/spec allowlist.

## Assumptions

- Existing package deletion behavior is correct and is not reopened by this feature.
- Existing catalog entries are sufficient when composed at the production destructive entry; the catalog itself is out of scope.
- A DEBUG-only in-memory production host is acceptable for deterministic XCUITest activation and geometry evidence because it renders the same production ActiveExerciseSection and row actions.
- The stopped candidate `bf66f046a810a368f317e386d7c0504ba41cf2c0` may be consulted only to understand failed evidence patterns.

## Non-Goals

- No SetType, ExerciseSet schema, CloudKit or HealthKit change.
- No WorkoutSetManager or other package change.
- No custom numeric-keyboard redesign.
- No exercise reordering, add-exercise FAB or snackbar redesign.
- No new localization key.
- No direct repair, continuation or renaming of MY-1484.
- No Draft PR #422 mutation; closing or superseding it is deferred until the successor PR exists.
