# Contract: Shared Row and Deletion Route

## Shared row composition

The standard row composition owns:

- editable weight and reps controls;
- completion control;
- action-menu trigger, item ordering and styling;
- normal/Large Mode sizing;
- row background, border and column alignment;
- shared delete hit-target container.

A normal row supplies its one-based set number. A sub-set supplies its parent main-set number and current pyramid/drop-set type. That leading identity is the only hierarchy-specific visual treatment.

SubSetRow remains as a thin source-internal adapter, but it may not own a second weight/reps/menu/completion implementation. The old tree-line connector is removed; parent index and current type are the complete hierarchy marker.

## Input and menu behavior

- Inputs reuse SetRow's current model synchronization and WorkoutNumericKeyboard integration.
- WorkoutNumericKeyboard.swift and its safe-area/layout behavior remain unchanged.
- Menu deletion, SetType and RPE behavior use the standard row composition.
- Existing SetType semantics determine whether a row remains a sub-set after a type change; this feature adds no new conversion rule.
- Existing working-set-only guards continue to control add-pyramid/add-drop keyboard actions.

## Deletion route

~~~text
shared row menu delete ─┐
                        ├─> ActiveExerciseSection.requestDelete
trailing full swipe ────┘        │
                                 └─> shared app-internal request seam
                                        ├─ SetDeletionPolicy.intent
                                        │      ├─ immediate ─┐
                                        │      └─ confirm ───┼─> production execution
                                        │                    │
                                        └────────────────────┘
                                               ├─ capture DeletedSetSnapshot
                                               ├─ WorkoutSetManager.deleteSet
                                               ├─ success: record undo/announcement,
                                               │           invoke callback,
                                               │           return focus target
                                               └─ refusal: no undo/announcement/callback
~~~

ActiveExerciseSection.requestDelete delegates to the request seam before policy dispatch. Tests invoke that same seam; they do not call only its downstream executor. The seam owns success-side-effect application; the view applies only returned confirmation/focus presentation state. No row may delete a model directly. No AppUI type may reproduce the package manager's cascade or minimum-one-row rules.

## Accessibility

- Every delete hit target is at least 44 by 44 points.
- When standard, pyramid and drop-set production rows are hosted adjacently, all three measured hit/accessibility target frames are at least 44 by 44 points and each neighboring pair has an empty intersection.
- A normal row identifies its set number and delete action.
- A sub-set identifies parent main-set number, current subtype and delete action.
- The sub-set label composes existing cataloged sub-set identity and delete strings; no new localization key is required.
- No decorative tree-line hierarchy glyph remains.
- Deletion continues to post the existing distinct announcement and expose undo.

## Test contract

Tests invoke the same app-internal request-level policy/execution seam used by requestDelete. Pyramid and drop-set cases must each assert model removal, undo state, restoration and parent/sibling survival. Automated coverage activates the production-configured menu-delete and full-swipe callbacks and proves each forwards the selected set exactly once through requestDelete. An only-remaining-set case must reach WorkoutSetManager refusal and assert the row remains, a fresh undo controller retains nil pending/announcement state, and a deletion-callback spy remains zero. Parent cascade confirmation and no-dangling-identity behavior remain covered.
