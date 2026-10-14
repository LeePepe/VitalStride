# Quickstart: Verify Reliable Editable Sub-Set Rows

All commands run from the repository root.

## 1. Focused Production Contract

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SharedEditableSetRowTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests \
  -only-testing:VitalStrideUITests/SubSetProductionRouteUITests
```

Expected evidence:

- The actual pyramid production menu entry produces one section request, one real-seam traversal, the intended row identity, one callback, and real undo state.
- A committed drag on the actual drop-set trailing full swipe produces the same exactly-once route; the test does not tap a revealed action.
- The only-row refusal reaches the package manager and produces no success effect or focus.
- Adjacent actual standard/pyramid/drop-set delete-access frames are each at least 44 by 44 points and neighboring intersections are empty.
- The three production rows expose and exercise the same actual weight, reps, menu, and completion composition; sub-set copy uses the real custom-keyboard route.
- Production destructive labels include catalog-backed displayed parent, current type, and delete intent.

## 2. Full AppUI and Catalog Gates

```bash
bash scripts/ci/run-app-target-tests.sh
python3 scripts/i18n_check_lproj_parity.py
```

The AppUI script is the canonical iPhone 17 gate and includes both unit and UI-test targets. Do not weaken its existing quarantine or add a successor-specific skip.

## 3. Scope and Immutable Planning

```bash
test -n "${DELIVERY_BASE_SHA:?export the exact reviewed planning SHA from registered issue metadata}"
git diff --name-only "${DELIVERY_BASE_SHA}...HEAD"
git diff --exit-code "${DELIVERY_BASE_SHA}" -- specs/026-reliable-editable-subset-rows
```

The first output must contain only the reviewed implementation allowlist. The second command must be empty/successful; implementation does not edit reviewed planning.

## 4. Simulator Review

Use the production `ActiveExerciseSection` host on iPhone 17 Simulator and capture:

- normal / light;
- normal / dark;
- Large Mode / light; and
- Large Mode / dark.

Every capture contains an adjacent standard/working row, pyramid row, and drop-set row. Confirm aligned unclipped weight/reps/menu/completion columns and no read-only tree-line presentation.

## 5. Manual Behavior Record

Record with the implementation candidate:

1. Pyramid actual menu delete removes only the pyramid row; Undo restores exact values/order.
2. Drop-set actual committed full swipe removes only the drop-set row; Undo restores it.
3. Parent delete returns the existing child-count confirmation before mutation.
4. Only-row deletion refuses with no undo, success announcement, callback, or focus move.
5. Sub-set weight/reps editing, completion, full menu, and custom-keyboard copy use the shared production controls.
6. VoiceOver destructive identities state displayed parent number, current pyramid/drop-set type, and delete intent.
