---

description: "Layer-scoped task graph for the Owner-review merge gate"
---

# Tasks: Owner-review merge gate

**Input**: Design documents from `specs/027-owner-review-merge-gate/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/owner-review-merge-gate.md`, `quickstart.md`

**Organization**: One delivery goal and PR, implemented as one RepoInfra behavior task followed by one support-documentation task. Live ruleset mutation remains an Owner-only post-merge dependency.

## Phase 1: User Story 1 - Protected pull requests wait for the Owner (Priority: P1)

**Goal**: Labelled or CODEOWNERS-matched pull requests are kept out of auto-merge while ordinary pull requests retain current squash auto-merge.

**Independent Test**: Run the focused deterministic regression against protected/ordinary fixtures and the full RepoInfra gate without app/package builds.

- [ ] T001 [US1] Add the regression first, then implement the trusted-base CODEOWNERS/label decision and idempotent merge-state wiring in `.github/CODEOWNERS`, `.github/workflows/auto-merge.yml`, `scripts/ci/owner-review-gate.py`, `scripts/tests/test_owner_review_gate.py`, and `scripts/rulesets/main-protection.json`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution §§III, Development Workflow, Cross-Cutting Quality Bars |
| Vertical slice | `US1` |
| Files in scope | New `.github/CODEOWNERS`; `.github/workflows/auto-merge.yml`; new `scripts/ci/owner-review-gate.py`; new `scripts/tests/test_owner_review_gate.py`; `scripts/rulesets/main-protection.json` |
| Files out of scope | Every other workflow; existing scripts/tests/hooks/gates; `scripts/rulesets/apply`; release/signing/lint/credential-policy content; product/app/package/prototype/generated paths; live settings |
| Interface impact | Internal RepoInfra decision boundary only. Inputs are trusted CODEOWNERS plus PR labels/paths/draft state; output is enable or disable. No public product signature. |
| Task-local acceptance | FR-001–FR-008. All protected fixtures disable, all ordinary fixtures enable, invalid input fails closed, current state makes mutation idempotent, enable/disable failure is visible, CODEOWNERS rows/non-rows are exact, tracked ruleset changes one authorized field, and trusted-base/security/check identity contracts remain. |
| Verification | From repo root: `python3 -B -m unittest discover -s scripts/tests -p 'test_owner_review_gate.py'`; `bash scripts/test-repoinfra.sh`; `python3 -m py_compile scripts/ci/owner-review-gate.py scripts/tests/test_owner_review_gate.py`; `git diff --check` |
| Blocking edges | Implementation: none. T002 depends on the final contract and paths from T001. Shipping additionally depends on exact implementation review, required CI, and the manual first-PR Owner gate. |

**Checkpoint**: The repository behavior is independently verifiable and no product/release behavior has changed.

---

## Phase 2: User Story 2 - Repository settings enforce the same contract (Priority: P1)

**Goal**: Current repository documentation and delivery handoff state the same protected-PR behavior, exact Owner settings mutation, bootstrap sequence, and readback requirement.

**Independent Test**: Compare the rendered documentation to the approved contract, then execute the quickstart evidence checklist during delivery without granting an agent live-settings authority.

- [ ] T002 [US2] Update the ordinary-versus-protected merge flow, first-PR bootstrap, exact ruleset `18932961` Owner toggle, and preservation/readback contract in `docs/ci-gates.md`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | Support-only repository documentation (explicit layer exclusion; no product dependency) |
| Context | `AGENTS.md` read contract; `docs/ci-gates.md`; Constitution Development Workflow and Quality Bar J |
| Vertical slice | `US2` |
| Files in scope | `docs/ci-gates.md` |
| Files out of scope | AGENTS/CLAUDE/contexts/constitution/ADRs; workflow/scripts/ruleset implementation (T001); live GitHub settings; product/package paths |
| Interface impact | Documentation/handoff only; it describes T001 and the Owner operation without creating a second policy source. |
| Task-local acceptance | FR-009–FR-011. Documentation distinguishes ordinary/protected auto-merge, records manual bootstrap evidence, quotes the one-field Owner toggle, requires before/after readback, and labels unrelated live/tracked drift unchanged. |
| Verification | From repo root: focused regression; `bash scripts/test-repoinfra.sh`; `git diff --check`; manual exact-text comparison to `quickstart.md` Owner handoff |
| Blocking edges | Depends on T001. After merge, Owner performs the live toggle; Team Lead/PR Manager records bootstrap, approval, and readback evidence. |

**Checkpoint**: The one PR is ready for exact-candidate review and normal CI; live settings remain untouched.

## External delivery dependencies

1. Team Lead/PR Manager adds `owner-review`, disables auto-merge on the first fix PR, and records the exact head/state.
2. Owner approves that exact head.
3. PR Manager ships through normal required checks; no bypass.
4. After merge, Owner enables only “Require review from Code Owners” on ruleset `18932961`.
5. Team Lead/PR Manager records live readback showing the field true and all other accessible fields preserved; Owner confirms inaccessible fields unchanged.

These are delivery evidence dependencies, not implementation tasks and not permission for an agent to mutate settings.

## Dependencies & Execution Order

```text
T001 RepoInfra behavior + regression
  -> T002 support documentation
  -> exact implementation review + required CI
  -> first-PR manual Owner gate
  -> merge
  -> Owner live toggle
  -> readback
```

- Tasks are serial because T002 documents the final T001 contract.
- Both tasks serve one goal and one PR.
- No child task spans product layers or reverses a dependency.
- Team Lead schedules implementation only after exact-revision planning approval.

## Acceptance Traceability

| Spec acceptance | Slice | Task/dependency | Verification surface |
|---|---|---|---|
| FR-001, FR-002 | US1 | T001 | Event and label/path decision fixtures |
| FR-003, FR-004 | US1 | T001 | Armed/disabled idempotence and API-failure fixtures |
| FR-005 | US1 | T001 | CODEOWNERS match/non-match matrix |
| FR-006 | US1 | T001 + Owner dependency | Tracked JSON assertion + live one-field readback |
| FR-007 | US1 | T001 | Focused deterministic unittest |
| FR-008 | US1 | T001 | Workflow trust/permission/check-identity contract assertions + full RepoInfra gate |
| FR-009, FR-010 | US2 | T002 + external delivery dependencies | Documentation exact text + first-PR evidence + live readback |
| FR-011 | US2 | T002 | `docs/ci-gates.md` contract review and diff check |
| SC-001–SC-004 | US1 | T001 | Focused and full local gates |
| SC-005, SC-006 | US2 | T002 + external delivery dependencies | Owner approval/disabled-state evidence and ruleset readback |

## Implementation Strategy

1. Write protected/ordinary, event, CODEOWNERS, invalid-input, and mutation-failure fixtures; demonstrate current behavior does not satisfy them.
2. Add the narrow CODEOWNERS contract and deterministic decision boundary, then wire idempotent enable/disable state changes without changing trust or check identities.
3. Change the tracked ruleset's code-owner-review field only and run focused plus full RepoInfra verification.
4. Update gate documentation with exact bootstrap/settings/readback wording.
5. Submit the single candidate through exact review and normal required CI, then follow the external delivery dependency sequence.
