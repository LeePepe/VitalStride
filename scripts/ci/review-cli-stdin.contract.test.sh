#!/usr/bin/env bash
# Regression test for scripts/ci/*-review.sh —— review 门调用 CLI 时必须提供 stdin。
#
# 起因（PR #391）:codex-review.sh 把 prompt 作为**位置参数**传给 `codex exec`,
# 重定向了 stdout 和 stderr,却没有重定向 stdin。codex 即便已经拿到 prompt 参数,
# 仍会尝试从 stdin 读「additional input」;CI step 没有交互式 stdin 也永远不会
# 收到 EOF,于是无限期阻塞,直到 job 的 timeout-minutes 把 step kill 掉。
#
# 这个失败模式极其难认:
#   - conclusion 是 `cancelled` 而不是 `failure` —— 看起来像并发取消或人工中断
#   - stderr 只有一行 `Reading additional input from stdin...`
#   - 脚本里此前的 echo 因为缓冲一个都没 flush,日志上看不到任何进度
#   - 于是它长得**完全像**「codex 正在认真审一个大 diff」,而不是挂死
# PR #391 因此连挂两次、白等 40 分钟,最后靠本地复现 + 读 stderr 才定位。
#
# 判据:凡是把 prompt 作为**位置参数**传给 CLI 的调用,必须显式 `</dev/null`。
# 用管道喂 prompt（`printf %s "$PROMPT" | claude -p ...`）的调用天然有 EOF,
# 不需要也不应该加 —— 加了反而会把 prompt 本身冲掉。
#
# 只做静态断言 —— 不 spawn 任何 CLI、不联网,毫秒级完成。
#
# 用法:
#   bash scripts/ci/review-cli-stdin.contract.test.sh
# 退出码:0 = PASS;非 0 = FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0

fail() { echo "[FAIL] $*"; FAILED=1; }
pass() { echo "[ok]   $*"; }

# ---- Track 1: codex-review.sh 的位置参数调用必须有 </dev/null ----------------
CODEX_SH="$SCRIPT_DIR/codex-review.sh"
if [ ! -f "$CODEX_SH" ]; then
    fail "codex-review.sh 不存在（路径漂移？）—— 拒绝在扫描目标缺失时判 PASS"
else
    # 正对照:先确认这个文件里确实有 codex exec 调用。若这条都取不到,说明
    # 调用形态变了,下面的断言即使「通过」也毫无意义（零命中 == 通过,同形）。
    if ! grep -q 'exec \\' "$CODEX_SH"; then
        fail "codex-review.sh 里找不到 \`exec \\\` 调用 —— 正对照失败,断言不可信"
    else
        pass "正对照:codex-review.sh 含 codex exec 调用"

        # 取 `"$CODEX_BIN" exec \` 起、到第一个不以反斜杠结尾的行为止的整段调用
        INVOCATION="$(awk '/^"\$CODEX_BIN" exec \\/{f=1} f{print; if($0 !~ /\\$/) exit}' "$CODEX_SH")"
        if [ -z "$INVOCATION" ]; then
            fail "无法提取 codex exec 调用块 —— 拒绝判 PASS"
        elif printf '%s' "$INVOCATION" | grep -q '</dev/null'; then
            pass "codex exec 调用显式重定向 stdin (</dev/null)"
        else
            fail "codex exec 调用缺少 \`</dev/null\` —— CI 里会无限阻塞到 timeout"
            echo "       实际调用块:"
            printf '%s\n' "$INVOCATION" | sed 's/^/       | /'
        fi
    fi
fi

# ---- Track 2: claude-review.sh 用管道喂 prompt,不应加 stdin 重定向 -----------
CLAUDE_SH="$SCRIPT_DIR/claude-review.sh"
if [ ! -f "$CLAUDE_SH" ]; then
    fail "claude-review.sh 不存在（路径漂移？）"
else
    if grep -qE 'printf %s "\$PROMPT" \| *claude' "$CLAUDE_SH"; then
        pass "正对照:claude-review.sh 用管道喂 prompt（天然有 EOF）"
    else
        fail "claude-review.sh 的 prompt 投喂方式变了 —— 若改成位置参数,必须补 </dev/null"
    fi
fi

# ---- Verdict ---------------------------------------------------------------
echo
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: review 门的 CLI 调用均已正确处理 stdin。"
    exit 0
fi
echo "FAIL: 见上面的 [FAIL] 行。"
exit 1
