# Contract: TestFlight profile handoff

## Exact Base and Generated-Project Prerequisite

- Product/source base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Implementation checkout base: the exact reviewed planning revision published for this repaired package; outside `specs/026-testflight-profile-reuse/**`, its tree is byte-identical to the product/source base.
- No synchronized exact base exists on or after the product/source base. `84a153962b50f10cd2f49717c4443fb6e953d4ce` is a divergent historical evidence tree, and `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` is an unreviewed candidate; neither is an authorized base.
- T000 runs before the profile-setting change and may write only `VitalStride.xcodeproj/project.pbxproj`. It changes no `project.yml`, source, test, context, package, workflow, or release file.
- The T000 generated delta is 101 additions/5 deletions in `project.pbxproj`. Combined with T001's two Release-setting substitutions, the assembled generated-project delta from the checkout base is 103 additions/7 deletions.

### Authorized generated membership manifest

`VitalStride` gains generated source membership for these existing files:

- `VitalStride/Sources/AI/AIRouterFactory.swift`
- `VitalStride/Sources/AI/RoutingSignalStore.swift`
- `VitalStride/Sources/AI/RoutingSignalStoreEnvironment.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStride/Sources/ActiveWorkout/RestCompletedPresenter.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionFocusTarget.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionUndoController.swift`
- `VitalStride/Sources/ExercisePickerSectionGrouping.swift`
- `VitalStride/Sources/RouterBackedProvider.swift`

`VitalStrideMac` gains generated source membership for the already-declared shared paths `AIRouterFactory.swift`, `RouterBackedProvider.swift`, `RoutingSignalStore.swift`, and `RoutingSignalStoreEnvironment.swift` above.

`VitalStrideTests` gains generated source membership for these existing tests:

- `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift`
- `VitalStrideTests/Sources/ExercisePickerSearchLayoutTests.swift`
- `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift`
- `VitalStrideTests/Sources/RestCompletedPresenterTests.swift`
- `VitalStrideTests/Sources/RouterBackedProviderTests.swift`
- `VitalStrideTests/Sources/SetDeletionUndoLocalizationTests.swift`
- `VitalStrideTests/Sources/SubSetDeletionUndoTests.swift`

`VitalStrideUITests` gains generated source membership for `VitalStrideUITests/Sources/SnackbarAccessibilityUITests.swift`. The `VitalStride` resource phase gains the already-selected `VitalStride/CONTEXT.md` resource. `VitalStrideWatchTests` may receive only XcodeGen's structural group-order normalization; no watch test membership is added or removed.

The only removed membership is the stale `VitalStride` app-target reference to deleted `VitalStride/Sources/WorkoutSetManager.swift`. `Packages/VitalModels/Sources/VitalModels/Repo/WorkoutSetManager.swift` and its tests remain untouched.

No other membership, resource, target, build phase, setting, or file content change is authorized by T000. A second generation over the assembled T000+T001 output must leave `project.pbxproj` unchanged.

## Target Map

| Release target | Bundle identifier | Canonical fetched-name source | Archive interface key |
|---|---|---|---|
| `VitalStride` | `com.leepepe.vitalstride` | `sigh_com.leepepe.vitalstride_appstore_profile-name` | `VITALSTRIDE_APP_PROFILE_SPECIFIER` |
| `VitalStrideWidgets` | `com.leepepe.vitalstride.widgets` | `sigh_com.leepepe.vitalstride.widgets_appstore_profile-name` | `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` |

## Fetch Contract

- Both bundle identifiers retain separate App Store profile fetches.
- Both fetches retain team selection, `force: true`, and installation enabled.
- The canonical fetched-name sources are read only after both fetches complete.
- Action return values are not alternate profile-name sources.

## Validation Contract

- Each canonical source must be present and non-empty.
- The two resolved values must remain target-distinct.
- A validation failure is terminal before `build_app`, upload, distribution, or release-tag mutation.
- Failure evidence names the affected target/interface key but excludes ASC values, key material, certificates, keychain data, and profile contents.

## Archive Contract

- The app Release `PROVISIONING_PROFILE_SPECIFIER` consumes only `VITALSTRIDE_APP_PROFILE_SPECIFIER`.
- The widget Release `PROVISIONING_PROFILE_SPECIFIER` consumes only `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`.
- The release lane transports both opaque names through shell-safe target-specific build arguments.
- A global `PROVISIONING_PROFILE_SPECIFIER` archive override is forbidden.
- Base/Debug Automatic signing and Release Manual/Apple Distribution signing remain unchanged.
- Explicit signing-disabled Release builds do not require either interface value.

## Export Contract

- The app bundle mapping uses the same resolved variable transported through `VITALSTRIDE_APP_PROFILE_SPECIFIER`.
- The widget bundle mapping uses the same resolved variable transported through `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`.
- Export may not re-read, reconstruct, or fall back to a different profile-name source.

## PR Regression Contract

The credential-free regression proves from repository source that:

1. both target-specific forced installed fetches remain;
2. both canonical fetched-name sources are required and fail closed;
3. fixed profile display names are absent from Release target configuration;
4. the two interface keys are distinct and mapped to the correct targets;
5. archive transport is shell-safe and target-specific;
6. export reuses the exact resolved app/widget variables;
7. the action-return fallback and global profile override are absent;
8. base Automatic and Release Manual signing remain;
9. the existing manual/force/freshness/main/concurrency assertions remain active.

The test performs no environment-secret read, ASC request, profile installation, signing, upload, workflow dispatch, or external mutation.

## Delivery Contract

- Candidate PR: non-Draft, `owner-review` label, required checks, and description of the manual new-runner procedure.
- Before explicit Owner consent: static/syntax/RepoInfra/XcodeGen/unsigned evidence only.
- After reviewed merge plus explicit Owner consent: one manual TestFlight run on `main` may establish production proof.
- Production proof: consent record, GitHub Actions run URL, successful terminal run, and processed TestFlight build identifier. Secret values and signing artifacts are excluded.

## Compatibility Contract

- Preserve manual-only workflow dispatch, force default and branch, `main` checkout, concurrency, build-number computation, telemetry build inputs, upload, internal-group distribution, and release-tag behavior.
- Preserve all existing TestFlight freshness assertions; no deletion or weakening is allowed.
- Preserve all source/test contents named in the generated membership manifest and the package-owned `WorkoutSetManager` implementation. The prerequisite reconciles generated membership only.
