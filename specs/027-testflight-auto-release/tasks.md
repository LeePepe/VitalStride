# Tasks: TestFlight auto-release after verified main CI

**Input**: Design documents from `/specs/027-testflight-auto-release/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/testflight-auto-release.md`, `quickstart.md`

**Constitution**: `.specify/memory/constitution.md` Development Workflow and Quality Bars A/J; `RepoInfra/CONTEXT.md`

**Delivery shape**: One goal, one RepoInfra implementation PR, one exact reviewed candidate. Tasks are serialized because they share files.

## Phase 1: US1 — Exact automatic candidate and marker-range eligibility (P1)

**Goal**: A successful app-relevant `CI` push run on `main` selects one exact candidate; marker/bootstrap relation and accumulated relevance decide safely without auxiliary durable state.

**Independent Test**: Credential-free tests cover automatic source, exact SHA, empty-tree bootstrap, marker ancestry/equality/stale/divergence, accumulated path records including all four exact `VitalStrideWidgets/**` predicates plus non-widget resource negatives, irrelevant→relevant and failure→later-pickup sequences, concurrency, and summaries.

- [ ] T001 [US1] Write red-first automatic marker-range coverage and implement exact-CI candidate capture, accumulated eligibility, sole-marker relation, one app concurrency group, and safe summaries in `scripts/tests/test_testflight_freshness.py` and `.github/workflows/testflight.yml`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Development Workflow and Quality Bars A/J |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml` |
| Files out of scope | `fastlane/Fastfile` until T002; all other `.github/**`, scripts/tests, product/app/package/Prototype paths, `project.yml`, CODEOWNERS/rulesets/secrets |
| Interface impact | Adds exact completed-`CI` automatic event; preserves manual input; adds sole-marker bootstrap/relation and exclusion-first accumulated relevance; keeps one non-cancelling group |
| Task-local acceptance | Red tests fail against the manual-only base; only exact `CI`/push/main/success proceeds; automatic checkout/diff/summary reuse one SHA; marker absence uses empty tree; ancestor range evaluates; equal/covered candidate skips; divergence fails; path positives/exclusions cover docs, package tests/contexts, mixed, deletion, and rename/copy endpoints; tests exercise each exact `VitalStrideWidgets/**/*.swift`, `VitalStrideWidgets/**/*.plist`, `VitalStrideWidgets/**/*.entitlements`, and `VitalStrideWidgets/**/*.xcassets/**` positive and prove matching `.plist`, `.entitlements`, and `.xcassets/**` paths outside `VitalStrideWidgets/**` stay negative unless another listed app predicate qualifies; irrelevant skips write no state; irrelevant→relevant and failed-relevant→later-candidate sequences retain accumulated eligibility; tests assert no per-SHA history/custom durable queue/cursor/journal/recovery refs; no rejected input reaches the lane; safe reason codes remain non-secret |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; inspect the two-file diff; `git diff --check` |
| Blocking edges | No predecessor. Blocks T002; T003 is transitively blocked. |

## Phase 2: US2 — Versioned fail-closed lane and final marker (P1)

**Goal**: One candidate-PR-derived marketing version and global build number flow through the critical lane; the sole marker advances and reads back only after earlier success.

**Independent Test**: Credential-free tests and Ruby syntax cover candidate-PR/version resolution, build output, signing/profile compatibility, strict critical phases, final marker sequencing/failure, and safe evidence.

- [ ] T002 [US2] Write red-first version/failure coverage and implement resolved version input, build output, strict release result, and final `testflight/last-released` update/readback in `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`, and `fastlane/Fastfile`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; `contracts/testflight-auto-release.md`; existing profile-reuse compatibility contract |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml`; `fastlane/Fastfile` |
| Files out of scope | All other workflow/Fastlane/script/test files; `project.yml`; generated project; product/package tests; Portal objects; new secrets |
| Interface impact | Both sources resolve exactly one candidate PR/label and uniform project version; Fastlane consumes one runtime marketing version and exposes app-wide build number; reviewed release phases become critical; only `last-released` is written/read |
| Task-local acceptance | Tests fail against hardcoded version and weakened critical results; zero/multiple candidate PR or invalid project versions fail before archive; exact candidate `release:minor` alone drives a per-run minor; archive/lookup/distribution/evidence share one version; global max+1 remains and is emitted; dynamic app/widget profiles, signing, telemetry, TEMP-PRELAUNCH warning, group mapping, and secret handling remain; internal distribution/dSYM failure cannot reach marker step; marker command is unreachable until all earlier critical phases succeed; exact readback is required for success; update/readback failure records safe evidence and creates no auxiliary state/retry/rollback; existing profile/log assertions remain |
| Verification | From repo root: focused Python unittest; `ruby -c fastlane/Fastfile`; inspect three-file diff; `git diff --check` |
| Blocking edges | Depends on T001 because files overlap and version follows eligibility. Blocks T003; T004 is transitively blocked. |

## Phase 3: US3 — Bounded manual force (P2)

**Goal**: Manual dispatch may pick up exact current `main` when normal relevance skips or a prior release failed, but force bypasses relevance only.

**Independent Test**: Credential-free tests cover default false, marker-range relevance, force-only bypass, same-released/covered skip, invalid marker rejection, and failed-current-main pickup.

- [ ] T003 [US3] Write red-first bounded-force cases and complete shared automatic/manual gate behavior in `scripts/tests/test_testflight_freshness.py` and `.github/workflows/testflight.yml`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; DEC-027-005 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml` |
| Files out of scope | `fastlane/Fastfile` except read-only verification; every other repository path; real tag mutation/upload during tests |
| Interface impact | Retains boolean manual `force=false`; candidate is captured current remote `main`; force changes only path relevance |
| Task-local acceptance | `force=false` uses bootstrap/marker-range relevance; `force=true` may release exact current main only when marker relation is valid/ahead; either value skips equal/covered candidates and rejects invalid marker/identity/PR/version/signing/critical failures; both use the same exact candidate-PR `release:minor` policy; after a failed release left current main ahead of marker, later manual dispatch may pick it up because no lifetime attempt state exists; summary distinguishes manual force from automatic eligibility |
| Verification | From repo root: focused Python unittest; inspect manual trigger/gate sections; `git diff --check` |
| Blocking edges | Depends directly on T002; T001 is transitive. Blocks T004. |

## Phase 4: Assembled Candidate and Publication Gate

- [ ] T004 [US2] Verify and freeze the complete RepoInfra candidate for `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `scripts/tests/test_testflight_freshness.py`, then publish only the exact reviewed SHA through the Owner-gated non-Draft PR path

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` integration/delivery verification; no source repair ownership |
| Context | `quickstart.md`; Constitution Workflow/Quality Bar J; MY-1766 Owner boundary |
| Files in scope | Read-only verification of three implementation paths; frozen manifest; after exact content PASS, normal commit/push/PR metadata |
| Files out of scope | Source repair in T004; fourth implementation path; real TestFlight dispatch; Owner-approval substitution; secret/signing material |
| Interface impact | None; proves assembled contract and delivery identity |
| Task-local acceptance | Fresh focused tests, Ruby syntax, complete RepoInfra output, and whitespace report zero failures/errors; diff is exactly three paths; static inspection proves exact CI/current-main identity, empty-tree bootstrap, marker relation, accumulated classifier, skipped/failed pickup, sole durable marker, one group/no custom queue, bounded force, candidate-PR version/global build, critical ordering, final marker readback, no auxiliary state/retry/rollback, and preserved signing/secrets/safe logs; exact pre-push content verdict binds to frozen candidate; published SHA/tree matches; PR is non-Draft; explicit Owner approval is recorded before merge; required checks/shipping go to PR Manager |
| Verification | From repo root: focused Python unittest; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check`; `git status --short`; exact local/remote/PR SHA proof |
| Blocking edges | Depends directly on T003. Content failure routes to owning task. Owner approval and required checks block merge. |

## Phase 5: Post-merge Outcome Evidence

- [ ] T005 [US1] Record the first eligible successful exact-main TestFlight outcome from `.github/workflows/testflight.yml` on MY-1766 with run, version, build, and sole-marker evidence

### T005 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` operational acceptance; execution-only, no repository edit |
| Context | MY-1766 Evidence requirement; contract Evidence section |
| Files in scope | Observation of `.github/workflows/testflight.yml`; safe MY-1766 evidence comment |
| Files out of scope | Workflow/Fastfile/test repair; marker rollback; secret/profile/certificate/keychain disclosure |
| Interface impact | None; consumes reviewed release evidence |
| Task-local acceptance | Implementation PR merged with explicit Owner approval; an eligible successful `CI` main candidate has a successful terminal TestFlight run; evidence records exact SHA, run URL, marketing version, unique build number, and confirmed `last-released` equal to candidate without sensitive material. Failure records phase/reason and last safe marker as incident only, leaves T005/MY-1766 incomplete, and proceeds through a later eligible merge or manual current-main run rather than automatic retry. |
| Verification | GitHub Actions run and remote sole-marker evidence for exact candidate; MY-1766 safe evidence comment |
| Blocking edges | Depends on T004, PR Manager merge, successful main CI, and eligible range. No dry run substitutes. |

## Dependencies and Execution Order

```text
T001 exact automatic candidate + marker-range eligibility
  └─> T002 version/build + fail-closed lane + final marker
        └─> T003 bounded manual force
              └─> T004 assembled verification/review/Owner-gated PR
                    └─> PR Manager required checks + merge
                          └─> T005 first eligible production success evidence
```

- No task is `[P]`: T001–T003 edit overlapping files.
- T004 performs no content repair; findings return to the owning task.
- T005 performs no repository write.
- Team Lead schedules the reviewed graph; this document assigns no implementation role.

## Acceptance Traceability

| Spec acceptance / requirement | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC1, US1/AC4; FR-001, FR-002; RB-001, RB-002 | US1 | T001, T004 | Automatic source/exact-SHA tests and static inspection |
| US1/AC2; FR-003, FR-004; RB-004 | US1 | T001, T004 | Accumulated NUL-safe path/exclusion/mixed/delete/rename matrices |
| US1/AC3; FR-006, FR-007, FR-008; RB-003 | US1 | T001, T002, T004, T005 | Marker relations, failed-range pickup, final update/readback, production marker evidence |
| US1/AC5 | US1 | T001, T002, T004 | Empty-tree bootstrap/invalid marker plus exact candidate PR/version failure |
| US2/AC1; FR-010 | US2 | T001, T004 | Single group/non-cancellation/no-custom-queue assertions |
| US2/AC2; FR-012, FR-015 | US2 | T002, T004, T005 | App-wide counter, safe output, production evidence |
| US2/AC3, US2/AC4; FR-013–FR-015; RB-006 | US2 | T002, T004, T005 | Exact candidate PR/label/project-version matrix and handoff |
| US2/AC5; FR-008, FR-009, FR-016, FR-017; RB-005 | US2 | T002, T004, T005 | Critical ordering, marker-step failure, no state/retry/rollback, incident evidence |
| US2/AC6; FR-016, FR-021 | US2 | T002, T005 | Safe success summary, exact marker, MY-1766 record |
| US3/AC1, US3/AC2, US3/AC3; FR-005, FR-006, FR-007, FR-008; RB-003 | US3 | T003, T004 | Manual range/default/force/same-released/failure-pickup matrix |
| US3/AC4; FR-013, FR-014 | US3 | T002, T003, T004 | Shared exact candidate-PR label policy |
| FR-011, FR-018, FR-019; RB-008 | Cross-cutting | T001–T004 | Existing secrets/runner/profile/signing/telemetry assertions |
| FR-020; RB-007; SC-007 | Delivery | T004 | Exact diff, content review, non-Draft PR, explicit Owner approval |
| SC-001, SC-002 | Credential-free | T001–T004 | Focused unittest, Ruby syntax, full RepoInfra, whitespace/static review |
| SC-003, SC-004 | Production/final marker | T002, T004, T005 | Success-only marker ordering/readback and operational evidence |
| SC-005 | Eligibility | T001, T003, T005 | Excluded skip/no-state, accumulated pickup, bounded force |
| SC-006 | Failure safety | T001, T002, T003, T005 | No pre-final mutation/automatic retry/rollback/auxiliary state; later fresh-run pickup |

## Completion Conditions

- Every task stays in its owned paths/layer and fulfills metadata.
- All 51 stable US/AC, FR, RB, and SC IDs map above to task/evidence surfaces.
- Tests are red-first and final full outputs report zero failures/errors.
- Any candidate content SHA change invalidates exact review.
- Owner approval for `.github/**` remains required after content PASS and before merge.
- Final outcome requires successful T005 evidence. Failure evidence never closes it; later eligible merge/manual pickup is permitted but no automatic retry is configured.
