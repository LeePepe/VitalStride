# ADR-0009: PR-Required Git Workflow

**Status**: Accepted (amended 2026-07-04)
**Date**: 2026-07-03
**Deciders**: tianpli (project owner)
**Supersedes**: [ADR-0001](0001-no-pr-workflow.md)

## Amendment 2026-07-04 — required review count 1 → 0

The **required-review** count on `main` was lowered from **1 → 0**. Everything else in
this ADR stands: the PR-required flow, the **6 required status checks** (`Lint & policy`
+ 5× `SPM …`), `enforce_admins: true`, and `pre-commit`/`pre-push` local gates are all
unchanged. `main` still only moves via a PR whose required checks are green.

Why: this is a **single-owner repo**. GitHub forbids approving your own PR, so a
`required_approving_review_count: 1` gate permanently blocked the owner's own PRs
(`REVIEW_REQUIRED → BLOCKED`) with no second human to approve — pure friction, not a
safety gain. The server-side protection that actually stops bad code (the CI checks) is
retained; only the human-approval requirement that could never be satisfied solo is
dropped. If a second reviewer (human or an automated Claude reviewer via the
`auto-review-merge` mechanism) is later added, restore the count to 1.

Sections below retain the original "1 required review" wording for historical accuracy;
read them through this amendment.

## Context

[ADR-0001](0001-no-pr-workflow.md) switched VitalStride to a **no-PR workflow**: agent feature
branches lived only in the local bare repo, and the Team Lead (TL) rebased them onto `github/main`
and pushed `main` directly. It cited three frictions with PRs (backlog stall, conflict overhead,
solo cognitive cost) and one second-order effect (public-remote branch pollution).

Since then the enforcement model has changed materially:

1. **A real server-side gate now exists.** `main` is branch-protected with **6 required status
   checks** (`Lint & policy` + 5× `SPM …`), **1 required review**, and **`enforce_admins: true`**.
   SwiftLint was also turned into a genuine blocking gate (`--strict --baseline`, dropping the old
   `|| true` / `continue-on-error`). A red CI or unreviewed change can no longer reach `main` —
   admins included.

2. **The no-PR enforcement was already removed.** The `pre-push` hook no longer rejects non-`main`
   pushes to the public remote (commit `0498143`) and no longer forces `MY-\d+` in commit messages
   (commit `13505cd`). CI already triggers on `pull_request → main`. The no-PR model was therefore
   only surviving in *documentation*, while the mechanics had already drifted to PR-ready.

3. **The no-PR model made the required gate impossible.** Pushing straight to `main` bypasses the
   only place a required status check can run before code lands. To make CI actually *block* bad
   code (the point of turning lint/CI blocking), code must flow through a PR.

## Decision

Switch back to a **PR-required workflow**. All code reaches `main` only via a GitHub Pull Request
that passes the required checks and review.

- **GitHub remote is canonical.** Agent feature branches `agent/<issue-key>-<task-id-short>` are
  pushed to `github` (not a local-bare-only repo).
- **FS** implements, commits, pushes the branch to `github`, and opens a PR via `gh pr create`,
  then reports the PR + assigns the issue back to TL.
- **CI runs as required status checks** on the PR (`pull_request → main`).
- **TL merges** via `gh pr merge` once CI is green and the review approval is in. TL still resolves
  trivial rebase conflicts and escalates semantic ones back to FS (unchanged from ADR-0001).
- **`pre-commit`** still blocks direct commits to `main`; **`pre-push`** still runs the full
  build/test + lint locally as a fast pre-gate. These now front-run the PR rather than a direct push.

## How the original ADR-0001 frictions are addressed

- **PR-backlog stall** (PRs sat OPEN because the merge step was manual and unowned): the merge is
  now a *gated* action — TL owns `gh pr merge` after checks go green, and **GitHub auto-merge** may
  be enabled (recommended) so a PR merges itself the moment checks + review pass. ADR-0001's own
  "Alternatives Considered #1" floated auto-merge but rejected it for not solving conflicts;
  branch protection now makes it safe because a failing check simply keeps the PR unmerged.
- **Conflict resolution**: unchanged — TL rebases/resolves trivial conflicts, escalates semantic
  ones. PRs don't add conflict cost beyond the previous rebase flow.
- **Solo cognitive overhead**: accepted. The trade is deliberate — a real, unbypassable server-side
  gate is worth one review click. This is the same reasoning that motivated turning lint/CI blocking.

## Consequences

### Good
- **The required-checks gate actually works.** Bad code cannot reach `main` (enforce_admins=true).
- **Per-PR CI**: every change is tested before merge, not after (ADR-0001 listed post-merge-only CI
  as a "Bad"). 
- **GitHub-native review surface** returns (inline comments, check annotations).

### Bad / watch
- **Branch pollution** on the public remote returns (the ADR-0001 second-order effect). Mitigate
  with periodic pruning of merged `agent/*` branches (or `gh pr merge --delete-branch`).
- **Live Multica agent instructions** (TL/FS stored prompts) must be re-patched to open/merge PRs;
  editing repo docs alone does not change running-agent behavior.

## Implementation references
- Branch protection: 6 required checks + enforce_admins on `main` (required-review count 0 as of
  Amendment 2026-07-04; was 1 at original acceptance).
- `.github/workflows/ci.yml` — `pull_request → main` + `push → main`.
- `AGENTS.md` § Git Workflow (PR-required) — full FS/TL command sequences.
- `scripts/hooks/pre-commit` — main-protect + staged-file lint; `scripts/hooks/pre-push` —
  build/test + lint pre-gate.
