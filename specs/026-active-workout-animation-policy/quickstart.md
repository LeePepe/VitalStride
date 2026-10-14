# Quickstart: Verify Active Workout Concurrency-Safe Animation Policy

Run commands from the exact successor delivery repository root. Do not use the MY-1486 workspace, branch, candidate, or Draft PR #420.

## 1. Confirm implementation scope and concurrency guard

```bash
git diff --name-only "$DELIVERY_BASE_SHA"...HEAD
git diff --check "$DELIVERY_BASE_SHA"...HEAD
git diff "$DELIVERY_BASE_SHA"...HEAD -- VitalStride/Sources/ActiveWorkoutView.swift VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift
```

Expected: exactly the three authorized AppUI paths, no removed/weakened existing test, and no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` addition.

## 2. Focused successor verification

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests
```

Expected: the six-state production policy, both transition directions, all three ownership mutations, and unchanged safe-area geometry tests pass.

## 3. Downstream MY-1487 full AppUI gate

Only after MY-1706 completes normal delivery, MY-1487 runs:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

Expected: the full VitalStride scheme test suite passes with zero failures.

## 4. Build the exact delivered successor revision

```bash
set -euo pipefail
MY1706_REVISION="$(git rev-parse HEAD)"
MY1706_DERIVED_DATA="./DerivedData/MY-1706-$MY1706_REVISION"
MY1706_APP_PATH="$MY1706_DERIVED_DATA/Build/Products/Debug-iphonesimulator/VitalStride.app"
MY1706_BUNDLE_ID="com.leepepe.vitalstride"
xcodebuild clean build -project VitalStride.xcodeproj -scheme VitalStride -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$MY1706_DERIVED_DATA" -skipPackagePluginValidation
test -d "$MY1706_APP_PATH"
test "$(plutil -extract CFBundleIdentifier raw -- "$MY1706_APP_PATH/Info.plist")" = "$MY1706_BUNDLE_ID"
```

## 5. Create one dedicated capture simulator

```bash
MY1706_RUNTIME_ID="$(xcrun simctl list runtimes available --json | jq -er '[.runtimes[] | select(.platform == "iOS" and .isAvailable == true)] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier')"
MY1706_DEVICE_TYPE_ID="$(xcrun simctl list devicetypes --json | jq -er '.devicetypes[] | select(.name == "iPhone 16") | .identifier')"
MY1706_UDID="$(xcrun simctl create "MY-1706-$MY1706_REVISION" "$MY1706_DEVICE_TYPE_ID" "$MY1706_RUNTIME_ID")"
xcrun simctl bootstatus "$MY1706_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$MY1706_UDID"
xcrun simctl install "$MY1706_UDID" "$MY1706_APP_PATH"
xcrun simctl launch --terminate-running-process "$MY1706_UDID" "$MY1706_BUNDLE_ID"
xcrun simctl list devices --json | jq -er --arg udid "$MY1706_UDID" '.devices[][] | select(.udid == $udid and .state == "Booted") | .name'
```

Expected: the final command prints `MY-1706-$MY1706_REVISION`. Use this explicit UDID for every capture.

## 6. Capture complete transitions

Light/rest:

```bash
xcrun simctl ui "$MY1706_UDID" appearance light
xcrun simctl io "$MY1706_UDID" recordVideo --codec=h264 --display=internal --force "./my-1706-$MY1706_REVISION-light.mp4"
```

Dark/undo:

```bash
xcrun simctl ui "$MY1706_UDID" appearance dark
xcrun simctl io "$MY1706_UDID" recordVideo --codec=h264 --display=internal --force "./my-1706-$MY1706_REVISION-dark.mp4"
```

Each recording begins before field focus, shows keyboard presentation and its settled state, then shows dismissal and its settled state. It must show exactly one snackbar, no paired header/list jump, no FAB/snackbar intersection while hidden, no focused-row/snackbar/keyboard overlap while visible, and final-row clearance.

Return to light appearance with the keyboard hidden and no snackbar, then capture:

```bash
xcrun simctl ui "$MY1706_UDID" appearance light
xcrun simctl io "$MY1706_UDID" screenshot --type=png --display=internal "./my-1706-$MY1706_REVISION-no-snackbar-light.png"
```

Attach both MP4 files, the PNG, exact revision, and explicit UDID to MY-1476. Remove runtime-local evidence copies after attachment. MY-1486 and Draft PR #420 are not valid verification inputs.
