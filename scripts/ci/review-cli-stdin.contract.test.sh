#!/usr/bin/env bash
# Regression test for the review gates（scripts/ci/*-review.sh + 两个 workflow）。
#
# 锁住 MY-1415 的两个死锁根因，以及修复本身依赖的几条不变量：
#   Track 1/2  CLI 调用的 stdin 处理（位置参数必须 </dev/null；管道投喂天然有 EOF）
#   Track 3    runner 执行的脚本不得含 heredoc / here-string（bash 5.3 >=512B 死锁）
#   Track 4    看门狗必须包住整个 gate、fail-closed，且 job timeout > 看门狗预算
#   Track 5    两道门必须 checkout 可信 base，而非 PR head
#
# 只做静态断言 —— 不 spawn 任何 CLI、不联网，毫秒级完成。
#
# 用法:
#   bash scripts/ci/review-cli-stdin.contract.test.sh
# 退出码:0 = PASS;非 0 = FAIL
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

# ---- Track 3: runner 上执行的脚本不得含 >= PIPE_BUF 的 heredoc / here-string --
# 起因(MY-1415, run 31929789189):修完 stdin 后 gate 仍然挂死,位置在**调用
# codex 之前** —— `scripts/ci/codex-review.sh:99` 的 schema heredoc。sample 显示
# Bash 阻塞在 `heredoc_write -> write`,lsof 显示 stdout 指向 0-byte schema 临时
# 文件。同一台 runner 上 `scripts/check-frontmatter.sh` 的 parser heredoc 也复现。
#
# 根因(本地二分复现):self-hosted mac runner 用的 bash 5.3 会把 heredoc 正文写进
# 一个管道而非临时文件;macOS 的 PIPE_BUF 是 **512 字节**,超过就写阻塞,而读端要
# 等 fork 出的命令才存在 —— 于是 >= 512B 的 heredoc **必然死锁**。实测边界精确:
#   511B → OK       512B → 永久阻塞      (bash 3.2 /bin/bash 全部 OK)
# here-string(`<<<`)走同一条路径,边界相同。
#
# 这个失败模式没有任何日志:进程在写 heredoc 时就停住,脚本自己的 echo 一个字都
# 没执行,job 20 分钟后报 cancelled —— 与 stdin bug 表现完全一致,所以修完 stdin
# 后仍然复现,白烧第三次 CI。
#
# 判据:runner 执行的脚本里**一个 heredoc / here-string 都不许有**。不按字节数
# 判 —— 阈值是 PIPE_BUF 这种平台细节,且内容会增长;一刀切最省心也最安全。
# 需要多行内容就放真实文件(schema → codex-review.schema.json,解析器 →
# scripts/lib/frontmatter.py);需要喂数据给循环就用进程替换 `< <(printf ...)`,
# 实测 60KB 无阻塞。
RUNNER_SCRIPTS="$SCRIPT_DIR/codex-review.sh $SCRIPT_DIR/claude-review.sh $SCRIPT_DIR/../check-frontmatter.sh"
for f in $RUNNER_SCRIPTS; do
    name="$(basename "$f")"
    if [ ! -f "$f" ]; then
        fail "$name 不存在（路径漂移？）—— 拒绝在扫描目标缺失时判 PASS"
        continue
    fi
    # 去掉整行注释后再找 `<<` —— 注释里讲解这个坑是合法的（本文件就是）。
    hits="$(grep -nE '<<' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    if [ -n "$hits" ]; then
        fail "$name 含 heredoc / here-string —— bash 5.3 在 >=512B 时会永久死锁"
        printf '%s\n' "$hits" | sed 's/^/       | /'
    else
        pass "$name 无 heredoc / here-string"
    fi
done

# 正对照:schema 必须真的是个文件,且是合法 JSON。否则「无 heredoc」可以靠
# 把 schema 整个删掉来满足 —— 那是把门拆了,不是修好。
SCHEMA_JSON="$SCRIPT_DIR/codex-review.schema.json"
if [ ! -f "$SCHEMA_JSON" ]; then
    fail "缺 $SCHEMA_JSON —— schema 必须是真实文件（不能回退成 heredoc）"
elif command -v python3 >/dev/null 2>&1 && ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SCHEMA_JSON" 2>/dev/null; then
    fail "codex-review.schema.json 不是合法 JSON"
else
    pass "verdict schema 是真实文件且为合法 JSON"
fi
# schema 必须真的被 codex-review.sh 使用 —— 独立于上面的存在性检查,否则
# 「文件在、但脚本指向别处」这种半吊子改动会溜过去。
if ! grep -q 'SCHEMA_FILE="\$SCRIPT_DIR/codex-review.schema.json"' "$CODEX_SH" 2>/dev/null; then
    fail "codex-review.sh 未指向 codex-review.schema.json —— schema 可能没被使用"
else
    pass "codex-review.sh 引用 codex-review.schema.json"
fi

FM_LIB="$SCRIPT_DIR/../lib/frontmatter.py"
if [ ! -f "$FM_LIB" ]; then
    fail "缺 $FM_LIB —— frontmatter 解析器必须是真实文件（不能回退成 heredoc）"
else
    pass "frontmatter 解析器是真实文件"
fi

# ---- Track 4: 看门狗必须包住整个 gate,且预算 + 余量 <= job timeout -----------
# PR #393 初版的看门狗只包住 codex exec 之后半段,对 line 99 的 heredoc 死锁完全
# 无效 —— 那次死锁发生在 exec **之前**。所以这里锁的是「整个 gate 被包住」,
# 不只是「有个看门狗」。
CODEX_YML="$SCRIPT_DIR/../../.github/workflows/codex-review.yml"
if ! grep -q 'GATE_TIMEOUT_SECONDS' "$CODEX_SH" 2>/dev/null; then
    fail "codex-review.sh 缺 GATE_TIMEOUT_SECONDS 看门狗 —— 挂死会退回「静默 cancelled、零证据」"
else
    pass "codex-review.sh 有 gate 看门狗"
    # 看门狗必须在**取 diff / 写 schema / 渲染 prompt 之前**就已生效,否则覆盖不全。
    wd_line="$(grep -n 'VS_GATE_SUPERVISED' "$CODEX_SH" | head -1 | cut -d: -f1)"
    first_work="$(grep -nE '^(stage fetch-diff|SCHEMA_FILE=|if ! git fetch)' "$CODEX_SH" | head -1 | cut -d: -f1)"
    if [ -n "$wd_line" ] && [ -n "$first_work" ] && [ "$wd_line" -lt "$first_work" ]; then
        pass "看门狗在第一个可能阻塞的阶段之前生效（覆盖整个 gate）"
    else
        fail "看门狗没有包住整个 gate（supervisor 行=${wd_line:-?}, 首个工作阶段行=${first_work:-?}）"
    fi

    # 行序只能证明「写在前面」,不能证明「真的会跑」——把 supervisor 的分支条件改成
    # 恒假,行序断言依然通过,但看门狗实际被完全绕过(PR #393 初版就是只包住 codex
    # exec 后半段,对 exec 之前的 heredoc 死锁毫无作用)。因此把**触发条件本身**钉死:
    # 它必须恰好是「未被监管时进入 supervisor 分支」这一种形态,不能挂任何额外条件。
    # 保持纯静态断言(不 spawn CLI、不联网),与本文件其余部分一致。
    if grep -qE '^if \[ -z "\$\{VS_GATE_SUPERVISED:-\}" \]; then$' "$CODEX_SH"; then
        pass "supervisor 触发条件未被附加条件削弱（看门狗必然生效）"
    else
        fail "supervisor 触发条件形态被改动 —— 看门狗可能被绕过（期望恰好为 \`if [ -z \"\\\${VS_GATE_SUPERVISED:-}\" ]; then\`）"
        grep -nE 'VS_GATE_SUPERVISED:-' "$CODEX_SH" | sed 's/^/       | /'
    fi
    # 超时路径必须 fail-closed:从「超时判定」那一行到紧随其后的 exit,中间不得
    # 出现 exit 0。取 supervisor 块内、超时分支起始处之后的 25 行做窗口。
    to_line="$(grep -n 'WAITED" -ge "\$GATE_TIMEOUT_SECONDS' "$CODEX_SH" | head -1 | cut -d: -f1)"
    if [ -z "$to_line" ]; then
        fail "找不到看门狗超时判定 —— 拒绝判 PASS"
    else
        window="$(sed -n "${to_line},$((to_line + 25))p" "$CODEX_SH")"
        first_exit="$(printf '%s\n' "$window" | grep -oE 'exit [0-9]+' | head -1)"
        if [ "$first_exit" = "exit 1" ]; then
            pass "看门狗超时路径 fail-closed（exit 1）"
        else
            fail "看门狗超时路径不是 fail-closed（首个 exit 为 '${first_exit:-无}'）—— 未审 diff 可能被放行"
        fi
    fi
fi

# job timeout 必须 > 脚本看门狗预算 + 余量,否则外层先到点,又退回零证据模式。
if [ ! -f "$CODEX_YML" ]; then
    fail "codex-review.yml 不存在（路径漂移？）"
else
    JOB_MIN="$(grep -E '^\s*timeout-minutes:' "$CODEX_YML" | head -1 | grep -oE '[0-9]+' || true)"
    GATE_SEC="$(grep -oE 'GATE_TIMEOUT_SECONDS:-[0-9]+' "$CODEX_SH" | grep -oE '[0-9]+' | head -1 || true)"
    if [ -z "$JOB_MIN" ] || [ -z "$GATE_SEC" ]; then
        fail "取不到 job timeout（${JOB_MIN:-?}）或 gate 预算（${GATE_SEC:-?}）—— 拒绝判 PASS"
    else
        # 余量必须覆盖 gate 之外的开销(checkout、fetch、贴 sticky comment)**并**
        # 确保脚本先于 job 到点。历史值 20min 对 600s 预算只剩 10min 余量,看似够
        # 用,但一旦预算上调就会悄悄反转大小关系 —— 所以这里锁的是**倍数关系**:
        # job timeout 至少是看门狗预算的 2 倍,且绝对余量 >= 8 分钟。
        # 二者同时满足才 PASS,避免「把 job timeout 调回 20 分钟」这类回归溜过去。
        NEED_ABS=$(( GATE_SEC + 480 ))
        NEED_MUL=$(( GATE_SEC * 2 ))
        JOB_SEC=$(( JOB_MIN * 60 ))
        if [ "$JOB_SEC" -ge "$NEED_ABS" ] && [ "$JOB_SEC" -ge "$NEED_MUL" ]; then
            pass "job timeout ${JOB_MIN}min >= gate 预算 ${GATE_SEC}s 的 2 倍且余量 >= 8min"
        else
            fail "job timeout ${JOB_MIN}min 相对 gate 预算 ${GATE_SEC}s 余量不足(需 >= $((NEED_ABS > NEED_MUL ? NEED_ABS : NEED_MUL))s) —— job 可能先超时,退回零证据 cancelled"
        fi
    fi
fi

# ---- Track 5: 两道 review 门必须 checkout base 而非 PR head ------------------
# 安全红线:评审脚本来自可信 base。若改成 checkout PR head,同仓库分支 PR 就能
# 改 scripts/ci/*.sh 在维护者机器上跑任意代码。
for yml in "$SCRIPT_DIR/../../.github/workflows/codex-review.yml" \
           "$SCRIPT_DIR/../../.github/workflows/claude-review.yml"; do
    yname="$(basename "$yml")"
    if [ ! -f "$yml" ]; then
        fail "$yname 不存在（路径漂移？）"
    elif grep -qE 'ref:\s*\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\}\}' "$yml"; then
        pass "$yname checkout 可信 base（非 PR head）"
    else
        fail "$yname 未 checkout base.sha —— 评审脚本必须来自可信 base"
    fi
done

# ---- Verdict ---------------------------------------------------------------
echo
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: review 门的 stdin / heredoc / 看门狗 / trusted-base 契约均成立。"
    exit 0
fi
echo "FAIL: 见上面的 [FAIL] 行。"
exit 1
