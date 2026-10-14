# Contract: Owner-review merge gate

## Trusted input boundary

- Workflow definition, CODEOWNERS content, and decision code come from the default branch under `pull_request_target`.
- Pull-request labels, file paths, URL, number, and current auto-merge state are untrusted data only.
- No PR-head checkout, executable, shell fragment, or configuration is evaluated.

## Decision boundary

The internal RepoInfra decision boundary receives:

1. the complete current label-name set;
2. the complete current changed-path set;
3. the trusted default-branch `.github/CODEOWNERS` content; and
4. draft state.

It produces exactly one intended merge-state action:

- `disable` for draft, `owner-review`, any CODEOWNERS match, or invalid/incomplete input;
- `enable` only for a non-draft pull request with valid complete input and no protected condition.

Unsupported CODEOWNERS syntax is not ignored. It produces a visible fail-closed result until the contract and regression deliberately add support.

## Mutation boundary

- The workflow queries the current auto-merge request before mutation.
- Desired state already present is a successful no-op.
- State changes use GitHub's API through `gh` with the existing minimum write permissions.
- Enable preserves squash mode and the existing bounded transient retry.
- Disable uses bounded retry and must reach a confirmed disabled state.
- Exhausted reads or mutations end the job unsuccessfully; no failure path enables auto-merge.

## Event contract

The workflow re-evaluates on:

- `opened`
- `reopened`
- `ready_for_review`
- `synchronize`
- `labeled`
- `unlabeled`

The concurrency key remains per pull request with in-progress cancellation, so the newest event wins.

## Protected-path contract

`.github/CODEOWNERS` owns the exact v1 patterns specified by FR-005 with `@LeePepe`. It has no catch-all row. The focused regression proves representative matches and non-matches and verifies the workflow consumes the trusted CODEOWNERS file rather than a second path list.

## Live settings contract

After merge, the Owner changes only `require_code_owner_review` on ruleset `18932961` from false to true. The Owner preserves the live values of every other field, including values that currently differ from tracked JSON or are not visible to the agent runtime. Agents do not perform or simulate this mutation.

## First-PR bootstrap contract

Before the feature can protect itself, Team Lead/PR Manager records:

1. `owner-review` present;
2. current auto-merge request explicitly disabled;
3. Owner approval on the exact PR head;
4. merge by the normal shipping owner; and
5. post-merge Owner settings readback.

Missing evidence blocks shipping; it is not replaced by green machine checks.
