# ADR-0021: Current Dev Team Delivery Contract

**Status**: Accepted
**Date**: 2026-09-05
**Deciders**: Team Lead + Dev Team
**Effective**: `AUTH-20260905-01` on 2026-09-05
**Supersedes**: stale role wording and exact-revision/dispatch clauses embedded in active governance docs and ADR-0009/0014; does not rewrite the accepted ADR bodies themselves

## Context

The repository's live governance text drifted into a split story:

- some instructions still describe Team Lead as the normal merger/rebaser for shipping work;
- some instructions still treat a PR comment or issue assignment as proof of dispatch without verifying a queued/dispatched/running run;
- the exact-revision contract and `delivery_base_sha`/`delivery_*` metadata proof were described in multiple places but not enforced as one canonical rule.

This made the active delivery contract harder to audit, especially for RepoInfra governance-support work that is intentionally small in surface but high in policy risk. The fix must be narrow, fail-closed, and non-invasive: preserve the historical ADR bodies, keep ADR-0019 path ownership unchanged, and add one explicit governance exception for the exact governance-support files admitted by T001.

## Decision

1. **Single canonical pipeline**
   - The active delivery pipeline is: `TL → Planner → FS → AI Reviewer → PR Manager`.
   - `Team Lead` owns readiness acceptance, scheduling, recovery, Owner escalation, and lifecycle closure.
   - `Planner Lead` owns the planning/DoR package but does not implement product code.
   - `Fullstack Engineer` owns the implementation, exact-candidate publication, and exact revision refresh, but does not own final shipping/merge readiness.
   - `AI Reviewer` owns exact-revision review and planning/DoR review.
   - `PR Manager` owns required-check supervision, final readiness, merge/cleanup, and shipping handoff.

2. **Exact-revision and workdir fail-closed proof**
   - The issue must carry the four `delivery_*` keys: `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha`.
   - `delivery_base_sha` must be the reviewed planning SHA and must remain the immutable planning baseline for the inherited `specs/025-dev-team-delivery-contract/**` folder.
   - Before any review or shipping handoff, the local `HEAD` must match the pushed branch OID and the PR `headRefOid`; mismatches are blockers, not warnings.
   - Missing or mismatched workdir metadata, branch identity, or exact SHA causes the issue to route back to Team Lead instead of silently moving forward.

3. **Dispatch proof is run evidence, not assignment text**
   - Parent assignment to Dev Team stays intact while the work is active.
   - The final role mention names the next actor explicitly and is not used as a substitute for a real queued/dispatched/running run.
   - A bare issue comment or plain assignment without observed run evidence is not valid dispatch proof.
   - The implementation must not claim a candidate is ready until the real run/PR state is visible.

4. **RepoInfra scheduling exception is bounded and support-only**
   - ADR-0019 path classification remains unchanged. This ADR adds a narrow scheduling exception only for designated governance-support files, not a general reclassification of repo infrastructure ownership.
   - The T001 allowlist remains exactly: `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, `.specify/memory/constitution.md`, `docs/adr/README.md`, the status-only pointer updates in `docs/adr/0009-pr-required-workflow.md` and `docs/adr/0014-restore-planner-review-dual-approval.md`, and the new `docs/adr/0021-current-dev-team-delivery-contract.md`.
   - All product/runtime paths, AppUI, packages, CI/workflow/rulesets, scripts, credential files, and inherited planning artifacts remain outside scope.

5. **Repair and migration rules**
   - In-flight planning, implementation, shipping, merged, changed-SHA, failed-dispatch, and mismatched-workdir states each have a forward-only migration boundary; no state is copied or rebuilt from an invalid prior run.
   - A shipping failure or repository-check failure routes `PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager` with the same scope and a fresh exact-revision review.
   - Conflicting evidence, ambiguous ownership, policy/content decisions, permissions, infrastructure, repeated repair, and merge conflicts route to Team Lead.

## Consequences

### Positive
- Delivery governance is explicit, canonical, and auditable.
- The exact revision, branch, PR, and workdir proofs are fail-closed instead of aspirational.
- Small governance-support changes remain possible without reclassifying the repository's product path ownership.
- The issue lifecycle and handoff boundaries are enforced consistently across review, repair, and shipping.

### Costs and constraints
- Governance documents must remain precise; drift in wording is treated as a real workflow failure.
- Team Lead now owns the lifecycle and recovery path more explicitly, which makes silent state drift less tolerated.
- The selected governance files must stay narrow; any attempt to expand into CI, product, or planning artifacts violates the ADR and the task scope.

## Implementation references
- `AGENTS.md` — active role pipeline and FS/PR Manager split
- `CLAUDE.md` — canonical Dev Team workflow and roles
- `CONTEXT.md` — root-layer contract and delivery invariants
- `.specify/memory/constitution.md` — version bump to 3.1.0 and workflow/role contract
- `docs/adr/README.md` — index row for ADR-0020 and ADR-0021
- `docs/adr/0009-pr-required-workflow.md` — status pointer only
- `docs/adr/0014-restore-planner-review-dual-approval.md` — status pointer only
- `specs/025-dev-team-delivery-contract/**` — immutable planning baseline at `delivery_base_sha`
