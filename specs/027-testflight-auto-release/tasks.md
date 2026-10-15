# Tasks: Minimal automatic TestFlight release after main CI

**Planning version**: v3
**Layer**: dependency-free `RepoInfra`
**Implementation ceiling**: `.github/workflows/testflight.yml`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`
**Expected changed paths**: workflow and classifier test only
**Scheduling**: Team Lead only, after exact-revision planning PASS

## T001 — Minimal workflow and classifier implementation

- [ ] T001 [US1] Add classifier-first coverage and implement the verified-main automatic gate, accumulated marker-range relevance, existing-lane invocation, and upload-success marker ordering.

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Files in scope | `.github/workflows/testflight.yml`; `scripts/tests/test_testflight_freshness.py` |
| Read-only compatibility path | `fastlane/Fastfile` |
| Files out of scope | Every other path, including any fourth implementation path, app/package/AppUI/Prototype/project/generated/policy/CODEOWNERS/ruleset/secret/signing path |
| Interface impact | Adds successful `CI` `workflow_run` automation; automatic candidate is exact `head_sha`; classifies `testflight/last-released..candidate`; invokes existing lane; updates sole marker after upload |
| Required permission/concurrency | Job-level `contents: write`; one stable app-scoped group; `cancel-in-progress: false` |
| Forbidden state/behavior | Per-SHA records, second marker, queue/cursor, CAS/lease, journal, pending/resolved/recovery state, automatic retry, rollback, second lane |
| Compatibility | Preserve manual entry point and existing Fastlane signing, secrets, version/build, runner, telemetry, and safe-log behavior without shadow-policy tests |
| Feature-specific verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `actionlint .github/workflows/testflight.yml` |
| Mandatory repository gate | From repo root: `bash scripts/test-repoinfra.sh`; read full output and require zero failures/errors |
| Blocking edge | No predecessor; blocks T002 |

### T001 acceptance

- Red-first classifier cases demonstrate the base lacks exact automatic source/candidate and accepted-range behavior before production edits.
- Only completed successful `CI` / `push` / `main` input enters the automatic lane; checkout, diff, lane, and marker target reuse exactly one `head_sha`.
- The marker must resolve as a candidate ancestor; invalid/missing marker fails closed.
- Classifier cases cover the exact positive roots, endpoint-first exclusions, docs, package tests/contexts, mixed records, deletion, and rename/copy endpoints.
- Widget positives separately exercise `VitalStrideWidgets/**/*.swift`, `VitalStrideWidgets/**/*.plist`, `VitalStrideWidgets/**/*.entitlements`, and `VitalStrideWidgets/**/*.xcassets/**`; matching suffixes outside `VitalStrideWidgets/**` remain negative unless another accepted predicate qualifies.
- Entitlement coverage proves `VitalStride/*.entitlements`, `VitalStrideMac/*.entitlements`, and `VitalStrideWatch Watch App/*.entitlements` are root-only positives, with one nested-entitlement negative case under each app root.
- An irrelevant range skips without state mutation; a later candidate still sees the accumulated range.
- A relevant range calls the existing `fastlane ios beta` lane. Marker update is unreachable until lane/upload success and targets the candidate.
- Failures before marker update leave the marker unchanged. No automatic retry/rollback or auxiliary durable state is added.
- The implementation changes only the workflow and classifier test. A need to edit Fastfile blocks and returns to Team Lead/Planner rather than expanding T001.

## T002 — Frozen candidate publication, exact review, and PR Manager handoff

- [ ] T002 [US1] Freeze and verify the complete two-path candidate; commit, push, and publish it as the single non-Draft PR; prove local `HEAD` = remote branch OID = PR `headRefOid`; request exact-candidate review for that published SHA; after PASS, re-prove identity and hand the same SHA to PR Manager.

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` delivery verification; no source-repair ownership |
| Read-only implementation paths | `.github/workflows/testflight.yml`; `scripts/tests/test_testflight_freshness.py`; verify `fastlane/Fastfile` unchanged |
| Allowed outputs | Frozen manifest/revision/tree; classifier-test, workflow-lint, and mandatory RepoInfra outputs; commit/push/non-Draft PR metadata; pre-review and post-PASS three-way identity proofs; exact review and PR Manager handoff evidence |
| Files out of scope | Any source repair in T002; fourth path; Fastfile edit; real dispatch/upload/tag mutation; secret/signing output; Owner-approval substitution |
| Feature-specific verification | From repo root, only `python3 -B -m unittest scripts.tests.test_testflight_freshness` and `actionlint .github/workflows/testflight.yml` |
| Mandatory repository gate | From repo root: `bash scripts/test-repoinfra.sh`; read full output and require zero failures/errors |
| Delivery sequence | Freeze/check → commit/push/create-or-update one non-Draft PR → prove local/remote/PR SHA identity → exact review of that published SHA → after PASS re-prove identity → hand the same SHA to PR Manager |
| Owner gate | Explicit Owner approval for `.github/workflows/testflight.yml` remains separately required before merge; AI review and CI cannot substitute |
| Blocking edge | Depends on T001; after PASS and identity re-proof, PR Manager owns required checks/merge |

### T002 acceptance

- Fresh classifier tests and workflow lint both report success; the separate mandatory RepoInfra gate also reports zero failures/errors when its full output is read. All outputs are retained.
- Candidate manifest contains exactly the workflow and classifier-test paths, while `fastlane/Fastfile` is unchanged.
- Static candidate inspection records exact `head_sha` reuse, accepted marker range, one non-cancelling group, job-level `contents: write`, existing-lane call, post-upload marker ordering, and absence of auxiliary state/retry/rollback.
- The frozen candidate is committed, pushed, and published in the single non-Draft PR before review; local `HEAD`, remote branch OID, and PR `headRefOid` are identical before the exact-candidate request.
- Independent content review binds to that published SHA. A finding returns content repair to T001; any change produces a fresh SHA that must be republished, identity-proven, and reviewed.
- After PASS, local `HEAD`, remote branch OID, and PR `headRefOid` are re-proven equal to the reviewed SHA before that same SHA is handed to PR Manager.
- AI review and CI do not satisfy the explicit Owner approval required for the workflow. PR Manager owns required-check and merge state.

## Dependency graph

```text
T001 minimal workflow + classifier implementation
  -> T002 freeze/check + publish non-Draft PR + three-way identity proof + exact review + post-PASS identity re-proof
       -> PR Manager
```

- No task is parallel because T002 consumes T001's frozen candidate.
- T002 findings return to T001; T002 does not repair source.
- No v3 task owns production workflow execution or outcome evidence.
- Team Lead schedules both rows; this plan starts neither.

## Existing child reconciliation after planning PASS

| Existing child | v3 disposition |
|---|---|
| MY-1772 / old T001 | Retain as v3 T001; replace v2 planning pin, title, outcome, scope, acceptance, verification, and dependency |
| MY-1773 / old T002 | Retain as v3 T002; replace version/Fastfile work with frozen-candidate verification/publication/identity/review/handoff |
| MY-1774 / old T003 | Cancel as superseded by the minimal-shape decision; manual-force slice removed |
| MY-1775 / old T004 | Cancel as superseded; its minimal candidate-publication/review/handoff responsibility moves into v3 T002 |
| MY-1776 / old T005 | Cancel as superseded; production-success evidence is no longer a v3 gate |

All five rows remain parked while planning is under review. Reconciliation occurs only after exact-revision PASS and does not assign or start implementation.

## Acceptance traceability

| Active identifiers | Task | Evidence surface |
|---|---|---|
| US1/AC1; FR-001, FR-002; RB-003 | T001, T002 | source-guard/exact-candidate classifier cases; frozen workflow inspection |
| US1/AC2; FR-003, FR-004, FR-005, FR-006 | T001, T002 | marker-range and exact path classifier matrices |
| US1/AC3; FR-007, FR-008; RB-001, RB-004 | T001, T002 | existing-lane call and post-upload marker ordering |
| US1/AC4; FR-004, FR-009, FR-011 | T001, T002 | fail-closed cases and absence of auxiliary state/retry/rollback |
| US1/AC5; FR-010 | T001, T002 | workflow lint and static candidate evidence |
| US1/AC6; FR-011, FR-014; RB-006 | T001, T002 | two-path manifest, three-path ceiling, review and Owner gate |
| FR-012; RB-002 | T001, T002 | unchanged Fastfile and preserved workflow compatibility surfaces |
| FR-013; RB-005 | T001, T002 | exactly two feature-specific checks plus the unchanged mandatory RepoInfra repository gate; removed-suite absence |
| SC-001 | T001, T002 | classifier unit-test output |
| SC-002 | T001, T002 | `actionlint` output |
| SC-003 | T002 | full mandatory RepoInfra output, frozen manifest, and static delivery evidence |
| SC-004 | T002 | pre-review published-SHA identity, exact review, post-PASS identity re-proof/PR Manager handoff, explicit Owner approval |

## Completion conditions

- The implementation diff remains exactly two paths inside the three-path ceiling.
- Only the classifier unit tests and workflow lint are feature-specific checks; `bash scripts/test-repoinfra.sh` remains the separate mandatory repository gate.
- Every active US/AC, FR, RB, and SC identifier maps above.
- Exact content review is invalidated by any candidate content change.
- Explicit Owner approval remains required for the workflow before merge.
- No upload, marker mutation, or production-success evidence is required to complete the v3 implementation task graph.
