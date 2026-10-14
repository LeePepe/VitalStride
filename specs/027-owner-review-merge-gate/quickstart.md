# Quickstart: Owner-review merge gate

## Implementation verification

Run from repository root:

1. Focused deterministic regression:
   `python3 -B -m unittest discover -s scripts/tests -p 'test_owner_review_gate.py'`
2. Complete RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
3. Python syntax:
   `python3 -m py_compile scripts/ci/owner-review-gate.py scripts/tests/test_owner_review_gate.py`
4. Workflow and contract assertions: covered by the focused regression against `.github/workflows/auto-merge.yml` and `.github/CODEOWNERS`.
5. Patch hygiene:
   `git diff --check`

Do not run `xcodebuild`; this slice changes no AppUI or package path.

## First-PR rollout

1. Publish the reviewed implementation PR through the normal Dev Team flow.
2. Add `owner-review` and immediately disable the PR's auto-merge request using authorized Team Lead/PR Manager/Owner operations.
3. Record the exact PR head and disabled state before relying on required checks.
4. Obtain Owner approval on that exact head.
5. Merge through the normal shipping owner; do not bypass required checks.
6. After `.github/CODEOWNERS` is on the default branch, Owner opens ruleset `18932961` (`main protection`) and enables only “Require review from Code Owners.”
7. Read back the live ruleset and record the toggle as true plus preservation of every other accessible field. Record Owner confirmation for fields the runtime cannot read.

## Regression evidence matrix

| Fixture | Expected action |
|---|---|
| owner-review label added while armed | disable |
| protected path introduced on synchronize | disable |
| owner-review removed but protected path remains | disable |
| protected path removed and no label remains | enable |
| unrelated label on ordinary PR | enable |
| draft PR | disable |
| missing/malformed labels, paths, or CODEOWNERS | visible failure; no enable |
| enable or disable API mutation fails after retries | failing workflow |

## Owner settings handoff (exact text)

On `LeePepe/VitalStride` default-branch ruleset `18932961` (`main protection`, target `~DEFAULT_BRANCH`), enable only **Require review from Code Owners** (`false` → `true`). Preserve all other live rules, review toggles, required-check contexts, merge methods, enforcement, and bypass actors. Agents must not perform this settings mutation.
