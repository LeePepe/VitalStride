# Contract: TestFlight profile handoff

## Exact Base and Ordered Generated Evidence

- Product/source base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Implementation checkout base: the exact reviewed planning revision published for this repaired package; outside `specs/026-testflight-profile-reuse/**`, its tree is byte-identical to the product/source base.
- No synchronized exact base exists on or after the product/source base. `84a153962b50f10cd2f49717c4443fb6e953d4ce` is a divergent historical evidence tree, and `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` is an unreviewed candidate; neither is an authorized base.
- T001 is the sole AppUI task and owns only the schedulable truth source `project.yml`. `VitalStride.xcodeproj/project.pbxproj` is its required generated evidence/output under Constitution IV, remains an unschedulable exclusion, and may never be hand-edited or assigned separate layer ownership.
- T001 first records the installed XcodeGen version and captures the semantic baseline below before evaluating its `project.yml` setting edit. It then changes only the two target-specific Release profile specifiers and regenerates the project.
- The semantic membership/resource/removal manifest below is authoritative. Numstat and PBXProject target-reference order are diagnostic only: the baseline may be 100 additions/4 deletions when `VitalStrideWatchTests` remains before `VitalStrideWidgets`, or 101/5 when those two unchanged target references are reordered. T001's two Release-setting substitutions contribute exactly 2/2, so the assembled output may be 102/6 or 103/7.

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

`VitalStrideUITests` gains generated source membership for `VitalStrideUITests/Sources/SnackbarAccessibilityUITests.swift`. The `VitalStride` resource phase gains the already-selected `VitalStride/CONTEXT.md` resource. The only permitted structural variation is whether the unchanged `VitalStrideWatchTests` target reference appears before or after `VitalStrideWidgets`; no watch/widget target or test membership is added, removed, or changed by that ordering.

The only removed membership is the stale `VitalStride` app-target reference to deleted `VitalStride/Sources/WorkoutSetManager.swift`. `Packages/VitalModels/Sources/VitalModels/Repo/WorkoutSetManager.swift` and its tests remain untouched.

No other membership, resource, target, build phase, setting, or file content change is authorized by T001's baseline component. A second generation over the assembled output using the recorded same XcodeGen executable must produce the same `project.pbxproj` blob; no cross-version blob/order identity is required.

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

- Prepublication: freeze the uncommitted local candidate tree, semantic manifest evidence, and credential-free results. Commit, push, and PR creation/update are forbidden until exact AI Reviewer content `PASS` and explicit publication permission are recorded for that tree. Any content change invalidates permission and returns to freeze/review.
- Post-permission: commit and push only the unchanged reviewed tree; create or update a non-Draft `owner-review` PR; include the manual new-runner procedure; prove reviewed tree = commit tree and local SHA = remote branch OID = PR `headRefOid`; then hand the published mapping to PR Manager for required-check supervision and merge.
- Before explicit Owner consent: static/syntax/RepoInfra/XcodeGen/unsigned evidence only; no TestFlight dispatch or upload.
- After reviewed merge plus explicit Owner consent: one manual TestFlight run on `main` may establish production proof.
- Production proof: consent record, GitHub Actions run URL, successful terminal run, and processed TestFlight build identifier. Secret values and signing artifacts are excluded.

## Compatibility Contract

- Preserve manual-only workflow dispatch, force default and branch, `main` checkout, concurrency, build-number computation, telemetry build inputs, upload, internal-group distribution, and release-tag behavior.
- Preserve all existing TestFlight freshness assertions; no deletion or weakening is allowed.
- Preserve all source/test contents named in the generated membership manifest and the package-owned `WorkoutSetManager` implementation. T001's baseline component reconciles generated membership only.
