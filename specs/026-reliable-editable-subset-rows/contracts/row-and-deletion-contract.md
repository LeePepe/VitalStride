# Contract: Shared Editable Row and Reliable Deletion

## Shared Production Composition

One production composition owns the actual:

- weight field and bilateral/unilateral editing behavior;
- reps field;
- complete action-menu trigger, ordering, styling, SetType/RPE actions, and destructive entry;
- completion control;
- smart-progression/previous-set behavior where already applicable;
- custom numeric-keyboard actions, including copy; and
- normal/Large Mode layout and hit-target sizing.

A standard/working row supplies its displayed set identity. A pyramid/drop-set row supplies displayed parent number plus its current type. This leading identity is the only hierarchy-specific row treatment. `SubSetRow` may adapt identity into the shared composition but may not own a second field/menu/completion tree.

Removed behavior: read-only pyramid/drop-set fields, tree connector/terminal-child state, and a sub-set-only delete menu.

## Deletion Route and Ownership

```text
actual shared-row menu delete ─┐
                               ├─> ActiveExerciseSection.requestDelete
actual trailing full swipe ────┘                 │
                                                  └─> app-internal request module
                                                        ├─ policy dispatch
                                                        │    ├─ return confirmation
                                                        │    └─ production execution
                                                        ├─ WorkoutSetManager.deleteSet
                                                        ├─ success: undo + announcement
                                                        │           + callback + return focus
                                                        └─ refusal: no success effect/focus
```

- Every production menu/full-swipe delete invokes `requestDelete(_:)` exactly once for its selected set.
- `requestDelete(_:)` invokes the real request module exactly once.
- The module owns policy dispatch, production manager execution, and every success-only effect.
- The view owns confirmation and focus presentation by applying the returned result once.
- The module accepts no focus/confirmation setter callback.
- No row, harness, or test deletes a model directly or reproduces package rules.

## Production Activation Evidence

The acceptance host renders `ActiveExerciseSection` with one adjacent standard/working row, pyramid row, and drop-set row. The host may install a counting decorator around the real request module and expose read-only counters, but it may not replace the module or add another action.

Acceptance requires:

1. opening the real pyramid menu and activating its actual destructive entry;
2. committing the actual drop-set trailing full swipe through a drag gesture;
3. exactly one section request and real-seam traversal for each action;
4. correct selected-row identity and one success callback; and
5. real deletion/undo state from the delegated production module.

Direct stored-closure invocation, hidden trigger buttons, separately configured test rows, and source-text assertions are prohibited evidence.

## Confirmation, Refusal, Undo, and Focus

- A parent with hidden child impact returns confirmation data with no mutation, undo, announcement, callback, or focus move.
- Confirmed execution re-enters the same production execution ownership; the view does not duplicate effects.
- A successful sub-set request removes only that set, records exactly one pending undo/announcement, calls the deletion callback once, and returns the existing surviving focus target.
- Undo restores values and relative order without parent/sibling loss.
- Package refusal of an only-row deletion leaves rows/order unchanged, leaves a fresh undo controller empty, calls the callback zero times, and returns no focus target.
- Repeated requests for an already removed row cannot create a second success effect.

## Accessibility, Localization, and Geometry

- The actual standard, pyramid, and drop-set delete-access controls have stable acceptance identifiers derived from row identity, not row position alone.
- Pyramid/drop-set destructive entries compose cataloged parent identity, current type, and delete intent at the production entry.
- No uncataloged interpolated key or helper-only production substitute is allowed.
- In one shared app coordinate space, each actual delete-access frame is at least 44 by 44 points.
- Standard/pyramid and pyramid/drop-set frame intersections are empty.
- Constants, whole-row sizes, context flags, separately hosted frames, and synthesized rectangles do not satisfy geometry acceptance.

## Compatibility

- Package-selected child isolation, parent cascade, minimum-one-row refusal, and order reflow remain authoritative and unchanged.
- Existing announcement differentiation, undo replacement/expiry/dead-parent behavior, and snackbar arbitration remain green.
- Standard-row smart progression, previous hints, bilateral editing, SetType/RPE menu behavior, completion, add-pyramid/add-drop generation, and custom keyboard behavior remain green.
- Copy on a sub-set uses the existing production keyboard route and updates/appends according to the current contract.
- All four production preview states contain adjacent standard/pyramid/drop-set rows for normal-light, normal-dark, Large-light, and Large-dark review.
