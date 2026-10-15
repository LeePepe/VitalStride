---
description: "Layer-scoped task graph for TestFlight per-call SIGH_NAME capture"
---

# Tasks: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Input**: `specs/028-testflight-sigh-name/`
**Layer**: dependency-free `RepoInfra`
**Scheduling**: Team Lead only, after exact-revision planning PASS

## Phase 1: User Story 1 - Repair the profile handoff (Priority: P1)

**Goal**: App and widget archive/export consume their own real per-call Fastlane profile names and retain every pre-archive safety guard.

**Independent Test**: The real-action Ruby fixture fails on the product base and passes after the narrow Fastfile repair without Apple access.

- [ ] T001 [US1] Add the real-action red regression and repair per-call profile-name capture in `scripts/tests/test_testflight_packaging.rb` and `fastlane/Fastfile`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Quality Bars A and I |
| Vertical slice | US1 |
| Files in scope | `fastlane/Fastfile`; new `scripts/tests/test_testflight_packaging.rb` |
| Read-only compatibility surfaces | `scripts/test-repoinfra.sh`; `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml`; `project.yml`; generated project; all product/package/test trees; existing RepoInfra tests |
| Files out of scope | Every other path, including workflows, project/generated output, app/packages/Prototype, entitlements, identities, secrets, keychains, rulesets, review policy, and release state |
| Interface impact | Internal only: each target neutralizes both stale-capable name locations, then captures the real scalar shared name at its exact action boundary; no public or workflow interface change |
| Task-local acceptance | Add the fixture before production edits and record the red base. The fixture dynamically resolves Homebrew formula Ruby/Fastlane, loads real Fastlane/Sigh and the real Fastfile, and replaces only `Sigh::Manager.start` plus unrelated credential/build/upload boundaries. Production neutralizes both `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME` before every real call and captures immediately afterward. The fixture proves two distinct calls/UUIDs and scalar overwrite; separately seeds both stale locations so missing app output fails as app before widget/build work and valid app capture followed by missing widget output fails as widget before build; rejects action stubs/fabricated keys/fallbacks; and proves blank/equal failure, shell-safe target mapping, and exact archive/export variable reuse. Preserve both forced installed fetches and every unrelated lane/test behavior. |
| Verification | From repo root on a declared supported executor: `GEM_PATH="$(brew --prefix fastlane)/libexec" "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb`; `ruby -c fastlane/Fastfile`; `git diff --check`; exact two-path T001 manifest and zero diff on read-only surfaces. Read the focused output and require both stale-seeded target cases plus the real-action positive cases to report zero failures/errors. |
| Blocking edges | None; blocks T002 |

**Checkpoint**: US1 is independently demonstrable without credentials or external mutation.

## Phase 2: User Story 2 - Make regression mandatory (Priority: P1)

**Goal**: Every RepoInfra gate run loads the real Fastlane/Sigh regression and fails closed if the runtime or contract is unavailable.

**Independent Test**: The complete RepoInfra gate invokes the Ruby fixture and finishes with zero failures/errors on the supported executor while every existing assertion remains active.

- [ ] T002 [US2] Add the minimal mandatory Ruby-test invocation to `scripts/test-repoinfra.sh`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Quality Bars I and J |
| Vertical slice | US2 |
| Files in scope | `scripts/test-repoinfra.sh` |
| Read-only inputs | T001's `scripts/tests/test_testflight_packaging.rb`; dynamically resolved Homebrew Fastlane formula and formula Ruby (observed supported versions: CI 2.238.0, release host 2.241.0) |
| Files out of scope | T001 source repair; `.github/workflows/ci.yml`; all other tests/scripts/workflows/product/project paths; dependency manifests and version pins |
| Interface impact | Repository-test entrypoint only; no product or release interface change |
| Task-local acceptance | The existing Python/shell/Kimi checks remain unchanged and active. The Ruby regression runs exactly once through the RepoInfra entrypoint using the same dynamically resolved `brew --prefix fastlane`/`brew --prefix ruby`, formula-Ruby, and Fastlane-`libexec` invocation as T001. Ambient `/usr/bin/ruby`, hard-coded ARM/Intel prefixes, dependency installation, and workflow edits are forbidden. Missing Homebrew/formula runtime or real Fastlane/Sigh fails rather than skips; no network, credential, signing, upload, workflow, or marker action occurs. |
| Verification | From repo root on a declared supported executor: `bash scripts/test-repoinfra.sh`; inspect full output and require exactly one Ruby fixture invocation plus every existing suite to report zero failures/errors; confirm the logged/resolved runtime is formula Ruby with the active Fastlane formula rather than ambient system Ruby; `git diff --check`; exact one-path T002 manifest |
| Blocking edges | Depends on T001; blocks T003 |

**Checkpoint**: US2 is enforced by the existing PR-time RepoInfra gate with no CI workflow edit.

## Phase 3: Delivery verification - Freeze, review, and publish the exact candidate

- [ ] T003 [US2] Freeze and verify `fastlane/Fastfile`, `scripts/tests/test_testflight_packaging.rb`, and `scripts/test-repoinfra.sh`, obtain exact AI Reviewer content PASS and publication permission, publish only the unchanged tree, and hand the published SHA to PR Manager

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | RepoInfra delivery verification; no source-repair ownership |
| Read-only implementation paths | The exact T001/T002 three-path candidate |
| Allowed outputs | Frozen tree/manifest and test output; exact content verdict/permission; commit/push/non-Draft PR metadata; local/remote/PR identity proof; PR Manager handoff |
| Files out of scope | Any source repair in T003; TestFlight dispatch/upload; credentials/signing/profile/keychain output; unrelated cleanup |
| Interface impact | None |
| Task-local acceptance | Stage A runs all T001/T002 verification, freezes the uncommitted candidate, proves only three paths changed, and obtains exact AI Reviewer PASS plus publication permission. Any content change returns to T001 or T002 and Stage A. Stage B commits/pushes only the unchanged tree, creates or updates one non-Draft owner-gated PR, proves reviewed tree = commit tree and local HEAD = remote branch OID = PR headRefOid, then hands the same SHA to PR Manager. |
| Verification | Fresh T001/T002 command outputs; frozen manifest; exact verdict; unchanged-tree proof; three-way SHA proof; verified PR Manager handoff run |
| Blocking edges | Depends on T001 and T002; PR Manager/Owner gates block merge; T004 waits for merge |

## Phase 4: User Story 3 - Post-merge production outcome (Priority: P1)

- [ ] T004 [US3] After PR Manager reports the reviewed repair merged to `main`, observe the qualifying automatic TestFlight workflow for the exact merged head and record its outcome on MY-1815

### T004 metadata

| Field | Contract |
|---|---|
| Owner | Team Lead operational evidence collection; not a Fullstack source task |
| Files in scope | Read-only observation of the existing automatic `.github/workflows/testflight.yml` run; no repository edit or release dispatch |
| Files out of scope | Any TestFlight dispatch; manual `force=true`; duplicate upload; workflow/Fastfile/source repair; secret/profile/certificate/keychain disclosure; unrelated release-policy change |
| Interface impact | None; exercises reviewed behavior on `main` |
| Task-local acceptance | The qualifying run source is `automatic-ci`; its `workflow_run.head_sha`, gate candidate, and run head all equal the exact merged `main` revision; existing workflow policy is unchanged; terminal result, marker/result state, and uploaded build number are recorded. Failure or missing qualifying automatic proof keeps MY-1815 open with exact evidence and is not replaced by a manual run. No release is dispatched. A manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers that exact SHA; `force=true` is forbidden. |
| Verification | Actions run URL; automatic source; exact merged SHA = workflow-run head = gate candidate = run head; terminal conclusion; marker/result state; uploaded TestFlight build number; no sensitive attachment and no duplicate dispatch |
| Blocking edges | Depends on T003, passing exact-candidate review, Owner-gated PR merge, and PR Manager delivery evidence |

## Dependency Graph

```text
T001 RepoInfra repair + real-action regression
  -> T002 mandatory RepoInfra gate wiring
       -> T003 frozen review, unchanged publication, PR Manager handoff
            -> PR Manager + Owner-gated merge
                 -> T004 Team Lead observes qualifying automatic TestFlight outcome
```

- No implementation task is parallel: T002 consumes T001's real-action fixture, and T003 consumes the complete candidate.
- T003 findings return to T001 or T002; T003 never edits source.
- T004 is read-only operational proof and never authorizes a release dispatch, duplicate upload, source change, or workflow change.
- Planner Lead and AI Reviewer do not assign or start implementation.

## Acceptance Traceability

| Active identifiers | Task | Evidence surface |
|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC5, US1/AC6, US1/AC7; FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-016; RB-001, RB-002, RB-003 | T001, T003 | real action/actual lane fixture, two-source pre-call neutralization, stale-seeded target-specific failures, target-correct build/export capture, source prohibition |
| US2/AC1, US2/AC2, US2/AC5; FR-008, FR-009, FR-010, FR-011 | T001, T003 | real Fastlane/Sigh loading through formula runtime, two-call overwrite/provenance proof, UUID non-use, fabricated-key prohibition |
| US2/AC3, US2/AC4; FR-012, FR-013, FR-014; RB-004 | T002, T003 | same-invocation mandatory RepoInfra execution, preserved existing suites and compatibility surfaces |
| US3/AC1, US3/AC2, US3/AC3, US3/AC4; FR-015, FR-017; RB-005 | T004 | qualifying merged-main automatic run identity, terminal result, marker/result, uploaded build number, no duplicate dispatch |
| SC-001, SC-002, SC-003, SC-004 | T001, T002, T003 | red/green focused regression, syntax, complete gate, diff/path evidence, exact content review |
| SC-005 | T003, T004 | owner-gated merge and production outcome record |

## Completion Conditions

- Every active acceptance identifier maps above.
- T001 and T002 each have one layer, exact paths, exclusions, runnable verification, and no unresolved decision.
- The full candidate changes exactly three implementation paths.
- No TestFlight action occurs before reviewed merge.
- MY-1815 completes only after Team Lead records the qualifying automatic post-merge run and uploaded build number for the exact merged SHA, with no duplicate dispatch.
