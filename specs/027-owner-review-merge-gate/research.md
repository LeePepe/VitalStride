# Research: Owner-review merge gate

## R-001 — Authority and version boundary

**Decision**: Treat MY-1734 as a new VitalStride-specific authorization at base `b9960bdab8ef98b86354d17100070a273a2f8285`, informed by but not implementing MY-1676 v6.

**Evidence**: MY-1676 v6 (`7ccaecd133195b4063c6aed41b0d0cce4b516cd7212ca821babd9058d823d64e`) found no VitalStride CODEOWNERS at its older base and explicitly made no VitalStride change. It established the Tier A categories, path-independent `owner-review`, and the default-deny rule for removing existing protection. MY-1734 explicitly authorizes the new VitalStride workflow, CODEOWNERS, ruleset-source, regression, and Owner-settings slice.

**Rejected**: Reusing the superseded broad MY-1676 inventories or describing this as an unfinished MY-1676 slice. Neither is accepted authority for current VitalStride paths.

## R-002 — Canonical protected-path contract

**Decision**: Make `.github/CODEOWNERS` the canonical path contract. Limit v1 rows to repo-grounded workflow/review/test-policy machinery, signing/release surfaces, and credential-policy configuration named in FR-005. The decision boundary supports the simple rooted file/directory patterns used by this contract and fails closed if the file is missing, malformed, or later contains unsupported syntax.

**Rationale**: GitHub enforces the same file once Code Owner review is enabled, and the workflow can evaluate the trusted default-branch copy without running pull-request code. A catch-all would change ordinary PR behavior and conflict with the accepted single-owner compatibility boundary.

**Rejected**:

- A second unlinked protected-path list in workflow YAML, because it can drift from CODEOWNERS.
- Classifying all tests as protected, because MY-1676 keeps test weakening semantic and path-independent through `owner-review`.
- Adding product/package paths, because the accepted issue concerns repository gates, signing/release, credential policy, and test policy.

## R-003 — Trusted, deterministic merge-state decision

**Decision**: Keep `pull_request_target`, check out only the trusted default branch, obtain changed paths and current labels as data, and pass them to one deterministic internal decision boundary. The boundary returns one of two actions: enable or disable. The workflow queries current auto-merge state and performs only the necessary idempotent mutation with bounded retry.

**Rationale**: This retains the existing fork-safe trust model, makes label/synchronize behavior fixture-testable, and proves behavior rather than only YAML text.

**Rejected**:

- Running PR-head scripts or workflow YAML, because a fork could execute untrusted code.
- Merely skipping the enable step, because a previously armed PR would remain mergeable.
- Relying only on the future ruleset toggle, because the first fix PR and live-setting lag remain vulnerable.

## R-004 — Ruleset source and Owner-only live mutation

**Decision**: Change only `require_code_owner_review` in the versioned ruleset source. After the feature is merged, the Owner enables only “Require review from Code Owners” on live ruleset `18932961`; agents do not run the live mutation. Readback compares all accessible fields and records inaccessible fields as Owner-confirmed unchanged.

**Evidence**: The accepted base and live readback both show the toggle false. The live ruleset additionally reports `require_extra_approval_for_unattributed_changes=true`, which is absent from tracked JSON, and bypass-actor visibility is incomplete. The settings step must therefore be a surgical Owner action, not a broad ruleset re-application that could erase or introduce unrelated values.

**Rejected**: Running `scripts/rulesets/apply` as part of agent implementation. It is an administrative live mutation and could reconcile pre-existing drift outside MY-1734 authority.

## R-005 — Bootstrap sequence

**Decision**: The first fix PR is manually fail-closed: apply `owner-review`, explicitly disable auto-merge before checks can complete, record the disabled state, obtain Owner approval, and let the normal shipping owner merge. Only after CODEOWNERS lands does the Owner toggle the live ruleset and record the readback.

**Rationale**: The pre-fix default-branch workflow does not react to labels and the pre-fix ruleset does not require Code Owner review. The new code cannot protect the PR that introduces it.

## R-006 — Compatibility and verification

**Decision**: Preserve all nine required-check identities, zero general approving reviews, merge methods, reviewer split, permissions, concurrency, trusted-base behavior, and product/package paths. Verify with a focused deterministic regression, the full RepoInfra fast gate, YAML parsing/contract assertions, Python syntax, and whitespace checks.

**Rationale**: This is a Tier A RepoInfra correction, not a general review-policy redesign. The focused regression must cover state transitions and API failure; the complete gate protects existing repository automation.

## Resolved risks

- A direct Owner-authored protected PR cannot self-approve under GitHub semantics. This feature intentionally remains fail-closed and does not invent another code owner or bypass policy.
- Pre-existing tracked/live ruleset drift is recorded but not repaired. The Owner action changes one field only.
- Ordinary tests remain outside CODEOWNERS; content review and `owner-review` retain the semantic safeguard against removal or weakening.
