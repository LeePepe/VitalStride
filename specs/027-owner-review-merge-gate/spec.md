# Feature Specification: Owner-review merge gate

**Feature Branch**: `027-owner-review-merge-gate`

**Created**: 2026-10-14

**Status**: Ready for Review

**Input**: MY-1734 v1 at base `b9960bdab8ef98b86354d17100070a273a2f8285`, extending the accepted MY-1676 tier policy with a VitalStride-specific enforcement slice.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Protected pull requests wait for the Owner (Priority: P1)

As the repository Owner, I need a pull request marked `owner-review` or changing a declared protected path to stay unmerged until I have reviewed it, even if all machine checks are green.

**Why this priority**: PR #441 demonstrated that the current auto-merge path can bypass the intended Tier A Owner gate.

**Independent Test**: Feed deterministic pull-request fixtures to the trusted-base gate and prove that both the label condition and every declared protected-path condition choose the fail-closed, auto-merge-disabled outcome while an ordinary pull request retains the current auto-merge outcome.

**Acceptance Scenarios**:

1. **Given** an already auto-merge-enabled pull request, **when** the `owner-review` label is added, **then** automation re-evaluates the pull request and disables auto-merge.
2. **Given** an unlabelled pull request, **when** its synchronized change set includes a path matched by the repository's CODEOWNERS contract, **then** automation disables or leaves disabled auto-merge.
3. **Given** a pull request with neither the label nor a protected path, **when** it is opened, reopened, made ready, synchronized, or has an unrelated label change, **then** the existing squash auto-merge behavior remains available.
4. **Given** the `owner-review` label is removed, **when** a protected path remains changed, **then** the pull request remains fail-closed.
5. **Given** a previously protected change set becomes ordinary after synchronization and no `owner-review` label remains, **when** automation re-evaluates it, **then** ordinary auto-merge behavior is restored.

---

### User Story 2 - Repository settings enforce the same contract (Priority: P1)

As the repository Owner, I need the default-branch ruleset and the versioned repository policy to agree that CODEOWNERS matches require a Code Owner review, so a manual or alternate merge path cannot bypass the workflow safeguard.

**Why this priority**: Workflow-only disarming does not protect manual merges, and the current live ruleset has `require_code_owner_review=false`.

**Independent Test**: Validate the versioned ruleset source, CODEOWNERS patterns, and exact Owner settings handoff; after Owner application, read back ruleset `18932961` and prove only the authorized code-owner-review field changed.

**Acceptance Scenarios**:

1. **Given** the feature has merged and CODEOWNERS is present on the default branch, **when** the Owner enables “Require review from Code Owners” on ruleset `18932961`, **then** a matching pull request cannot merge without a valid Code Owner approval.
2. **Given** the tracked ruleset and live ruleset are compared before and after Owner application, **then** target, enforcement, review-count, stale-review, last-push, thread-resolution, merge methods, required checks, and bypass actors are unchanged except for the explicitly authorized code-owner-review toggle.
3. **Given** the first pull request containing this fix is evaluated under the vulnerable pre-fix default branch, **then** its auto-merge state is manually disabled and kept disabled until the Owner approves and the normal shipping owner merges it.

### Edge Cases

- A fork pull request cannot cause untrusted pull-request code or workflow YAML to execute while the gate calculates labels and changed paths.
- A change to `.github/CODEOWNERS` is itself protected because `.github/**` is protected.
- Failure to obtain labels, changed paths, CODEOWNERS, or the GitHub auto-merge mutation result is visible and fail-closed; it never falls through to enabling auto-merge.
- Removing or weakening an existing test remains a semantic `owner-review` condition even when the test path is not in CODEOWNERS; this feature does not classify all ordinary tests as protected paths.
- The tracked ruleset currently differs from the live response for unattributed-change approval and possibly bypass actors. The Owner readback must preserve the live values and must not use this feature to reconcile unrelated drift.
- A Code Owner cannot approve their own pull request under GitHub review semantics. The existing general approving-review count remains zero; this feature does not invent a second reviewer or a bypass policy.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Auto-merge automation MUST re-evaluate pull requests on `opened`, `reopened`, `ready_for_review`, `synchronize`, `labeled`, and `unlabeled` activity.
- **FR-002**: The automation MUST treat `owner-review` as a path-independent protected condition and MUST treat any changed path matched by the trusted default branch's CODEOWNERS file as a protected condition.
- **FR-003**: A protected condition MUST disable an already armed auto-merge request or leave auto-merge disabled; read or mutation failure MUST be a visible non-success and MUST NOT enable auto-merge.
- **FR-004**: A non-draft pull request with no protected condition MUST retain the existing squash auto-merge behavior, including bounded retry for transient GitHub API failure.
- **FR-005**: `.github/CODEOWNERS` MUST assign the repository Owner to the accepted v1 protected-path inventory: `.github/**`; `scripts/ci/**`; `scripts/rulesets/**`; `scripts/hooks/**`; `scripts/setup-hooks.sh`; `scripts/test-repoinfra.sh`; `scripts/check-frontmatter.sh`; `fastlane/**`; `project.yml`; `.gitleaks.toml`; `.swiftlint.yml`; and `.swiftlint-baseline.json`. The file MUST NOT add a catch-all owner or classify ordinary product/package/test paths as protected.
- **FR-006**: `scripts/rulesets/main-protection.json` MUST set `require_code_owner_review` to true while leaving the zero general approving-review count, required-check identities, merge methods, target, enforcement, and other review fields unchanged.
- **FR-007**: A focused deterministic regression MUST exercise at least: `owner-review` added to an already armed PR; protected path added on synchronize; protected path retained after label removal; protected path removed with no label; ordinary PR; missing/malformed gate input; disable failure; and enable failure. It MUST assert the selected enable/disable action rather than only search workflow text.
- **FR-008**: The implementation MUST preserve the existing trusted-base `pull_request_target` security boundary, minimum workflow permissions, non-draft rule, concurrency behavior, required check names, required/advisory reviewer split, and all product/package behavior.
- **FR-009**: The delivery handoff MUST include a bootstrap sequence for the first fix PR: add `owner-review`, explicitly disable auto-merge using Owner/PR Manager authority before machine checks can merge it, obtain Owner approval, merge through the normal shipping owner, then perform the settings step and verify live readback.
- **FR-010**: The exact Owner settings handoff MUST say: on VitalStride default-branch ruleset `18932961` (`main protection`, target `~DEFAULT_BRANCH`), enable only “Require review from Code Owners” (`false` to `true`); preserve all other live rules, review toggles, required-check contexts, merge methods, enforcement, and bypass actors; agents do not perform this settings mutation.
- **FR-011**: Repository gate documentation MUST distinguish ordinary auto-merge from Owner-gated protected pull requests and record the settings/readback procedure without claiming unrelated live/tracked drift was repaired.

## Behavior Contract

### Existing behavior

- No tracked CODEOWNERS file exists at the accepted base.
- `.github/workflows/auto-merge.yml` arms squash auto-merge for every non-draft pull request on open, reopen, ready, or synchronize; it does not respond to label changes or inspect changed paths.
- Ruleset `18932961` and the tracked ruleset source require nine named checks and zero general approving reviews, but code-owner review is disabled.
- `codex-review-target` is the only required AI review; Kimi is advisory and Claude is paused. Target workflows evaluate trusted base content.
- RepoInfra changes use `bash scripts/test-repoinfra.sh`; full app/package gates remain required CI.

### Compatibility

- Ordinary non-draft pull requests keep squash auto-merge and the current transient-retry behavior.
- The nine required-check identities, required/advisory review split, workflow trust model, permissions, and product/package behavior remain unchanged.
- General approving-review count stays zero, preserving the single-owner repository's existing non-protected path behavior. Code-owner review applies only to exact CODEOWNERS matches.
- Semantic removal or weakening of tests continues to require `owner-review`; CODEOWNERS does not replace content review or classify every ordinary test as Tier A.
- MY-1676 v6 remains historical authority for tier policy, but MY-1734 is the new explicit authorization for this VitalStride CODEOWNERS/ruleset change.

### Removed behavior

- A pull request carrying `owner-review` can no longer remain auto-merge-enabled.
- A pull request changing a declared protected path can no longer be automatically armed by this workflow.
- The default-branch ruleset no longer permits a CODEOWNERS-matched pull request to merge without Code Owner approval after the Owner applies the authorized setting.
- No existing test, required check, merge method, reviewer identity, product behavior, package behavior, or release behavior is removed or weakened.

## Scope

### Files in scope

- `.github/CODEOWNERS` (new)
- `.github/workflows/auto-merge.yml`
- `scripts/ci/owner-review-gate.py` (new internal trusted-base decision boundary)
- `scripts/tests/test_owner_review_gate.py` (new focused deterministic regression)
- `scripts/rulesets/main-protection.json`
- `docs/ci-gates.md`
- `specs/027-owner-review-merge-gate/**` (planning evidence only)

### Files NOT to touch

- Other `.github/workflows/**`, including `ci.yml`, `codex-review-target.yml`, `kimi-review.yml`, and `testflight.yml`
- `fastlane/**`, `project.yml`, `.gitleaks.toml`, `.swiftlint.yml`, and `.swiftlint-baseline.json` (protected by the new contract but behaviorally unchanged)
- Existing `scripts/ci/**`, `scripts/rulesets/apply`, `scripts/hooks/**`, `scripts/test-repoinfra.sh`, `scripts/check-frontmatter.sh`, and existing tests
- `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, `RepoInfra/CONTEXT.md`, `.specify/**`, and existing specs/ADRs
- `Packages/**`, app targets/tests, `Prototype/**`, generated projects, credentials, runner configuration, and live GitHub settings

### Interface contract

- Internal only: the workflow supplies trusted pull-request metadata, labels, changed paths, and the default branch's CODEOWNERS content to one deterministic decision boundary that returns exactly one action: enable or disable auto-merge.
- No product API, persisted data, package dependency, Xcode target, or public Swift signature changes.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every protected fixture selects disable and every ordinary fixture selects enable with zero ambiguous outcomes.
- **SC-002**: Label and synchronize event fixtures prove an already armed protected pull request is disarmed.
- **SC-003**: The CODEOWNERS fixture covers every FR-005 pattern and proves representative product/package/ordinary-test paths remain unmatched.
- **SC-004**: Focused regression, complete RepoInfra fast gate, workflow syntax/contract validation, and `git diff --check` complete with zero failures.
- **SC-005**: After Owner application, live readback of ruleset `18932961` shows code-owner review enabled and no authorized-field drift.
- **SC-006**: The first fix PR has recorded evidence of manual auto-merge disablement and Owner approval before merge.

## Assumptions and Dependencies

- The GitHub repository Owner and CODEOWNERS identity is `@LeePepe`.
- Team Lead/PR Manager supplies the first-PR bootstrap evidence and performs normal delivery; Planner and implementation agents do not mutate live rulesets.
- The Owner performs the exact ruleset settings step only after the CODEOWNERS file is on the default branch.
- The accepted policy dependency is MY-1676 revision `MY-1676/spec/codeowners-tiering/v6`, SHA-256 `7ccaecd133195b4063c6aed41b0d0cce4b516cd7212ca821babd9058d823d64e`, PASS comment `01a135ce-5b29-72a7-a0c6-c180a52b7b07`; MY-1734 supplies the new VitalStride-specific authorization.
- Constitution §§III, Development Workflow, Planning Review / Dual-Approval Gate, and Cross-Cutting Quality Bars remain authoritative.
