# Tasks: Current Dev Team Delivery Contract

**Input**: Design documents from `specs/025-dev-team-delivery-contract/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/delivery-workflow-contract.md`, `quickstart.md`

## Phase 1: User Story 1 — One fail-closed delivery contract (P1)

**Goal**: All active VitalStride governance exposes one current Dev Team pipeline, preserves every
fail-closed guarantee, and supplies a forward-only migration for in-flight work.

**Independent Test**: Review the eight-file change and verify the canonical pipeline, five role
boundaries, exact revision/workdir/required-check/privacy/PR invariants, dispatch run proof, ADR
supersession, and migration behavior; then run the RepoInfra gate from the repository root.

- [ ] T001 [US1] Align the current Dev Team delivery contract across the exact eight-file governance allowlist in `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, `.specify/memory/constitution.md`, `docs/adr/README.md`, `docs/adr/0009-pr-required-workflow.md`, `docs/adr/0014-restore-planner-review-dual-approval.md`, and new `docs/adr/0021-current-dev-team-delivery-contract.md`

### T001 Definition of Ready

| Field | Contract |
|---|---|
| Owning layer | RepoInfra under ADR-0021's bounded governance-support scheduling exception; `depends_on: []`, `depended_by: []`; ADR-0019 path classification remains unchanged |
| Context pointers | `CONTEXT.md`, `RepoInfra/CONTEXT.md`, constitution, ADR-0009/0014/0017/0019/0020, `spec.md`, `plan.md`, `research.md`, workflow contract |
| FS editable files in scope | Exactly the eight governance paths named in T001 |
| Immutable inherited PR scope | `specs/025-dev-team-delivery-contract/**`, already committed at `delivery_base_sha`; Fullstack verifies byte identity and does not edit |
| Files NOT to touch | All other paths, especially `RepoInfra/CONTEXT.md`, ADR-0017/0019/0020 bodies, all `specs/**` except the immutable inherited feature folder, `.github/**`, `scripts/**`, packages, app/test roots, `project.yml`, Xcode project, rulesets, credentials, existing delivery issues, MY-1490 refs, PR #418/#426/#430 |
| Public interface/contract | Repository delivery-governance contract only; no product/runtime API |
| Required content | Canonical pipeline; five role boundaries; FS candidate/PR publication vs PR Manager readiness/shipping split; clear implementation/check repair loop back through fresh AI review to PR Manager; exceptional/ambiguous failure route to Team Lead; exact-revision and workdir invariants; the nine current required checks; Dev Team parent + final role mention + observed run proof; migration note; recovery/Owner escalation; narrow ADR supersession; bounded RepoInfra scheduling with unchanged support exclusions; constitution 3.1.0 |
| Explicit exclusions | No implementation code, CI/ruleset/hook change, product behavior, issue mutation, gate weakening, old-state reuse, or layer reclassification |
| Task-local acceptance | AC-1…AC-8 below and FR-001…FR-017 in `spec.md` all hold at one revision |
| Verification | From repository root: `bash scripts/test-repoinfra.sh` |
| Blocking tasks | None |
| Entry gates | Exact planning `PASS`/`PASS WITH FOLLOW-UP`; Team Lead readiness acceptance; clean Team Lead-provisioned workdir with all four validated `delivery_*` metadata keys and planning SHA as `delivery_base_sha`; proven queued/dispatched/running Fullstack run |
| Vertical slice | US1 |

### T001 Acceptance

- **AC-1 Pipeline consistency**: `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, and the constitution name one
  consistent canonical pipeline and role ownership model.
- **AC-2 Shipping/lifecycle split**: PR Manager exclusively owns CI/readiness/merge/delivery/cleanup;
  Team Lead owns readiness acceptance, scheduling, recovery/Owner escalation, and lifecycle closure.
- **AC-3 Fail-closed guarantees**: Exact planning/implementation revision, issue workdir metadata,
  local/remote/PR identity, required checks, privacy, PR-required delivery, and no-bypass behavior are
  explicit and unchanged.
- **AC-4 Dispatch proof**: Parent stays assigned to Dev Team; the final role mention identifies the
  next actor; queued/dispatched/running run evidence is required and missing evidence routes to Team
  Lead.
- **AC-5 Migration**: In-flight planning, implementation, shipping, merged, changed-SHA, failed
  dispatch, and mismatched-workdir states each have a forward-only next boundary without copying or
  rebuilding valid state.
- **AC-6 ADR governance and scope**: ADR-0021/constitution 3.1.0 follow governance; ADR-0009/0014 body
  history, ADR-0017/0019, layer routes, and every out-of-scope surface remain unchanged.
- **AC-7 Planning evidence and candidate identity**: The inherited planning folder is byte-identical
  to `delivery_base_sha`; local `HEAD`, pushed branch OID, and PR `headRefOid` match before review and
  shipping; Fullstack creates/updates the candidate PR but does not own readiness or shipping.
- **AC-8 Shipping failure routing**: Active governance routes a clear code/build/test/lint/repository-
  check failure directly from PR Manager to Fullstack Engineer, requires the repaired SHA to complete
  fresh exact-revision AI review, and returns it to PR Manager; conflicting evidence, ambiguous
  ownership, policy/content decisions, permissions, infrastructure, repeated repairs, and merge
  conflicts route to Team Lead.

## Dependencies & Execution Order

- Slice graph: `US1` has no upstream slice.
- Task graph: `T001` has no blocking task and is the only executable node, but cannot enter execution
  until every entry gate in its DoR row is proven.
- Parallel work: none; all files express one atomic contract and cannot be safely split.
- Completion: T001 is demonstrable only when all ACs pass together at one exact revision.

## Acceptance Coverage

| Spec acceptance | Slice | Task | Verification surface |
|---|---|---|---|
| Scenario 1 / FR-001–FR-003, FR-008 | US1 | T001 | Active planning/review text + ADR-0021 |
| Scenario 2 / FR-004, FR-007 | US1 | T001 | AGENTS/constitution dispatch text + migration contract |
| Scenario 3 / FR-003, FR-005, FR-008 | US1 | T001 | Active implementation-review handoff text |
| Scenario 4 / FR-004, FR-006 | US1 | T001 | Shipping/lifecycle role table and contract |
| Scenario 5 / FR-008–FR-010, FR-014 | US1 | T001 | Fail-closed invariants + RepoInfra gate |
| Scenario 6 / FR-011–FR-015 | US1 | T001 | ADR status/index/new decision + migration table + diff allowlist |
| Scenario 7 / FR-016 | US1 | T001 | Reviewed planning SHA as `delivery_base_sha` + immutable inherited PR scope |
| Scenario 8 / FR-017 | US1 | T001 | Normative repair loop + failure classification + active recovery residue review |

## Implementation Strategy

Implement T001 as one atomic governance patch, verify locally, publish normally so repository hooks
run, self-review the exact diff against both Standards and Spec, and request AI Reviewer for the exact
implementation revision. On PASS/PASS WITH FOLLOW-UP, hand the same revision directly to PR Manager.
