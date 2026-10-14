# Quickstart: Verify Reliable Editable Sub-Set Rows

All commands run from the repository root.

## 1. Focused Production Contract

```bash
xcodegen generate
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
- A one-parent/one-child fixture exposes the parent's actual menu-delete; after cascade confirmation, the real manager refuses the zero-row result with no success effect or focus.
- Adjacent actual standard/pyramid/drop-set action-menu-trigger frames are each at least 44 by 44 points and neighboring intersections are empty.
- The three production rows expose and exercise the same actual weight, reps, menu, and completion composition; child subtype/RPE/unilateral/copy effects are real, the child picker contains only pyramid/drop-set, and add-child actions remain main-only.
- Production destructive label/value pairs compose translated delete/set-number/type fragments and communicate the required identity in English and Simplified Chinese.
- Rendering/interacting with sub-set rows performs no history lookup or smart-progression tree walk.

## 2. Full AppUI and Catalog Gates

```bash
bash scripts/ci/run-app-target-tests.sh
python3 scripts/i18n_check_lproj_parity.py
git restore --source=HEAD -- VitalStride.xcodeproj
git diff --exit-code -- project.yml VitalStride.xcodeproj
```

The AppUI script is the canonical iPhone 17 gate and includes both unit and UI-test targets. `xcodegen generate` is required before the focused command because the project uses explicit file/build-phase entries; its generated project diff is ephemeral verification output and must be discarded before candidate freeze. Do not stage/commit it, weaken the existing quarantine, or add a successor-specific skip.

## 3. Scope and Immutable Planning

```bash
test -n "${DELIVERY_BASE_SHA:?export the exact reviewed planning SHA from registered issue metadata}"
git diff --name-only "${DELIVERY_BASE_SHA}"
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
4. In the one-parent/one-child fixture, confirmed parent cascade deletion reaches manager refusal with no undo, success announcement, callback, focus move, or row/order change.
5. Sub-set weight/reps editing, completion, full menu, subtype/RPE changes, unilateral editing and custom-keyboard copy use the shared production controls; the child SetType picker contains only pyramid/drop-set and add-child actions remain main-only.
6. VoiceOver destructive label/value pairs state displayed parent number, current pyramid/drop-set type, and delete intent in English and Simplified Chinese.
7. The measured geometry belongs to each actual action-menu trigger identified by stable row identity, not a swipe item or row proxy.
