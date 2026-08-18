#!/usr/bin/env bash
# Regression test for MY-1430: UTF-8 safe diff truncation in review gates.
#
# Verifies:
#   Track 1  Both review scripts use python3 UTF-8-safe truncation (not head -c)
#   Track 2  The renderer does not crash on surrogate characters (defense-in-depth)
#   Track 3  Truncation produces valid UTF-8 at or below MAX_BYTES
#   Track 4  TRUNCATED disclosure still present after truncation
#   Track 6  Claude gate cannot load tools or user-configured MCP servers
#
# Only does local assertions — no CLI spawn, no network.
#
# Usage:
#   bash scripts/ci/review-utf8-truncation.contract.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RENDERER="$SCRIPT_DIR/render-review-prompt.py"
TEMPLATE="$SCRIPT_DIR/review-prompt.md"

fail=0
pass=0

assert_pass() { echo "[PASS] $1"; pass=$((pass + 1)); }
assert_fail() { echo "[FAIL] $1"; fail=$((fail + 1)); }

# --- Track 1: Both scripts use python3 UTF-8-safe truncation, not head -c ---

for gate in claude-review.sh codex-review.sh; do
    target="$SCRIPT_DIR/$gate"
    if [ ! -f "$target" ]; then
        assert_fail "$gate not found"
        continue
    fi

    # Must NOT use head -c for diff truncation
    if grep -qE 'head -c.*MAX_BYTES' "$target"; then
        assert_fail "$gate still uses head -c for diff truncation (byte-unsafe)"
    else
        assert_pass "$gate does not use head -c for diff truncation"
    fi

    # Must use python3 decode with 'ignore' for safe truncation
    if grep -qE "decode\('utf-8',\s*'ignore'\)" "$target"; then
        assert_pass "$gate uses python3 UTF-8-safe decode('utf-8', 'ignore')"
    else
        assert_fail "$gate missing python3 UTF-8-safe truncation"
    fi

    # Python must consume stdin before slicing so the upstream shell builtin
    # never writes into a closed pipe and emits the Broken pipe seen in MY-1430.
    if grep -qF 'sys.stdin.buffer.read()[:' "$target"; then
        assert_pass "$gate consumes the full diff before truncating"
    else
        assert_fail "$gate can still close the diff pipe early (SIGPIPE risk)"
    fi
done

# --- Track 2: Renderer defense-in-depth against surrogates ----------------------

if [ ! -f "$RENDERER" ]; then
    assert_fail "render-review-prompt.py not found"
else
    # The renderer must have the encode/decode defense-in-depth
    if grep -qE '\.encode\(.*replace.*\)\.decode' "$RENDERER"; then
        assert_pass "renderer has encode('utf-8','replace').decode defense-in-depth"
    else
        assert_fail "renderer missing surrogate defense-in-depth"
    fi

    # Feed the renderer a DIFF containing lone surrogates via surrogateescape.
    # This simulates what happens when os.environ decodes truncated UTF-8 bytes.
    if [ -f "$TEMPLATE" ]; then
        RENDER_OUT="$(mktemp)"
        RENDER_ERR="$(mktemp)"
        # Use python to inject a surrogate into the DIFF env var
        if python3 -c "
import os, subprocess, sys

# Simulate a truncated UTF-8 byte (0xe4) decoded with surrogateescape
bad_diff = 'normal text\udce4'  # lone surrogate

env = os.environ.copy()
env['CHANGED'] = 'test.swift'
env['TRUNCATED'] = ''
env['DIFF'] = bad_diff

result = subprocess.run(
    [sys.executable, '$RENDERER', '$TEMPLATE'],
    env=env, capture_output=True, text=False
)
sys.exit(result.returncode)
" >"$RENDER_OUT" 2>"$RENDER_ERR"; then
            assert_pass "renderer does not crash on surrogate input"
        else
            assert_fail "renderer crashes on surrogate input (UnicodeEncodeError)"
            cat "$RENDER_ERR" >&2 || true
        fi
        rm -f "$RENDER_OUT" "$RENDER_ERR"
    fi
fi

# --- Track 3: Python truncation produces valid UTF-8 at or below MAX_BYTES ------

# Construct a >200000-byte string where byte 200000 falls in a multi-byte char
TRUNC_OUT="$(python3 -c "
import sys

# 580000 bytes of Chinese text (each char = 3 bytes)
raw = ('这是中文测试内容 abc ' * 20000).encode('utf-8')
cut = raw[:200000]

# The old code would fail here:
try:
    cut.decode('utf-8')
    # If this succeeds, the cut happened to land on a boundary (unlikely but possible)
    pass
except UnicodeDecodeError:
    pass  # Expected: byte 200000 is mid-character

# The fix: decode with 'ignore' should always produce valid UTF-8
result = cut.decode('utf-8', 'ignore')

# Verify result is valid UTF-8 and within byte budget
encoded = result.encode('utf-8')
if len(encoded) <= 200000:
    print('OK')
else:
    print(f'OVER: {len(encoded)} bytes')
    sys.exit(1)
" 2>&1)"

if [ "$TRUNC_OUT" = "OK" ]; then
    assert_pass "python3 truncation produces valid UTF-8 within byte budget"
else
    assert_fail "python3 truncation failed: $TRUNC_OUT"
fi

# Verify the cut point actually splits a multi-byte character (confirming the
# test is meaningful — if the cut always lands on a boundary, this test is vacuous)
python3 -c "
raw = ('这是中文测试内容 abc ' * 20000).encode('utf-8')
cut = raw[:200000]
try:
    cut.decode('utf-8', 'strict')
    # A boundary-aligned fixture would not reproduce the old bug.
    import sys; sys.exit(1)
except UnicodeDecodeError:
    # Expected: proves head -c would have produced invalid UTF-8
    import sys; sys.exit(0)
" && assert_pass "fixture confirms byte 200000 is mid-character (pre-fix would crash)"

# --- Track 4: TRUNCATED disclosure still present after truncation ----------------

for gate in claude-review.sh codex-review.sh; do
    target="$SCRIPT_DIR/$gate"
    [ ! -f "$target" ] && continue
    if grep -qF 'TRUNCATED="（diff 已截断至' "$target"; then
        assert_pass "$gate still sets TRUNCATED disclosure text"
    else
        assert_fail "$gate missing TRUNCATED disclosure text"
    fi
done

# --- Track 5: Required CI executes this regression contract -----------------------

CI_WORKFLOW="$SCRIPT_DIR/../../.github/workflows/ci.yml"
if [ -f "$CI_WORKFLOW" ] && grep -qF 'bash scripts/ci/review-utf8-truncation.contract.test.sh' "$CI_WORKFLOW"; then
    assert_pass "Lint & policy executes the UTF-8 truncation regression contract"
else
    assert_fail "Lint & policy does not execute review-utf8-truncation.contract.test.sh"
fi

# --- Track 6: Claude review is isolated from tools and MCP servers ---------------

CLAUDE_GATE="$SCRIPT_DIR/claude-review.sh"
if grep -qF -- '--tools ""' "$CLAUDE_GATE" \
    && grep -qF -- '--strict-mcp-config' "$CLAUDE_GATE" \
    && grep -qF -- '--mcp-config '\''{"mcpServers":{}}'\''' "$CLAUDE_GATE"; then
    assert_pass "claude-review disables tools and user-configured MCP servers"
else
    assert_fail "claude-review can still load tools or user-configured MCP servers"
fi

# --- Summary ---
echo
echo "review-utf8-truncation.contract.test.sh: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
