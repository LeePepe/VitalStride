---

description: "Layer-scoped task graph for App-target required-gate recovery"
---

# Tasks: App-target required-gate recovery

**Input**: Design documents from `specs/024-app-target-gate-recovery/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/app-target-gate.md`, `quickstart.md`

**Organization**: One independently verifiable vertical recovery slice implemented by one RepoInfra task.

## Phase 1: User Story 1 - Fail fast with observable gate evidence (Priority: P1)

**Goal**: A deterministic non-quarantined App-target failure reaches a visible terminal result after one suite invocation while the required gate remains intact.

**Independent Test**: Run the focused controlled-command regression and the complete RepoInfra fast gate without a simulator.

- [ ] T001 [US1] Add the deterministic regression first, then extract and wire the fail-closed single-invocation App-target runner in `scripts/tests/test_app_target_gate.py`, `scripts/ci/run-app-target-tests.sh`, and `.github/workflows/ci.yml`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md` |
| Vertical slice | `US1` |
| Files in scope | `.github/workflows/ci.yml`; new `scripts/ci/run-app-target-tests.sh`; new `scripts/tests/test_app_target_gate.py` |
| Files out of scope | `project.yml`; `VitalStride.xcodeproj/**`; `VitalStrideTests/**` including MY-1490's catalog assertion; all app roots; `Packages/**`; `scripts/rulesets/main-protection.json`; other workflows/hooks/review gates; MY-1489 delivery branch and PR #418 head |
| Interface impact | Internal RepoInfra runner boundary only. Preserve `app` / `App target`, production command parameters, and the sole explicit quarantine exclusion; no product API change. |
| Task-local acceptance | Controlled failure invokes once and propagates nonzero; controlled success invokes once and returns zero; live progress and terminal markers are asserted; production arguments/quarantine and workflow wiring are asserted; no whole-suite retry or fail-open path remains. |
| Verification | From repo root: `python3 -B -m unittest discover -s scripts/tests -p 'test_app_target_gate.py'`; `bash scripts/test-repoinfra.sh`; `bash -n scripts/ci/run-app-target-tests.sh`; `git diff --check` |
| Blocking edges | Implementation: none. May run parallel with MY-1490. Shipping unblock for MY-1489 requires reviewed T001 merge + MY-1490 merge + a fresh terminal-success `App target` check for PR #418. |

**Checkpoint**: The RepoInfra change can be independently demonstrated locally; it does not claim the catalog expectation is fixed or PR #418 is shippable.

## Dependencies & Execution Order

```text
T001 RepoInfra recovery ───────┐
                              ├─> fresh PR #418 App target success ─> MY-1489 shipping unblocked
MY-1490 catalog expectation ──┘
```

- `T001` and MY-1490 are parallel blockers with disjoint layer ownership.
- Team Lead schedules implementation only after exact-revision planning approval.
- Team Lead requests the fresh PR #418 required gate only after both reviewed changes have merged through their normal delivery paths.
- No task in this graph modifies the VitalModels delivery branch.

## Acceptance Traceability

| Spec acceptance | Slice | Task | Verification surface |
|---|---|---|---|
| FR-001, FR-002 | US1 | T001 | Controlled failing command invocation count and propagated exit |
| FR-003, FR-005 | US1 | T001 | Workflow/runner contract assertions |
| FR-004 | US1 | T001 | Captured progress, grouping, and terminal marker assertions |
| FR-006, FR-007 | US1 | T001 | Focused unittest plus `bash scripts/test-repoinfra.sh` |
| FR-008, FR-009 | US1 | T001 | Exact diff boundary and MY-1490 dependency edge |

## Implementation Strategy

1. Add the controlled-command regression and demonstrate that the current inline whole-suite policy does not satisfy it.
2. Extract the runner and wire the workflow without changing required job identity or quarantine scope.
3. Run focused and complete RepoInfra verification.
4. Hand the implementation revision through normal code review and required CI; do not modify or merge PR #418 from this task.

