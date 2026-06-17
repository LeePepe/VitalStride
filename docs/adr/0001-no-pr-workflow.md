# ADR-0001: No-PR Git Workflow

**Status**: Accepted
**Date**: 2026-06-16
**Deciders**: tianpli (project owner)

## Context

VitalStride is a personal project. The original workflow used GitHub PRs:

- Multica FS agent creates a feature branch in its worktree
- FS pushes the branch to `github` remote and opens a PR via `gh pr create`
- AI Reviewer reviews on GitHub
- TL or user merges the PR via `gh pr merge --squash`

This worked but had three recurring frictions:

1. **PR backlog stall** — multiple PRs (e.g. #89, #92, #96) sat OPEN for hours because the squash-merge step was a separate manual action no agent owned. Issue pipeline reported "done" while the code wasn't on `main`.

2. **Conflict resolution overhead** — when parallel PRs touched the same files, GitHub's conflict UI required local checkouts to resolve; agent could not handle them.

3. **Cognitive overhead for a one-person project** — PRs are designed for code review across teams. Solo development with AI agents doesn't need a separate review surface; review happens via Multica issue comments.

A second-order effect: every FS push hit the public remote, polluting `git branch -a` and the GitHub branches list with hundreds of `agent/fullstack-engineer/<sha>` branches.

## Decision

Switch to a **no-PR workflow** for this project:

- **GitHub remote remains** as the canonical mirror of `main`. CI/Actions and external visibility are preserved.
- **Agent feature branches live only in the local bare repo** (`~/multica_workspaces/.repos/<ws>/<repo>.git`). They are not pushed to `github`.
- **FS pushes** `agent/<issue-key>-<task-id-short>` to the local bare repo and reports the branch + commit SHA in an issue comment, then assigns the issue back to TL.
- **TL fetches the FS branch from the local bare repo**, rebases it onto `github/main`, resolves trivial conflicts itself, escalates semantic conflicts back to FS, and pushes the result directly to `github` `main`.
- **The `pre-push` hook enforces** the rule mechanically: any push to a remote whose URL contains `github.com` (or `gitlab.com`) is rejected unless the local ref is `refs/heads/main`.

### Conflict policy (B2)

TL resolves "trivial" conflicts itself:
- different lines in the same file
- import additions
- separate methods or properties
- whitespace / formatting

TL escalates "semantic" conflicts back to FS:
- same line modified by both sides
- deletion of code the other side changed
- logic-overlapping edits

### Failure handling

When TL's `git push github main` fails (post-merge build error, non-fast-forward race), TL decides recovery itself — no fixed playbook. Options include re-fetch + re-rebase, splitting commits, or assigning the issue back to FS with a description of the failure.

### Hooks

- `scripts/hooks/pre-commit`: blocks commits to `main`; lints staged Swift files (fast).
- `scripts/hooks/pre-push`: enforces the public-remote-only-main rule, runs `xcodebuild test` (or `swift build/test` for SPM-only changes), runs SwiftLint on changed Swift files.
- Build acceleration: shared `derived-data/` and `flock`-protected `build.lock` under `<git-common-dir>/`, so all worktrees of the same bare repo share the build cache while serializing concurrent xcodebuild invocations.

## Consequences

### Good

- **No more PR backlog**: FS → comment → TL fetch + rebase + push is one continuous flow inside the Multica pipeline. There is no manual squash-merge step.
- **GitHub branches list stays clean**: only `main` ever lands there.
- **Faster TL conflict resolution**: trivial conflicts (the majority) handled inline; the bare repo gives TL access to all FS branches in one place.
- **Linear `main` history** by default (rebase, not squash). Each FS commit appears verbatim in `main`.
- **Bare-repo path is the only "remote" agents see**: removes a class of bugs where agents accidentally pushed to GitHub.

### Bad

- **No GitHub PR comments / inline review** (review happens in Multica issue comments only). Acceptable because no second human reviews this codebase.
- **GitHub Actions CI** runs only on push to `main`, not on every FS commit. If we want per-FS-commit CI, we'd need a different signal source (out of scope for v1).
- **Force-push to `main`** is now possible if TL pushes a rebased history that conflicts with what someone else pushed. The pre-push hook does not currently block force pushes; we rely on TL discipline.
- **The bare repo accumulates** `agent/<issue>-<task>` branches over time. Multica's workspace GC currently doesn't prune bare-repo branches; manual cleanup may be needed periodically (`git -C $BARE branch -D agent/old-issue-*`).

### Neutral

- **Other Multica projects keep PR workflow** — TL/FS agent instructions detect this project via its `AGENTS.md` "Git Workflow" section and switch behavior accordingly. Other projects without that section keep the legacy `gh pr create` flow.

## Alternatives Considered

1. **Keep PRs, add an auto-merge cron**: lower effort but doesn't solve conflict resolution, and adds a moving part that can fail silently.
2. **Delete GitHub remote entirely** (originally requested): rejected after discovering Multica's `repocache` strongly assumes a `github` remote URL for `git worktree add`. Migrating Multica to local-path remotes is a much larger change.
3. **Squash-merge instead of rebase in TL**: discarded — squash loses individual FS commit history that's useful for `git blame` and review attribution.

## Implementation references

- `scripts/hooks/pre-push` — public-remote-only-main guard, build/test, lint
- `scripts/hooks/pre-commit` — main-protect + staged-file lint
- `AGENTS.md` § Git Workflow — full FS/TL command sequences
- `CONTEXT.md` § Git Hooks — short-form decision summary
