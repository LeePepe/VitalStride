# Implementation Plan: Owner-review merge gate

**Branch**: `027-owner-review-merge-gate` | **Date**: 2026-10-14 | **Spec**: `specs/027-owner-review-merge-gate/spec.md`

**Input**: Feature specification from `specs/027-owner-review-merge-gate/spec.md`

## Summary

Replace unconditional auto-merge arming with one trusted-base, deterministic protection decision driven by `owner-review` and the default branch's CODEOWNERS contract. Add the narrow VitalStride protected-path inventory, set the tracked code-owner-review ruleset field, and lock enable/disable state transitions with a focused behavior regression. Preserve ordinary auto-merge and every existing required check. Deliver the first PR through an explicit manual fail-closed bootstrap, then hand the Owner one surgical live-settings toggle and readback.

## Technical Context

**Language/Version**: GitHub Actions YAML, Python 3 standard library, CODEOWNERS syntax, JSON ruleset source

**Primary Dependencies**: GitHub `pull_request_target`, GitHub CLI/API, default-branch `.github/CODEOWNERS`, repository ruleset `18932961`

**Storage**: No product persistence; ephemeral PR metadata and workflow state only

**Testing**: Python `unittest`, `bash scripts/test-repoinfra.sh`, focused workflow/CODEOWNERS contract assertions, Python syntax, `git diff --check`

**Target Platform**: GitHub Actions hosted runner and GitHub repository/ruleset APIs

**Project Type**: Repository automation and policy enforcement

**Performance Goals**: One bounded evaluation per triggering event; no app/package build added to the local gate

**Constraints**: Trusted-base only; fail closed; no live settings mutation by agents; preserve ordinary squash auto-merge, nine check identities, zero general approving reviews, and existing reviewer split

**Scale/Scope**: One workflow, one CODEOWNERS contract, one internal decision boundary, one focused regression, one tracked ruleset field, and one gate-documentation update

## Constitution Check

### Before design

- Constitution Principle III and ADR-0019: PASS. Executable/configurable paths belong to the dependency-free RepoInfra layer; `docs/ci-gates.md` is a support-only documentation exclusion.
- Constitution Development Workflow and ADR-0021: PASS. Planner writes only planning artifacts and publishes an exact planning revision; implementation and live delivery remain downstream.
- Constitution Planning Review / Dual-Approval Gate: PASS. No implementation starts before exact-revision AI Reviewer PASS and Team Lead approval.
- Cross-Cutting Quality Bars A, C, I, and J: PASS. Scope is exact, trust boundaries are explicit, the regression is behavioral, and live ruleset mutation is assigned to the Owner.
- Issue Tracker / Spec Execution: PASS. This is one goal and one PR; layer ownership and task dependencies are explicit.

### After design

- Dependency direction remains acyclic: RepoInfra has no product dependency; support documentation depends on the completed RepoInfra contract only.
- The workflow evaluates trusted base code and treats PR labels/paths only as data.
- The path contract has one authority (`.github/CODEOWNERS`); unsupported evolution fails closed rather than silently drifting.
- The general review count and all existing CI/reviewer identities remain intact.
- The first-PR bootstrap and Owner-only settings step close the gap that the new workflow cannot retroactively protect.
- No constitution, ADR, domain model, public product interface, or package dependency changes; no exception is required.

## Repository and incident evidence

- Accepted base: `b9960bdab8ef98b86354d17100070a273a2f8285`.
- No tracked CODEOWNERS exists at this base.
- `.github/workflows/auto-merge.yml` currently handles only open/reopen/ready/synchronize and enables auto-merge for every non-draft PR.
- `scripts/rulesets/main-protection.json` and live ruleset `18932961` both report `require_code_owner_review=false` and nine required contexts.
- PR #441 merged with `owner-review` and zero reviews, demonstrating the enforcement gap.
- MY-1676 accepted artifact `MY-1676/spec/codeowners-tiering/v6` supplies tier policy but explicitly made no VitalStride change; MY-1734 is the current authorization.
- Live ruleset readback includes unrelated state not fully represented by tracked JSON. The Owner operation must change one field only.

## Project Structure

### Documentation (this feature)

```text
specs/027-owner-review-merge-gate/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/
│   └── requirements.md
├── contracts/
│   └── owner-review-merge-gate.md
└── tasks.md
```

### Source Code (repository root)

```text
.github/
├── CODEOWNERS
└── workflows/
    └── auto-merge.yml
scripts/
├── ci/
│   └── owner-review-gate.py
├── rulesets/
│   └── main-protection.json
└── tests/
    └── test_owner_review_gate.py
docs/
└── ci-gates.md
```

**Structure Decision**: Keep the GitHub-native ownership contract in `.github/CODEOWNERS`, isolate deterministic protection matching under existing RepoInfra `scripts/ci`, auto-discover the regression under `scripts/tests`, and update only the current gate reference document.

## Files in Scope

- `.github/CODEOWNERS` (new)
- `.github/workflows/auto-merge.yml`
- `scripts/ci/owner-review-gate.py` (new)
- `scripts/tests/test_owner_review_gate.py` (new)
- `scripts/rulesets/main-protection.json`
- `docs/ci-gates.md`
- `specs/027-owner-review-merge-gate/**` (planning only)

## Files NOT to Touch

- Other `.github/workflows/**`, especially CI, Codex/Kimi/Claude review, and TestFlight workflows
- Existing `scripts/ci/**`, `scripts/rulesets/apply`, hooks, gates, and tests
- `fastlane/**`, `project.yml`, lint/credential-policy files, credentials, runner configuration, and live settings
- `AGENTS.md`, `CLAUDE.md`, contexts, constitution, ADRs, and existing specs
- Product/app/package/prototype paths and generated projects

## Interface Contract

- Internal RepoInfra boundary only; no public product signature.
- Inputs: current labels, complete changed paths, draft state, and trusted default-branch CODEOWNERS content.
- Output: exactly `enable` or `disable`; invalid/incomplete input exits unsuccessfully without enabling.
- Workflow executor reaches the requested state idempotently and confirms it; bounded mutation retry is retained.
- Full contract: `contracts/owner-review-merge-gate.md`.

## Protected-path contract

The CODEOWNERS rows assign `@LeePepe` to:

- `.github/**`
- `scripts/ci/**`
- `scripts/rulesets/**`
- `scripts/hooks/**`
- `scripts/setup-hooks.sh`
- `scripts/test-repoinfra.sh`
- `scripts/check-frontmatter.sh`
- `fastlane/**`
- `project.yml`
- `.gitleaks.toml`
- `.swiftlint.yml`
- `.swiftlint-baseline.json`

No catch-all, product/package, or ordinary-test row is added. Semantic test weakening continues through `owner-review`.

## Dependency and rollout strategy

```text
T001 RepoInfra gate + regression
  -> T002 support documentation + exact handoff
  -> AI Reviewer exact implementation review / normal CI
  -> first-PR manual auto-merge disable + Owner approval
  -> merge
  -> Owner toggles ruleset 18932961 code-owner review only
  -> live readback
```

- `T001` and `T002` ship in one goal/PR; `T002` depends on the final T001 contract wording.
- The Owner setting is an external post-merge dependency, not an implementation-agent task.
- Missing bootstrap or readback evidence blocks delivery completion and returns to Team Lead/Owner; agents do not compensate by changing live settings.

## Verification Strategy

From repository root:

1. `python3 -B -m unittest discover -s scripts/tests -p 'test_owner_review_gate.py'`
2. `bash scripts/test-repoinfra.sh`
3. `python3 -m py_compile scripts/ci/owner-review-gate.py scripts/tests/test_owner_review_gate.py`
4. `git diff --check`

The focused regression must be red-capable against the current unconditional behavior and green only when both enable and disable state transitions, label/synchronize events, CODEOWNERS matches/non-matches, trusted-base wiring, and API-failure handling satisfy the contract. No `xcodebuild` or SwiftPM command is required because no AppUI or package path changes.

## Exact Owner settings handoff

On `LeePepe/VitalStride` default-branch ruleset `18932961` (`main protection`, target `~DEFAULT_BRANCH`), enable only **Require review from Code Owners** (`false` → `true`). Preserve all other live rules, review toggles, required-check contexts, merge methods, enforcement, and bypass actors. Agents do not perform this settings mutation. Record before/after readback and Owner confirmation for inaccessible fields.

## Open risks and follow-ups

- Direct Owner-authored protected PRs cannot self-approve. This v1 remains fail-closed; any second-code-owner or bypass policy is a separate Owner decision.
- Pre-existing tracked/live ruleset drift remains visible and unchanged. A broad reconciliation is not authorized by MY-1734.
- CODEOWNERS evolution beyond the supported rooted v1 patterns must update decision logic and regression in the same protected PR.

## Complexity Tracking

No constitutional exception, new product layer, or external dependency is required.
