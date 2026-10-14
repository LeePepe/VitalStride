# Feature Specification: TestFlight auto-release after verified main CI

**Feature Branch**: `027-testflight-auto-release`

**Created**: 2026-10-15

**Status**: Ready for independent planning review

**Input**: MY-1766 revision 3 and Owner decision dated 2026-10-14, planned from exact VitalStride `main` base `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`.

## Decision Register

- **DEC-027-001 — Automatic release source**: After a successful `CI` push run for `main`, release the exact `workflow_run.head_sha`; never substitute a later moving `main` SHA. Authority: MY-1766 Owner decision.
- **DEC-027-002 — App-relevance boundary**: Automatic eligibility is the accumulated diff from `testflight/last-released` to the exact candidate and is limited to shipped app/package sources and resources, `project.yml`, and the two release-lane files `fastlane/Fastfile` and `fastlane/Appfile`. Documentation, specs, tests, generated project output, workflow-only changes, and CI-only scripts do not independently trigger a release. Authority: MY-1766 Owner decision.
- **DEC-027-003 — Attempt and success markers**: Keep `testflight/last-released` as the successful-release marker and add a moving `testflight/last-attempted` claim before the release lane. A failed claim write aborts before upload; once a SHA is claimed, neither automatic nor manual dispatch retries that SHA. This closes the upload-succeeded/tag-failed ambiguity while preserving the successful marker. Authority: MY-1766 fail-closed, no-retry, and never-upload-the-same-SHA-twice requirements.
- **DEC-027-004 — Version policy**: The build number remains the App Store Connect app-wide maximum plus one and is never scoped to a marketing version. The marketing version is the uniform value declared by the shipping targets in `project.yml`, except an exact merged PR labelled `release:minor` receives a per-run minor increment without writing back to the repository. Authority: MY-1766 Owner decision.
- **DEC-027-005 — Manual force semantics**: `workflow_dispatch` remains available. `force=true` may bypass app-path eligibility for the current exact `main` SHA, but it cannot bypass a prior attempt claim or successful-release marker. Authority: compatibility plus MY-1766 duplicate/no-retry constraints.
- **DEC-027-006 — Fail-closed release boundary**: Candidate resolution, marker ancestry, merged-PR resolution, version derivation, attempt claim, signing, archive, upload, Apple processing, internal-group distribution, dSYM publication, and successful-marker mutation are release-critical. Failure stops the run, records the phase/reason, and performs no retry or rollback. The existing internal-TestFlight TEMP-PRELAUNCH audit remains warning-only by its narrower accepted policy.
- **DEC-027-007 — Owner approval for `.github/**`**: The implementation PR changes one `.github/**` file and therefore requires explicit Owner approval before merge. No tracked `CODEOWNERS` rule enforces this on the planning base; the issue decision is the fail-closed authority and AI Reviewer PASS does not replace it.

## User Scenarios & Testing

### User Story 1 - Publish an eligible verified merge automatically (Priority: P1)

As the app owner, I want a successful main-branch CI result to queue one TestFlight release for the exact verified app-relevant SHA so normal delivery no longer requires a manual upload.

**Why this priority**: Automatic post-merge publication is the requested outcome and must not race ahead of CI or release a different commit.

**Independent Test**: Credential-free workflow contract tests present synthetic automatic events, marker states, and changed-path sets and prove only a successful `CI` push run on `main` with an eligible exact SHA reaches the attempt boundary.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** workflow `CI` completed successfully for a `push` to `main` at SHA `S`, the successful marker is an ancestor of `S`, and `marker..S` contains an app-relevant path, **When** the release workflow runs, **Then** it checks out and releases exactly `S`, never the later value of `main`.
2. **US1/AC2** — **Given** the accumulated diff contains only docs, specs, tests, generated project output, `.github/**`, or CI-only scripts, **When** automatic eligibility is evaluated, **Then** no build or upload starts and the job summary records a path-ineligible skip reason.
3. **US1/AC3** — **Given** `S` equals `testflight/last-released` or `testflight/last-attempted`, **When** either automatic or manual dispatch evaluates `S`, **Then** it does not upload `S`, even when manual `force=true`, and records the duplicate/attempted reason.
4. **US1/AC4** — **Given** the source workflow is a PR run, manual CI run, failed run, non-`main` run, or a workflow other than exact `CI`, **When** it completes, **Then** no automatic release job reaches checkout or upload.
5. **US1/AC5** — **Given** a candidate marker is absent, is not an ancestor of `S`, the exact merged PR cannot be resolved unambiguously, or the attempt claim cannot be written, **When** the automatic release evaluates it, **Then** it fails before archive/upload with a non-secret reason and no retry.

---

### User Story 2 - Preserve release semantics while making each attempt unique (Priority: P1)

As the release operator, I need queued attempts to preserve the trusted runner, signing, monotonic versioning, and distribution behavior while failing visibly at the first unsafe or incomplete phase.

**Why this priority**: Automation increases release frequency; the existing signing and distribution safety contracts must remain intact and partial failures must not become duplicate uploads.

**Independent Test**: Static and unit-level contract coverage proves concurrency, runner, secrets, profile reuse, version derivation, attempt/success marker ordering, and fail-closed step guards without contacting Apple or mutating GitHub.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** two eligible release events arrive for VitalStride, **When** they are queued, **Then** one app-scoped concurrency group serializes them and no in-progress release is cancelled.
2. **US2/AC2** — **Given** App Store Connect reports app-wide maximum build number `N`, **When** a release archives, **Then** it uses build `N+1`, reports that value, and no later successful run reuses it.
3. **US2/AC3** — **Given** all shipping targets declare marketing version `M` in `project.yml` and the uniquely associated merged PR has no `release:minor` label, **When** release inputs are assembled, **Then** the archive and post-upload lookup use `M` without repository mutation.
4. **US2/AC4** — **Given** the uniquely associated merged PR has `release:minor`, **When** release inputs are assembled, **Then** the archive and post-upload lookup use the next minor version derived from `M` for that run only, without repository mutation.
5. **US2/AC5** — **Given** any release-critical phase fails after the attempt claim, **When** the workflow terminates, **Then** it leaves the claim in place, does not move `testflight/last-released`, performs no automatic retry/rollback, and records the failed phase for dashboard collection.
6. **US2/AC6** — **Given** upload, Apple processing, internal distribution, dSYM publication, and successful-marker update all complete, **When** the run finishes, **Then** the summary records the exact SHA, run URL, marketing version, and build number without exposing secrets or signing material.

---

### User Story 3 - Retain a bounded manual recovery entry point (Priority: P2)

As the owner, I want a manual dispatch with an explicit force option so I can release a current-main candidate that automatic path filtering skipped, without weakening exact-SHA or duplicate protections.

**Why this priority**: Manual control remains a required compatibility surface, but it must not become a bypass for CI identity or idempotency.

**Independent Test**: Contract tests prove manual default and force behavior against eligible, path-ineligible, successful, and already-attempted SHAs.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** current `main` SHA `S` is unreleased and unattempted, **When** manual dispatch uses `force=false`, **Then** it applies the same accumulated app-path eligibility rule as automatic release.
2. **US3/AC2** — **Given** current `main` SHA `S` is unreleased, unattempted, and path-ineligible, **When** manual dispatch uses `force=true`, **Then** it may claim and release exactly `S`.
3. **US3/AC3** — **Given** current `main` SHA `S` is already successful or attempted, **When** manual dispatch uses either force value, **Then** it skips before upload and cannot remove or rewrite the prior evidence.

### Edge Cases

- The exact CI candidate is no longer the tip of `main`: automatic release still uses the exact CI SHA if marker ancestry and main membership remain valid; a later event queues behind it.
- `testflight/last-released` is missing or not an ancestor of the candidate: automatic release fails closed. Manual force does not fabricate a success baseline; Owner recovery must establish a valid marker.
- The attempt claim succeeds and archive/upload later fails: the claim remains and the same SHA is never retried; a later merge is a new candidate and may include the unreleased changes.
- The upload succeeds but successful-marker mutation fails: the attempt marker prevents a duplicate; the run remains failed and requires Owner recovery of the success marker.
- Multiple or zero merged PRs are associated with the exact automatic SHA: version-label resolution is ambiguous and automatic release fails before the attempt claim.
- Shipping target marketing versions disagree or are not numeric major/minor values: fail before the attempt claim; do not guess a version.
- A `release:minor` PR at project version `1.1` uses `1.2` for that run; a three-component value increments the minor component and resets the patch component to zero.
- App Store Connect or GitHub is temporarily unavailable: record the failing phase and stop; do not auto-retry or roll back markers.
- A release contains only a test change: tests do not independently trigger TestFlight, even though required CI ran.
- A secret is absent: fail before signing/upload and report only the secret name, never its value.

## Requirements

### Functional Requirements

- **FR-001**: The workflow MUST listen for completed runs of workflow name `CI` and MUST automatically proceed only when `workflow_run.event == push`, `head_branch == main`, and `conclusion == success`.
- **FR-002**: Automatic release MUST bind candidate identity, checkout, eligibility, markers, summary, and upload evidence to the exact 40-character `workflow_run.head_sha`.
- **FR-003**: Automatic app relevance MUST be calculated from `testflight/last-released..candidate` against exactly: `Packages/**`, `VitalStride/**`, `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`, `project.yml`, `fastlane/Fastfile`, and `fastlane/Appfile`.
- **FR-004**: Documentation, `specs/**`, app/test-only roots, `Prototype/**`, `VitalStride.xcodeproj/**`, `.github/**`, and CI-only scripts MUST NOT independently qualify an automatic release.
- **FR-005**: The workflow MUST preserve `workflow_dispatch` with boolean `force` defaulting to `false`; force MAY bypass only FR-003/FR-004 for the exact current `main` SHA.
- **FR-006**: Neither automatic nor manual dispatch MAY upload a SHA equal to `testflight/last-released` or `testflight/last-attempted`, regardless of force.
- **FR-007**: Before invoking the release lane, the workflow MUST atomically move `testflight/last-attempted` to the candidate and MUST abort before upload if that remote write is not confirmed.
- **FR-008**: `testflight/last-released` MUST move to the exact candidate only after all release-critical phases succeed; failure MUST leave it unchanged.
- **FR-009**: Release-critical phases MUST include candidate/marker validation, unique merged-PR and label resolution, version derivation, attempt claim, signing, archive, binary upload, Apple processing, internal-group distribution, dSYM publication, and success-marker mutation.
- **FR-010**: The workflow MUST use one VitalStride TestFlight concurrency group with `cancel-in-progress: false` on `[self-hosted, vitalstride-mac]`.
- **FR-011**: The workflow MUST reuse the existing ASC API key, keychain, GlitchTip, Aptabase, signing-profile, and GitHub token inputs and MUST introduce no new secret.
- **FR-012**: The build number MUST remain the maximum TestFlight build number across all marketing versions plus one; it MUST be exposed as non-secret workflow output/summary evidence and MUST NOT be written back to `project.yml`.
- **FR-013**: Automatic release MUST resolve exactly one merged PR associated with the exact candidate, based on `main`, before reading `release:minor`; ambiguous or missing association MUST fail before the attempt claim.
- **FR-014**: Without `release:minor`, the marketing version MUST be the uniform shipping-target value from `project.yml`. With `release:minor`, the run MUST increment that value's minor component and reset an existing patch component to zero. The runtime override MUST feed archive and post-upload lookup without modifying tracked files.
- **FR-015**: The release lane MUST consume one resolved marketing-version input for archive, TestFlight build lookup, internal distribution, and evidence; its existing app-wide build-number query MUST remain unfiltered by marketing version.
- **FR-016**: Each skip or failure MUST write a concise GitHub job summary containing candidate SHA, decision/phase, reason code, and safe next action; a successful run MUST additionally include run URL, marketing version, and build number.
- **FR-017**: The workflow MUST perform no automatic retry or rollback. A new main SHA is a new candidate; an attempted SHA remains blocked from later automatic or manual upload.
- **FR-018**: Existing dynamic app/widget profile reuse, manual Release signing, Apple Distribution identity, TEMP-PRELAUNCH audit semantics, telemetry inputs, internal-group distribution, and successful tag behavior MUST remain covered by credential-free regression tests.
- **FR-019**: Existing manual-only assertions in `scripts/tests/test_testflight_freshness.py` MUST be replaced with automatic/manual event-contract assertions; unrelated signing/profile assertions MUST not be deleted or weakened.
- **FR-020**: The implementation PR MUST change only the declared RepoInfra paths and MUST receive explicit Owner approval because it touches `.github/workflows/testflight.yml`; AI Reviewer or required CI success is not a substitute.
- **FR-021**: After merge, the first eligible main candidate MUST produce evidence on MY-1766 containing its exact SHA, run URL, terminal conclusion, marketing version, build number, and marker state, with no secret/signing material.

## Existing Behaviour

- `.github/workflows/testflight.yml` is manual-only (`workflow_dispatch`), defaults `force=false`, checks out moving `main`, and lets force bypass the successful-marker equality check.
- The workflow uses `testflight/last-released`, one non-cancelling `testflight` concurrency group, and runner labels `[self-hosted, vitalstride-mac]`.
- `.github/workflows/ci.yml` is named exactly `CI` and runs for PRs, `push` to `main`, and manual dispatch. No TestFlight workflow currently consumes its result.
- `fastlane/Fastfile` regenerates the project, queries the app-wide maximum TestFlight build number plus one, dynamically fetches and reuses separate app/widget profiles, archives, uploads, waits for Apple processing, and adds the build to internal groups.
- The Fastfile currently hardcodes marketing version `1.1` for post-upload lookup while `project.yml` declares `1.1` on shipping targets; there is no label-derived version interface.
- Internal-group distribution errors are swallowed unless `TESTFLIGHT_STRICT_UPLOAD=1`, and dSYM installation/upload is best-effort. A later step can therefore move the success marker after those auxiliary failures.
- `scripts/tests/test_testflight_freshness.py` has ten passing credential-free tests at the planning base. It explicitly rejects automatic triggers and protects force/freshness, concurrency, signing, dynamic profile reuse, and shell-safe handoff.
- The prior `026-testflight-profile-reuse` planning package made manual-only publication and per-upload Owner consent explicit. The 2026-10-14 Owner decision supersedes those publication constraints while preserving its signing/profile contract.

## Compatibility

- Preserve the existing self-hosted Mac label, serialized non-cancelling app concurrency, ASC API secrets, keychain unlock, runtime-fetched target-specific profiles, manual Release signing, and Apple Distribution team/bundle mappings.
- Preserve app-wide monotonic build numbering, GlitchTip/Aptabase build inputs, internal TestFlight group distribution, and the TEMP-PRELAUNCH audit's nonblocking internal-release semantics.
- Preserve the successful `testflight/last-released` marker and add the attempt marker only to close the no-retry/idempotency failure window.
- Preserve manual dispatch and its `force=false` default, narrowed by the never-attempt/never-duplicate rules.
- Preserve all unrelated profile/signing regression assertions and run the full RepoInfra gate; no app target or package source changes are authorized.
- Preserve PR-required delivery and required CI. Exact AI Reviewer PASS covers content; explicit Owner approval separately covers the `.github/**` change.
- Preserve secret non-disclosure. Job summaries and MY-1766 evidence contain identifiers, versions, URLs, and reasons only.

## Removed Behaviour

- **RB-001**: Remove manual-only TestFlight publication; successful eligible `CI` push runs on `main` now trigger automatically. **Authority**: DEC-027-001 and the 2026-10-14 Owner decision, superseding 026's manual-only non-goal.
- **RB-002**: Remove moving-`main` substitution for automatic release; exact CI SHA is authoritative. **Authority**: DEC-027-001.
- **RB-003**: Remove force's ability to re-upload a successful or already-attempted SHA; force now bypasses only path eligibility. **Authority**: DEC-027-003 and DEC-027-005.
- **RB-004**: Remove automatic release for docs/specs/tests/CI-only changes; only DEC-027-002 paths qualify. **Authority**: DEC-027-002.
- **RB-005**: Remove best-effort swallowing of internal-group and dSYM publication failures from the release-success path; those phases fail closed and prevent the successful marker from moving. **Authority**: DEC-027-006.
- **RB-006**: Remove hardcoded Fastfile marketing-version selection as an independent source; the lane receives the version resolved from `project.yml` plus the exact PR label decision. **Authority**: DEC-027-004.
- **RB-007**: Remove per-upload Owner confirmation from 026; Owner approval is required for the `.github/**` implementation PR, after which eligible uploads are automatic. **Authority**: the 2026-10-14 Owner decision.
- **RB-008**: Remove no test and weaken no unrelated signing/profile assertion. Any additional deletion or weakening requires a new Owner decision. **Authority**: compatibility contract and Constitution Quality Bar A.

## Scope Boundaries

### In scope

- Automatic and manual TestFlight event selection, exact-SHA eligibility, path classification, attempt/success markers, job summaries, and fail-closed sequencing.
- Marketing/build-number input and evidence handoff between the workflow and existing Fastlane lane.
- Credential-free regression coverage through the existing RepoInfra validation path.
- Explicit Owner-approval and post-merge evidence contracts.

### Non-goals

- Changing the required `CI` workflow, branch protection, CODEOWNERS, repository rulesets, or review workflows.
- Adding a schedule, automatic retry, rollback, second runner, new secret, or new release service.
- Changing app/package source, tests, entitlements, bundle identifiers, signing team, Developer Portal objects, or `project.yml` contents.
- Changing App Store submission/external TestFlight behavior; this feature remains internal TestFlight publication.
- Treating planning review, CI, or a bot approval as the explicit Owner approval required for `.github/**`.
- Dispatching or simulating a real TestFlight upload during planning or pre-merge implementation verification.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Credential-free contract tests cover every automatic/manual event, path, marker, force, version-label, and failure-summary branch with zero external mutations.
- **SC-002**: The focused TestFlight regression, Fastfile syntax check, and complete RepoInfra validation finish with zero failures on the implementation candidate.
- **SC-003**: The first eligible successful `CI` main candidate after merge queues exactly one non-cancelled TestFlight run for the same SHA.
- **SC-004**: That run records one unique app-wide build number, its marketing version, run URL, successful terminal state, and matching attempted/success markers on MY-1766.
- **SC-005**: Docs/specs/tests/CI-only main changes produce a recorded skip and zero TestFlight uploads unless an unattempted current-main manual dispatch uses `force=true`.
- **SC-006**: A release-critical failure leaves `testflight/last-released` unchanged, preserves the attempt claim, emits a dashboard-readable phase/reason, and causes no retry or rollback.
- **SC-007**: The implementation PR contains explicit Owner approval for `.github/workflows/testflight.yml` before merge.

## Assumptions

- VitalStride main continues to be PR-only, so an automatic push SHA has one uniquely associated merged PR; violation fails closed rather than inventing label state.
- `release:minor` is the exact case-sensitive label. The label changes only that run's marketing version and does not edit repository files.
- Git tag writes through the existing `GITHUB_TOKEN` remain available; no additional credential is needed for the attempt marker.
- The first implementation candidate remains RepoInfra-only; therefore app `xcodebuild` and package build/test are not local verification requirements.
