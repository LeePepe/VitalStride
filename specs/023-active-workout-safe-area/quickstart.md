# Quickstart: Verify Active Workout Safe-Area Stability

Run all commands from the repository root.

## 1. Focused automated regression

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests
```

Expected: the keyboard-visible/hidden × none/rest/undo matrix and host geometry assertions pass.

## 2. Full AppUI layer gate

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

Expected: the full `VitalStride` scheme test suite passes with zero failures.

## 3. Build the visual-evidence target

```bash
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation
```

## 4. Capture the interaction evidence

On a booted iPhone 16 Simulator:

1. Start or resume a workout with multiple exercises and enough sets to require scrolling.
2. Scroll to the final set and confirm its controls can be placed above the hidden-keyboard FAB/snackbar region.
3. Make a rest snackbar visible, focus the final set's weight or reps input, then dismiss the keyboard.
4. Repeat the show/hide path with an undo snackbar and once with no snackbar.
5. Repeat the active-snackbar show/hide path in light and dark appearance.
6. Capture consecutive screenshots of the settled state before show, after show, and after hide.

Evidence must show:

- no paired header/list jump;
- exactly one active snackbar;
- no FAB/snackbar intersection while the keyboard is hidden;
- no focused-row/snackbar/keyboard overlap while the keyboard is visible;
- final-row scroll clearance;
- correct light/dark margins.

Attach the files to MY-1476. Do not report runtime-local file paths as delivered evidence.
