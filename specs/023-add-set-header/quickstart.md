# Quickstart — 023 Add Set Header

## Working Directory

Use only the Multica-provided isolated checkout. Run every command from the VitalStride repository root unless the command says otherwise.

## Execution Order

1. Add the targeted AppUI regression test in `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`.
2. Run that targeted test against the unchanged production source and retain the expected red result proving the action is still a `Section` content row.
3. Implement the header placement in `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`, preserving the add-set mutation and existing exercise menu.
4. Rerun the targeted suite, then run the MY-1474 iPhone 16 command and the formal AppUI iPhone 17 gate.
5. Collect the before/after light/dark, accessibility Dynamic Type, VoiceOver edit-mode, and hit-target evidence defined in `plan.md`.
6. Confirm the implementation diff contains only the authorized production and test files.

## Regression-First Targeted Gate

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ActiveExerciseSectionAddSetHeaderTests
```

## Complete App-Target Gates

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

## Scope Check

Implementation files authorized by this feature:

- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`

Do not edit `Packages/**`, `ActiveWorkoutView`, set/sub-set models, `project.yml`, generated Xcode project files, or localization resources.
