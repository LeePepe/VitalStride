# Raven review operations (INACTIVE / OFFLINE LEGACY)

> **Status: INACTIVE / OFFLINE LEGACY MAINTENANCE ONLY.**
>
> No active GitHub Actions workflow invokes this Raven review bundle. The active required AI review gate (`codex-review-target`) is powered by reusable `LeePepe/shared-ci/.github/workflows/codex-review.yml@6e354f476bc53d68f0f09fc231d5cd938466af9c` (see `docs/ci-gates.md` and `docs/codex-review-rules.md`).
>
> The files `scripts/ci/codex-review.sh`, `scripts/ci/review-raven.py`, `scripts/ci/codex-review.schema.json`, their coupled offline contract tests, and this document are retained as an inactive/offline legacy bundle. All instructions below apply strictly to offline local debugging or historical reference.

## Offline Architecture & Context

The historical `codex-review.sh` script invoked the standard Codex CLI through
`review-raven.py`. Only the existing daily provider's connection metadata was
imported: `CODEX_RAVEN_CONFIG`, or `$HOME/.codex/config.toml` by default,
when selecting `model_provider = "raven"`. The helper required a loopback HTTP(S)
endpoint with an explicit port, Responses transport, and no OpenAI account
authentication requirement. It never copied the daily config or changed models.

## Offline Runner Readiness & Authentication Context (Legacy)

1. The historical review client authenticated to Raven using the provider's named
   environment variable: `OPENAI_API_KEY` or `RAVEN_API_KEY`.
2. Raven owned its separate upstream Copilot authentication.
3. Offline execution required Python 3.11+ on PATH (stdlib `tomllib`) and the local
   standard Codex binary (`CODEX_BIN`, normally `/opt/homebrew/bin/codex`).

## Dedicated Review Home (Legacy Context)

The historical caller set `CODEX_HOME=${CODEX_REVIEW_HOME:-$HOME/.codex-review}`.
The live shared-ci workflow continues to use the dedicated review home (`$HOME/.codex-review`).

## Offline Verification & Legacy Maintenance

Offline contracts exercise the historical caller with fake Git/GitHub/Codex tools;
they make no model request and are not an actual review.

Local verification is `bash scripts/test-repoinfra.sh`; its existing unittest discovery
invokes these legacy Raven contracts for backward compatibility. Live production review
is handled exclusively by the shared-ci gate.
