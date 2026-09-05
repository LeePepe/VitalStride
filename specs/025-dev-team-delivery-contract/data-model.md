# Data Model: Delivery Workflow Evidence

No product or persisted data model changes are required. These conceptual records define the
governance contract and acceptance vocabulary.

## Planning Revision

- **Identity**: full Git SHA
- **Content**: `spec.md`, `plan.md`, `tasks.md`, required Plan artifacts
- **Owner**: Planner Lead
- **Valid when**: published and identical to the revision requested from AI Reviewer
- **Invalidated by**: any content change producing a new SHA

## Delivery Workspace

- **Identity**: issue-scoped directory
- **Required keys**: `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, `delivery_base_sha`
- **Provisioner**: Team Lead
- **Consumers**: Fullstack Engineer, AI Reviewer, PR Manager
- **Invalid state**: missing/mismatched metadata or concurrent ownership

## Delivery Candidate

- **Identity**: full implementation Git SHA
- **Required equality at both review and shipping handoffs**: local `HEAD` equals pushed branch OID
  equals PR `headRefOid`
- **Owner before PASS**: Fullstack Engineer
- **Owner after exact PASS handoff**: PR Manager
- **Invalidated by**: new commit, rewritten branch, target mismatch, or stale review

## Dispatch Evidence

- **Intent**: final exact role mention in a handoff comment
- **Proof**: at least one run for that role in `queued`, `dispatched`, or `running`
- **Invalid state**: comment or mention without an observable run
- **Recovery owner**: Team Lead

## Shipping Evidence

- **Owner**: PR Manager
- **Attributes**: reviewed head, required-check state, PR state, merge result/target revision, cleanup
- **Valid when**: all evidence refers to the exact approved candidate or documented merge result
- **Consumer**: Team Lead for lifecycle closure

## Shipping Failure Classification

- **Implementation-owned**: clear code, build, test, lint, or repository-check failure. PR Manager
  sends the exact candidate/failure evidence and unchanged scope directly to Fullstack Engineer.
- **Exceptional/ambiguous**: conflicting CI/review/repository evidence, ambiguous ownership,
  policy/content decision, permission, infrastructure failure, repeated repair, or merge conflict.
  PR Manager sends the evidence and required decision to Team Lead.
- **Repair invariant**: Fullstack reuses the exact delivery workdir, publishes a new SHA, obtains a
  fresh exact-revision AI Reviewer verdict, and returns a passing candidate to PR Manager.

## State Sequence

1. Planner Lead authors, commits, and pushes a Planning Revision.
2. Planner Lead and AI Reviewer refine until an exact-revision PASS/PASS WITH FOLLOW-UP.
3. Team Lead accepts readiness, provisions T001 with the Planning Revision as `delivery_base_sha`,
   and proves Fullstack dispatch.
4. Fullstack Engineer authors and publishes a Delivery Candidate, creates/updates its PR, and proves
   the inherited planning folder is byte-identical to `delivery_base_sha`.
5. Fullstack Engineer and AI Reviewer refine until an exact-revision PASS/PASS WITH FOLLOW-UP.
6. Fullstack Engineer proves PR Manager dispatch.
7. PR Manager supervises and confirms Shipping Evidence.
8. Team Lead performs Lifecycle Closure.

If step 7 finds an implementation-owned failure, the flow returns to steps 4–7 through fresh review.
If it finds an exceptional/ambiguous failure, it routes to Team Lead recovery without changing scope
or weakening a gate.

No state permits a role to infer missing revision, workdir, run, check, or merge evidence.
