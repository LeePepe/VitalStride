# Feature Specification: Current Dev Team Delivery Contract

**Feature Branch**: `agent/planner-lead/25e4f92aa35e`

**Created**: 2026-09-06

**Status**: Ready for independent planning review

**Input**: MY-1537 and owner decision `AUTH-20260905-01`

## User Scenarios & Testing

### User Story 1 - One fail-closed delivery contract (Priority: P1)

A Dev Team participant can read the active repository governance and follow one unambiguous role
pipeline from planning through closure without receiving stale dispatch, review, shipping, recovery,
or merge instructions.

**Why this priority**: Conflicting actor ownership can bypass an exact-revision gate, strand a
handoff, or ask the wrong role to mutate shipping state.

**Independent Test**: Review the authorized governance surface and confirm that every active
workflow summary resolves to the same pipeline, role ownership, dispatch proof, migration rule,
and fail-closed guarantees.

**Acceptance Scenarios**:

1. **Given** a change that requires Spec Kit planning, **When** Planner Lead publishes a candidate,
   **Then** Planner Lead and AI Reviewer close an exact-revision review loop before Team Lead accepts
   readiness or schedules implementation.
2. **Given** a ready layer task, **When** Team Lead dispatches Fullstack Engineer, **Then** the parent
   remains assigned to Dev Team, the final role mention selects the next actor, and a
   queued/dispatched/running run is required as dispatch proof.
3. **Given** Fullstack Engineer publishes an implementation candidate, **When** AI Reviewer returns
   a passing verdict for that exact revision, **Then** Fullstack Engineer hands it directly to PR
   Manager for shipping.
4. **Given** a shipping candidate, **When** CI, readiness, merge, or cleanup is required, **Then** PR
   Manager owns that state and Team Lead performs lifecycle closure only after delivery evidence.
5. **Given** any exact-SHA, workdir, privacy, required-check, or PR-required evidence is missing or
   contradictory, **When** an actor evaluates the handoff, **Then** the pipeline stops and routes the
   evidence to Team Lead rather than guessing, bypassing, or weakening a gate.
6. **Given** an issue already in flight under the prior repository wording, **When** it reaches its
   next actor boundary, **Then** it adopts the current live contract without rebuilding or copying
   its workdir, branch, commit, PR, or valid exact-revision evidence.
7. **Given** the planning revision receives a passing exact-revision verdict, **When** Team Lead
   provisions T001, **Then** that planning SHA becomes `delivery_base_sha` and its planning artifacts
   remain immutable inherited scope in the implementation PR.
8. **Given** PR Manager observes a shipping-time failure, **When** it classifies the evidence,
   **Then** a clear implementation/check failure routes directly through
   `PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager`, while conflicting evidence,
   ownership, policy, permissions, infrastructure, repeated repair, or merge conflicts route to Team
   Lead for recovery or escalation.

### Edge Cases

- A mention/comment exists but no downstream run is queued, dispatched, or running: the handoff is
  not dispatched and Team Lead owns recovery.
- A reviewed SHA changes before shipping: the prior verdict is stale and fresh independent review is
  required.
- A workdir or any of `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, or
  `delivery_base_sha` is absent or mismatched: implementation/review/shipping stops and returns
  evidence to Team Lead.
- A PR is already merged when the new contract is adopted: PR Manager confirms shipping and cleanup
  evidence, then Team Lead closes the lifecycle.
- A required check is red, missing, or evaluated on a different head: shipping remains blocked.
- A code, build, test, lint, or repository-check failure is clearly owned by the implementation:
  PR Manager sends the exact failure evidence and unchanged scope directly to Fullstack Engineer;
  the repaired SHA requires fresh independent review before returning to PR Manager.
- A shipping failure is a merge conflict, permission/infrastructure fault, contradictory evidence,
  ambiguous ownership, repeated repair, or policy/content decision: PR Manager routes the evidence
  to Team Lead and stops without guessing or weakening the gate.
- An older accepted ADR contains historical actor wording: its history remains intact and a new ADR
  identifies only the superseded clauses.
- A governance file is classified as a support exclusion by ADR-0019: the classification remains
  unchanged even though the implementation task is scheduled under the single RepoInfra subject.

## Requirements

### Functional Requirements

- **FR-001**: Active repository governance MUST name the canonical pipeline as
  `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`.
- **FR-002**: Active governance MUST define Planner Lead as planning/DoR author and owner of the
  direct planning-review refinement loop, without implementation authority.
- **FR-003**: Active governance MUST define AI Reviewer as content-review owner for pinned planning
  and implementation revisions, without build/test/lint/hook/CI/shipping authority.
- **FR-004**: Active governance MUST define Team Lead as readiness acceptor, scheduler, recovery and
  Owner-escalation authority, delivery-workspace provisioner, and lifecycle closer.
- **FR-005**: Active governance MUST define Fullstack Engineer as implementation, optional local
  validation, commit/push, PR creation/update as candidate publication before independent review,
  self-review, and direct implementation-review loop owner; Fullstack MUST NOT mark the PR ready,
  supervise CI, enable merge, merge, or clean delivery state.
- **FR-006**: Active governance MUST define PR Manager as the sole owner of CI supervision,
  merge-readiness, repository-approved shipping, exact delivery confirmation, and task cleanup.
- **FR-007**: Dispatch MUST keep the parent issue assigned to Dev Team, use a final exact role
  mention for the next actor, and verify a queued/dispatched/running run; a comment alone MUST NOT
  count as dispatch proof.
- **FR-008**: Planning and implementation review MUST remain pinned to an exact published revision;
  a changed revision MUST invalidate the prior verdict.
- **FR-009**: Delivery MUST require exact metadata keys `delivery_repo_url`, `delivery_work_dir`,
  `delivery_branch`, and `delivery_base_sha`; all delivery roles MUST use that one workdir, and local
  `HEAD`, pushed branch OID, and PR `headRefOid` MUST be byte-identical before implementation review
  and again before shipping.
- **FR-010**: The PR-required path, direct-main prohibition, nine required status checks
  (`Lint & policy`, `SPM VitalModels`, `SPM HealthKitService`, `SPM AIService`, `SPM VitalUI`,
  `SPM TelemetryKit`, `SPM DesignKit`, `App target`, and `codex-review-target`), privacy constraints,
  and no-gate-bypass rules MUST remain fail-closed; Claude MUST remain paused and Kimi advisory.
- **FR-011**: The repository MUST record the authority change in a new accepted ADR, partially
  supersede only the stale delivery-role clauses of ADR-0009 and ADR-0014, preserve ADR-0017, and
  bump the constitution version according to governance.
- **FR-012**: A migration note MUST preserve in-flight work and switch it at the next actor boundary;
  it MUST define behavior for planning review, implementation review, shipping, merged work,
  changed SHA, and failed dispatch.
- **FR-013**: The implementation MUST remain one RepoInfra execution-layer task under ADR-0021's
  narrow governance-support scheduling exception, with no product-layer dependency and an exact
  editable file allowlist.
- **FR-014**: Governance, ADR, Spec Kit planning, design evidence, generated artifacts, caches, logs,
  credentials, and secrets MUST remain support/generated exclusions as defined by ADR-0019.
- **FR-015**: The accepted issue non-goals and the recovery contract prohibiting reuse of
  MY-1531/MY-1534 execution state or artifacts MUST remain explicit.
- **FR-016**: The exact reviewed planning artifacts MUST be committed and pushed by Planner Lead;
  Team Lead MUST provision T001 with that planning SHA as `delivery_base_sha`; the eventual PR scope
  MUST include the inherited `specs/025-dev-team-delivery-contract/**` artifacts byte-for-byte while
  Fullstack's editable allowlist remains the eight governance files.
- **FR-017**: Active governance MUST define shipping-time failure classification: clear code, build,
  test, lint, or repository-check failures owned by implementation route directly from PR Manager to
  Fullstack Engineer in the same workdir and unchanged scope, then through fresh exact-revision AI
  review back to PR Manager; conflicting evidence, ambiguous ownership, policy/content decisions,
  permissions, infrastructure failures, repeated repairs, and merge conflicts route to Team Lead.

### Key Entities

- **Planning Revision**: The published Spec Kit artifact set identified by one immutable Git SHA.
- **Delivery Candidate**: A committed implementation revision whose local, remote, and PR head
  identities agree where applicable.
- **Dispatch Evidence**: A queued, dispatched, or running run for the role named in the final
  handoff comment.
- **Shipping Evidence**: Required-check, PR/merge, target-revision, and cleanup facts returned by PR
  Manager.
- **Lifecycle Closure**: Team Lead's state transition after proven delivery.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All active workflow summaries expose exactly one canonical pipeline and all five role
  ownership boundaries.
- **SC-002**: Every stale statement identified in `research.md` maps to an authorized replacement,
  an ADR supersession pointer, or an explicit preserved historical statement.
- **SC-003**: All eight acceptance scenarios map to the single vertical slice and its one RepoInfra
  implementation task.
- **SC-004**: Fullstack's editable allowlist contains exactly eight governance files and no product,
  test, package, Xcode project, CI workflow, ruleset, credential, or delivery-issue mutation.
- **SC-005**: Repository-declared RepoInfra verification exits successfully without invoking
  `xcodebuild`.
- **SC-006**: A semantic residue review finds no active instruction assigning CI/merge/cleanup to
  Team Lead, no active instruction sending passing implementation back to Team Lead, and no active
  assign+todo-only dispatch contract.
- **SC-007**: The implementation PR contains the eight reviewed planning artifacts unchanged from
  `delivery_base_sha` plus changes only to the eight editable T001 governance paths.
- **SC-008**: Every active shipping-recovery instruction distinguishes the direct Fullstack repair
  loop from the Team Lead exceptional-recovery route and requires fresh review after candidate change.

## Assumptions

- `AUTH-20260905-01` is the approved authority decision and is not open for re-litigation.
- The live role instructions captured on 2026-09-06 are authoritative for actor ownership.
- The repository remains PR-required and keeps its currently declared required checks.
- The governance documents remain ADR-0019 support exclusions; this planning package does not
  alter layer routing to make them schedulable infrastructure.

## Non-Goals

- No product code, tests, package code, Xcode project, `project.yml`, CI gate, workflow, ruleset,
  branch protection, credential, secret, or existing delivery-issue mutation.
- No weakening of required checks, exact-SHA review, workdir identity, privacy, or PR-required
  guarantees.
- No rewrite of accepted ADR history beyond status/supersession metadata permitted by governance.
- No changes to ADR-0017, ADR-0019, `RepoInfra/CONTEXT.md`, MY-1490 references, or PR #418/#426/#430.
- No retry, reopen, resume, repair, copy, or import of MY-1531 or MY-1534 execution state, workdirs,
  sessions, branches, commits, reviews, or planning artifacts.
- No implementation dispatch by Planner Lead.
