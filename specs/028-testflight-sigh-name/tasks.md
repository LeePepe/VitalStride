---
description: "Layer-scoped task graph for TestFlight per-call SIGH_NAME capture"
---

# Tasks: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Input**: `specs/028-testflight-sigh-name/`
**Layer**: dependency-free `RepoInfra`
**Scheduling**: Team Lead only, after exact-revision planning PASS

## Phase 1: User Story 1 - Repair the profile handoff (Priority: P1)

**Goal**: Preserve the merged production repair in which app and widget archive/export consume their own real per-call Fastlane profile names and retain every pre-archive safety guard.

**Independent Test**: Implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` contains the merged Fastfile repair and broad real-action fixture; resumed work proves the Fastfile is unchanged and revalidates all behavior without Apple access.

- [x] T001 [US1] Preserve the merged per-call profile-name repair and broad real-action regression at implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Quality Bars A and I |
| Vertical slice | US1 |
| Status / evidence | Completed by MY-1819 and normal merge PR #449 at `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`; not rescheduled or reopened |
| Merged paths | `fastlane/Fastfile`; `scripts/tests/test_testflight_packaging.rb` |
| Read-only compatibility surfaces for resumed work | `fastlane/Fastfile`; `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml`; `project.yml`; generated project; all product/package/test trees; existing RepoInfra tests |
| Files out of scope | Every other path, including workflows, project/generated output, app/packages/Prototype, entitlements, identities, secrets, keychains, rulesets, review policy, and release state |
| Interface impact | Internal only: each target neutralizes both stale-capable name locations, then captures the real scalar shared name at its exact action boundary; no public or workflow interface change |
| Task-local acceptance | The merged Fastfile neutralizes both `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME` before every real call and captures immediately afterward. The merged fixture loads real Fastlane/Sigh and the real Fastfile; replaces only `Sigh::Manager.start` plus unrelated credential/build/upload boundaries; proves distinct names/UUIDs and scalar overwrite; separately seeds both stale locations for target-specific missing-app/widget failures; rejects fabricated keys and UUID/name fallback; and proves blank/equal failure, shell-safe mapping, and archive/export reuse. Decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515` removes only T001's exact-2.238.0/independent-command executor premise; all substantive behavior becomes mandatory T002 compatibility. |
| Verification | T002/T003 rerun the revised real-action fixture and prove `git diff --exit-code 49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8...HEAD -- fastlane/Fastfile`; every substantive T001 case reports zero failures/errors through the resolved actual toolchain. |
| Blocking edges | Satisfied at the implementation base; T002 consumes this read-only baseline |

**Checkpoint**: US1 is independently demonstrable without credentials or external mutation.

## Phase 2: User Story 2 - Make regression mandatory (Priority: P1)

**Goal**: Every RepoInfra gate run uses the executor's actual unchanged-PATH Fastlane toolchain, loads the full real Fastlane/Sigh regression exactly once, and fails closed if the runtime or contract is unavailable or below the documented minimum.

**Independent Test**: The complete RepoInfra gate invokes the Ruby fixture and finishes with zero failures/errors on the supported executor while every existing assertion remains active.

- [ ] T002 [US2] Replace the exact-2.238.0 fixture bootstrap with resolve-actual-fastlane compatibility in `scripts/tests/test_testflight_packaging.rb` and make that fixture mandatory in `scripts/test-repoinfra.sh`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Quality Bars I and J |
| Vertical slice | US2 |
| Files in scope | `scripts/tests/test_testflight_packaging.rb`; `scripts/test-repoinfra.sh` |
| Read-only inputs | Merged T001 `fastlane/Fastfile` behavior at `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`; every substantive case already present in the Ruby fixture; executor's `fastlane` command from unchanged `PATH`; 2.238.0 as minimum-compatible evidence, not exact selection |
| Files out of scope | Any `fastlane/Fastfile` repair; `.github/workflows/ci.yml`; all other tests/scripts/workflows/product/project paths; dependency manifests; dependency install/version changes; PATH mutation/workaround; packaging-source/formula/architecture probes; alternate runtime/fallback; skip; hook bypass |
| Interface impact | Repository-test entrypoint only; no product or release interface change |
| Task-local acceptance | The fixture resolves `fastlane` from unchanged `PATH`, uses only the actual RubyGems toolchain selected/provided by that command, derives one version, and proves its CLI, corresponding gem, loaded library, and loaded Fastlane/Sigh action sources agree exactly. It rejects a version below 2.238.0 and fails closed for missing Fastlane, unparseable version, absent corresponding gem/library, mismatch, or load failure. All pre-existing real-action/per-call/stale/fabricated-key/UUID/blank/equal/shell/export cases remain active and unchanged in meaning. The existing shell/Python/Kimi checks remain active, and the RepoInfra entrypoint invokes the canonical fixture exactly once without duplicating a divergent version policy. No network, credential, signing, upload, workflow, or marker action occurs. |
| Verification | From repo root with unchanged `PATH`: `command -v fastlane`; `fastlane --version`; `ruby scripts/tests/test_testflight_packaging.rb`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check`. Inspect full output: actual resolved version is reported; it is at least 2.238.0; CLI/gem/loaded-library/source versions agree; real Fastlane/Sigh loads; every behavioral case and existing suite reports zero failures/errors; the full gate invokes the Ruby fixture exactly once. Prove exact two-path manifest relative to `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` and zero Fastfile/other-surface diff. |
| Blocking edges | Depends on T001; blocks T003 |

**Checkpoint**: US2 is enforced by the existing PR-time RepoInfra gate with no CI workflow edit.

## Phase 3: Delivery verification - Freeze, review, and publish the exact candidate

- [ ] T003 [US2] Freeze and verify the two-path T002 candidate, obtain exact AI Reviewer content PASS and publication permission, publish only the unchanged tree, and hand the published SHA to PR Manager

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | RepoInfra delivery verification; no source-repair ownership |
| Read-only implementation paths | The exact two-path candidate: `scripts/tests/test_testflight_packaging.rb` and `scripts/test-repoinfra.sh`; merged `fastlane/Fastfile` is a zero-diff compatibility surface |
| Allowed outputs | Frozen tree/manifest and test output; exact content verdict/permission; commit/push/non-Draft PR metadata; local/remote/PR identity proof; PR Manager handoff |
| Files out of scope | Any source repair in T003; TestFlight dispatch/upload; credentials/signing/profile/keychain output; unrelated cleanup |
| Interface impact | None |
| Task-local acceptance | Stage A runs all T001-compatibility/T002 verification, freezes the uncommitted candidate, proves only two paths changed relative to `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, and obtains exact AI Reviewer PASS plus publication permission. Any content change returns to T002 and Stage A. Stage B commits/pushes only the unchanged tree, creates or updates one non-Draft owner-gated PR, proves reviewed tree = commit tree and local HEAD = remote branch OID = PR headRefOid, then hands the same SHA to PR Manager. |
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
T001 merged RepoInfra repair + broad real-action baseline at 49b6f1f
  -> T002 actual-toolchain compatibility + mandatory RepoInfra gate wiring (two paths)
       -> T003 frozen review, unchanged publication, PR Manager handoff
            -> PR Manager + Owner-gated merge
                 -> T004 Team Lead observes qualifying automatic TestFlight outcome
```

- T001 is already satisfied by the implementation base and is not dispatched again. T002 consumes its behavior and owns the only resumed source changes.
- T003 findings return to T002; T003 never edits source.
- T004 is read-only operational proof and never authorizes a release dispatch, duplicate upload, source change, or workflow change.
- Planner Lead and AI Reviewer do not assign or start implementation.

## Acceptance Traceability

| Active identifiers | Task | Evidence surface |
|---|---|---|
| US1/AC1, US1/AC2, US1/AC3, US1/AC4, US1/AC5, US1/AC6, US1/AC7; FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-016; RB-001, RB-002, RB-003 | T001, T002, T003 | merged actual-lane repair; preserved real-action cases; two-source neutralization; stale-seeded target failures; target-correct build/export capture; zero Fastfile diff |
| US2/AC1, US2/AC2; FR-009, FR-010, FR-011 | T001, T002, T003 | preserved real Fastlane/Sigh action path, two-call overwrite/provenance proof, UUID non-use, fabricated-key prohibition |
| US2/AC5; FR-008, FR-012; RB-006 | T002, T003 | unchanged-PATH actual-toolchain resolution, CLI/gem/loaded-library/source equality, minimum 2.238.0, fail-closed runtime evidence, exactly-once canonical gate invocation |
| US2/AC3, US2/AC4; FR-013, FR-014; RB-004 | T002, T003 | mandatory RepoInfra execution, preserved existing suites and compatibility surfaces |
| US3/AC1, US3/AC2, US3/AC3, US3/AC4; FR-015, FR-017; RB-005 | T004 | qualifying merged-main automatic run identity, terminal result, marker/result, uploaded build number, no duplicate dispatch |
| SC-001, SC-002, SC-003, SC-004 | T001, T002, T003 | merged-baseline preservation, focused regression, actual-toolchain proof, syntax, complete gate, two-path diff evidence, exact content review |
| SC-005 | T003, T004 | owner-gated merge and production outcome record |

## Completion Conditions

- Every active acceptance identifier maps above.
- T001 is bound to the merged base; T002 has one layer, two exact paths, exclusions, runnable verification, and no unresolved decision.
- The resumed candidate changes exactly two implementation paths relative to `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`; `fastlane/Fastfile` has zero diff.
- No TestFlight action occurs before reviewed merge.
- MY-1815 completes only after Team Lead records the qualifying automatic post-merge run and uploaded build number for the exact merged SHA, with no duplicate dispatch.
