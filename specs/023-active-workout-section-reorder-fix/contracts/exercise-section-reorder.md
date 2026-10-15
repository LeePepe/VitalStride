# Contract: Exercise Section Reorder

## Scope

This internal AppUI contract connects the active-workout edit interaction to persisted `WorkoutExercise.order`. It is not a public API.

## Interaction contract

- Edit mode exposes one discoverable move control per outer exercise section when reordering is meaningful.
- The drag identity is the section's `WorkoutExercise`, never an individual set or sub-set.
- A completed cross-section drag routes through the single production reorder operation.
- The rendered order changes during the completed interaction, without leaving and reopening the screen.
- Normal and Large Mode expose the same operation.
- VoiceOver receives the existing localized exercise display text plus system move/adjustable control semantics.

## Edit-mode composition contract

- Every sorted `WorkoutExercise` retains one title/content-bearing section composition in edit mode; the existing localized title remains an independent `StaticText` element.
- Exactly one distinct move control coexists with that title/content composition. Its identifier remains `ActiveWorkoutExerciseMoveHandle_<nameEn>`, its label remains the localized exercise name, and its hit target remains at least 44×44 points.
- The title, full existing set/sub-set content, and control move as one exercise identity. The control label does not replace or merge away the title element.
- One separate terminal target remains discoverable after the last exercise as `ActiveWorkoutExerciseEndDropTarget`.
- A per-exercise sibling handle `Section` and a handles-only edit tree are forbidden composition shapes because the preserved runtime evidence proves each loses a required interface surface.

## Ordering contract

**Inputs**:

- Current exercises sorted by existing `order`.
- A valid move source and destination derived from workout-exercise identities.

**Postconditions**:

- The moved identity occupies the requested destination.
- Every original identity is present exactly once.
- All order values are rewritten to `0..<count` in resulting sequence order.
- A no-op or invalid move does not partially renumber the collection.

## Persistence contract

- Reorder uses existing SwiftData model objects and training storage.
- A saved move must be observable after a new `ModelContext` fetch.
- No schema, package, CloudKit policy, or public signature changes are permitted.
- Failure handling may not force-crash, silently discard an explicit save error, or log workout/health values.

## Published-baseline compatibility contract

- The implementation base contains MY-1706's `ActiveWorkoutSnackbarLayout.policy`-driven header and bottom safe-area composition plus `.activeWorkoutRootAnimation(policy:)` ownership.
- Reorder work in `ActiveWorkoutView.swift` must preserve that snackbar/FAB placement, keyboard-state behavior, accessibility focus routing, `@MainActor` policy isolation, and single root geometry-animation owner.
- Existing ExercisePicker and snackbar DEBUG harnesses in `VitalStrideApp.swift` continue to operate; the published reorder fixture is a separate opt-in launch-argument path and does not change their selectors or startup behavior. Its flag selects deterministic isolated storage and suppresses ordinary catalog seeding while preserving the existing ExercisePicker flag/container path.
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift` and `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift` remain unchanged; the full AppUI verification must retain their MY-1706 policy and mutation-sensitive coverage.
- No existing test may be deleted or weakened to accommodate the reorder repair.
- The two published `ActiveWorkoutSectionReorderUITests` are fixed compatibility clients. Their `StaticText` title queries, handle/end-target identifiers, labels, frame assertions, drag operations, and order assertions remain unchanged.

## DEBUG harness contract

- The published opt-in launch argument, available only in DEBUG, selects isolated test storage, seeds three distinguishable workout exercises, and presents the production `ActiveWorkoutView`.
- Without that launch argument, normal Debug behavior is unchanged; the test entry and fixture have no Release behavior.
- Stable UI-test selectors identify outer workout exercises and move targets without making any API public.
- The harness may support leaving and re-entering the hosted workout so persistence is observed through the production view reconstruction path.

## Behavioral XCUITest contract

- Preserve both published focused XCUITests byte-for-byte; do not recreate their already-accepted RED phase.
- The first test enters edit mode on the production screen, performs the whole-section drag from the third exercise before the first, and confirms immediate and reopened C/A/B plus Large Mode behavior.
- The second test moves the first exercise to the independently discoverable terminal target and confirms B/C/A.
- Both tests resolve titles through their existing `StaticText` queries and target outer exercise controls rather than an individual set/sub-set row.

## Ordering/persistence unit-test contract

- Seed three distinguishable workout exercises through existing test fixtures.
- Invoke the production reorder operation to move the third identity before the first.
- Assert exact identity order and contiguous values.
- Save, create a fresh context, refetch, and assert the same identity order and values.
- Do not duplicate collection movement or order assignment in the test.
- This invariant complements the behavioral XCUITest and is not required to fail against the pre-fix interaction.
