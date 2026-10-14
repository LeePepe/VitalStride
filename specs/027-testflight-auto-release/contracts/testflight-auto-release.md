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
2. Authoritatively enumerate `testflight/success-pending/*` and `testflight/success-resolved/*`. Every ref name must be well formed and its target must equal the SHA encoded in that name. Malformed names, mismatched targets, and orphan resolved refs fail closed. A confirmed pending SHA without its matching resolved SHA fails every candidate before upload with `success-marker-recovery-required`; an exact valid pair clears only this recovery gate and never reclassifies a prior failed run as success.
3. Resolve `testflight/last-released`; missing, invalid, or non-ancestor state fails before upload.
4. Skip when candidate equals the successful marker.
5. Skip when immutable ref `testflight/attempted/<candidate>` exists, regardless of claims for newer SHAs.
6. After eligibility and version validation, create `testflight/attempted/<candidate>` without force and confirm the exact remote ref.
7. Only after confirmation may the release lane start. Existing, failed, ambiguous, or unconfirmed claim state fails before upload; claims are never moved, deleted, or rolled back.
8. On any later failure, retain the immutable claim; do not retry or roll back.
9. Retain the freshly confirmed prior successful-marker OID. After every earlier critical phase succeeds, create and remotely confirm immutable `testflight/success-pending/<candidate>` without force. Failed/ambiguous confirmation stops before success-marker mutation; any remotely observed pending ref is a durable recovery gate.
10. Mutate `testflight/last-released` toward the candidate only with the retained prior OID as a compare-and-swap/lease expectation, then freshly read the remote ref.
11. Failure before step 9 preserves the prior successful marker. Only exact candidate readback may proceed; lease rejection/confirmed prior value is failure, a different SHA is conflict, and failed or unavailable readback is `success-marker-indeterminate`. Record the prior baseline, candidate, lease/push result, and last safely observed remote value; do not assert unchanged state, overwrite conflict, or roll back.
12. After exact candidate readback, create and remotely confirm immutable `testflight/success-resolved/<candidate>` without force. Only that confirmation in the current run completes success. Confirmed absence fails with an unpaired pending ref and requires Owner recovery. Ambiguous confirmation fails the current run without asserting whether the write landed; the next authoritative preflight may clear only the recovery gate when it observes the exact valid pair, retains Owner recovery when it confirms the resolved ref absent, and fails closed on malformed/mismatched/orphan state. No later observation rewrites the failed terminal result as T005/MY-1766 success; neither ref is moved or deleted.

## App-Relevance Contract

The accumulated diff is `testflight/last-released..candidate`. Exclusions are evaluated first. A release is app-relevant only when at least one remaining changed path matches:

- `Packages/*/Package.swift`
- `Packages/*/Sources/**`
- `Packages/*/Plugins/**`
- `VitalStride/Sources/**`
- `VitalStride/Resources/**`
- `VitalStride/Assets.xcassets/**`
- `VitalStride/*.entitlements`
- `VitalStrideMac/Sources/**`
- `VitalStrideMac/Resources/**`
- `VitalStrideMac/Assets.xcassets/**`
- `VitalStrideMac/*.entitlements`
- `VitalStrideWatch Watch App/Sources/**`
- `VitalStrideWatch Watch App/Resources/**`
- `VitalStrideWatch Watch App/Assets.xcassets/**`
- `VitalStrideWatch Watch App/*.entitlements`
- `VitalStrideWidgets/**/*.swift`
- `VitalStrideWidgets/**/*.plist`
- `VitalStrideWidgets/**/*.entitlements`
- `VitalStrideWidgets/**/*.xcassets/**`
- `project.yml`
- `fastlane/Fastfile`
- `fastlane/Appfile`

The classifier consumes NUL-safe change records. Here `**` matches zero or more path segments and matching is repository-root-relative. Exclusions apply per endpoint before positive matching. A relevant deletion qualifies; either relevant endpoint makes a rename/copy record relevant; excluded-to-excluded does not; excluded records do not veto a co-changed relevant record. No other path independently qualifies. In particular, documentation/context files, specs, `Packages/*/Tests/**`, app/test-only roots, `Prototype/**`, generated `VitalStride.xcodeproj/**`, `.github/**`, and CI-only scripts are excluded. Manual `force=true` bypasses only this path decision for an otherwise valid unattempted current-main candidate.

## Owner Recovery Contract

A confirmed unpaired `testflight/success-pending/<SHA>` durably blocks later candidates until the Owner resolves the remote ref with safe release evidence. When an automatic resolution confirmation was ambiguous, authoritative preflight first determines whether an exact valid pair already exists; a valid pair clears only the gate, while confirmed absence enters this Owner path:

- remote equals candidate: reconcile successful-marker/build evidence without re-uploading the claimed SHA, record the disposition, then create/confirm matching immutable `success-resolved/<SHA>`;
- remote equals the captured prior baseline: verify App Store Connect evidence before any Owner-authorized leased forward advance and confirmation, record it, then create/confirm matching immutable `success-resolved/<SHA>`;
- remote equals another SHA: never overwrite automatically; reconcile and record release ordering/supersession, then create/confirm matching immutable `success-resolved/<SHA>` only when the evidence is safe;
- remote is unreadable/invalid: make no mutation or resolution write, leave the pending ref unpaired, and remain blocked.

Recovery never deletes or moves an attempt/pending/resolved ref, rolls a marker back, or retries the claimed SHA. Automatic execution may create the resolved ref only after exact candidate readback; all exceptional resolution authority belongs to the Owner. Reconciliation of a later-observed exact pair never converts the earlier failed run into completion evidence.

## Merged-PR and Version Contract

- Automatic and manual release each resolve exactly one merged PR associated with the candidate and based on `main`; zero or multiple matches fail before claim, and force does not bypass the lookup.
- The exact case-sensitive label is `release:minor`.
- Shipping target marketing versions in `project.yml` must agree and be numeric major/minor or major/minor/patch values.
- No label: runtime marketing version equals the project value.
- Label present: increment the minor component; reset an existing patch component to zero.
- The resolved runtime value is not written to tracked files and is the only marketing version used by archive, post-upload lookup, distribution, summary, and issue evidence.
- The build number remains the maximum across all TestFlight marketing versions plus one. It is exposed as safe workflow evidence.

## Release-Critical Contract

The following must stop the run on failure: candidate/source validation, marker/ancestry and pending/resolved namespace validation, merged-PR/label lookup for either source, project-version validation, immutable per-SHA attempt claim, existing secret/keychain/profile checks, archive, binary upload, Apple processing, internal-group distribution, dSYM tool/install/upload, success-pending creation/confirmation, success-marker mutation/readback, and success-resolution creation/confirmation.

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

Every skip/failure writes candidate SHA, source, decision/phase, stable reason code, and safe next action to the job summary. Claim-related evidence names only the immutable ref and SHA. `success-marker-recovery-required` names the confirmed unpaired pending ref; `success-marker-indeterminate` additionally records the prior baseline, candidate, push outcome, and last safely observed remote value. Ambiguous resolution confirmation records no paired/unpaired assertion. Success additionally writes run URL, marketing version, build number, immutable attempt claim, confirmed successful-marker SHA, and confirmed pending/resolved pair from that same successful run.

After merge, MY-1766 receives the first eligible run URL, exact SHA, terminal conclusion, marketing version, build number, immutable attempt-claim state, successful-marker state, and safely known pending/resolved pair state. A failure record is incident evidence and does not satisfy the outcome, even when a later preflight observes a valid pair; after any required recovery/reconciliation, completion requires a successful run for a distinct eligible SHA. That operational record is not replaced by planning tests or CI checks.

## Regression Contract

Credential-free tests must prove:

1. automatic event name/event/branch/conclusion guards;
2. exact-SHA checkout and reuse;
3. NUL-safe narrow accumulated path positives plus endpoint exclusion precedence, including package tests/contexts, documentation-only, mixed, deletion, and rename/copy matrices;
4. manual force default and bounded bypass;
5. duplicate/lifetime per-SHA claim protection (including A→B→A) and claim-before-lane/success-after-critical ordering;
6. concurrency/runner behavior;
7. automatic and manual unique associated-PR label and marketing-version handoff;
8. app-wide build-number query and safe output;
9. critical failure behavior, pending/resolved name-and-target validation, malformed/mismatched/orphan rejection, durable confirmed-unpaired rejection, ambiguous-resolution next-preflight reconciliation, leased success-marker prior/conflict/indeterminate states, all four Owner-recovery dispositions/resolution transitions, no retroactive success, and summary fields;
10. all pre-existing target-specific profile/signing/shell-safety assertions remain effective.

Tests make no GitHub write, ASC request, profile installation, signing action, workflow dispatch, or upload.
