# Tasks: TestFlight auto-release after verified main CI

**Input**: Design documents from `/specs/027-testflight-auto-release/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/testflight-auto-release.md`, `quickstart.md`

**Constitution**: `.specify/memory/constitution.md` Development Workflow and Quality Bars A/J; `RepoInfra/CONTEXT.md`

**Delivery shape**: One goal, one RepoInfra implementation PR, one exact reviewed candidate. Tasks are serialized because they share files.

## Format

Every executable row uses `- [ ] Txxx [US#] Action with exact file path`. Metadata below each row fixes the owning layer, exclusions, contract, acceptance, verification, and dependency edges.

## Phase 1: User Story 1 — Publish an eligible verified merge automatically (P1)

**Goal**: A successful app-relevant `CI` push run on `main` queues one exact-SHA release attempt and every ineligible/unsafe state stops before upload with safe evidence.

**Independent Test**: Credential-free tests exercise automatic source events, exact SHA, accumulated changed paths, marker ancestry/duplicates, attempt-before-lane ordering, concurrency, and summary reason codes without GitHub/ASC mutation.

- [ ] T001 [US1] Write red-first automatic-release contract coverage and implement exact-CI-SHA eligibility, attempt/success marker ordering, concurrency, and safe summaries in `scripts/tests/test_testflight_freshness.py` and `.github/workflows/testflight.yml`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Development Workflow and Quality Bars A/J |
| Vertical slice | US1 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml` |
| Files out of scope | `fastlane/Fastfile` until T002; every other `.github/**`; all other scripts/tests; app/package/AppUI/Prototype paths; `project.yml`; CODEOWNERS/rulesets/secrets |
| Interface impact | Adds completed-`CI` automatic event contract; preserves manual input; binds candidate to exact SHA; adds accumulated path classifier and pre-attempt/success marker state; keeps one non-cancelling runner group |
| Task-local acceptance | Test changes precede workflow changes and demonstrate the manual-only base fails the new cases; automatic input accepts only exact `CI`/push/main/success; checkout/diff/summary/markers reuse one SHA; exact path allowlist/exclusions hold; missing/non-ancestor marker fails; successful/attempted SHA skips; attempt tag is remotely confirmed before the lane; no critical action can start on rejected input; unrelated existing signing/profile assertions remain |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; inspect `git diff -- .github/workflows/testflight.yml scripts/tests/test_testflight_freshness.py`; `git diff --check` |
| Blocking edges | No implementation predecessor. Blocks T002 and T003. |

**Checkpoint**: US1's event/eligibility state machine is independently proven without Apple credentials.

## Phase 2: User Story 2 — Preserve release semantics and unique version evidence (P1)

**Goal**: One project/label-derived marketing version and one app-wide monotonic build number flow through a fail-closed lane whose critical result controls the successful marker.

**Independent Test**: Credential-free tests and Ruby syntax inspection prove merged-PR/label resolution, project-version validation, version reuse, build-number output, strict distribution/dSYM behavior, and preserved dynamic signing/profile logic.

- [ ] T002 [US2] Write red-first version/failure contract coverage and implement the resolved marketing-version input, build-number output, and strict release result in `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`, and `fastlane/Fastfile`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; `contracts/testflight-auto-release.md`; 026 profile-reuse compatibility contract |
| Vertical slice | US2 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml`; `fastlane/Fastfile` |
| Files out of scope | Every other workflow/Fastlane/script/test file; `project.yml`; generated project; app/package/tests; Developer Portal objects; new secrets |
| Interface impact | Workflow resolves exactly one merged PR/label and uniform project marketing version, passes one runtime value to Fastlane, receives the app-wide next build number, and treats upload/processing/distribution/dSYM/success-tag phases as critical |
| Task-local acceptance | Tests fail against hardcoded `MARKETING_VERSION` and best-effort success; zero/multiple associated PR or malformed/mismatched project version fails before attempt; exact `release:minor` derives the next minor for that run; archive/lookup/distribution/evidence share one version; build-number query remains app-wide max+1 and exposes its value; dynamic app/widget profiles, signing, telemetry, TEMP-PRELAUNCH audit, group mapping, and secret handling remain; internal distribution/dSYM failures cannot lead to success-marker movement |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; inspect `git diff -- .github/workflows/testflight.yml fastlane/Fastfile scripts/tests/test_testflight_freshness.py`; `git diff --check` |
| Blocking edges | Depends on T001 because files overlap and version evaluation follows candidate eligibility. Blocks T003/T004. |

**Checkpoint**: US2 is credential-free and independently demonstrates version/failure behavior without archive or upload.

## Phase 3: User Story 3 — Retain bounded manual force (P2)

**Goal**: Manual dispatch can release an otherwise path-ineligible current-main SHA but cannot bypass identity, marker, version, claim, or no-retry protections.

**Independent Test**: Credential-free cases cover default false, no-force eligibility, force path bypass, and successful/attempted SHA rejection.

- [ ] T003 [US3] Write red-first bounded-force cases and complete shared automatic/manual gate behavior in `scripts/tests/test_testflight_freshness.py` and `.github/workflows/testflight.yml`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; DEC-027-005 |
| Vertical slice | US3 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml` |
| Files out of scope | `fastlane/Fastfile` except read-only contract verification; every other repository path; tag mutation/upload during testing |
| Interface impact | Keeps `workflow_dispatch.inputs.force` boolean default false; manual candidate is exact captured current `main`; force bypasses only path eligibility |
| Task-local acceptance | `force=false` uses the shared path rule; `force=true` may release only an unattempted/unreleased valid current-main SHA; both values reject success/attempt markers and invalid baselines; no manual path can skip version/claim/critical-release guards; summary distinguishes manual force from automatic eligibility |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; inspect the manual trigger/gate portions of `.github/workflows/testflight.yml`; `git diff --check` |
| Blocking edges | Depends on T001 and T002; blocks assembled verification T004. |

**Checkpoint**: All three stories are credential-free and share one deterministic state machine.

## Phase 4: Assembled Candidate and Publication Gate

**Purpose**: Verify the exact one-PR candidate, obtain independent content review, and preserve the separate Owner approval boundary for `.github/**`.

- [ ] T004 [US2] Verify and freeze the complete RepoInfra candidate for `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `scripts/tests/test_testflight_freshness.py`, then publish only the exact reviewed SHA through the Owner-gated non-Draft PR path

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` integration/delivery verification; no source repair ownership |
| Context | `quickstart.md`; Constitution Development Workflow/Quality Bar J; MY-1766 explicit Owner boundary |
| Vertical slice | US1 + US2 + US3 assembled delivery |
| Files in scope | Read-only verification of the three implementation paths; frozen candidate manifest; after exact content PASS, normal commit/push/PR metadata |
| Files out of scope | Source repair in T004; any fourth implementation path; real TestFlight dispatch; Owner-approval substitution; secret/signing material |
| Interface impact | None; proves the assembled contract and delivery identity |
| Task-local acceptance | Focused tests, Ruby syntax, full RepoInfra output, and whitespace check are fresh with zero failures/errors; diff is exactly three files; static contract inspection is complete; exact pre-push AI Reviewer verdict binds to the frozen candidate; published SHA/tree equals reviewed candidate; PR is non-Draft; explicit Owner approval for `.github/workflows/testflight.yml` is recorded before merge; required-check/shipping state is handed to PR Manager, not claimed by AI Reviewer |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check`; `git status --short`; exact local/remote/PR SHA proof after publication |
| Blocking edges | Depends on T001–T003. Content failure routes to the owning task. Owner approval and required checks block merge. |

## Phase 5: Post-merge Outcome Evidence

**Purpose**: Prove the requested production outcome on the first eligible merge without expanding repository scope.

- [ ] T005 [US1] Record the first eligible exact-main TestFlight outcome from `.github/workflows/testflight.yml` on MY-1766 with run, version, build, and marker evidence

### T005 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` operational acceptance; execution-only, no repository edit |
| Context | MY-1766 Evidence requirement; `contracts/testflight-auto-release.md` Evidence Contract |
| Vertical slice | US1 production outcome, US2 evidence |
| Files in scope | Execution-only observation of `.github/workflows/testflight.yml`; MY-1766 evidence comment |
| Files out of scope | Workflow/Fastfile/test repair; manual rerun of attempted SHA; marker rollback; secret/profile/certificate/keychain disclosure |
| Interface impact | None; consumes reviewed release evidence |
| Task-local acceptance | The implementation PR merged with explicit Owner approval; the first eligible successful `CI` main SHA has exactly one TestFlight attempt; evidence records exact SHA, run URL, terminal conclusion, marketing version, unique build number, and attempted/success marker SHAs; no secret/signing material is attached. On failure, record phase/reason and preserved markers without retry/rollback. |
| Verification | GitHub Actions run and remote marker evidence for the exact candidate; MY-1766 comment containing the required safe fields |
| Blocking edges | Depends on T004, PR Manager merge, successful main CI, and an eligible path diff. No substitute dry run completes it. |

## Dependencies and Execution Order

```text
T001 exact automatic candidate/eligibility
  └─> T002 version + fail-closed lane
        └─> T003 bounded manual force
              └─> T004 assembled verification/review/Owner-gated PR
                    └─> PR Manager required checks + merge
                          └─> T005 first eligible production evidence
```

- No task is marked `[P]`: T001–T003 edit overlapping files and must remain sequential.
- T004 performs no content repair; it returns findings to the owning task so the exact candidate can be re-frozen/reviewed.
- T005 is operational acceptance and performs no repository write.
- Team Lead reconciles/schedules the reviewed graph; this document does not assign implementation roles.

## Acceptance Traceability

| Spec acceptance / requirement | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC1, US1/AC4; FR-001, FR-002; RB-001, RB-002 | US1 | T001, T004 | Automatic event/identity tests; static exact-SHA inspection |
| US1/AC2; FR-003, FR-004; RB-004 | US1 | T001, T004 | Accumulated path matrix and skip-summary cases |
| US1/AC3, US1/AC5; FR-006–FR-008, FR-017; RB-003 | US1 | T001, T004 | Marker/ancestry/claim ordering and no-retry cases |
| US2/AC1; FR-010 | US2 | T001, T004 | Concurrency/runner assertions |
| US2/AC2; FR-012, FR-015 | US2 | T002, T004, T005 | App-wide counter assertions, build output, production evidence |
| US2/AC3, US2/AC4; FR-013–FR-015; RB-006 | US2 | T002, T004, T005 | Unique PR/label/project-version matrix and runtime handoff |
| US2/AC5; FR-009, FR-016, FR-017; RB-005 | US2 | T002, T004, T005 | Critical failure cases, attempt retention, failed-phase evidence |
| US2/AC6; FR-016, FR-021 | US2 | T002, T005 | Safe success summary and MY-1766 record |
| US3/AC1–US3/AC3; FR-005, FR-006; RB-003 | US3 | T003, T004 | Manual default/force matrix and shared marker guards |
| FR-011, FR-018, FR-019; RB-008 | Cross-cutting | T001–T004 | Existing secret/profile/signing/telemetry assertions and complete RepoInfra gate |
| FR-020; RB-007; SC-007 | Delivery | T004 | Exact three-file diff, AI review, non-Draft PR, explicit Owner approval with no per-upload confirmation gate |
| SC-001, SC-002 | All credential-free slices | T001–T004 | Focused unittest, Ruby syntax, complete RepoInfra output, whitespace/static review |
| SC-003, SC-004 | Production outcome | T005 | Exact eligible main CI/TestFlight run, versions, markers |
| SC-005 | Eligibility | T001, T003, T005 | Ineligible automatic skip and bounded manual force evidence |
| SC-006 | Failure safety | T001, T002, T005 | Critical failure, retained attempt, unchanged success marker, no retry/rollback |

## Completion Conditions

- Every task stays inside its owned paths/layer and fulfills its metadata.
- Every acceptance/FR/SC maps above to a task and evidence surface.
- Credential-free tests are written red-first and all final required command outputs are read in full.
- Any new content SHA invalidates exact content review and is re-reviewed.
- Owner approval for `.github/**` remains required after content PASS and before merge.
- Final product outcome is not complete until T005 evidence exists on MY-1766.
