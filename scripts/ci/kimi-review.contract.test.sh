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
grep -Fq 'ready_for_review' "$KIMI_WORKFLOW"
grep -Fq '!github.event.pull_request.draft' "$KIMI_WORKFLOW"
grep -Fq '    branches: [main]' "$KIMI_WORKFLOW"
grep -Fq 'ref: ${{ github.event.pull_request.base.sha }}' "$KIMI_WORKFLOW"
! grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$KIMI_WORKFLOW"
grep -Fq -- '--unified=15' "$KIMI_SH"
grep -Fq 'MAX_BYTES="${REVIEW_MAX_BYTES:-40000}"' "$KIMI_SH"
grep -Fq 'KIMI_MAX_ATTEMPTS="${KIMI_MAX_ATTEMPTS:-1}"' "$KIMI_SH"
grep -Fq 'p[:8000]' "$KIMI_SH"
! grep -Fq 'p[:24000]' "$KIMI_SH"
grep -Fq 'already has a completed Kimi review; skipping per once-per-PR quota policy.' "$KIMI_SH"
grep -Fq 'No non-documentation code changes; skipped Kimi LLM invocation to conserve quota.' "$KIMI_SH"
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

TMP_WORK="$(mktemp -d -t kimi-contract-test.XXXXXX)"
trap 'rm -rf "$TMP_WORK"' EXIT
mkdir -p "$TMP_WORK/repo/scripts/ci" "$TMP_WORK/tools" "$TMP_WORK/out"
cp "$KIMI_SH" "$TMP_WORK/repo/scripts/ci/kimi-review.sh"
cp "$KIMI_AGENT" "$TMP_WORK/repo/scripts/ci/kimi-review-agent.md"
chmod +x "$TMP_WORK/repo/scripts/ci/kimi-review.sh"
(
    unset $(git rev-parse --local-env-vars)
    cd "$TMP_WORK/repo"
    git init -q -b main
    git config user.name "t"
    git config user.email "t@example.invalid"
    echo "# rules" > AGENTS.md
    echo "X=1" > code.sh
    git add .
    git commit -qm "base"
    BASE_SHA="$(git rev-parse HEAD)"
    echo "X=2" > code.sh
    git add code.sh
    git commit -qm "code head"
    CODE_HEAD_SHA="$(git rev-parse HEAD)"
    git checkout -q "$BASE_SHA"
    echo "# docs" > README.md
    git add README.md
    git commit -qm "docs head"
    DOCS_HEAD_SHA="$(git rev-parse HEAD)"
    git checkout -q --detach "$BASE_SHA"
    git remote add origin "$TMP_WORK/repo"

    cat > "$TMP_WORK/tools/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"--paginate"*".body // empty"*)
    printf "%s" "${STUB_EXISTING_STICKY:-}"
    ;;
  *"--paginate"*)
    printf "%s" "${STUB_COMMENT_ID:-}"
    ;;
  "pr comment"*)
    prev=""
    for a in "$@"; do
      [ "$prev" = "--body" ] && printf "%s" "$a" > "$STUB_OUT/comment"
      prev="$a"
    done
    ;;
  *)
    for a in "$@"; do
      case "$a" in body=*) printf "%s" "${a#body=}" > "$STUB_OUT/comment" ;; esac
    done
    ;;
esac
exit 0
EOF
    chmod +x "$TMP_WORK/tools/gh"

    cat > "$TMP_WORK/tools/kimi" <<'EOF'
#!/bin/sh
touch "$STUB_OUT/kimi_invoked"
printf '%s\n' '{"role":"assistant","content":"{\"verdict\":\"pass\",\"summary\":\"ok\",\"blockers\":[],\"notes\":[]}"}'
EOF
    chmod +x "$TMP_WORK/tools/kimi"

    # 1. Once-per-PR guard skips when completed sticky comment exists
    rm -f "$TMP_WORK/out/"*
    OUT1="$(PATH="$TMP_WORK/tools:$PATH" PR_NUMBER=11 BASE_SHA="$BASE_SHA" HEAD_SHA="$CODE_HEAD_SHA" BASE_REPO="LeePepe/VitalStride" \
        KIMI_BIN="$TMP_WORK/tools/kimi" STUB_OUT="$TMP_WORK/out" GITHUB_OUTPUT="$TMP_WORK/out/gh_out" \
        STUB_EXISTING_STICKY="$(printf '<!-- kimi-advisory-review -->\n## ✅ Kimi advisory review: pass\n')" \
        bash "$TMP_WORK/repo/scripts/ci/kimi-review.sh")"
    printf '%s\n' "$OUT1" | grep -Fq "[kimi-review] PR #11 already has a completed Kimi review; skipping per once-per-PR quota policy."
    [ ! -f "$TMP_WORK/out/kimi_invoked" ]
    grep -Fq "completed=true" "$TMP_WORK/out/gh_out"

    # 2. Docs-only diff skips Kimi invocation and posts pass note
    rm -f "$TMP_WORK/out/"*
    OUT2="$(PATH="$TMP_WORK/tools:$PATH" PR_NUMBER=12 BASE_SHA="$BASE_SHA" HEAD_SHA="$DOCS_HEAD_SHA" BASE_REPO="LeePepe/VitalStride" \
        KIMI_BIN="$TMP_WORK/tools/kimi" STUB_OUT="$TMP_WORK/out" GITHUB_OUTPUT="$TMP_WORK/out/gh_out" \
        bash "$TMP_WORK/repo/scripts/ci/kimi-review.sh")"
    [ ! -f "$TMP_WORK/out/kimi_invoked" ]
    grep -Fq "No non-documentation code changes; skipped Kimi LLM invocation to conserve quota." "$TMP_WORK/out/comment"
    grep -Fq "completed=true" "$TMP_WORK/out/gh_out"
)

echo "Kimi advisory / Claude pause contract passed."
