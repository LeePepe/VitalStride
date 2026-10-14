# Data Model: Active Workout Exercise Section Reorder Fix

## Existing entities

### Workout

- Owns the active training session and its existing collection of workout exercises.
- No property, relationship, schema, or migration change.

### WorkoutExercise

- Represents one movable exercise section.
- Existing identity is the drag/drop identity.
- Existing integer `order` is the sole persisted ordering field.
- No public or package API change.

### ExerciseSet

- Remains a child of one workout exercise.
- Never participates as a drag identity or reorder target in this feature.
- No property, relationship, schema, or UI change.

## Invariants

For a workout with `n` exercises after a completed move:

1. Every pre-move `WorkoutExercise` occurs exactly once after the move.
2. Sorted order values are exactly the integer range `0..<n`.
3. No two exercises share an order value.
4. Exercise sets remain attached to their original workout exercise.
5. A save followed by a fresh-context fetch reconstructs the same exercise identity order.

## State transitions

### Completed move

1. Resolve the source and destination against the current order-sorted workout exercises.
2. Move the outer workout-exercise identity.
3. Renumber the full resulting sequence contiguously from zero.
4. Publish the model mutations to the observed UI immediately.
5. Persist through the existing SwiftData training configuration.

### Invalid or cancelled move

- Missing source, invalid target, empty/single-item collection, or cancelled drag leaves identity and order values unchanged.

## Migration

None. This feature changes behavior around existing fields only.
