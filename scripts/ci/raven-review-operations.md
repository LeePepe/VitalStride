# Raven review operations

The trusted `codex-review.sh` invokes the standard Codex CLI through
`review-raven.py`. Only the existing daily provider's connection metadata is
imported: `CODEX_RAVEN_CONFIG`, or `$HOME/.codex/config.toml` by default,
must select `model_provider = "raven"`. The helper requires a loopback HTTP(S)
endpoint with an explicit port, Responses transport, and no OpenAI account
authentication requirement. It never copies the daily config or changes models.

## Runner readiness and two authentication layers

1. The review client authenticates to Raven using the provider's named
   environment variable: only `OPENAI_API_KEY` or `RAVEN_API_KEY` is allowed.
   The value must already exist in the actual noninteractive runner/job process.
2. Raven owns its separate upstream Copilot authentication. A valid client key
   does not prove that upstream authentication is ready.

Credential provisioning belongs to the host bootstrap, not this repository.
Project code never sources credential files, shell startup files, or auth.json;
it never selects GH_TOKEN/GITHUB_TOKEN as model credentials. GitHub's job token
remains solely for repository/comment operations. A working terminal does not
prove launchd/runner environment readiness. Arrange narrowly scoped runner env
provisioning separately; do not print keys, copy daily auth caches, or restart
services as an automatic repair.

Runner prerequisites: Python 3.11+ on PATH (stdlib `tomllib`), the existing
standard Codex binary (`CODEX_BIN`, normally `/opt/homebrew/bin/codex`), the
daily provider metadata, and its allowed environment variable. Missing or unsafe
provider setup fails before Codex starts, with a sanitized `Raven setup failed`
diagnostic and no direct-OpenAI fallback or retry.

## Independent review home

The caller sets `CODEX_HOME=${CODEX_REVIEW_HOME:-$HOME/.codex-review}`.
An inherited daily CODEX_HOME is deliberately ignored. Provision that independent
review home separately and preserve its existing model/effort, no-hooks/no-MCP,
read-only sandbox and never-approval settings. The caller continues to pin
read-only and never-approval; the provider helper does not provision or verify
the whole home, and does not modify login state or auth caches.

Legacy auth-refresh/model-catalog warnings are separate diagnostics: do not
change login, CLI version, model or network policy merely to silence them.
Judge invocation by its exit status and actual output, not a warning alone.

## Trusted-base migration and acceptance

`pull_request_target` checks out the trusted base SHA. A candidate's new helper
does not repair the old base's own review execution. First establish runner env
readiness, land the approved bootstrap through the existing protected process,
then verify a later event whose base contains that bootstrap. Never substitute
PR-head code into the trusted runner, bypass checks, or blindly rerun unchanged
missing-environment failures.

Offline contracts exercise the real caller with fake Git/GitHub/Codex tools;
they make no model request and are not an actual review. No setup-only `--check`
mode is added: this helper's normal invocation starts Codex.

Keep evidence distinct: provider setup readiness; actual model invocation;
schema/verdict for the exact PR head; required Actions checks; protected merge.
A successful synthetic model call proves only that process's invocation, not
service environment or Actions consumption. Acceptance requires the real
`codex-review-target` run from the intended trusted base for the exact PR head,
a valid review verdict, and all existing required statuses. Kimi stays advisory,
Claude/legacy workflows and schedules stay paused, and existing deterministic
test/build gates and internal Reviewer responsibilities remain unchanged.

VitalStride retains the full-gate supervisor, process-group cleanup, stage markers,
CLI stdin EOF, and verdict/schema handling. Local verification is
`bash scripts/test-repoinfra.sh`; its existing unittest discovery invokes these
Raven contracts. The separate stdin/watchdog contract also follows the helper
invocation; no App builds are part of this change.
