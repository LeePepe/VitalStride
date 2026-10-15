# Quickstart: Active Workout Exercise Section Reorder Fix

Run commands from the VitalStride repository root.

## Automated acceptance

The successor repair reuses the published fixture and tests at PR #448 head `db43fab774b06ef887add8014b3c2470ff396c8d`. Do not edit either reorder test.

```bash
# Published production-seam ordering/persistence invariant.
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExerciseManagementTests

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# Successor focused gate: both existing reorder tests together on the current
# AppUI layer simulator, with a fresh result bundle.
xcodegen generate --quiet && xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideUITests/ActiveWorkoutSectionReorderUITests \
  -resultBundlePath ../successor-reorder/reorder-tests.xcresult
```

Required CI additionally runs the AppUI layer gate declared by `VitalStride/CONTEXT.md` on iPhone 17 Simulator.

## Interactive acceptance

1. Launch on iPhone 16 Simulator and create an active workout with three distinguishable exercises.
2. In normal mode, enter edit mode and confirm every localized exercise title and its existing set content remain visible beside a separate move control.
3. Move the third section before the first and confirm immediate visible order.
4. Leave and reopen the workout; confirm the moved order persists.
5. Repeat move-control use in Large Mode.
6. Enable VoiceOver; confirm each control identifies its exercise and exposes system movement semantics.
7. Confirm set and sub-set rows did not gain independent move controls and their edit/delete behavior is unchanged.

## Scope audit

```bash
git diff --name-only "$DELIVERY_BASE_SHA"...HEAD
```

The successor implementation change must be confined to:

- `VitalStride/Sources/ActiveWorkoutView.swift`

The published fixture and tests are fixed verification surfaces. Confirm the reorder-test blob remains `7738a0c270a884510fe88755aedef7605a0b53a1` with `git hash-object VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`.

Planning-only changes are confined to `specs/023-active-workout-section-reorder-fix/**`.

`DELIVERY_BASE_SHA` remains the approved implementation base recorded for the registered MY-1812 workspace. Run implementation verification only from that existing `delivery_work_dir`; preserve its uncommitted candidate and return missing or conflicting identity evidence to Team Lead without another checkout.

MY-1706 is part of the compatibility baseline. The successor plan does not authorize Fullstack work; after an exact planning PASS, Team Lead must separately authorize execution. Any later executor reuses the registered MY-1812 workspace and must preserve MY-1706's policy-driven snackbar/FAB, keyboard, accessibility-focus, and root-animation behavior in `ActiveWorkoutView.swift`.
