# Contract: TestFlight profile handoff

## AppUI Truth-Source Reconciliation

- The immutable replacement source/ancestry base is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; it is distinct from the later trusted event-base revision used by T004.
- T001 owns one AppUI `project.yml` commit with three authorized truth-source edits: first add `CONTEXT.md` to the `VitalStride` source-entry exclusions as baseline reconciliation, then replace the app and widget fixed Release profile specifiers with their target-specific interface keys.
- The baseline component excludes the unchanged support document `VitalStride/CONTEXT.md` from `VitalStride` target file/resource membership. It does not edit that document, any app/package source or test, or any RepoInfra path.
- `VitalStride.xcodeproj/project.pbxproj` is generated synchronization evidence under Constitution Principle IV. It is regenerated from `project.yml`, contains no `VitalStride/CONTEXT.md` file or resource-build reference, and is never hand-edited or assigned independent layer ownership.
- Regeneration with the same recorded XcodeGen executable is idempotent. The repaired candidate's observed `99/7` generated-project numstat against the approved base is diagnostic only; the normative contract is the resource exclusion plus the two target-correct profile-setting substitutions and absence of unrelated generated drift.

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

- Each canonical source must be present/non-nil, and its validation-only whitespace-stripped view must be non-empty.
- Validation must retain the original raw value: it may inspect a stripped view for blankness but may not replace, trim, or normalize any nonblank name.
- The two preserved raw values must remain target-distinct.
- A validation failure is terminal before `build_app`, upload, distribution, or release-tag mutation.
- Failure evidence names the affected target/interface key but excludes ASC values, key material, certificates, keychain data, and profile contents.

## Archive Contract

- The app Release `PROVISIONING_PROFILE_SPECIFIER` consumes only `VITALSTRIDE_APP_PROFILE_SPECIFIER`.
- The widget Release `PROVISIONING_PROFILE_SPECIFIER` consumes only `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`.
- The release lane transports both original opaque names verbatim through shell-safe target-specific build arguments, including leading, trailing, or embedded whitespace and shell-significant characters.
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
2. both canonical fetched-name sources are required; absent/nil and whitespace-only outputs fail closed before `build_app`;
3. fixed profile display names are absent from Release target configuration;
4. the two interface keys are distinct and mapped to the correct targets;
5. archive transport is shell-safe and target-specific, and nonblank whitespace-containing raw values are preserved verbatim rather than replaced by their validation views;
6. export reuses the exact resolved app/widget variables;
7. the action-return fallback and global profile override are absent;
8. base Automatic and Release Manual signing remain;
9. the existing manual/force/freshness/main/concurrency assertions remain active.

The test performs no environment-secret read, ASC request, profile installation, signing, upload, workflow dispatch, or external mutation.

After the candidate regression is authored, historical red proof uses an isolated temporary overlay rather than reverting T001 or mutating the working tree. Export `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `project.yml` from the immutable source base, copy only the candidate `scripts/tests/test_testflight_freshness.py` into that overlay, and run the candidate full module there. The markers `HISTORICAL_FIXED_PROFILE_NAMES_REJECTED` and `HISTORICAL_ACTION_RETURN_FALLBACK_REJECTED` are reserved exclusively for the two intended historical assertions. The fail-closed guard accepts the run only when unittest returns status 1, reports exactly two `FAIL:` records, includes both reserved markers, and ends with exactly `FAILED (failures=2)`. Any additional failure, error, skip, expected failure, unexpected success, setup/import failure, or fixture failure changes that exact result shape and is not red evidence. Final-green full-module and complete RepoInfra commands run separately in the repaired working tree. The validated temporary overlay is the only disposable path.

## Delivery Contract

- Recovery is forward-only from immutable replacement source/ancestry base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` in the preserved delivery workspace on a new branch. T001 publishes one AppUI commit and T002 publishes one RepoInfra commit; integration and shipping verification add no source commit.
- Freeze the local uncommitted candidate and obtain exact AI Reviewer content `PASS` plus publication permission before commit, push, or PR creation/update. Publish only the unchanged reviewed tree.
- Candidate PR: replacement for #441, non-Draft, `owner-review` label, required checks, clean layer-scoped history, and description of the manual new-runner procedure.
- PR #441 and its branch remain unchanged until the replacement is published; PR Manager then closes #441 with the replacement link. No force-push or history rewrite is authorized.
- Before explicit Owner consent: static/syntax/RepoInfra/XcodeGen/unsigned evidence only.
- After T004 passes, reviewed merge, and explicit Owner consent: one manual TestFlight run on `main` may establish production proof.
- Production proof: consent record, GitHub Actions run URL, successful terminal run, and processed TestFlight build identifier. Secret values and signing artifacts are excluded.

## Trusted Review Shipping Contract

- Before T004 can accept shipping evidence, MY-1675 / PR #442 must have merged through its one-time exact-head human bootstrap.
- The #442 bootstrap is scoped only to that exact #442 head. It cannot be copied, referenced, or treated as a bypass for MY-1660.
- Replacement publication and the independently progressing #442 merge are separate prerequisites that join at T004.
- T004's trusted event base is the fresh eligible `pull_request_target` event's `github.event.pull_request.base.sha` on default branch `main`; that exact revision must contain the merged #442 fix. It is not the immutable replacement source base, and advancing it must not rebase or rewrite replacement ancestry.
- Shipping evidence must include a real schema-valid, passing `codex-review-target` result for that fresh event and the replacement head. A stale result, a pre-fix event base, a synthetic result, or the #442 bypass does not satisfy the gate.

## Compatibility Contract

- Preserve manual-only workflow dispatch, force default and branch, `main` checkout, concurrency, build-number computation, telemetry build inputs, upload, internal-group distribution, and release-tag behavior.
- Preserve all existing TestFlight freshness assertions; no deletion or weakening is allowed.
- Preserve the unchanged support-document content and layer boundaries: `project.yml` is AppUI, Fastlane/workflow/test changes are RepoInfra, and the generated project is evidence rather than a third implementation layer.
