# Quickstart: Implement and Verify the Governance Alignment

## Preconditions

- Work only in the Team Lead-provisioned implementation child's `delivery_work_dir`.
- Confirm `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha`, the
  clean starting state, and exact T001 allowlist. `delivery_base_sha` is the reviewed planning SHA.
- Read the constitution, AGENTS, root and RepoInfra contexts, ADR-0009/0014/0017/0019/0020, this
  feature package, and the current live role contract.
- Do not access or reuse MY-1531/MY-1534 sessions, workdirs, or artifacts.

## Implementation Sequence

1. Add ADR-0021 with `AUTH-20260905-01` effective on 2026-09-05, the canonical pipeline, role boundaries, exact-revision and
   dispatch-proof guarantees, the bounded RepoInfra scheduling rule that leaves support exclusions
   unchanged, migration table, consequences, and implementation references.
2. Add ADR-0021 and the currently missing ADR-0020 row to the ADR index; do not fix unrelated index
   history.
3. Change only status/supersession metadata in ADR-0009 and ADR-0014.
4. Amend constitution workflow/roles/recovery/governance text and bump `3.0.0` to `3.1.0`.
5. Align AGENTS, CLAUDE, and root CONTEXT active workflow text, including FS ownership of candidate
   PR creation/update before exact review and PR Manager ownership beginning at readiness/shipping.
6. Confirm the inherited `specs/025-dev-team-delivery-contract/**` files are byte-identical to
   `delivery_base_sha` and have not been edited by Fullstack.
7. Confirm ADR-0017, ADR-0019, `RepoInfra/CONTEXT.md`, layer routes, CI/workflows/rulesets, and all
   product paths are unchanged.

## Semantic Residue Review

In active documents (`AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, constitution), confirm:

- exactly one canonical pipeline is present;
- PR Manager owns CI/readiness/merge/cleanup;
- Team Lead owns readiness/scheduling/recovery/Owner escalation/lifecycle closure;
- Planner and Fullstack each own their direct exact-revision AI Reviewer loop;
- parent assignment, final role mention, and queued/dispatched/running proof are explicit;
- no instruction tells Team Lead to merge/rebase/watch CI as normal work;
- no instruction tells Fullstack to hand a passing candidate to Team Lead;
- no instruction treats assign+todo or a comment alone as proven dispatch;
- current required-check names and advisory/paused reviewers agree.

Historical ADR bodies may retain superseded actor wording; the status metadata and ADR-0021 identify
the current decision.

## Repository Verification

From repository root run:

```bash
bash scripts/test-repoinfra.sh
```

Do not run `xcodebuild`; this governance/RepoInfra task has no AppUI or package surface.

The repository has no executable `check-tasks-fresh`; do not claim that it ran. Planner Lead's
published exact revision and AI Reviewer verdict are the freshness evidence for T001.

## Rollback Boundary

If verification or review fails, change only the eight allowlisted governance files and publish a new
exact revision for review. Do not weaken checks, edit routes, reset/copy the delivery workdir, modify
accepted ADR history beyond status metadata, or expand into CI/product files.
