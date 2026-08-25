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

## 3. Build before visual capture

```bash
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation
```

## 4. Record the transition evidence

Boot an iPhone 16 Simulator and make it the active Simulator device. Prepare a workout with multiple exercises and enough sets to require scrolling.

For the light recording:

```bash
xcrun simctl ui booted appearance light
xcrun simctl io booted recordVideo --codec=h264 --force ./my-1476-light.mp4
```

While the foreground recording command is running, use the Simulator UI to:

1. Start with the final set visible and a rest snackbar active.
2. Focus the final set's weight or reps field and let the keyboard finish appearing.
3. Keep the settled keyboard-visible state on screen briefly.
4. Dismiss the keyboard and let the hide animation finish.
5. Keep the settled keyboard-hidden state on screen briefly, then stop the recording with Control-C.

For the dark recording, repeat the complete sequence with an undo snackbar active:

```bash
xcrun simctl ui booted appearance dark
xcrun simctl io booted recordVideo --codec=h264 --force ./my-1476-dark.mp4
```

Each recording must show continuously:

- no paired header/list jump;
- exactly one active snackbar;
- no FAB/snackbar intersection while the keyboard is hidden;
- no focused-row/snackbar/keyboard overlap while the keyboard is visible;
- final-row scroll clearance;
- the complete show and hide animations, not only their settled endpoints;
- correct light/dark margins.

After both recordings, return to a settled light appearance with the keyboard hidden, no rest snackbar, and no pending undo. Scroll the final set above the FAB, then capture the no-snackbar spacing evidence:

```bash
xcrun simctl ui booted appearance light
xcrun simctl io booted screenshot --type=png ./my-1476-no-snackbar-light.png
```

The screenshot must show the FAB inside the bottom safe area and the complete final set row above it.

Attach both MP4 files and the PNG file to MY-1476, then remove the local copies. Do not report runtime-local file paths as delivered evidence.
