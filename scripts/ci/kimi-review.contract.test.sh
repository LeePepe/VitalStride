#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIMI_SH="$ROOT/scripts/ci/kimi-review.sh"
KIMI_AGENT="$ROOT/scripts/ci/kimi-review-agent.md"
KIMI_WORKFLOW="$ROOT/.github/workflows/kimi-review.yml"
CODEX_TARGET_WORKFLOW="$ROOT/.github/workflows/codex-review-target.yml"
CODEX_LEGACY_WORKFLOW="$ROOT/.github/workflows/codex-review.yml"
CLAUDE_WORKFLOW="$ROOT/.github/workflows/claude-review.yml"

grep -q '^tools: \[\]$' "$KIMI_AGENT"
grep -q '^subagents: \[\]$' "$KIMI_AGENT"
grep -q -- '--agent-file "$SCRIPT_DIR/kimi-review-agent.md"' "$KIMI_SH"
grep -q -- '--output-format stream-json' "$KIMI_SH"
grep -q 'KIMI_REVIEW_MODEL:-kimi-code/k3' "$KIMI_SH"
! grep -Eq -- '(^|[[:space:]])(--yolo|--auto)([[:space:]]|$)' "$KIMI_SH"
grep -q 'Advisory only: this check and its findings are not required for merge' "$KIMI_SH"
begin_line="$(grep -n '===== BEGIN UNTRUSTED PR DIFF' "$KIMI_SH" | head -1 | cut -d: -f1)"
paths_line="$(grep -n '^Changed paths:$' "$KIMI_SH" | head -1 | cut -d: -f1)"
end_line="$(grep -n '===== END UNTRUSTED PR DIFF' "$KIMI_SH" | head -1 | cut -d: -f1)"
[ "$begin_line" -lt "$paths_line" ] && [ "$paths_line" -lt "$end_line" ]
grep -q '^  pull_request_target:$' "$KIMI_WORKFLOW"
grep -Fq '    branches: [main]' "$KIMI_WORKFLOW"
grep -Fq 'ref: ${{ github.event.pull_request.base.sha }}' "$KIMI_WORKFLOW"
! grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$KIMI_WORKFLOW"
grep -q '^  pull_request_target:$' "$CODEX_TARGET_WORKFLOW"
grep -q '^  codex-review-target:$' "$CODEX_TARGET_WORKFLOW"
grep -Fq '    branches: [main]' "$CODEX_TARGET_WORKFLOW"
grep -Fq 'ref: ${{ github.event.pull_request.base.sha }}' "$CODEX_TARGET_WORKFLOW"
! grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$CODEX_TARGET_WORKFLOW"
grep -q '^  workflow_dispatch:$' "$CODEX_LEGACY_WORKFLOW"
! grep -q '^  pull_request:$' "$CODEX_LEGACY_WORKFLOW"
grep -q '^  workflow_dispatch:$' "$CLAUDE_WORKFLOW"
! grep -q '^  pull_request:$' "$CLAUDE_WORKFLOW"

if [ -f "$ROOT/scripts/rulesets/main-protection.json" ]; then
    ! jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="kimi-review" or .context=="claude-review")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
    jq -e '.rules[]? | select(.type=="required_status_checks")
      | .parameters.required_status_checks[]? | select(.context=="codex-review-target")' \
      "$ROOT/scripts/rulesets/main-protection.json" >/dev/null
fi

# AC-01 & AC-02: Shared-ci pin, caller inputs, and AGENTS.md parity
PIN="6e354f476bc53d68f0f09fc231d5cd938466af9c"
grep -qF "uses: LeePepe/shared-ci/.github/workflows/codex-review.yml@$PIN" "$CODEX_TARGET_WORKFLOW"
grep -qF "LeePepe/shared-ci@$PIN/ai/agent-protocol.md" "$ROOT/AGENTS.md"
grep -qF "LeePepe/shared-ci@$PIN/ai/" "$ROOT/AGENTS.md"
! grep -qF 'secrets: inherit' "$CODEX_TARGET_WORKFLOW"
grep -qF "runs-on: '[\"self-hosted\", \"vitalstride-mac\"]'" "$CODEX_TARGET_WORKFLOW"
grep -qF 'codex-bin: /opt/homebrew/bin/codex' "$CODEX_TARGET_WORKFLOW"
grep -qF 'rules-file: docs/codex-review-rules.md' "$CODEX_TARGET_WORKFLOW"
grep -qF 'timeout-minutes: 25' "$CODEX_TARGET_WORKFLOW"

# AC-03 & AC-05: Hosted completion job and Raven detachment
grep -qE '^\s*codex-review-target:' "$CODEX_TARGET_WORKFLOW"
grep -qE 'needs:\s*\[?codex-review\]?' "$CODEX_TARGET_WORKFLOW"
grep -qE 'runs-on:\s*ubuntu-latest' "$CODEX_TARGET_WORKFLOW"
grep -qE 'permissions:\s*\{\}' "$CODEX_TARGET_WORKFLOW"
! grep -qE '(codex-review\.sh|review-raven\.py|RAVEN_API_KEY|CODEX_RAVEN_CONFIG)' "$CODEX_TARGET_WORKFLOW"

# AC-05 & docs: Raven operations doc and ci-gates doc
grep -qF 'INACTIVE / OFFLINE LEGACY MAINTENANCE ONLY' "$ROOT/scripts/ci/raven-review-operations.md"
grep -qF 'shared-ci' "$ROOT/scripts/ci/raven-review-operations.md"
grep -qF 'shared-ci' "$ROOT/docs/ci-gates.md"
grep -qF "$PIN" "$ROOT/docs/ci-gates.md"

# AC-06: Compact trusted review rules file
RULES_DOC="$ROOT/docs/codex-review-rules.md"
[ -f "$RULES_DOC" ]
rules_size="$(wc -c < "$RULES_DOC" | tr -d ' ')"
[ "$rules_size" -gt 0 ] && [ "$rules_size" -le 24000 ]
! grep -qE '\{\{(CHANGED|DIFF|TRUNCATED|REPO_RULES|ARCHITECTURE|OWNER_DECISIONS)\}\}' "$RULES_DOC"

echo "Kimi advisory / Claude pause / shared-ci review contract passed."
