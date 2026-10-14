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

- [ ] T001 [US1] Write red-first automatic-release contract coverage and implement exact-CI-SHA eligibility, immutable attempt-claim/success-marker ordering, concurrency, and safe summaries in `scripts/tests/test_testflight_freshness.py` and `.github/workflows/testflight.yml`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Development Workflow and Quality Bars A/J |
| Vertical slice | US1 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml` |
| Files out of scope | `fastlane/Fastfile` until T002; every other `.github/**`; all other scripts/tests; app/package/AppUI/Prototype paths; `project.yml`; CODEOWNERS/rulesets/secrets |
| Interface impact | Adds completed-`CI` automatic event contract; preserves manual input; binds candidate to exact SHA; adds exclusion-first narrow path classification, immutable per-SHA attempt claims, authoritative pending/resolved namespace preflight, and success-marker normal/indeterminate state; keeps one non-cancelling runner group |
| Task-local acceptance | Test changes precede workflow changes and demonstrate the manual-only base fails the new cases; automatic input accepts only exact `CI`/push/main/success; checkout/diff/summary/refs reuse one SHA; narrow positive paths and exclusion precedence reject package tests/contexts and docs; missing/non-ancestor success marker fails; preflight validates every pending/resolved ref name and encoded-SHA target, rejects malformed/mismatched/orphan state, fails every candidate on a confirmed unpaired pending ref with `success-marker-recovery-required`, and treats an exact valid pair as gate reconciliation only; successful or durably claimed SHA skips; A→B→A cannot re-enter; immutable attempt claim is remotely confirmed before the lane and never rewritten; success-marker mutation uncertainty records `success-marker-indeterminate` and blocks for Owner recovery without rollback; no critical action can start on rejected input; unrelated existing signing/profile assertions remain |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; inspect `git diff -- .github/workflows/testflight.yml scripts/tests/test_testflight_freshness.py`; `git diff --check` |
| Blocking edges | No implementation predecessor. Blocks T002; T003 is blocked transitively. |

**Checkpoint**: US1's event/eligibility state machine is independently proven without Apple credentials.

## Phase 2: User Story 2 — Preserve release semantics and unique version evidence (P1)

**Goal**: One project/label-derived marketing version and one app-wide monotonic build number flow through a fail-closed lane whose critical result controls the successful marker through an immutable pending/resolved transaction pair, leased update, fresh readback, and explicit recovery state.

**Independent Test**: Credential-free tests and Ruby syntax inspection prove merged-PR/label resolution, project-version validation, version reuse, build-number output, strict distribution/dSYM behavior, immutable pending/resolved lifecycle and namespace validation, leased successful-marker prior/conflict/indeterminate states, ambiguous-resolution next-preflight reconciliation, Owner recovery dispositions/transitions, no retroactive success, and preserved dynamic signing/profile logic.

- [ ] T002 [US2] Write red-first version/failure contract coverage and implement the resolved marketing-version input, build-number output, and strict release result in `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`, and `fastlane/Fastfile`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; `contracts/testflight-auto-release.md`; 026 profile-reuse compatibility contract |
| Vertical slice | US2 |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `.github/workflows/testflight.yml`; `fastlane/Fastfile` |
| Files out of scope | Every other workflow/Fastlane/script/test file; `project.yml`; generated project; app/package/tests; Developer Portal objects; new secrets |
| Interface impact | Workflow resolves exactly one merged PR/label for either automatic or manual candidate plus a uniform project marketing version, passes one runtime value to Fastlane, receives the app-wide next build number, treats upload/processing/distribution/dSYM/success-tag phases as critical, and represents success-marker mutation as immutable pending/resolved plus leased prior/confirmed-candidate/conflict/indeterminate state |
| Task-local acceptance | Tests fail against hardcoded `MARKETING_VERSION` and best-effort success; zero/multiple associated PR for either source or malformed/mismatched project version fails before attempt; exact `release:minor` derives the next minor for that run; archive/lookup/distribution/evidence share one version; build-number query remains app-wide max+1 and exposes its value; dynamic app/widget profiles, signing, telemetry, TEMP-PRELAUNCH audit, group mapping, and secret handling remain; internal distribution/dSYM failures cannot reach success-marker mutation; immediately before mutation the workflow creates/confirms immutable `success-pending/<SHA>`; mutation captures the confirmed prior OID, uses only that OID as the lease/CAS expectation, and freshly reads the remote ref; exact candidate readback is followed by create/confirm of matching immutable `success-resolved/<SHA>` before success; confirmed-prior, conflicting-SHA, unreadable/unknown, and resolution-confirmation outcomes fail closed with safe evidence; ambiguous resolution confirmation makes that run fail without a pair assertion, and next preflight covers exact-valid-pair gate reconciliation, confirmed-absence Owner recovery, malformed/mismatched/orphan rejection, and all four Owner recovery dispositions/transitions without overwrite, deletion, rollback, retry, or retroactive success |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; inspect `git diff -- .github/workflows/testflight.yml fastlane/Fastfile scripts/tests/test_testflight_freshness.py`; `git diff --check` |
| Blocking edges | Depends on T001 because files overlap and version evaluation follows candidate eligibility. Blocks T003; T004 is blocked transitively. |

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
| Task-local acceptance | `force=false` uses the shared exclusion-first path rule; `force=true` may release only an unattempted/unreleased valid current-main SHA; both values reject the success marker, immutable attempt claim, confirmed-unpaired pending state, and malformed/mismatched/orphan success-ref state, while an exact valid pair clears only the shared recovery gate; both resolve exactly one merged PR, apply the same `release:minor` decision, and reject invalid baselines; no manual path can skip version/claim/recovery/critical-release guards; summary distinguishes manual force from automatic eligibility |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; inspect the manual trigger/gate portions of `.github/workflows/testflight.yml`; `git diff --check` |
| Blocking edges | Depends directly on T002; T001 is a transitive predecessor. Blocks T004. |

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
| Task-local acceptance | Focused tests, Ruby syntax, full RepoInfra output, and whitespace check are fresh with zero failures/errors; diff is exactly three files; static contract inspection proves the exclusion-first path/rename/deletion matrix, immutable A→B→A lifetime claims, shared automatic/manual exact-PR version policy, confirmed success-pending before mutation, captured-prior-OID lease/CAS, fresh success-marker readback, confirmed matching success-resolved before success, next-run name/target validation and malformed/mismatched/orphan or confirmed-unpaired rejection, exact-pair gate-only reconciliation after ambiguous resolution confirmation, prior/conflict/indeterminate evidence, all four Owner recovery dispositions/transitions, and no retroactive success; exact pre-push AI Reviewer verdict binds to the frozen candidate; published SHA/tree equals reviewed candidate; PR is non-Draft; explicit Owner approval for `.github/workflows/testflight.yml` is recorded before merge; required-check/shipping state is handed to PR Manager, not claimed by AI Reviewer |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check`; `git status --short`; exact local/remote/PR SHA proof after publication |
| Blocking edges | Depends directly on T003; T001/T002 are transitive predecessors. Content failure routes to the owning task. Owner approval and required checks block merge. |

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
| Task-local acceptance | The implementation PR merged with explicit Owner approval; an eligible successful `CI` main SHA has exactly one TestFlight attempt and a successful terminal run; completion evidence records exact SHA, run URL, marketing version, unique build number, immutable attempt claim, confirmed successful-marker SHA, and confirmed success-pending/resolved pair from that run; no secret/signing material is attached. A failed run records phase/reason, safely known or indeterminate pair state, and known/indeterminate marker evidence as an incident only, leaves T005 and MY-1766 outcome acceptance incomplete even if later preflight observes the exact pair, never retries the claimed SHA, and proceeds only through required gate reconciliation/Owner recovery plus a distinct eligible main SHA. |
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
| US1/AC2; FR-003, FR-004; RB-004 | US1 | T001, T004 | Narrow accumulated path matrix, exclusion precedence, and skip-summary cases |
| US1/AC3; FR-006, FR-007, FR-017; RB-003 | US1 | T001, T004 | Marker/ancestry, immutable claim ordering, A→B→A, and no-retry cases |
| US1/AC5 | US1 | T001, T002, T004 | T001 proves missing/non-ancestor `testflight/last-released` and failed/unconfirmed immutable claim fail before upload; T002 proves zero/multiple exact-PR fail before claim; T004 verifies the assembled surfaces only |
| US2/AC1; FR-010 | US2 | T001, T004 | Concurrency/runner assertions |
| US2/AC2; FR-012, FR-015 | US2 | T002, T004, T005 | App-wide counter assertions, build output, production evidence |
| US2/AC3, US2/AC4; FR-013–FR-015; RB-006 | US2 | T002, T004, T005 | Unique PR/label/project-version matrix and runtime handoff |
| US2/AC5; FR-008, FR-009, FR-016, FR-017; RB-005 | US2 | T001, T002, T004, T005 | Critical failure cases, attempt retention, pending/resolved namespace validation and durable lockout, ambiguous-resolution next-preflight matrix, leased successful-marker prior/conflict/indeterminate tests, four Owner recovery dispositions/transitions, no retroactive success, and failed-phase evidence |
| US2/AC6; FR-016, FR-021 | US2 | T002, T005 | Safe success summary, confirmed pending/resolved pair, and MY-1766 record |
| US3/AC1, US3/AC2, US3/AC3; FR-005, FR-006; RB-003 | US3 | T003, T004 | Manual default/force matrix and shared immutable claim/recovery guards |
| US3/AC4; FR-013, FR-014 | US3 | T002, T003, T004 | Shared automatic/manual exact-PR label matrix; T004 is assembled verification only |
| FR-011, FR-018, FR-019; RB-008 | Cross-cutting | T001–T004 | Existing secret/profile/signing/telemetry assertions and complete RepoInfra gate |
| FR-020; RB-007; SC-007 | Delivery | T004 | Exact three-file diff, AI review, non-Draft PR, explicit Owner approval with no per-upload confirmation gate |
| SC-001, SC-002 | All credential-free slices | T001–T004 | Focused unittest, Ruby syntax, complete RepoInfra output, whitespace/static review |
| SC-003, SC-004 | Production outcome | T005 | Exact eligible main CI/TestFlight successful run, versions, immutable claim, confirmed success marker, and confirmed pending/resolved pair |
| SC-005 | Eligibility | T001, T003, T005 | Ineligible automatic skip and bounded manual force evidence |
| SC-006 | Failure safety | T001, T002, T005 | Critical failure after claim, retained immutable claim, validated pending/resolved durable recovery gate, proven-prior or indeterminate success-marker state, gate-only pair reconciliation or Owner recovery, no retry/rollback/retroactive success; T005 failure evidence is incident-only |

## Completion Conditions

- Every task stays inside its owned paths/layer and fulfills its metadata.
- Every acceptance/FR/SC maps above to a task and evidence surface.
- Credential-free tests are written red-first and all final required command outputs are read in full.
- Any new content SHA invalidates exact content review and is re-reviewed.
- Owner approval for `.github/**` remains required after content PASS and before merge.
- Final product outcome is not complete until successful T005 evidence exists on MY-1766. Failure evidence never closes T005, including after later exact-pair gate reconciliation; same-SHA retry is forbidden, and the forward path is gate reconciliation/Owner recovery when required plus a distinct eligible candidate.
