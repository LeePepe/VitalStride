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
| Interface impact | Internal only: each target captures the real scalar shared name at its action boundary; no public or workflow interface change |
| Task-local acceptance | Add the fixture before production edits and record the red base. The fixture loads real Fastlane/Sigh and the real Fastfile, replaces only `Sigh::Manager.start` plus unrelated credential/build/upload boundaries, proves two distinct calls/UUIDs and scalar overwrite, rejects action stubs/fabricated keys/fallbacks, proves immediate capture, missing/blank/equal pre-build failure, shell-safe target mapping, and exact archive/export variable reuse. Preserve both forced installed fetches and every unrelated lane/test behavior. |
| Verification | From repo root: `GEM_PATH="$(brew --prefix fastlane)/libexec" "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb`; `ruby -c fastlane/Fastfile`; `git diff --check`; exact two-path T001 manifest and zero diff on read-only surfaces |
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
| Read-only inputs | T001's `scripts/tests/test_testflight_packaging.rb`; installed Homebrew Fastlane/Ruby environment |
| Files out of scope | T001 source repair; `.github/workflows/ci.yml`; all other tests/scripts/workflows/product/project paths; dependency manifests and version pins |
| Interface impact | Repository-test entrypoint only; no product or release interface change |
| Task-local acceptance | The existing Python/shell/Kimi checks remain unchanged and active; the Ruby regression runs exactly once through the RepoInfra entrypoint; missing Fastlane/Sigh fails rather than skips; no network, credential, signing, upload, workflow, or marker action occurs. |
| Verification | From repo root: `bash scripts/test-repoinfra.sh`; inspect full output and require the Ruby fixture plus every existing suite to report zero failures/errors; `git diff --check`; exact one-path T002 manifest |
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

- [ ] T004 [US3] After PR Manager reports the reviewed repair merged to `main`, rerun the existing manual TestFlight workflow and record the outcome on MY-1815

### T004 metadata

| Field | Contract |
|---|---|
| Owner | Team Lead operational validation; not a Fullstack source task |
| Files in scope | Execution-only use of the existing `.github/workflows/testflight.yml`; no repository edit |
| Files out of scope | Any pre-merge dispatch; workflow/Fastfile/source repair; secret/profile/certificate/keychain disclosure; unrelated release-policy change |
| Interface impact | None; exercises reviewed behavior on `main` |
| Task-local acceptance | Run head is the merged `main` revision; existing workflow policy is unchanged; terminal result and uploaded build number are recorded. Failure keeps MY-1815 open with the exact failed step. |
| Verification | Actions run URL/head SHA, terminal conclusion, uploaded TestFlight build number; no sensitive attachment |
| Blocking edges | Depends on T003, passing exact-candidate review, Owner-gated PR merge, and PR Manager delivery evidence |

## Dependency Graph

```text
T001 RepoInfra repair + real-action regression
  -> T002 mandatory RepoInfra gate wiring
       -> T003 frozen review, unchanged publication, PR Manager handoff
            -> PR Manager + Owner-gated merge
                 -> T004 Team Lead TestFlight outcome
```

- No implementation task is parallel: T002 consumes T001's real-action fixture, and T003 consumes the complete candidate.
- T003 findings return to T001 or T002; T003 never edits source.
- T004 is operational proof and never authorizes source or workflow changes.
- Planner Lead and AI Reviewer do not assign or start implementation.

## Acceptance Traceability

| Active identifiers | Task | Evidence surface |
|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC5; FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007; RB-001, RB-002, RB-003 | T001, T003 | real action/actual lane fixture, fail-closed cases, target-correct build/export capture, source prohibition |
| US2/AC1, US2/AC2; FR-008, FR-009, FR-010, FR-011 | T001, T003 | real Fastlane/Sigh loading, two-call overwrite proof, UUID non-use, fabricated-key prohibition |
| US2/AC3, US2/AC4; FR-012, FR-013, FR-014; RB-004 | T002, T003 | mandatory RepoInfra invocation, preserved existing suites and compatibility surfaces |
| US3/AC1, US3/AC2, US3/AC3; FR-015 | T004 | merged-main manual run URL, terminal result, uploaded build number |
| SC-001, SC-002, SC-003, SC-004 | T001, T002, T003 | red/green focused regression, syntax, complete gate, diff/path evidence, exact content review |
| SC-005 | T003, T004 | owner-gated merge and production outcome record |

## Completion Conditions

- Every active acceptance identifier maps above.
- T001 and T002 each have one layer, exact paths, exclusions, runnable verification, and no unresolved decision.
- The full candidate changes exactly three implementation paths.
- No TestFlight action occurs before reviewed merge.
- MY-1815 completes only after Team Lead records the post-merge uploaded build number.
