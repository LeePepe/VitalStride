# Data Model: Reliable Editable Sub-Set Rows

No persisted entity, field, relationship, enum case, migration, or CloudKit rule changes.

## Existing Persisted Entities

- **ExerciseSet**: Existing order, weight, optional right-side weight, reps, completion, RPE, and `SetType` data.
- **WorkoutExercise**: Existing ordered set collection and parent exercise relationship.
- **Deleted-set snapshot**: Existing undo data preserving deleted values and relative placement.

## Existing Package Invariants

1. The existing `SetType.isSubSet` distinction identifies pyramid/drop-set children; there is no `SetType.standard` case.
2. A standard/main set owns the consecutive sub-set run until the next non-sub-set.
3. Deleting a selected sub-set removes only that record.
4. Deleting a main set removes its consecutive children only after the AppUI confirmation contract is satisfied.
5. Deletion refuses a result with zero remaining sets.
6. Successful deletion reflows survivor order.
7. Undo restores snapshots without changing `SetType` meaning.

## New Transient AppUI Values

### Row identity/configuration

Immutable, app-internal presentation data that distinguishes a standard/working row from a pyramid/drop-set row. It carries displayed main/parent number, existing set type, stable acceptance identity, and capabilities consumed by the one shared production composition. Main rows enable existing history/add-child behavior and SetType choices; child rows disable history/add-child behavior and non-child SetType choices while retaining pyramid/drop-set subtype, RPE, unilateral and copy behavior. It is not persisted and owns no controls.

### Delete request result

A return-only app-internal result with three observable outcomes:

- confirmation required, including existing hidden-child impact data;
- successful deletion, including an optional surviving focus target; or
- refusal/no change, with no focus or success effect.

The result never contains presentation setter callbacks.

### Route observation

DEBUG-only, in-memory acceptance evidence recording section request count, wrapped real-seam traversal count, success callback count, and selected-row identity. It observes/delegates only; it cannot choose policy, mutate models, create undo, or invoke deletion.

## State Transitions

```text
actual menu/full swipe
  -> section request
  -> request module policy
      -> confirmation required (no mutation/effects)
      -> immediate/confirmed execution
          -> package refusal (unchanged; no effects/focus)
          -> package success (undo + announcement + callback; return focus)
```

The production-reachable refusal fixture has one main row and its sole child. The main menu is visible because two rows exist; confirmation accepts the existing cascade; the package manager then refuses the zero-row result.

## Explicit Non-Changes

- No `ExerciseSet`, `WorkoutExercise`, `SetType`, CloudKit, HealthKit, or schema change.
- No package deletion or tree-query algorithm change.
- No persisted test instrumentation.
- No public interface.
