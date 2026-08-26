# Quickstart: implementation and verification

All commands run from the repository root.

## Stage 1 — VitalModels

Implement only T001's declared files, then run:

```bash
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels
```

Do not run `xcodebuild` for this package-only stage.

## Stage 2 — AppUI integration contracts

After T001 is available, implement only T002's declared test files, then run:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisesJSONTests \
  -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests \
  -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests
```

Expected assembled distribution: 12 nonempty sections, Bodyweight 376, Weighted 36, Other 96, total 1,558.

## Scope guard

The implementation must not modify catalog resources, importer/provenance, Seeder, picker production views, TelemetryKit, XcodeGen configuration, or generated project files.
