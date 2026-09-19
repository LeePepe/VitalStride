# Data Model: Unified Editable Sub-Set Rows

No new entity, field, relationship, migration or persistence rule is introduced.

## Existing entities

- ExerciseSet supplies order, weight, optional right-side weight, reps, completion, RPE and SetType.
- WorkoutExercise owns the ordered set collection.
- DeletedSetSnapshot captures deleted set values and relative placement for undo.

## Existing invariants

1. SetType.isSubSet determines whether a row is a pyramid/drop-set child.
2. A main set owns the consecutive sub-set run that follows it until the next non-sub-set.
3. Deleting a sub-set removes only that row.
4. Deleting a main set removes its consecutive child run after confirmation.
5. Deletion cannot leave zero rows.
6. Survivors are re-numbered by WorkoutSetManager.
7. Undo restores snapshots without changing SetType meaning.

## Presentation-only data

The new app-internal row identity/configuration is transient and not persisted. It contains only the displayed parent/main number and existing SetType-derived identity required to render and localize the shared row.

## Explicit non-changes

- No SetType case or meaning change.
- No ExerciseSet schema change.
- No WorkoutSetManager algorithm change.
- No CloudKit or HealthKit impact.
