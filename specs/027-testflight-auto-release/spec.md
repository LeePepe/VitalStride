# Feature Specification: TestFlight auto-release after verified main CI

**Feature Branch**: `027-testflight-auto-release`

**Created**: 2026-10-15

**Status**: Ready for independent planning review

**Input**: MY-1766 Owner decision dated 2026-10-14, Owner follow-up `01a13b86-1f43-7964-b7e7-013db4029fe3`, delegated Owner decision `01a13b86-1ed5-7b57-b69a-3deaa4299249`, and Team Lead marker-only handoff `01a13b8b-7541-7ef5-b7c9-ae16701118bb`, planned from exact VitalStride `main` base `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`.

## Decision Register

- **DEC-027-001 — Automatic release source**: After a successful `CI` push run for `main`, release the exact `workflow_run.head_sha`; never substitute a later moving `main` SHA. Authority: MY-1766 Owner decision.
- **DEC-027-002 — App-relevance boundary**: Automatic eligibility is the accumulated diff from `testflight/last-released` to the exact candidate and is limited to narrow shipped package manifests/sources/plugins, shipped app sources/resources/assets/configuration, `project.yml`, and the two release-lane files `fastlane/Fastfile` and `fastlane/Appfile`. Classification consumes NUL-safe change records; exclusions are evaluated per endpoint before positive matching; either relevant endpoint makes a rename/copy relevant. Documentation, contexts, specs, tests, generated output, workflow-only changes, and CI-only scripts do not independently trigger a release. Authority: MY-1766 Owner decision.
- **DEC-027-003 — Single durable release marker**: `testflight/last-released` is the only durable release state. No per-SHA attempt/skip record, queue/cursor ref, compare-and-swap lease, transaction journal, or auxiliary recovery ref is created or consulted. Skipped and failed commits remain represented implicitly by the unchanged `marker..candidate` range. Authority: Owner follow-up and delegated Owner decision `01a13b86-1ed5-7b57-b69a-3deaa4299249`, adopted for VitalStride by Team Lead.
- **DEC-027-004 — Version policy**: The build number remains the App Store Connect app-wide maximum plus one. The marketing version is the uniform shipping-target value in `project.yml`, except the exact candidate's uniquely associated merged PR receives a per-run minor increment when it carries case-sensitive `release:minor`. Earlier PRs merely accumulated in `marker..candidate` do not change the candidate's label decision. Authority: MY-1766 Owner decision and the preserved reviewed v1 version policy.
- **DEC-027-005 — Manual force semantics**: `workflow_dispatch` remains. Its candidate is the exact current remote `main`. `force=true` bypasses only app relevance; it does not bypass current-main identity, an invalid/divergent marker, candidate-equals-marker protection, unique PR/version resolution, signing/secrets, or release-critical failures. Authority: delegated Owner decision and Team Lead handoff.
- **DEC-027-006 — Fail-closed release and final marker ordering**: One app-scoped concurrency group serializes active release lanes without cancelling an in-progress lane. Candidate/marker, PR/version, signing, archive, upload, Apple processing, internal-group distribution, dSYM publication, and final marker update/readback are release-critical. The workflow attempts the sole marker update only after every earlier critical phase succeeds. Any earlier failure invokes no marker mutation, records safe phase/reason evidence, and performs no automatic retry or rollback. If the final marker update or its readback fails, the run fails, writes no auxiliary state, performs no retry/rollback, and the next invocation re-reads the remote marker as the sole authority; the design does not claim an unobservable remote write stayed unchanged. Authority: MY-1766 fail-closed decision refined by the marker-only Owner decision.
- **DEC-027-007 — Owner approval for `.github/**`**: The implementation PR changes one `.github/**` file and requires explicit Owner approval before merge. No tracked `CODEOWNERS` rule enforces this on the planning base; AI Reviewer PASS and CI do not substitute for the explicit approval.
- **DEC-027-008 — Marker bootstrap and ordering**: When `testflight/last-released` is absent, eligibility uses the Git empty tree as an ephemeral baseline and evaluates the candidate snapshot without creating bootstrap state. When the marker equals or is a descendant of the candidate, the candidate is already covered and skips; when the marker is an ancestor, the normal range is evaluated; divergence, an unreadable marker, or a non-commit marker fails closed. Authority: Team Lead's requirement for explicit marker-absent bootstrap and the no-new-state constraint.

## User Scenarios & Testing

### User Story 1 - Publish an eligible verified merge automatically (Priority: P1)

As the app owner, I want a successful main-branch CI result to publish the exact verified app-relevant candidate while accumulated skipped or failed changes remain eligible until a release succeeds.

**Why this priority**: Automatic post-merge publication is the requested outcome and must not race ahead of CI or lose relevant changes behind irrelevant merges.

**Independent Test**: Credential-free tests present automatic events, marker relations, bootstrap state, and NUL-safe change records and prove only a successful exact `CI` main candidate with an eligible accumulated range reaches the release lane.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** workflow `CI` completed successfully for a `push` to `main` at SHA `S`, the remote marker is an ancestor of `S`, and `marker..S` contains an app-relevant path, **When** the release workflow runs, **Then** it checks out and releases exactly `S`, never a later moving `main` SHA.
2. **US1/AC2** — **Given** one or more accumulated merges since the marker contain only excluded paths, **When** automatic eligibility is evaluated, **Then** no build/upload starts, no skip state is written, and the job summary records a path-ineligible reason; a later relevant candidate evaluates the entire still-unreleased range.
3. **US1/AC3** — **Given** a relevant candidate fails before the final marker update, **When** a later main candidate arrives, **Then** the unchanged marker makes the later candidate's accumulated range include the failed changes. A candidate equal to or already covered by the marker skips, including manual `force=true`.
4. **US1/AC4** — **Given** the source workflow is a PR run, manual CI run, failed run, non-`main` run, or a workflow other than exact `CI`, **When** it completes, **Then** no automatic release job reaches checkout or upload.
5. **US1/AC5** — **Given** the marker is absent, **When** the first candidate is evaluated, **Then** the empty-tree bootstrap applies without durable bootstrap state. An unreadable/divergent marker or ambiguous exact-candidate PR/version fails before archive/upload with safe evidence.

### User Story 2 - Preserve release semantics and advance one marker only after success (Priority: P1)

As the release operator, I need serialized releases to preserve runner, signing, monotonic versioning, and distribution behavior while the sole marker advances only after the complete critical lane succeeds.

**Why this priority**: Automation increases release frequency; existing release safety must remain intact without adding a second durable state machine.

**Independent Test**: Static and unit-level coverage proves concurrency, runner, secrets, profile reuse, version derivation, fail-closed critical ordering, final marker sequencing, and safe summaries without contacting Apple or mutating GitHub.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** multiple release events exist, **When** they target VitalStride, **Then** one app-scoped concurrency group permits at most one active release lane and never cancels an in-progress run; no durable FIFO queue or cursor is promised.
2. **US2/AC2** — **Given** App Store Connect reports app-wide maximum build number `N`, **When** a release archives, **Then** it uses build `N+1`, reports that value, and no later successful run reuses it.
3. **US2/AC3** — **Given** all shipping targets declare marketing version `M` and the exact candidate's merged PR lacks `release:minor`, **When** inputs are assembled, **Then** archive and post-upload lookup use `M` without repository mutation.
4. **US2/AC4** — **Given** the exact candidate's uniquely associated merged PR has case-sensitive `release:minor`, **When** inputs are assembled, **Then** archive and post-upload lookup use the next minor derived from `M` for that run only.
5. **US2/AC5** — **Given** any critical phase before final marker update fails, **When** the run terminates, **Then** it does not invoke marker mutation, performs no automatic retry/rollback, and records the failed phase. If marker update/readback itself fails, it records that terminal phase without auxiliary recovery state and the next invocation uses the freshly fetched remote marker as truth.
6. **US2/AC6** — **Given** every release-critical phase and final marker readback succeeds, **When** the run finishes, **Then** `testflight/last-released` equals the exact candidate and the summary records exact SHA, run URL, marketing version, and build number without exposing secrets or signing material.

### User Story 3 - Retain bounded manual force (Priority: P2)

As the owner, I want manual dispatch with an explicit force option so I can pick up the exact current-main candidate after filtering or failure, without weakening identity, version, signing, or final-marker ordering.

**Why this priority**: Manual control is a compatibility surface and the explicit forward path after a failed release; it must remain narrowly bounded.

**Independent Test**: Credential-free cases cover default false, accumulated relevance, force-only relevance bypass, same-released protection, and a failed current-main candidate picked up by a later manual run.

**Acceptance Scenarios**:

1. **US3/AC1** — **Given** exact current `main` is ahead of a valid marker, **When** manual dispatch uses `force=false`, **Then** it applies the same accumulated marker-range relevance rule as automatic release.
2. **US3/AC2** — **Given** exact current `main` is ahead of a valid marker but the range is path-ineligible, **When** manual dispatch uses `force=true`, **Then** it may release current `main` while all non-relevance gates still apply.
3. **US3/AC3** — **Given** current `main` equals or is already covered by the marker, **When** manual dispatch uses either force value, **Then** it skips before upload. Given a prior failed run left current `main` ahead of the marker, a later manual dispatch may pick it up because no lifetime attempt record exists.
4. **US3/AC4** — **Given** current `main` has exactly one associated merged PR, **When** manual dispatch evaluates it, **Then** it applies the same exact-candidate `release:minor` decision as automatic release; zero or multiple matches fail before the release lane.

### Edge Cases

- An exact automatic candidate is older than a marker advanced by another completed run in the same app group: it skips as already covered. A protected-history divergence fails closed.
- The marker is absent: use empty-tree-to-candidate classification for this invocation only; create no bootstrap ref or cursor.
- Several irrelevant candidates skip without state; the next relevant candidate evaluates all changes since the unchanged marker and releases the newest exact candidate.
- A relevant candidate fails before final marker update; a later eligible merge or manual current-main run picks up its changes. This is a new event/run, not an automatic retry of the failed job.
- The final marker command/readback fails after release-critical work: fail the run, record the phase and last safely observed marker, and create no journal/recovery ref. The next run reads the remote marker and follows equality/ancestry rules.
- Multiple or zero merged PRs are associated with the exact automatic or manual candidate: version-label resolution is ambiguous and fails before archive.
- An earlier PR inside the accumulated range carries `release:minor` but the exact candidate PR does not: the candidate PR alone decides the marketing version.
- Shipping target versions disagree or are not numeric major/minor values: fail before archive; do not guess.
- App Store Connect or GitHub is unavailable: record the phase and stop; do not auto-retry or roll back.
- A relevant source is deleted or renamed to/from an excluded test/context path: deletion remains relevant; either relevant rename/copy endpoint qualifies after exclusions. A mixed diff releases when any record is relevant.
- A secret is absent: fail before signing/upload and report only the secret name, never its value.

## Requirements

### Functional Requirements

- **FR-001**: The workflow MUST listen for completed workflow `CI` runs and automatically proceed only when `workflow_run.event == push`, `head_branch == main`, and `conclusion == success`.
- **FR-002**: Automatic release MUST bind candidate identity, checkout, relevance, marker decisions, summary, and upload evidence to the exact 40-character `workflow_run.head_sha`; manual release MUST capture exact current remote `main` once and reuse it.
- **FR-003**: App relevance MUST use NUL-safe change records from the selected baseline to candidate against only: `Packages/*/Package.swift`, `Packages/*/Sources/**`, `Packages/*/Plugins/**`; `VitalStride/Sources/**`, `VitalStride/Resources/**`, `VitalStride/Assets.xcassets/**`, `VitalStride/*.entitlements`; equivalent `VitalStrideMac/**` and `VitalStrideWatch Watch App/**` shipped source/resource/asset/entitlement families; `VitalStrideWidgets/**/*.swift`, `VitalStrideWidgets/**/*.plist`, `VitalStrideWidgets/**/*.entitlements`, `VitalStrideWidgets/**/*.xcassets/**`; and exact `project.yml`, `fastlane/Fastfile`, `fastlane/Appfile`. Matching is repository-root-relative and `**` matches zero or more segments.
- **FR-004**: Exclusions MUST apply per endpoint before positives. Documentation/context, `specs/**`, `Packages/*/Tests/**`, app test roots, `Prototype/**`, `VitalStride.xcodeproj/**`, `.github/**`, CI-only scripts, and unlisted paths MUST NOT independently qualify. Relevant deletion qualifies; either relevant rename/copy endpoint qualifies; excluded records do not veto a co-changed relevant record.
- **FR-005**: The workflow MUST preserve boolean manual `force` default `false`; `force=true` MAY bypass only FR-003/FR-004 for exact current `main`.
- **FR-006**: `testflight/last-released` MUST be the only durable release state. Missing marker MUST select the Git empty tree as ephemeral baseline; marker ancestor of candidate MUST select `marker..candidate`; candidate equal to or ancestor of marker MUST skip as already covered; unreadable/non-commit/divergent marker MUST fail closed.
- **FR-007**: The workflow MUST NOT create or consult durable per-SHA attempt/skip history, queue/cursor refs, transaction journals, CAS/lease state, or auxiliary marker-recovery refs. A skipped or failed range remains pending solely because `testflight/last-released` did not advance.
- **FR-008**: The workflow MUST attempt to advance `testflight/last-released` to candidate only after every earlier critical phase succeeds, then freshly read the remote marker. Exact candidate readback is required for terminal success. Marker update/readback failure MUST fail the run with safe evidence and MUST NOT trigger a second overwrite attempt, retry, rollback, or auxiliary-state creation.
- **FR-009**: Critical phases MUST include source/candidate/marker validation, unique candidate-PR/label resolution, version derivation, signing/profile setup, archive, binary upload, Apple processing, internal-group distribution, dSYM publication, and final marker update/readback. TEMP-PRELAUNCH remains warning-only under its existing narrower policy.
- **FR-010**: The workflow MUST use one VitalStride TestFlight concurrency group with `cancel-in-progress: false` on `[self-hosted, vitalstride-mac]`; it MUST NOT add a custom durable queue or claim FIFO execution of pending platform runs.
- **FR-011**: The workflow MUST reuse existing ASC API key, keychain, GlitchTip, Aptabase, signing-profile, and GitHub token inputs and MUST introduce no new secret.
- **FR-012**: Build number MUST remain maximum TestFlight build across all marketing versions plus one, be emitted as safe evidence, and not be written to `project.yml`.
- **FR-013**: Automatic and manual releases MUST resolve exactly one merged PR associated with the exact candidate and based on `main` before the release lane; force MUST NOT bypass it.
- **FR-014**: Without `release:minor`, marketing version MUST equal the uniform shipping-target value in `project.yml`; with the exact candidate label, increment minor and reset an existing patch to zero. Do not edit tracked files.
- **FR-015**: The lane MUST consume one resolved marketing version for archive, lookup, distribution, and evidence; the build query MUST remain app-wide.
- **FR-016**: Each skip/failure MUST write candidate SHA, source, decision/phase, stable reason code, and safe next action. Codes MUST distinguish bootstrap, path-ineligible, already-covered, marker-invalid, release-phase failure, and marker-update failure. Success MUST additionally include run URL, marketing version, build number, and confirmed marker SHA. No secret/profile/certificate/keychain value or health value may appear.
- **FR-017**: The workflow MUST configure no automatic retry or rollback. A later successful main-CI event or manual dispatch is a new run that re-evaluates the unchanged marker range; the system MUST NOT persist lifetime same-SHA attempt prohibition.
- **FR-018**: The workflow MUST run on existing labels `[self-hosted, vitalstride-mac]` and preserve one non-cancelling app group.
- **FR-019**: Existing dynamic app/widget profile reuse, manual Release signing, ASC processing wait, internal group targeting, optional Aptabase behavior, GlitchTip inputs, and non-secret telemetry/logging safeguards MUST remain unless FR-009 deliberately makes a formerly best-effort failure release-critical.
- **FR-020**: Implementation MUST modify only `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `scripts/tests/test_testflight_freshness.py`; the non-Draft PR MUST receive exact content review, required checks, and explicit Owner approval for `.github/**` before merge.
- **FR-021**: After merge, MY-1766 MUST record the first eligible successful run's exact SHA, run URL, terminal conclusion, marketing version, build number, and confirmed `testflight/last-released` state. Failure evidence is incident-only and does not complete the outcome.

## Existing Behaviour

- At the product base, `.github/workflows/testflight.yml` is manual-only, checks out moving `main`, compares only HEAD with `testflight/last-released`, and lets `force=true` bypass its no-new-commit gate.
- It already uses runner `[self-hosted, vitalstride-mac]`, concurrency group `testflight`, and `cancel-in-progress: false`.
- `testflight/last-released` is the only existing release marker and moves after the lane/ancillary steps.
- Fastlane queries the app-wide TestFlight maximum plus one, hardcodes marketing version `1.1`, uses dynamic target-specific profiles/manual signing, waits for processing, and distributes to the internal group.
- Internal-group distribution and dSYM publication include best-effort behavior at the base; the new fail-closed contract deliberately removes that weakening under DEC-027-006.
- The focused regression suite asserts the manual-only trigger, force gate, secrets/shell safety, profile reuse, and Fastlane behavior.

## Compatibility

- Preserve manual dispatch and its boolean input, the runner/group, exact existing secret names, keychain and dynamic profile handoff, signing identities, ASC app-wide build counter, Apple processing, internal group, TEMP-PRELAUNCH warning policy, optional telemetry inputs, and non-secret summaries.
- Preserve one moving `testflight/last-released` marker; no other durable release ref is introduced.
- Preserve `project.yml` as read-only version truth and do not alter app/package/product interfaces.
- Preserve all unrelated regression assertions; add red-first coverage without deleting or weakening baseline signing/profile/security checks.

## Removed Behaviour

- **RB-001**: Remove manual-only TestFlight publication; successful eligible `CI` push runs on `main` now trigger automatically while manual dispatch remains. **Authority**: DEC-027-001 and the MY-1766 Owner decision, superseding 026's manual-only non-goal.
- **RB-002**: Remove moving-`main` substitution for automatic release; the exact successful CI SHA is authoritative. **Authority**: DEC-027-001.
- **RB-003**: Remove force's ability to bypass the current successful-marker protection; force bypasses only path relevance and cannot release a candidate equal to or already covered by `testflight/last-released`. **Authority**: DEC-027-003/005 and delegated Owner decision `01a13b86-1ed5-7b57-b69a-3deaa4299249`.
- **RB-004**: Remove the manual default's ability to treat every fresh SHA as releasable without app-path classification; automatic and `force=false` manual runs use the accumulated marker range, while bounded `force=true` retains the explicit relevance-only override. **Authority**: DEC-027-002/005.
- **RB-005**: Remove best-effort continuation for release-critical internal-group distribution and dSYM publication failures; those phases fail closed before the final marker step. **Authority**: DEC-027-006 and the original fail-closed Owner requirement.
- **RB-006**: Remove hardcoded Fastlane marketing-version selection as an independent source; the lane receives the value resolved from uniform `project.yml` targets plus the exact candidate-PR label decision. **Authority**: DEC-027-004.
- **RB-007**: Remove per-upload Owner confirmation from 026; explicit Owner approval is required for the `.github/**` implementation PR, after which eligible uploads are automatic. **Authority**: the MY-1766 Owner decision and DEC-027-007.
- **RB-008**: Remove no existing test and weaken no unrelated signing/profile/security assertion; any additional deletion or weakening requires a new Owner decision. **Authority**: compatibility contract and Constitution Quality Bar A.

The marker-only Owner decision also supersedes unimplemented v1 planning for per-SHA claims, queue/cursor state, CAS/lease mutation, pending/resolved refs, recovery dispositions, distinct-SHA-only forward progress, and lifetime attempt prohibition. Those were never product-base behaviour. **Authority**: DEC-027-003/006 and delegated Owner decision `01a13b86-1ed5-7b57-b69a-3deaa4299249`.

## Scope

### In Scope

- Exact successful main-CI candidate capture and exact checkout.
- Single-marker bootstrap/order validation, accumulated relevance, bounded manual force, shared version/build policy, serialized critical lane, final marker update/readback, and safe evidence.
- Credential-free regression coverage plus post-merge production evidence.

### Out of Scope

- Any durable release state other than `testflight/last-released`.
- New workflow, secret, release service, runner, schedule, CODEOWNERS/ruleset/policy change, or per-upload Owner prompt.
- `project.yml`, generated project, app/package/test/Prototype source, Developer Portal changes, or a fourth implementation path.
- Real upload during planning/pre-merge verification.

## Success Criteria

- **SC-001**: Credential-free tests cover exact source/SHA, empty-tree bootstrap, marker ancestry/equality/stale/divergence, accumulated irrelevant→relevant ranges, relevant failure→later pickup, path matrices, concurrency, bounded force, version policy, final marker ordering, and safe summaries.
- **SC-002**: Focused unittest, Ruby syntax, full RepoInfra output, and whitespace check report zero failures/errors when their full output is read.
- **SC-003**: The first eligible successful production candidate produces one successful TestFlight workflow run whose exact SHA, URL, marketing version, unique build number, and confirmed final marker are recorded on MY-1766.
- **SC-004**: Static/test evidence proves no marker mutation command can execute before every earlier critical phase succeeds and terminal success requires exact marker readback.
- **SC-005**: Excluded-only automatic ranges produce no archive/upload or durable skip state; the next relevant candidate sees accumulated changes, while manual force bypasses only relevance.
- **SC-006**: Every tested critical failure stops, records safe evidence, initiates no pre-final marker mutation, automatic retry, rollback, or auxiliary state; later merge/manual pickup is a fresh evaluation.
- **SC-007**: The implementation diff is exactly the three authorized RepoInfra paths, gets exact content review, required checks, and explicit Owner approval before merge.

## Assumptions

- This workflow is the sole authorized automated writer of `testflight/last-released`; external/manual tag mutation is outside its serialization guarantee and is handled by the next run's fail-closed relation check.
- Protected PR-only `main` normally yields exactly one merged PR for the candidate. Zero/multiple matches remain a designed failure.
- Empty-tree bootstrap is computational only and creates no durable state.
- Candidate-associated PR alone controls `release:minor`, even when the accumulated range contains earlier PRs.
- No local `xcodebuild` or package build is warranted for a RepoInfra-only implementation diff.
