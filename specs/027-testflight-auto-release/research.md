# Research: TestFlight auto-release after verified main CI

**Exact base**: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`

**Current authority**: MY-1766 Owner decision plus comments `01a13b86-1f43-7964-b7e7-013db4029fe3`, `01a13b86-1ed5-7b57-b69a-3deaa4299249`, and Team Lead handoff `01a13b8b-7541-7ef5-b7c9-ae16701118bb`.

## R1 — Trigger and candidate identity

**Decision**: Consume completed workflow `CI` through `workflow_run`; accept only successful `push` runs whose head branch is `main`; bind every automatic decision to `workflow_run.head_sha`. Manual dispatch captures current remote `main` once.

**Why**: A direct push trigger does not prove required CI passed for that SHA. Checking out moving `main` may release a later unverified commit.

**Rejected**: direct `push: main`; workflow-name/conclusion checks without event/branch guards; moving-main checkout.

## R2 — Accumulated app relevance and bootstrap

**Decision**: With a valid ancestor marker, classify NUL-safe records in `testflight/last-released..candidate`. With no marker, classify empty-tree-to-candidate as an ephemeral bootstrap. Use narrow shipped path predicates with endpoint-first exclusions. A relevant deletion or either relevant rename/copy endpoint qualifies; a mixed diff qualifies when any record is relevant.

**Why**: `workflow_run` offers no useful path filter. Keeping the marker unchanged makes skipped and failed changes accumulate naturally without a cursor or skip record. Empty-tree bootstrap allows first use without an out-of-band tag or second state.

**Ordering**: marker equal to or ahead of candidate means already covered and skips; marker ancestor of candidate evaluates normally; unreadable/non-commit/divergent marker fails closed.

**Rejected**: trigger-time paths; merged-PR-only diff; broad `Packages/**`; treating every commit as relevant; a durable bootstrap/cursor ref.

## R3 — One success marker and no automatic retry

**Decision**: `testflight/last-released` is the sole persistent release state and advances only after the critical lane succeeds. Do not persist per-SHA attempt/skip history, a custom queue/cursor, a transaction journal, compare-and-swap lease, or recovery refs. A failure before the final marker step leaves the marker untouched. A later main-CI event or manual dispatch re-evaluates the unchanged range as a new run.

**Why**: The delegated Owner decision deliberately chooses the smallest model. Accumulated range evaluation preserves skipped/failed changes without auxiliary state. One app concurrency group serializes active lanes; it is not a durable FIFO queue and does not promise every platform-pending event runs in arrival order.

**Final marker failure**: The marker update/readback is terminal. If either fails, record the phase and last safely observed value, write no compensating state, and do not retry or roll back. A later invocation freshly fetches the remote marker as sole truth. Without the removed journal/lease machinery, the plan intentionally does not claim that a lost remote acknowledgement proves the tag stayed unchanged.

**Rejected**: immutable attempt tags; queue/skip/cursor refs; marker transaction pairs; lifetime same-SHA prohibition; distinct-SHA-only recovery; automatic retry or rollback.

## R4 — Version seam

**Decision**: Read and validate one uniform project marketing version. Resolve the exact candidate's uniquely associated merged PR for both automatic and manual candidates; case-sensitive `release:minor` makes a per-run minor increment. Earlier PR labels in the accumulated range do not affect this candidate. Pass one resolved value to Fastlane. Keep the existing app-wide ASC maximum-plus-one build counter and expose it safely.

**Why**: Fastfile's hardcoded value drifts from `project.yml`. Repository writes from the release runner would violate PR-required delivery and XcodeGen ownership.

**Rejected**: committing a version bump; keeping hardcoded Fastfile version; applying labels from any earlier range PR; scoping build counter by marketing version; GitHub run number.

## R5 — Fail-closed release phases and final marker ordering

**Decision**: Candidate/marker/PR/version validation, signing, archive, upload, Apple processing, internal distribution, dSYM publication, marker update, and marker readback are critical. No marker command runs until every earlier critical phase succeeds. Exact marker readback is required for terminal success. Each failure records a safe phase/reason and performs no automatic retry/rollback. TEMP-PRELAUNCH remains warning-only under its accepted internal-TestFlight policy.

**Why**: The base contains best-effort distribution/dSYM behavior that could advance the marker after incomplete release work. The original Owner requirement is fail closed. The final marker is the only completion boundary in the simplified model.

**Rejected**: moving marker before the lane; rescue-and-continue for critical phases; writing a second state to resolve marker ambiguity; asserting unobservable remote state.

## R6 — Approval and permission boundary

**Decision**: Limit implementation to one workflow, the existing Fastfile, and its existing regression module. Require explicit Owner approval before merge. GitHub permissions cover only exact PR-label reads and the sole moving marker write/read; add no secret.

**Why**: No tracked CODEOWNERS or machine-enforced code-owner review exists on the planning base. Owner approval remains separate from AI content review and CI.

**Rejected**: CODEOWNERS/ruleset expansion; AI PASS as Owner approval; a second release workflow/service.

## R7 — Verification boundary

**Decision**: Use credential-free contract tests for event identity, exact SHA, bootstrap/marker ordering, accumulated path matrices, irrelevant→relevant accumulation, failure→later pickup, stale/divergent events, bounded force, shared version policy, concurrency, final marker ordering, and safe summaries. Add Fastfile syntax, complete RepoInfra output, whitespace/static inspection, and one post-merge operational record. Planning and pre-merge checks never upload or mutate tags.

**Baseline note**: The focused base test reports 10/10 passing. The full RepoInfra wrapper previously returned zero while nested Python output contained one failure and one error under Xcode Python 3.9; completion evidence must inspect full output, not exit code alone.
