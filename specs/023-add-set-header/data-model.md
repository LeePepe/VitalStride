# Data Model — 023 Add Set Header

## Result

No data-model change.

The feature continues to use the existing `WorkoutExercise` to `ExerciseSet` relationship and the current add-set mutation. It introduces no entity, property, migration, persistence configuration, or serialization contract.

## Frozen Behavioral Projection

Automated coverage must observe, without changing model policy:

- one activation inserts exactly one main set;
- defaults come from the last main set rather than a trailing sub-set;
- the new set order is continuous with the existing collection;
- the relationship back to the same workout exercise is preserved.

Concrete initializers and parameter labels remain implementation-owned and are intentionally not specified here.
