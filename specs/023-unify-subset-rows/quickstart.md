# Quickstart: Verify Unified Editable Sub-Set Rows

## Automated

From the repository root:

~~~bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SubSetRowParityTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
~~~

## Automated Expectations

- Pyramid and drop-set positive cases enter the request-level seam used by ActiveExerciseSection.requestDelete, covering SetDeletionPolicy dispatch, WorkoutSetManager execution, pending undo and exact restoration.
- Production-configured menu-delete and full-swipe callbacks each forward the selected set exactly once through requestDelete to that seam.
- An only-remaining-set request reaches WorkoutSetManager refusal, leaves the row intact, leaves a fresh undo controller's pending/announcement state nil, and keeps a deletion-callback spy at zero.
- One hosted standard row followed by pyramid and drop-set rows exposes three delete hit/accessibility frames at least 44 by 44 points; the standard/pyramid and pyramid/drop-set frame intersections are empty.

## Demonstration

1. Start an active workout and add a main working set.
2. Add one pyramid and one drop-set sub-set.
3. Verify all three rows share weight, reps, menu and completion alignment.
4. Edit weight and reps on both sub-sets.
5. Delete the pyramid through its menu; verify the parent and drop-set remain; tap Undo.
6. Delete the drop-set with a trailing full swipe; verify the parent and pyramid remain; tap Undo.
7. Delete the parent; verify the existing child-count confirmation still appears.
8. With VoiceOver enabled, focus each sub-set delete entry and confirm parent number, type and delete intent are spoken.

## Visual Matrix

Capture one screen containing a normal row, pyramid row and drop-set row in:

- normal mode / light;
- normal mode / dark;
- Large Mode / light;
- Large Mode / dark.

Use iPhone 16 Simulator. Attach comparisons to the PR and confirm the field, menu and completion columns align without clipping.
