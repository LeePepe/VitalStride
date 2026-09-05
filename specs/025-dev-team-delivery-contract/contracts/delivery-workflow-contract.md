# Contract: Current Dev Team Delivery Workflow

## Authority and Scope

This contract operationalizes `AUTH-20260905-01` for VitalStride repository governance. It changes
documentation only and preserves the MY-1537 recovery contract and all issue non-goals.

## Canonical Pipeline

`Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`

- `⇄` means the artifact author owns a direct exact-revision review/refinement loop.
- `→` means the upstream role posts a final handoff naming the next role and verifies a downstream
  run becomes queued, dispatched, or running.
- Parent issues remain assigned to Dev Team. Individual-role reassignment is not the dispatch model.

## Role Boundaries

| Role | Owns | Must not own |
|---|---|---|
| Planner Lead | clarification, Spec Kit artifacts, vertical slices, task graph, planning review loop | implementation, implementation dispatch, CI, shipping, lifecycle |
| AI Reviewer | exact-revision content review and verdict | artifact fixes, build/test/lint/hook/CI, shipping, lifecycle |
| Team Lead | readiness acceptance, scheduling, workspace provisioning, recovery, Owner escalation, lifecycle closure | planning authoring, implementation, content review, CI supervision, merge, cleanup |
| Fullstack Engineer | implementation, optional local validation, commit/push, PR creation/update as candidate publication before review, self-review, implementation review loop | cross-layer expansion, PR readiness, CI supervision, merge, cleanup, lifecycle |
| PR Manager | CI/readiness supervision, repository-approved shipping, delivery confirmation, task cleanup | implementation repair, content review, scope/acceptance changes, lifecycle closure |

## Fail-Closed Invariants

1. Planning and implementation reviews apply to one published exact Git revision.
2. A revision change invalidates the earlier verdict.
3. Delivery uses exactly one issue-scoped workdir and exact keys `delivery_repo_url`,
   `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha`.
4. At both implementation-review and shipping handoffs, local `HEAD`, the pushed branch OID, and PR
   `headRefOid` are byte-identical.
5. All nine status checks remain required: `Lint & policy`, `SPM VitalModels`,
   `SPM HealthKitService`, `SPM AIService`, `SPM VitalUI`, `SPM TelemetryKit`, `SPM DesignKit`,
   `App target`, and `codex-review-target`; Claude remains paused and Kimi remains advisory-only.
6. Direct main pushes, force pushes, bypassed hooks/checks/reviews, fabricated evidence, and stale
   verdicts are prohibited.
7. Health data privacy and all constitution Core Principles remain unchanged.
8. A final role mention without a queued/dispatched/running run is a failed dispatch.
9. Missing, mismatched, or contradictory evidence routes to Team Lead; no role guesses or weakens a
   gate.
10. Cleanup is limited to task-owned artifacts after delivery is proven.

## Shipping-Time Failure Routing

PR Manager classifies complete current-head failure evidence before routing it.

### Clear implementation/check failure

For a code, build, test, lint, or repository-check failure clearly owned by the implementation:

1. PR Manager posts one structured repair request with the PR, exact failing HEAD, failing checks,
   concise evidence, unchanged scope, and Fullstack Engineer as the next actor.
2. Fullstack Engineer reuses the exact `delivery_work_dir`, repairs only the authorized scope,
   publishes a new exact SHA/PR head, and performs self-review.
3. Fullstack Engineer requests fresh exact-revision review from AI Reviewer; the prior verdict is
   stale after any candidate change.
4. On `PASS` or `PASS WITH FOLLOW-UP`, Fullstack Engineer hands the new reviewed SHA directly back to
   PR Manager, which restarts shipping supervision.

This conditional loop is
`PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager`. Team Lead is not a normal hop in a
clear implementation repair.

### Exceptional or ambiguous failure

PR Manager routes merge conflicts, permissions, infrastructure failures, contradictory
CI/review/repository evidence, ambiguous ownership, repeated repair failure, and any policy/content
decision to Team Lead with the exact evidence and required decision. PR Manager stops without
guessing, widening scope, implementing a repair, or weakening a gate. Team Lead owns recovery,
re-scope, rerouting, or Owner escalation.

## Effective Cutover and In-Flight Migration

`AUTH-20260905-01` became effective when approved on 2026-09-05. The governance PR merge records the
already-authoritative contract; it is not the cutoff. An actor active at approval may finish only its
current atomic action. Every subsequent handoff uses this contract. Migration is forward-only and
does not recreate or move existing work.

| Existing state | Required transition |
|---|---|
| Planner is authoring or refining | Publish the current fresh planning revision, finish exact review with AI Reviewer, then hand `PASS` or `PASS WITH FOLLOW-UP` evidence to Team Lead |
| Planning `PASS` or `PASS WITH FOLLOW-UP` exists for unchanged SHA | Preserve it; Team Lead performs readiness acceptance/scheduling without duplicate review |
| Fullstack is implementing or refining | Preserve workdir/branch/commits; create/update the candidate PR, finish exact review with AI Reviewer, then hand `PASS` or `PASS WITH FOLLOW-UP` directly to PR Manager |
| Implementation `PASS` or `PASS WITH FOLLOW-UP` exists for unchanged SHA | Preserve it; hand the exact candidate to PR Manager without routing through Team Lead |
| Candidate SHA changed | Treat prior verdict as stale and obtain a fresh exact-revision review |
| Shipping has a clear implementation/check failure | PR Manager sends exact evidence directly to Fullstack; Fullstack publishes a new SHA, obtains fresh AI review, and returns a passing candidate to PR Manager |
| Shipping has conflicting evidence, ownership/policy/permission/infrastructure uncertainty, repeated repair, or merge conflict | PR Manager stops and routes exact evidence to Team Lead for recovery or escalation |
| TL is performing shipping work under old text | Stop shipping mutation; hand exact candidate/PR/gate evidence to PR Manager and verify its run |
| PR is already merged | PR Manager confirms exact delivery and task cleanup, then hands evidence to Team Lead for closure |
| Mention/comment produced no run | Treat dispatch as failed; Team Lead recovers or escalates with evidence |
| Workdir or delivery metadata mismatches | Stop; preserve state and return exact evidence to Team Lead |

Existing issue/workdir/branch/commit/PR/review evidence stays in place. No migration step copies
between workdirs, resets a branch, mutates an unrelated issue, or imports MY-1531/MY-1534 state.

## Governance

- ADR-0021 is the durable decision that partially supersedes only stale actor/exact-revision/dispatch
  clauses of ADR-0009 and ADR-0014.
- ADR-0017 no-code-inlining and visual acceptance decisions remain unchanged.
- ADR-0019 support/generated path classification remains unchanged. ADR-0021 creates only a narrow
  execution-layer scheduling exception for this bounded governance alignment and its RepoInfra gate.
- The constitution receives a MINOR version bump to 3.1.0.
