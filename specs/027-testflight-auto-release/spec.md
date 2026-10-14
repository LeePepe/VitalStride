# Feature Specification: Minimal automatic TestFlight release after main CI

**Planning version**: v3
**Target**: VitalStride `main`
**Product base**: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`
**Supersedes planning revision**: `73dd9ffd2f7cb1980cbe986d0ea9cd3442ecff85`
**Authority**: 2026-10-15 Lead direction `01a13cc2-e475-758b-b825-a9f622ca117a` and Team Lead handoff `01a13cc7-9937-74fb-bdc7-4f9a10aaa98d`

## Intent

After the repository's `CI` workflow succeeds for a push to `main`, evaluate the verified `workflow_run.head_sha` against the changes accumulated since `testflight/last-released`. If the range contains an accepted app path, invoke the existing release lane to build and upload TestFlight, then move the sole marker only after that upload succeeds.

This version deliberately specifies the smallest accepted shape. It does not redesign the release lane, version policy, signing, secret handling, recovery, or production-observation process.

## Owner decisions

- **DEC-027-001 — Verified automatic candidate**: automatic evaluation starts only from a completed, successful `workflow_run` for workflow `CI`, event `push`, branch `main`; the candidate is that run's `head_sha`.
- **DEC-027-002 — Accumulated relevance**: automatic relevance is the accepted-path result of `git diff testflight/last-released..head_sha`. The marker must resolve as a commit ancestor of the candidate; otherwise the run fails closed before release.
- **DEC-027-003 — Existing lane**: the existing release lane remains responsible for build and upload. This feature adds orchestration around it, not a second lane or a lane redesign.
- **DEC-027-004 — Sole success marker**: `testflight/last-released` is the only durable release state and is advanced to the candidate only after the existing lane reports successful upload. Any earlier failure leaves it unchanged. There is no automatic retry or rollback.
- **DEC-027-005 — Minimal serialization and permission**: one app-scoped concurrency group uses `cancel-in-progress: false`; the release job has job-level `contents: write` and no broader GitHub permission.
- **DEC-027-006 — Narrow feature verification with mandatory repository gate**: feature-specific verification consists only of classifier unit tests and workflow lint. The repository-mandated `bash scripts/test-repoinfra.sh` remains a separate, non-waivable RepoInfra gate whose full output must report no failure/error. No shadow-policy, release-policy mirror, Ruby-only, upload, tag-mutation, or production-run suite is added by this feature.
- **DEC-027-007 — Ownership boundary**: the implementation ceiling remains `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `scripts/tests/test_testflight_freshness.py`. The expected minimal patch changes only the workflow and classifier test; `fastlane/Fastfile` is a read-only compatibility surface unless an independently approved revision proves a necessary in-ceiling edit. Any merge containing `.github/**` still requires explicit Owner approval; AI review and CI do not substitute.

## Existing behaviour

At the product base:

- `.github/workflows/testflight.yml` is manually dispatched and runs the existing Fastlane release lane on the `self-hosted` / `vitalstride-mac` runner.
- `fastlane/Fastfile` owns the established archive/upload behaviour, build-number selection, processing/distribution behaviour, and existing signing/secret integrations.
- `testflight/last-released` is the existing release marker.
- `scripts/tests/test_testflight_freshness.py` is the credential-free regression surface for workflow classification.
- Repository release documentation and the workflow already define signing, App Store Connect secrets, telemetry inputs, and safe-log boundaries.

## Compatibility

- Preserve the existing release lane's build/upload call and all unaffected signing, profiles, keychain, App Store Connect, telemetry, runner-label, and non-secret logging behaviour.
- Add no secret, service, workflow, runner, schedule, source/package/app change, project configuration edit, CODEOWNERS edit, or ruleset edit.
- Preserve the existing manual entry point as baseline compatibility; v3 adds no manual-force acceptance contract and does not require a manual-policy test matrix.
- Preserve the accepted app-path predicates below and treat unlisted paths as irrelevant to automatic release.
- Preserve a single delivery goal and a single implementation PR.

## Removed behaviour

The following are removed from active v3 planning by DEC-027-001 through DEC-027-007 and the cited Lead/Team Lead authority:

- v2 candidate-PR lookup, `release:minor`, project-version parsing, runtime marketing-version handoff, and build-number shadow assertions;
- v2 bounded manual-force acceptance and its cross-source policy matrix;
- v2 empty-tree bootstrap, already-covered/ahead taxonomy, exact readback protocol, critical-phase shadow model, safe-summary schema, and post-merge production-evidence task;
- v2 Fastfile modification requirement, Ruby-only feature gate, and broad signing/profile/telemetry shadow-policy tests; the mandatory repository-level RepoInfra gate remains unchanged;
- any CAS/lease boundary, per-SHA attempt/skip state, queue, cursor, journal, pending/resolved state, recovery ref, automatic retry, or rollback.

These removals supersede planning requirements, not unrelated product-base behaviour. Existing lane internals remain compatible unless the minimal contract directly requires a workflow orchestration change.

## User story 1 — Release relevant verified main changes (P1)

As the repository owner, I want one automatic TestFlight run after successful main CI when changes since the last successful release affect accepted app paths, so verified changes can use the existing release lane without auxiliary release state.

### Acceptance scenarios

- **US1/AC1 — Exact source and candidate**: a completed `CI` workflow with conclusion `success`, source event `push`, and head branch `main` proceeds using exactly its verified `head_sha`; any other workflow, conclusion, event, or branch does not enter the release lane.
- **US1/AC2 — Accumulated relevance**: with `testflight/last-released` resolving to an ancestor commit, the classifier evaluates the NUL-safe change records for `marker..candidate`; any accepted path makes the range relevant and an all-irrelevant range skips the lane.
- **US1/AC3 — Existing lane and success marker**: a relevant range invokes the existing release lane once. Only after its upload succeeds may the workflow move `testflight/last-released` to the candidate.
- **US1/AC4 — Failure boundary**: source, marker, diff, classification, build, or upload failure does not run the marker-update step. The run fails without automatic retry or rollback.
- **US1/AC5 — Concurrency and permission**: the release job uses one stable app-scoped concurrency group with `cancel-in-progress: false` and declares job-level `contents: write`.
- **US1/AC6 — Minimal state and scope**: the workflow creates no auxiliary durable release state and the implementation remains inside the three-path ceiling, with explicit Owner approval required for the workflow change.

## App relevance

Change records are parsed NUL-safely. For rename/copy records, either endpoint may qualify. A relevant deletion qualifies. A mixed range qualifies when at least one record is relevant.

Positive shipped paths are:

- `Packages/*/Package.swift`, `Packages/*/Sources/**`, `Packages/*/Plugins/**`
- `VitalStride/Sources/**`, `VitalStride/Resources/**`, `VitalStride/Assets.xcassets/**`, `VitalStride/*.entitlements`
- `VitalStrideMac/Sources/**`, `VitalStrideMac/Resources/**`, `VitalStrideMac/Assets.xcassets/**`, `VitalStrideMac/*.entitlements`
- `VitalStrideWatch Watch App/Sources/**`, `VitalStrideWatch Watch App/Resources/**`, `VitalStrideWatch Watch App/Assets.xcassets/**`, `VitalStrideWatch Watch App/*.entitlements`
- `VitalStrideWidgets/**/*.swift`, `VitalStrideWidgets/**/*.plist`, `VitalStrideWidgets/**/*.entitlements`, `VitalStrideWidgets/**/*.xcassets/**`
- exact `project.yml`, `fastlane/Fastfile`, and `fastlane/Appfile`

Documentation/context, specs, package/app tests, `Prototype/**`, generated project output, `.github/**`, CI-only scripts, and every unlisted path are irrelevant by themselves. Exclusion wins for an endpoint before positive matching.

## Functional requirements

- **FR-001**: The automatic trigger MUST be a completed successful `workflow_run` for `CI`, source event `push`, and head branch `main`.
- **FR-002**: Every automatic checkout, diff, lane invocation, and marker target MUST use the same verified `workflow_run.head_sha`.
- **FR-003**: The workflow MUST fetch enough history and tags to resolve `testflight/last-released` and evaluate `testflight/last-released..candidate`.
- **FR-004**: A missing, unreadable, non-commit, non-ancestor, or otherwise invalid marker MUST fail closed before the release lane.
- **FR-005**: Relevance MUST use the accepted predicates and NUL-safe add/modify/delete/rename/copy handling defined above.
- **FR-006**: An irrelevant accumulated range MUST skip the release lane and MUST NOT mutate the marker.
- **FR-007**: A relevant range MUST call the existing release lane for build and upload without introducing a second release implementation.
- **FR-008**: The marker-update step MUST be ordered after successful upload and MUST target the exact candidate.
- **FR-009**: Failure before marker update MUST leave the marker unchanged; the workflow MUST configure no automatic retry or rollback.
- **FR-010**: The release job MUST declare job-level `contents: write`, one app-scoped concurrency group, and `cancel-in-progress: false`.
- **FR-011**: The workflow MUST create no per-SHA state, queue, cursor, CAS/lease, journal, pending/resolved state, or recovery ref.
- **FR-012**: Existing lane signing, secrets, runner, telemetry, and safe-log behaviour MUST remain compatible.
- **FR-013**: Feature-specific verification MUST be limited to classifier unit tests and workflow lint; neither may contact GitHub for writes, App Store Connect, signing services, or TestFlight. Separately, the mandatory repository-level `bash scripts/test-repoinfra.sh` gate MUST run with full output inspected and no failure/error.
- **FR-014**: Implementation MUST remain within the three-path ceiling, and `.github/workflows/testflight.yml` MUST receive explicit Owner approval before merge.

## Requirements by compatibility class

- **RB-001 — Preserve**: existing release lane and manual entry point remain available.
- **RB-002 — Preserve**: signing, secret, runner, telemetry, and safe-log boundaries remain unchanged.
- **RB-003 — Change**: add verified successful-main automatic orchestration and accumulated relevance.
- **RB-004 — Change**: advance the sole marker only after successful upload.
- **RB-005 — Remove from v3**: heavier v2 version/manual/recovery/shadow-policy and production-evidence contracts are not implementation requirements.
- **RB-006 — Protect**: three-path ceiling and explicit Owner approval remain mandatory.

## Success criteria

- **SC-001**: Classifier unit tests pass for source guards, exact candidate reuse, accepted-path positives, exclusions, mixed/deletion/rename/copy records, and marker-range skip/release/failure decisions.
- **SC-002**: Workflow lint passes for `.github/workflows/testflight.yml`.
- **SC-003**: The mandatory `bash scripts/test-repoinfra.sh` gate reports no failure/error when full output is read, and static delivery evidence shows the candidate diff stays within the three-path ceiling, uses one non-cancelling concurrency group, has job-level `contents: write`, orders marker update after the existing lane, and contains no auxiliary state/retry/rollback implementation.
- **SC-004**: The frozen candidate is committed, pushed, and published as the single non-Draft PR; local `HEAD`, remote branch OID, and PR `headRefOid` are proven identical before exact-candidate review, then re-proven after PASS before the same SHA is handed to PR Manager. Explicit Owner approval remains a separate pre-merge requirement.

## Out of scope

- Running or observing a real TestFlight upload, mutating a production marker during verification, or requiring a first-production-run record.
- Redesigning or shadow-testing Fastlane versioning, build-number, signing, processing, distribution, dSYM, telemetry, or secret behaviour.
- Manual-force product policy, candidate PR/label lookup, marketing-version policy, or repository version edits.
- Auxiliary release state, custom queuing, CAS/lease semantics, recovery workflows, retry, or rollback.
- Any fourth implementation path or any app/package/Prototype/project/ruleset/CODEOWNERS change.

## Evidence required for readiness

- Exact planning revision, tree, artifact paths, and blob SHAs with independent AI Reviewer verdict.
- Reconciled task graph and child rows, kept parked until Team Lead schedules implementation.
- Safe reuse instructions for the preserved Fullstack candidate; Planner Lead does not mutate that workspace.
