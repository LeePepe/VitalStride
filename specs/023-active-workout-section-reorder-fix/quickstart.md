# Quickstart: Active Workout Exercise Section Reorder Fix

Run commands from the VitalStride repository root.

## Automated acceptance

```bash
# True behavioral RED/GREEN: add the DEBUG harness and this test first, then
# capture a whole-section interaction failure before repairing ActiveWorkoutView.
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStrideUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideUITests/ActiveWorkoutSectionReorderUITests

# Production-seam ordering/persistence invariant (not the interaction RED).
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExerciseManagementTests

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

Required CI additionally runs the AppUI layer gate declared by `VitalStride/CONTEXT.md` on iPhone 17 Simulator.

## Interactive acceptance

1. Launch on iPhone 16 Simulator and create an active workout with three distinguishable exercises.
2. In normal mode, enter edit mode and confirm every whole exercise section exposes a move control.
3. Move the third section before the first and confirm immediate visible order.
4. Leave and reopen the workout; confirm the moved order persists.
5. Repeat move-control use in Large Mode.
6. Enable VoiceOver; confirm each control identifies its exercise and exposes system movement semantics.
7. Confirm set and sub-set rows did not gain independent move controls and their edit/delete behavior is unchanged.

## Scope audit

```bash
git diff --name-only "$DELIVERY_BASE_SHA"...HEAD
```

Implementation changes must be confined to:

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/VitalStrideApp.swift` (DEBUG-only harness)
- `VitalStrideTests/Sources/ExerciseManagementTests.swift`
- `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`

Planning-only changes are confined to `specs/023-active-workout-section-reorder-fix/**`.

`DELIVERY_BASE_SHA` is the reviewed planning revision persisted by Team Lead on parked MY-1567; the scope audit therefore excludes immutable planning artifacts and shows only implementation changes.

MY-1486 is cancelled and successor MY-1706 is already part of the declared current base. Before Fullstack dispatch or AppUI validation, Team Lead must confirm MY-1484's still-active shared Xcode/simulator lane is quiescent, then provision MY-1567's task-local delivery workspace and build artifacts. The implementation must preserve MY-1706's policy-driven snackbar/FAB, keyboard, accessibility-focus, and root-animation behavior in `ActiveWorkoutView.swift`.
