# Implementation Plan: Current Dev Team Delivery Contract

**Branch**: `agent/planner-lead/25e4f92aa35e` | **Date**: 2026-09-06 | **Spec**: `spec.md`

**Input**: MY-1537, `AUTH-20260905-01`, and the repository/live-role audit in `research.md`

## Summary

Align active VitalStride governance to the live Dev Team pipeline by recording a new durable ADR,
updating the constitution and active operator/context documents, and attaching narrow partial
supersession metadata to the two accepted ADRs whose delivery-role clauses are stale. The change is
one dependency-free RepoInfra governance task over an eight-file support-only allowlist. It does not
change product behavior, repository automation, required checks, layer routing, or any existing
delivery state. It preserves the direct shipping-repair loop for clear implementation/check failures
and the Team Lead route for exceptional recovery.

## Technical Context

**Language/Version**: Markdown governance; constitution semantic version `3.0.0 → 3.1.0`

**Primary Dependencies**: Repository ADR governance, Spec Kit planning artifacts, live Multica role
instructions, `AUTH-20260905-01`

**Storage**: Git-tracked Markdown only; no runtime/persisted data model

**Testing**: `bash scripts/test-repoinfra.sh` from repository root plus read-only acceptance-to-task,
scope, and dependency consistency checks

**Target Platform**: Repository governance consumed by Multica delivery roles

**Project Type**: Support-only repository governance change scheduled under RepoInfra

**Performance Goals**: N/A

**Constraints**: Exact-revision review; one declared layer; eight-file implementation allowlist;
no product/CI/ruleset changes; no prior recovery-state reuse; no gate weakening

**Scale/Scope**: One vertical slice, one implementation task, zero layer dependencies

## Constitution Check — Before Research

| Gate | Result | Evidence |
|---|---|---|
| Privacy and product principles remain unchanged | PASS | Governance-only scope; no health values or product paths |
| One layer per executable task | PASS | One RepoInfra task under ADR-0021's narrow support-governance scheduling exception, `depends_on: []` |
| Support exclusions remain exclusions | PASS | No change to root routing or `RepoInfra/CONTEXT.md` |
| Accepted ADR history is not silently rewritten | PASS | New ADR-0021; ADR-0009/0014 status pointer only |
| Constitution change follows governance | PASS | New ADR + constitution patch + MINOR version bump + PR requirement |
| Exact review and delivery gates remain fail-closed | PASS | Contract preserves revision/workdir/check/PR/privacy invariants |
| Planner remains planning-only | PASS | Only `specs/025-*` authored in this phase; no implementation files changed |

## Phase 0: Research

`research.md` records the baseline SHA, source hierarchy, complete conflict inventory, decisions,
alternatives, and absence of the repository-declared freshness executable. No unresolved product or
authority question remains because actor authority is supplied by `AUTH-20260905-01` and the live
role instructions.

## Phase 1: Design

- `data-model.md` defines the non-persisted handoff evidence model and state boundaries.
- `contracts/delivery-workflow-contract.md` is the normative behavior and migration contract.
- The contract classifies shipping failures and defines the conditional
  `PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager` repair loop.
- `quickstart.md` gives the implementation sequence, residue review, rollback boundary, and exact
  repository verification.
- `tasks.md` defines one vertical slice and one layer-scoped task with the eight-file allowlist.

## Constitution Check — After Design

| Gate | Result | Evidence |
|---|---|---|
| Every acceptance criterion maps to a slice and task | PASS | `tasks.md` coverage matrix maps AC-1…AC-8 and FR-001…FR-017 to US1/T001 |
| Task contains complete DoR fields | PASS | Scope in/out, contract impact, acceptance, dependencies, context, verification |
| Dependency graph is acyclic | PASS | Single node `T001`, no edges |
| No compile-level implementation is inlined | PASS | Planning documents use behavioral prose and commands only |
| Exact implementation allowlist is bounded | PASS | Eight named governance files; planning artifacts explicitly excluded from FS scope |
| Fail-closed guarantees are testable | PASS | Contract and quickstart enumerate revision, workdir, dispatch, CI, PR, privacy checks |
| ADR-0017 and ADR-0019 bodies remain intact | PASS | ADR-0021 preserves ADR-0019 path classification while adding only a bounded scheduling exception |

## Project Structure

### Planning Documentation

```text
specs/025-dev-team-delivery-contract/
├── checklists/requirements.md
├── contracts/delivery-workflow-contract.md
├── data-model.md
├── plan.md
├── quickstart.md
├── research.md
├── spec.md
└── tasks.md
```

Planner Lead commits and pushes these files as the exact planning revision. Team Lead provisions T001
with that SHA as `delivery_base_sha`. They are immutable inherited PR evidence: Fullstack MUST verify
they remain byte-identical to the base and MUST NOT edit them.

### Implementation Surface

```text
AGENTS.md
CLAUDE.md
CONTEXT.md
.specify/memory/constitution.md
docs/adr/README.md
docs/adr/0009-pr-required-workflow.md
docs/adr/0014-restore-planner-review-dual-approval.md
docs/adr/0021-current-dev-team-delivery-contract.md
```

**Structure Decision**: Schedule the eight support files as one RepoInfra execution-layer task under
the narrow exception that ADR-0021 must record, because the decision is atomic and all files describe
the same delivery contract. ADR-0019 continues to classify governance/docs/`.specify/memory` as
support exclusions before layer matching; the exception affects scheduling and gate selection only.
T001 MUST preserve path classification and MUST NOT change `CONTEXT.md` routing or
`RepoInfra/CONTEXT.md`.

## Exact Allowlist and Edit Boundaries

| File | Authorized change |
|---|---|
| `AGENTS.md` | Replace stale role/workflow/recovery/dispatch sections with canonical live contract |
| `CLAUDE.md` | Replace “every agent watches/fixes/merges” with the canonical role handoff summary |
| `CONTEXT.md` | Update active workflow summary, role table, check names, and conflict ownership |
| `.specify/memory/constitution.md` | Amend workflow/roles/recovery text and bump version to `3.1.0` |
| `docs/adr/README.md` | Add missing ADR-0020 and new ADR-0021 index rows only |
| `docs/adr/0009-pr-required-workflow.md` | Status metadata only: delivery-role clauses partially superseded by ADR-0021 |
| `docs/adr/0014-restore-planner-review-dual-approval.md` | Status metadata only: exact-revision/shipping/dispatch clauses partially superseded by ADR-0021 |
| `docs/adr/0021-current-dev-team-delivery-contract.md` | New accepted decision, narrow RepoInfra execution-layer scheduling exception over unchanged support-path classification, migration, guarantees, consequences, references |

## Dependency and Contract Direction

- Declared execution layer: `RepoInfra` under the ADR-0021 governance-support scheduling exception.
- Repository layer dependencies: `depends_on: []`; `depended_by: []`.
- No product layer or package consumes this change as a code dependency.
- The new ADR is the durable decision source; the constitution is the governing summary; AGENTS is
  the operator manual; CLAUDE and CONTEXT remain thin active summaries.
- Live role instructions remain runtime authority; repository documents align to them and do not
  attempt to mutate Multica agent definitions.
- Shipping-time code/build/test/lint/repository-check failures with clear implementation ownership
  route directly from PR Manager to Fullstack Engineer, through fresh exact-revision review, and back
  to PR Manager. Exceptional or ambiguous recovery routes to Team Lead.

## Planning Publication and Implementation PR Scope

1. Planner Lead commits and pushes the eight `specs/025-dev-team-delivery-contract/**` artifacts and
   requests planning review against that exact SHA.
2. After an exact `PASS` or `PASS WITH FOLLOW-UP`, Team Lead uses that SHA as T001
   `delivery_base_sha`, provisions the single delivery workdir, and accepts readiness.
3. The eventual implementation PR is based on that SHA. Its three-dot diff against `main` includes
   the immutable reviewed planning folder plus the eight-file editable implementation allowlist.
4. Before implementation review, Fullstack proves the planning folder is unchanged from
   `delivery_base_sha` and proves local `HEAD ==` pushed branch OID `==` PR `headRefOid`.
5. Any change to the planning folder invalidates its prior verdict and is out of T001 scope; return
   it to Team Lead rather than silently absorbing it into implementation.

## Verification Strategy

From repository root:

1. `bash scripts/test-repoinfra.sh` — canonical RepoInfra gate; validates path/frontmatter,
   shell/Python syntax, and tooling tests without `xcodebuild`.
2. Read-only Analyze/manual checks — validate placeholders, Spec Kit task syntax, acceptance coverage,
   one-layer ownership, exact allowlist, and an acyclic dependency graph.
3. Git identity/scope checks — verify the immutable planning folder against `delivery_base_sha`, the
   eight-file editable allowlist, and local/remote/PR head equality.

The repository references `check-tasks-fresh` in governance but contains no executable by that name.
This plan MUST NOT claim that nonexistent check ran. Freshness is instead pinned by the exact Git
revision and the read-only consistency review above.

## Complexity Tracking

| Apparent exception | Why needed | Simpler alternative rejected because |
|---|---|---|
| RepoInfra scheduling over support exclusions | ADR-0021 authorizes one bounded execution-layer exception while ADR-0019 path classification remains unchanged | Reclassifying governance paths as ordinary RepoInfra ownership would expand the layer universe |
| One atomic task over eight files | All active summaries and ADR pointers must agree at one revision | Splitting files would create intermediate contradictory governance and file conflicts |
