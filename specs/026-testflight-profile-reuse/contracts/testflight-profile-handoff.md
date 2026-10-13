# Contract: TestFlight profile handoff

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
