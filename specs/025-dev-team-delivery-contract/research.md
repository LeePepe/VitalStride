# Research: Current Dev Team Delivery Contract

## Baseline and Provenance

- Fresh MY-1537 checkout baseline: `b72876cda30e503f073c76358351f99f0fac39fd`
- Branch: `agent/planner-lead/25e4f92aa35e`
- Authority: owner decision `AUTH-20260905-01`
- Recovery: new issue/workdir/session only; no MY-1531/MY-1534 state or artifact was reused
- `docs/DESIGN.md`: absent on the baseline and therefore not a source for this change

## Source Hierarchy

1. Repository constitution and active repository instructions.
2. Accepted ADR governance and applicable context files.
3. MY-1537 authority, acceptance, non-goals, and recovery contract.
4. Live Planner Lead, AI Reviewer, Team Lead, Fullstack Engineer, and PR Manager instructions read on
   2026-09-06.

Where older repository text conflicts with the live delivery contract, ADR-0021 records the durable
alignment rather than silently editing historical rationale.

## Decisions

### D1 — One canonical pipeline

Use `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`.
The bidirectional links are exact-revision author/reviewer refinement loops. The terminal Team Lead
owns lifecycle closure, not shipping.

### D2 — New ADR with narrow partial supersession

Create ADR-0021. Preserve accepted ADR history. Change only the status metadata of ADR-0009 and
ADR-0014 to point at the clauses superseded by ADR-0021. Leave ADR-0017 and ADR-0019 bodies
unchanged; ADR-0021 adds a narrow scheduling exception without changing ADR-0019 path ownership.

### D3 — Constitution version 3.1.0

This adds/formalizes a delivery role and dispatch-proof contract without reversing a Core Principle.
It is a MINOR amendment, analogous to the stage addition recorded for constitution 2.5.0.

### D4 — One RepoInfra governance task without reclassification

The Fullstack task has one declared execution layer (`RepoInfra`) and zero task dependencies under
ADR-0021's bounded governance-support scheduling exception. All authorized governance files remain
support exclusions under ADR-0019; no route/frontmatter change is allowed.

### D5 — Exact revision and dispatch evidence

Planning and implementation review apply only to the pinned published revision. A final role mention
is the dispatch mechanism, but success requires an observed queued/dispatched/running run. Failure to
observe one routes to Team Lead recovery.

### D6 — In-flight migration at the next actor boundary

`AUTH-20260905-01` became effective when approved on 2026-09-05; the governance PR merge documents
that authority but does not delay it. Preserve existing workdir, delivery metadata, branch, commits,
PR, and valid review evidence. An actor already executing may finish only its current atomic action;
its next handoff uses the new route. A changed SHA requires new review; unchanged valid evidence is
not repeated.

### D7 — Classify shipping failures before routing

Preserve the live conditional loop. A clear code, build, test, lint, or repository-check failure
owned by implementation routes `PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager` with
the same workdir and scope, a new published SHA, and fresh exact-revision review. Contradictory
CI/review/repository evidence, ambiguous ownership, policy/content decisions, permissions,
infrastructure failures, repeated repairs, and merge conflicts route to Team Lead for recovery or
Owner escalation.

## Complete Conflict Inventory

| Source | Conflicting statement | Resolution in T001 |
|---|---|---|
| `AGENTS.md` Roles | Planner does not push; FS opens PR to TL; TL owns CI/merge/conflicts; PR Manager absent | Define all five live roles; Planner may publish planning revisions; FS creates/updates the candidate PR before exact review; FS review pass goes to PR Manager; TL closes lifecycle |
| `AGENTS.md` Planning Review | Old double-approval wording lacks exact candidate/run-proof semantics | Preserve independent planning review; require exact revision, Team Lead readiness acceptance, final role mention, and run proof |
| `AGENTS.md` FS workflow | FS opens PR and assigns back to TL without independent exact-revision handoff | Replace with implementation → publish → AI Reviewer loop → direct PR Manager handoff |
| `AGENTS.md` TL workflow | TL locates PR, watches CI, rebases, merges, deletes branch | Move all shipping state to PR Manager; TL retains recovery and post-delivery closure |
| `AGENTS.md` auto-merge | TL monitors machine merge and performs shipping follow-up | PR Manager monitors/ships/cleans; Team Lead acts on final delivery evidence |
| `AGENTS.md` dispatch | assign+todo is the dispatch mechanism; bare mention is non-triggering | Parent remains Dev Team; exact role mention dispatches; observed run is required proof |
| `AGENTS.md` recovery | Hermes auto-dispatch/background recovery is the default and delays Owner escalation | Team Lead classifies recovery and performs precise Owner escalation when external authority is required; no background-and-yield contract |
| `AGENTS.md` startup scan | TL scans, reviews, and merges open PRs | PR Manager owns shipping state; Team Lead only handles lifecycle/recovery state |
| `AGENTS.md` Spec Kit block | `/speckit-implement` is unused but the stated pipeline is `TL → FS → Reviewer` and task import precedes review | Keep implementation outside Spec Kit; insert planning exact-revision review and PR Manager/final TL stages |
| `.specify/workflows/speckit/workflow.yml` | Bundled generic workflow contains an `implement` step | Preserve file; repository overlay continues to stop at Tasks/Analyze and route implementation through Multica |
| `CLAUDE.md` PR flow | Any agent must poll to merge, directly repair failures, force-with-lease if needed, and sync the user checkout | Replace with role-owned handoffs; no cross-role repair, force push, or user-checkout mutation |
| `CLAUDE.md` checks | `codex-review` and `claude-review` are both required | Use current `codex-review-target`; Claude paused; Kimi advisory; deterministic checks remain required |
| `CONTEXT.md` Git summary | FS opens PR and TL merges/resolves shipping conflicts | Use canonical pipeline; PR Manager ships, Team Lead recovers/closes |
| `CONTEXT.md` required checks | Claude + Codex and a stale total are required | Match current AGENTS/constitution without weakening any declared gate |
| Constitution role table | Only FS/TL/Reviewer are shown and TL merges | Add Planner Lead and PR Manager and current ownership boundaries |
| Constitution Issue Tracker | Hermes writes planning and pipeline ends at Reviewer | Planner Lead owns planning; canonical pipeline includes both review loops, PR Manager, and final Team Lead |
| Constitution dual approval | Does not distinguish exact review from Team Lead readiness acceptance | AI Reviewer returns an exact-revision verdict; Team Lead accepts readiness and schedules |
| Constitution Quality Bar J | Correctly separates AI Reviewer content review from PR Manager gate classification and routes patch-induced implementation failures to Fullstack | Preserve this branch and complete it with fresh exact-revision review back to PR Manager; route non-implementation/ambiguous recovery to Team Lead |
| Constitution recovery | Routine failures require Hermes and a fixed retry path | Team Lead owns recovery and Owner escalation; preserve classification and fail-closed behavior |
| Constitution startup scan | TL advances/merges open PRs | PR Manager owns shipping; Team Lead owns lifecycle/recovery |
| Constitution governance roster | Omits Planner/PR Manager and lists stale actors | Name all live delivery roles |
| ADR-0009 | FS hands PR to TL; TL owns CI/review/rebase/merge; stale check totals/full pre-push wording | Partially supersede actor clauses only; preserve PR-required/main-protection decision; active docs carry current gates |
| ADR-0014 planning clause | Planning review assumes artifacts on `github/main` and older verdict vocabulary | Review a pinned candidate revision using current verdict contract |
| ADR-0014 D5 | TL monitors auto-merge/shipping | PR Manager owns shipping observation; Team Lead owns closure |
| ADR-0014 D6 | assign+todo rather than mention dispatches FS | Final role mention plus verified run; parent stays Dev Team |
| ADR-0017 alternative | Describes Planner as not pushing | Clarify in ADR-0021 that Planner may publish planning documents but never implementation; preserve ADR-0017 D1-D3 unchanged |
| ADR-0019 / `RepoInfra/CONTEXT.md` | Governance files are support exclusions | Preserve exactly; do not reclassify to satisfy task scheduling |
| `docs/adr/README.md` | Index omits ADR-0020 and contains historical count/order drift | Add ADR-0020 and ADR-0021 rows only; do not repair unrelated duplicate ADR-0015 |
| Live PR Manager shipping contract | Clear implementation failures return directly to Fullstack; merge conflicts, permissions, infrastructure, contradictory evidence, ambiguous ownership, repeated repair, and policy/content decisions return to Team Lead | Install both conditional routes in active governance; every candidate repair requires fresh AI review before shipping resumes |

## Preserved Guarantees

- Health data privacy and all constitution Core Principles.
- PR-required delivery, direct-main prohibition, branch protection, hooks, and required checks.
- Nine required checks: `Lint & policy`, `SPM VitalModels`, `SPM HealthKitService`, `SPM AIService`,
  `SPM VitalUI`, `SPM TelemetryKit`, `SPM DesignKit`, `App target`, `codex-review-target`; Claude
  paused; Kimi advisory only.
- Exact planning/implementation revision review and local/remote/PR identity equality where applicable.
- One issue-scoped workdir with pinned repository, branch, and base SHA.
- No force push, bypass, fabricated check, stale verdict, destructive cleanup, or cross-layer expansion.
- AI Reviewer content-only boundary; PR Manager gate/shipping boundary.

## Alternatives Considered

- **Edit ADR-0009/0014 bodies in place**: rejected; accepted ADRs are historical artifacts.
- **Treat live instructions as temporary and keep repository wording**: rejected; violates the approved
  alignment outcome and continues contradictory dispatch.
- **Move governance files into ordinary RepoInfra path ownership**: rejected; ADR-0021 instead adds a
  bounded scheduling/gate exception while preserving ADR-0019 classification.
- **Split the implementation by file**: rejected; produces contradictory intermediate governance and
  overlapping task scopes.
- **Reuse predecessor planning**: rejected by the recovery contract; this package is fresh.

## Validation Capability Gap

The constitution and ADR-0014 mention `check-tasks-fresh`, but the baseline contains no tracked
executable, workflow, or command with that name. The package uses native prerequisite checks plus
read-only semantic/coverage analysis and exact Git revision pinning. It does not fabricate a
freshness result.
