# Quickstart: Verify Active Workout Safe-Area Stability

Run all commands from the repository root in the same shell so the task-specific variables remain bound through build, install, launch, and capture.

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
set -euo pipefail
MY1476_REVISION="$(git rev-parse HEAD)"
MY1476_DERIVED_DATA="./DerivedData/MY-1476-$MY1476_REVISION"
MY1476_APP_PATH="$MY1476_DERIVED_DATA/Build/Products/Debug-iphonesimulator/VitalStride.app"
MY1476_BUNDLE_ID="com.leepepe.vitalstride"
xcodebuild clean build -project VitalStride.xcodeproj -scheme VitalStride -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$MY1476_DERIVED_DATA" -skipPackagePluginValidation
test -d "$MY1476_APP_PATH"
test "$(plutil -extract CFBundleIdentifier raw -- "$MY1476_APP_PATH/Info.plist")" = "$MY1476_BUNDLE_ID"
```

## 4. Create and launch the exact capture simulator

Resolve the latest available iOS runtime and the repository-required iPhone 16 device type, then create one dedicated simulator. Preserve the returned UDID for every remaining command:

```bash
MY1476_RUNTIME_ID="$(xcrun simctl list runtimes available --json | jq -er '[.runtimes[] | select(.platform == "iOS" and .isAvailable == true)] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')"
MY1476_DEVICE_TYPE_ID="$(xcrun simctl list devicetypes --json | jq -er '.devicetypes[] | select(.name == "iPhone 16") | .identifier')"
MY1476_UDID="$(xcrun simctl create "MY-1476-$MY1476_REVISION" "$MY1476_DEVICE_TYPE_ID" "$MY1476_RUNTIME_ID")"
xcrun simctl bootstatus "$MY1476_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$MY1476_UDID"
xcrun simctl install "$MY1476_UDID" "$MY1476_APP_PATH"
xcrun simctl launch --terminate-running-process "$MY1476_UDID" "$MY1476_BUNDLE_ID"
xcrun simctl list devices --json | jq -er --arg udid "$MY1476_UDID" '.devices[][] | select(.udid == $udid and .state == "Booted") | .name'
```

The final command must print `MY-1476-$MY1476_REVISION`. Confirm the Simulator window shows that dedicated device before interacting. The launched foreground app is now the exact build from `$MY1476_REVISION`; prepare a workout with multiple exercises and enough sets to require scrolling.

## 5. Record the transition evidence

For the light recording:

```bash
xcrun simctl ui "$MY1476_UDID" appearance light
xcrun simctl io "$MY1476_UDID" recordVideo --codec=h264 --display=internal --force "./my-1476-$MY1476_REVISION-light.mp4"
```

While the foreground recording command is running, use the Simulator UI to:

1. Start with the final set visible and a rest snackbar active.
2. Focus the final set's weight or reps field and let the keyboard finish appearing.
3. Keep the settled keyboard-visible state on screen briefly.
4. Dismiss the keyboard and let the hide animation finish.
5. Keep the settled keyboard-hidden state on screen briefly, then stop the recording with Control-C.

For the dark recording, repeat the complete sequence with an undo snackbar active:

```bash
xcrun simctl ui "$MY1476_UDID" appearance dark
xcrun simctl io "$MY1476_UDID" recordVideo --codec=h264 --display=internal --force "./my-1476-$MY1476_REVISION-dark.mp4"
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
xcrun simctl ui "$MY1476_UDID" appearance light
xcrun simctl io "$MY1476_UDID" screenshot --type=png --display=internal "./my-1476-$MY1476_REVISION-no-snackbar-light.png"
```

The screenshot must show the FAB inside the bottom safe area and the complete final set row above it.

Attach both revision-named MP4 files and the PNG file to MY-1476, and record `$MY1476_REVISION` plus `$MY1476_UDID` in the result comment. Then remove the local evidence copies. Do not report runtime-local file paths as delivered evidence.
