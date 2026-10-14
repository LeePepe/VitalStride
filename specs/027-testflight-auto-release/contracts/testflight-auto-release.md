# Contract: TestFlight auto-release

## Exact Base and Ownership

- Planning product base: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789` on VitalStride `main`.
- Implementation base: the exact AI-Reviewer-passed planning revision, or another Team-Lead-approved base containing byte-identical reviewed `specs/027-testflight-auto-release/**` artifacts.
- Implementation owner layer: `RepoInfra`.
- Exact implementation allowlist: `.github/workflows/testflight.yml`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`.
- `.github/workflows/testflight.yml` requires explicit Owner approval before merge. No tracked CODEOWNERS rule substitutes for this evidence.

## Event Contract

Automatic input is a completed run of workflow name `CI`. A release candidate exists only when the source run is a successful `push` on `main`. Candidate SHA is the exact source run head SHA.

Manual input remains `workflow_dispatch` with boolean `force`, default `false`. Candidate SHA is the exact current `main` SHA captured for that dispatch.

Automatic and manual paths converge before marker, path, version, claim, and release evaluation. They never substitute a later moving branch SHA after candidate capture.

## Marker Contract

1. Fetch full history and tags.
2. Resolve `testflight/last-released`; missing, invalid, or non-ancestor state fails before upload.
3. Skip when candidate equals the successful marker.
4. Skip when candidate equals `testflight/last-attempted`.
5. After eligibility and version validation, move `testflight/last-attempted` to the candidate and confirm the remote ref equals it.
6. Only after confirmation may the release lane start.
7. On any later failure, leave both marker states as they are; do not retry or roll back.
8. After every critical phase succeeds, move `testflight/last-released` to the candidate and confirm the remote ref.

## App-Relevance Contract

The accumulated diff is `testflight/last-released..candidate`. A release is app-relevant when at least one changed path matches:

- `Packages/**`
- `VitalStride/**`
- `VitalStrideMac/**`
- `VitalStrideWatch Watch App/**`
- `VitalStrideWidgets/**`
- `project.yml`
- `fastlane/Fastfile`
- `fastlane/Appfile`

No other path independently qualifies. In particular, docs, specs, test-only roots, `Prototype/**`, generated `VitalStride.xcodeproj/**`, `.github/**`, and CI-only scripts are excluded. Manual `force=true` bypasses only this path decision for an otherwise valid unattempted current-main candidate.

## Merged-PR and Version Contract

- Automatic release resolves exactly one merged PR associated with the candidate and based on `main`; zero or multiple matches fail before claim.
- The exact case-sensitive label is `release:minor`.
- Shipping target marketing versions in `project.yml` must agree and be numeric major/minor or major/minor/patch values.
- No label: runtime marketing version equals the project value.
- Label present: increment the minor component; reset an existing patch component to zero.
- The resolved runtime value is not written to tracked files and is the only marketing version used by archive, post-upload lookup, distribution, summary, and issue evidence.
- The build number remains the maximum across all TestFlight marketing versions plus one. It is exposed as safe workflow evidence.

## Release-Critical Contract

The following must stop the run on failure: candidate/source validation, marker/ancestry validation, merged-PR/label lookup, project-version validation, attempt claim, existing secret/keychain/profile checks, archive, binary upload, Apple processing, internal-group distribution, dSYM tool/install/upload, and success-marker mutation/confirmation.

No automatic retry, rescue-and-continue, `continue-on-error`, or rollback is permitted for those phases. TEMP-PRELAUNCH remains a warning-only internal-TestFlight audit under its existing accepted policy. Optional Aptabase inputs retain their current fail-safe empty behavior.

## Concurrency and Runner Contract

- One app-scoped TestFlight concurrency group.
- Queued execution; `cancel-in-progress: false`.
- Runner labels exactly include `self-hosted` and `vitalstride-mac`.
- No second runner, schedule, or release workflow is introduced.

## Secret and Permission Contract

- Reuse existing ASC API key, keychain password, GlitchTip, Aptabase, and GitHub token inputs.
- Add no secret and print no value.
- GitHub token permissions are the minimum required to read exact PR labels and write/verify release tags.
- Evidence excludes profile/certificate/keychain contents and names.

## Evidence Contract

Every skip/failure writes candidate SHA, source, decision/phase, stable reason code, and safe next action to the job summary. Success additionally writes run URL, marketing version, build number, and both marker SHAs.

After merge, MY-1766 receives the first eligible run URL, exact SHA, terminal conclusion, marketing version, build number, and marker state. That operational record is not replaced by planning tests or CI checks.

## Regression Contract

Credential-free tests must prove:

1. automatic event name/event/branch/conclusion guards;
2. exact-SHA checkout and reuse;
3. accumulated path allowlist and explicit exclusions;
4. manual force default and bounded bypass;
5. duplicate/attempted protection and attempt-before-lane/success-after-critical ordering;
6. concurrency/runner behavior;
7. unique associated-PR label and marketing-version handoff;
8. app-wide build-number query and safe output;
9. critical failure behavior and summary fields;
10. all pre-existing target-specific profile/signing/shell-safety assertions remain effective.

Tests make no GitHub write, ASC request, profile installation, signing action, workflow dispatch, or upload.
