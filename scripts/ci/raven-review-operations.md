# Raven review operations

The trusted local `codex-review.sh` gate invokes the standard Codex CLI through
`review-raven.py`. Provider selection and connection configuration are governed
exclusively by the isolated review home: `$CODEX_HOME/config.toml`, where
`CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"`.

The gate is provider-neutral: any valid provider selected via `model_provider`
in the review home's configuration is accepted. The launcher imposes no provider-name
restriction (such as requiring `raven`), injects no CLI provider overrides, and
requires no environment-level credentials.

## Runner readiness and authentication

1. Provider authentication and network transport belong to Codex within the
   isolated review home. The launcher does not require `RAVEN_API_KEY`,
   `OPENAI_API_KEY`, or any specific environment variable before execution.
2. The launcher does not inspect unrelated CI secrets (such as `GH_TOKEN` or
   `GITHUB_TOKEN`), does not inspect source files, and does not read, copy, or
   write authentication caches.
3. Runner prerequisites: Python 3.11+ on PATH (stdlib `tomllib`), the standard
   Codex binary (`CODEX_BIN`, normally `/opt/homebrew/bin/codex`), and a valid
   review home configuration (`$HOME/.codex-review/config.toml`).

Host and runner provisioning belongs to host bootstrap and is outside this
repository's scope. Repository code never sources credential files or persists
secrets into source control.

## Isolated review home

The caller sets `CODEX_HOME="${CODEX_REVIEW_HOME:-$HOME/.codex-review}"`.
An inherited daily `CODEX_HOME` or `$HOME/.codex/config.toml` is deliberately
ignored and never serves as provider authority.

The isolated review home preserves its configured model, reasoning effort,
disabled hooks/MCP (`hooks = false`), read-only sandbox (`sandbox_mode = "read-only"`),
and never-approval policy (`approval_policy = "never"`). The caller continues
to enforce read-only sandbox and never-approval explicitly on the CLI.

## Fail-closed operation and diagnostics

Missing, unreadable, malformed, or provider-unselected review home configuration
fails closed with a sanitized `Setup failed` diagnostic and exit code 1.
There is no direct-OpenAI fallback, daily-home fallback, or automatic retry.

Executable/CLI failures, empty or unparseable output, timeouts, and blocker
findings (`verdict = "changes"`) all exit nonzero to prevent unreviewed or
failing diffs from passing the gate.

## Offline verification vs real Actions review

Offline test contracts (`scripts/ci/tests/review_raven_contract.py`) exercise
the real shell caller, prompt renderer, helper, and watchdog with fake Git/GitHub/Codex
tools without making network calls or model requests.

Local verification entry is `bash scripts/test-repoinfra.sh`, which automatically
discovers and runs the offline contract tests alongside other RepoInfra checks.

A successful offline test proves process invocation and contract safety, not
live runner service readiness. Production acceptance requires the real
`codex-review-target` required check on GitHub Actions, running on the self-hosted
mac runner (`vitalstride-mac`) against trusted base code.

## Trusted-base rollout and proof

Because `.github/workflows/codex-review-target.yml` checks out trusted `base.sha`,
the repair PR itself runs the pre-repair launcher from the base branch, exhibiting
the expected setup failure signature. Bounded bootstrap and production proof proceed
under the exact-head Owner approval and post-merge verification flow.
