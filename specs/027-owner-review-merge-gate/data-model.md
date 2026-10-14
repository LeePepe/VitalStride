# Data Model: Owner-review merge gate

This feature introduces no persisted product data. The model below defines ephemeral RepoInfra contract records used for deterministic evaluation and handoff.

## PullRequestEvaluation

| Field | Meaning | Constraint |
|---|---|---|
| `draft` | Current draft state | Draft pull requests are never armed |
| `labels` | Current label names | `owner-review` is path-independent protection |
| `changed_paths` | Complete current pull-request file list | Treated as untrusted data; no path execution |
| `codeowners_contract` | Trusted default-branch CODEOWNERS content | Missing, malformed, or unsupported content fails closed |
| `current_auto_merge_state` | Armed or disabled | Used to make the mutation idempotent |

## ProtectionDecision

| Value | Preconditions | Required workflow result |
|---|---|---|
| `disable` | Draft, `owner-review`, any CODEOWNERS match, or incomplete/invalid evaluation | Leave disabled or disarm; no enable attempt |
| `enable` | Non-draft, no `owner-review`, complete valid inputs, no CODEOWNERS match | Leave armed or enable squash auto-merge |

There is no permissive “unknown” state. Unknown input maps to a visible failure and no enable action.

## ProtectedPathContract

- Canonical record: `.github/CODEOWNERS` on the trusted default branch.
- Owner: `@LeePepe`.
- Pattern surface: the exact rooted file/directory patterns in FR-005.
- Exclusions by absence: product/app/package paths and ordinary test paths.
- Evolution rule: unsupported or malformed new syntax fails closed until the decision boundary and regression are deliberately updated together.

## RulesetSettingsHandoff

| Field | Required value |
|---|---|
| Repository | `LeePepe/VitalStride` |
| Ruleset | `18932961` / `main protection` |
| Target | `~DEFAULT_BRANCH` |
| Authorized live mutation | “Require review from Code Owners”: false → true |
| Preserved state | Every other live rule, toggle, check, merge method, enforcement value, and bypass actor |
| Actor | Owner only; no agent mutation |
| Verification | Before/after live readback plus recorded inaccessible-field Owner confirmation |

## State transitions

```text
ordinary + disabled  -> enable
ordinary + armed     -> no-op success
protected + armed    -> disable
protected + disabled -> no-op success
invalid/incomplete   -> visible failure, remain disabled/no enable
```
