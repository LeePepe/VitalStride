#!/usr/bin/env bash
# VitalStride 自动 code review（codex）—— 在 self-hosted runner 上用本地 `codex` CLI 跑。
#
# 与 claude-review.sh 并列的第二道独立门（不同模型交叉验证）。
# 由 .github/workflows/codex-review.yml 的 codex-review job 调用。
# **安全边界在 workflow YAML 的 job-level `if`**(来自 base 分支、fork 改不到):
# 只有同仓库分支 PR 才会到达这里;fork PR 由另一个 job 处理,PR 代码不在本机执行。
# 本脚本不自行判 fork —— 那个判断放在被 PR 篡改的脚本里是不可信的。
#
# 设计成确定性门:
#   - 无 blocker           → 贴一条 sticky comment,exit 0(check 绿)
#   - 有 blocker(P0/严重) → 更新 sticky comment,exit 1(check 红 → 挡 auto-merge)
#   - 任何工具异常          → exit 1(fail closed,宁可卡住也不放行未审的 diff)
#
# 依赖:git, gh(runner 环境自带 GITHUB_TOKEN), jq, codex(已订阅登录)。
# 需要的环境变量(workflow 注入):
#   PR_NUMBER, BASE_SHA, HEAD_SHA, BASE_REPO, GH_TOKEN
#
# 认证:与 claude-review 对等——用 ChatGPT 订阅凭证(落磁盘),不依赖任何 API key。
# 凭证放在独立的 CODEX_HOME(默认 ~/.codex-review),与 cmux 日常用的 ~/.codex 隔离,
# 互不影响。该目录的 config.toml 已关 hooks / 清空 MCP / 只读沙箱。

set -uo pipefail

# 独立 CODEX_HOME:review 门专用,不碰用户日常的 ~/.codex(raven/cmux)。
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex-review}"
# 用标准 codex 二进制(runner PATH 里可能有 cmux shim,显式指定避免走到 raven)。
CODEX_BIN="${CODEX_BIN:-/opt/homebrew/bin/codex}"
command -v "$CODEX_BIN" >/dev/null 2>&1 || CODEX_BIN="codex"

# 在 cd 之前解析脚本目录:后面要读同目录的 review-prompt.md / 渲染器。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

: "${PR_NUMBER:?}"; : "${BASE_SHA:?}"; : "${HEAD_SHA:?}"; : "${BASE_REPO:?}"

STICKY="<!-- vitalstride-mac-codex-review -->"

post_sticky() {
    # 维护同一条 sticky 评论(避免每次 synchronize 刷屏)。$1=正文。
    # 用 REST 直接按 marker 找本 bot 已发的那条并 PATCH;没有则新建。
    local body="$1" id
    id="$(gh api "repos/$BASE_REPO/issues/$PR_NUMBER/comments" --paginate \
        --jq "[.[] | select(.body | contains(\"$STICKY\"))] | last | .id" 2>/dev/null || true)"
    if [ -n "$id" ] && [ "$id" != "null" ]; then
        gh api -X PATCH "repos/$BASE_REPO/issues/comments/$id" -f body="$body" >/dev/null \
            && return 0
    fi
    gh pr comment "$PR_NUMBER" --body "$body" >/dev/null
}

# ---- 全 gate 看门狗 ------------------------------------------------------
# 这道门是 required check,任何挂死都会表现为「job 静默 timeout → conclusion
# cancelled → 零证据」。MY-1415 连挂三次(run 31921971093 两次 + 31929789189)才
# 定位,原因正是**没有证据**:两次死锁都发生在调用 codex 之前或之中,进程被
# SIGKILL,连脚本自己的 echo 都没能 flush。
#
# 因此看门狗必须包住**整个 gate**,而不只是 codex exec 那一段 —— 已知的两个死锁
# 点(schema heredoc、stdin)一个在 exec 之前、一个在 exec 之中;只包后半段的
# 看门狗对前者完全无效。做法:脚本以 supervisor 模式重新 exec 自己,子进程跑真正
# 的 gate 并把当前阶段写进 stage 文件;超时则杀掉整棵进程树,并用 stage 文件报出
# **卡在哪一阶段** —— 这就是下一次排查需要的、之前完全缺失的证据。
#
# 超时一律 exit 1(fail-closed):未审的 diff 绝不放行。
GATE_TIMEOUT_SECONDS="${GATE_TIMEOUT_SECONDS:-600}"

stage() { printf '%s' "$1" > "${VS_GATE_STAGE_FILE:-/dev/null}" 2>/dev/null || true; }

if [ -z "${VS_GATE_SUPERVISED:-}" ]; then
    VS_GATE_STAGE_FILE="$(mktemp -t codex-review-stage.XXXXXX)"
    export VS_GATE_STAGE_FILE VS_GATE_SUPERVISED=1
    printf 'startup' > "$VS_GATE_STAGE_FILE"

    # `set -m` 让子进程成为独立进程组的组长(pgid == pid)。超时时按**进程组**
    # 整组 kill,而不是 `pkill -P`(只杀直接子进程,会漏掉孙子进程 —— 实测
    # codex / python 这类被 gate 派生的进程会作为孤儿继续占用 runner)。
    set -m
    VS_GATE_SUPERVISED=1 bash "$0" "$@" &
    GATE_PID=$!
    set +m

    WAITED=0
    while kill -0 "$GATE_PID" 2>/dev/null; do
        if [ "$WAITED" -ge "$GATE_TIMEOUT_SECONDS" ]; then
            LAST_STAGE="$(cat "$VS_GATE_STAGE_FILE" 2>/dev/null || echo unknown)"
            # 整组 kill:codex / python 会派生子进程,漏杀会留下孤儿占用 runner。
            kill -KILL -- "-$GATE_PID" 2>/dev/null || true
            pkill -KILL -P "$GATE_PID" 2>/dev/null || true
            kill -KILL "$GATE_PID" 2>/dev/null || true
            wait "$GATE_PID" 2>/dev/null || true
            rm -f "$VS_GATE_STAGE_FILE"
            echo "[codex-review] ❌ gate 超过 ${GATE_TIMEOUT_SECONDS}s 未完成,已主动终止(卡在阶段: ${LAST_STAGE})"
            post_sticky "$STICKY
⚠️ 自动 review 超过 ${GATE_TIMEOUT_SECONDS}s 未完成,已主动终止(卡在阶段 \`${LAST_STAGE}\`)。为安全起见 **暂不放行**,请重跑;若稳定复现,按该阶段排查。"
            exit 1
        fi
        sleep 5
        WAITED=$((WAITED + 5))
    done
    wait "$GATE_PID"; GATE_RC=$?
    rm -f "$VS_GATE_STAGE_FILE"
    exit "$GATE_RC"
fi

# ---- 以下为被监管的真正 gate 逻辑 ----------------------------------------

# ---- 取 diff ------------------------------------------------------------
# 工作树是 checkout base 的,PR 的 HEAD 对象只能靠这次 fetch 才存在。因此 fetch
# 失败不能吞掉——否则 HEAD 取不到 → diff 为空 → 被误判成"无 diff pass",一次网络
# 抖动就能让 review 门在未审 diff 的情况下放绿灯(fail-open)。这里 fail-closed:
# fetch 失败、或 fetch 后 BASE/HEAD 对象仍缺失,一律 exit 1(宁可卡住不放行)。
stage fetch-diff
if ! git fetch --no-tags --depth=100 origin "$BASE_SHA" "$HEAD_SHA" 2>/tmp/codex-fetch.err; then
    echo "[codex-review] ❌ git fetch 失败,无法取 PR diff"; cat /tmp/codex-fetch.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能取到 PR diff(git fetch 失败)。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null || ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
    echo "[codex-review] ❌ fetch 后 BASE/HEAD 对象仍缺失,无法可靠取 diff"
    post_sticky "$STICKY
⚠️ 自动 review 无法取到完整 PR 提交对象。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
stage compute-diff
DIFF="$(git diff "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff "$BASE_SHA..$HEAD_SHA")"
CHANGED="$(git diff --name-only "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff --name-only "$BASE_SHA..$HEAD_SHA")"

# 此处 DIFF 为空 = BASE/HEAD 对象都在但两者间确无差异(罕见但合法)。对象已确认
# 存在,空 diff 是真·无改动,可安全 pass。
if [ -z "$DIFF" ]; then
    post_sticky "$STICKY
✅ 无代码 diff,自动 review 通过。"
    echo "[codex-review] empty diff(对象已验证存在); pass"
    exit 0
fi

# diff 过大时截断(保护 CLI 上下文;截断本身在 prompt 里声明)。
# 必须按字符边界截断:head -c 是字节切,会切裂 UTF-8 多字节字符(中文 3 字节),
# 产生孤立代理字符 → 渲染器 UnicodeEncodeError → 门 fail-closed(MY-1430)。
MAX_BYTES=200000
TRUNCATED=""
if [ "$(printf %s "$DIFF" | wc -c)" -gt "$MAX_BYTES" ]; then
    DIFF="$(printf %s "$DIFF" | python3 -c "
import sys
b = sys.stdin.buffer.read($MAX_BYTES)
sys.stdout.write(b.decode('utf-8', 'ignore'))
")"
    TRUNCATED="（diff 已截断至 ${MAX_BYTES} 字节；未覆盖部分请人工留意）"
fi

# ---- verdict schema -----------------------------------------------------
# codex --output-schema 要求 schema 放在文件里。schema 直接就是仓库里的一个
# 真实文件（scripts/ci/codex-review.schema.json），不再由脚本在运行时用 heredoc
# 写出来 —— 那个 heredoc 正是 MY-1415 的第二个死锁点：self-hosted mac runner 的
# bash 5.3 在 heredoc payload >= PIPE_BUF(512B) 时会永久阻塞，而这段 schema 是
# 762B。脚本因此在**调用 codex 之前**就挂死，日志零输出、job 20 分钟后报
# `cancelled` —— 与 stdin 那个 bug 表现完全一致，所以修完 stdin 后仍然复现
# （run 31929789189）。schema 走可信 base checkout，与脚本同源，安全边界不变。
stage load-schema
SCHEMA_FILE="$SCRIPT_DIR/codex-review.schema.json"
if [ ! -f "$SCHEMA_FILE" ]; then
    echo "[codex-review] ❌ 缺 verdict schema: $SCHEMA_FILE"
    post_sticky "$STICKY
⚠️ 自动 review 缺少 verdict schema 文件。为安全起见 **暂不放行**,请人工检查。"
    exit 1
fi
OUT_FILE="$(mktemp -t codex-review-out.XXXXXX.json)"
ERR_FILE="$(mktemp -t codex-review-err.XXXXXX.log)"
cleanup() { rm -f "$OUT_FILE" "$ERR_FILE"; }
trap cleanup EXIT

# ---- review prompt ------------------------------------------------------
# prompt 规则的唯一真相是 scripts/ci/review-prompt.md(两道 review 门共用,
# claude-review.sh 读同一份 —— 同一套仓库宪法,两个模型交叉验证)。要改 review
# 规则就改那个文件,不要改这里。
#
# 占位符替换走 python3 的纯文本 str.replace,**不经 shell 求值** —— 模板里的
# 反引号(`swift test`、`project.yml`、`cloudKitDatabase: .none` …)因此原样
# 送达 CLI,不会被当成命令替换执行掉(MY-1355 那类 quoting 事故的根治)。
PROMPT_TEMPLATE="$SCRIPT_DIR/review-prompt.md"
stage render-prompt
if ! PROMPT="$(CHANGED="$CHANGED" TRUNCATED="$TRUNCATED" DIFF="$DIFF" \
    python3 "$SCRIPT_DIR/render-review-prompt.py" "$PROMPT_TEMPLATE" 2>"$ERR_FILE")" \
    || [ -z "$PROMPT" ]; then
    echo "[codex-review] ❌ review prompt 渲染失败"; tail -c 2000 "$ERR_FILE" >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能渲染 review prompt。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

echo "[codex-review] running codex on PR #$PR_NUMBER ($(printf '%s\n' "$CHANGED" | grep -c . | tr -d ' ') files)..."

# codex exec：非交互、结构化输出到 --output-last-message 文件。
# --skip-git-repo-check：checkout 目录是 detached HEAD，跳过 git 仓库信任检查。
# hooks / MCP / 沙箱 / effort 均由独立 CODEX_HOME 的 config.toml 固定；这里只
# 再显式钉一遍关键项，防 config 缺失时回退到危险默认。
#
# `</dev/null` 是必需的，不是保险起见：即使 prompt 已作为位置参数传入，codex
# 仍会尝试从 stdin 读「additional input」。CI step 没有交互式 stdin 也没有 EOF，
# 于是它无限期阻塞，直到 job 的 timeout-minutes 把整个 step kill 掉 —— 表现为
# conclusion=cancelled、stderr 只有一行 "Reading additional input from stdin..."、
# 且脚本此前的 echo 一个都没 flush 出来，看起来极像「codex 在慢慢审」而不是挂死。
# 显式喂 EOF 才能让它立刻开始处理 prompt。
#
# 姊妹脚本 claude-review.sh 没有这个问题：它用 `printf %s "$PROMPT" | claude -p`，
# stdin 被管道占着，天然有 EOF。改这里时别把 stdin 重定向删掉。
#
# 这一段本身**没有**单独的超时:整个 gate 已被脚本顶部的 supervisor 看门狗包住
# (含本阶段),超时会连同进程树一起收口并报出 stage=codex-exec。
stage codex-exec
"$CODEX_BIN" exec \
    --output-schema "$SCHEMA_FILE" \
    -o "$OUT_FILE" \
    --skip-git-repo-check \
    -c sandbox_mode=read-only \
    -c approval_policy=never \
    "$PROMPT" >/dev/null 2>"$ERR_FILE" </dev/null
CLI_RC=$?

stage parse-verdict
RAW="$(cat "$OUT_FILE" 2>/dev/null)"

if [ "$CLI_RC" -ne 0 ] || [ -z "$RAW" ]; then
    echo "[codex-review] ❌ codex CLI 失败 (rc=$CLI_RC)"; tail -c 2000 "$ERR_FILE" >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能完成(codex CLI 异常)。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

# codex -o 直接落最终 JSON 对象；若被包了额外文本则尝试提取首个 JSON 块兜底。
VERDICT_JSON="$(printf %s "$RAW" | jq -c '.' 2>/dev/null)"
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    VERDICT_JSON="$(printf %s "$RAW" | sed -n '/{/,/}/p' | jq -c '.' 2>/dev/null | head -1)"
fi
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    echo "[codex-review] ❌ 无法解析 verdict"; printf %s "$RAW" | head -c 2000 >&2
    post_sticky "$STICKY
⚠️ 自动 review 输出无法解析。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

VERDICT="$(printf %s "$VERDICT_JSON" | jq -r '.verdict')"
SUMMARY="$(printf %s "$VERDICT_JSON" | jq -r '.summary')"
N_BLOCK="$(printf %s "$VERDICT_JSON" | jq -r '.blockers | length')"

# 渲染评论正文
render() {
    printf '%s\n' "$STICKY"
    if [ "$VERDICT" = "changes" ]; then
        printf '## 🔴 codex review:需要修改（%s 个阻塞项）\n\n' "$N_BLOCK"
    else
        printf '## ✅ codex review:通过\n\n'
    fi
    printf '%s\n' "$SUMMARY"
    if [ "$N_BLOCK" -gt 0 ]; then
        printf '\n### 阻塞项\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.blockers[] | "- **\(.severity)** `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.why)"'
    fi
    local n_notes
    n_notes="$(printf %s "$VERDICT_JSON" | jq -r '.notes | length')"
    if [ "$n_notes" -gt 0 ]; then
        printf '\n### 建议（不阻塞）\n'
        printf %s "$VERDICT_JSON" | jq -r \
            '.notes[] | "- `\(.file)\(if .line then ":\(.line)" else "" end)` — \(.note)"'
    fi
    printf '\n\n<sub>由本地 codex 自动生成。critical/high = 阻塞合并。</sub>\n'
}
stage post-comment
BODY="$(render)"

if [ "$VERDICT" = "changes" ] && [ "$N_BLOCK" -gt 0 ]; then
    post_sticky "$BODY"
    echo "[codex-review] ❌ verdict=changes, blockers=$N_BLOCK → exit 1"
    exit 1
fi

post_sticky "$BODY"
echo "[codex-review] ✅ verdict=pass → exit 0"
exit 0
