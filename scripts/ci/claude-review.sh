#!/usr/bin/env bash
# VitalStride 自动 code review —— 在 self-hosted runner 上用本地 `claude` CLI 跑。
#
# 由 .github/workflows/claude-review.yml 的 claude-review job 调用。
# **安全边界在 workflow YAML 的 job-level `if`**(来自 base 分支、fork 改不到):
# 只有同仓库分支 PR 才会到达这里;fork PR 由另一个 job 处理,PR 代码不在本机执行。
# 本脚本不自行判 fork —— 那个判断放在被 PR 篡改的脚本里是不可信的。
#
# 设计成确定性门:
#   - 无 blocker           → 贴一条 sticky comment,exit 0(check 绿)
#   - 有 blocker(P0/严重) → 更新 sticky comment,exit 1(check 红 → 挡 auto-merge)
#   - 任何工具异常          → exit 1(fail closed,宁可卡住也不放行未审的 diff)
#
# 依赖:git, gh(runner 环境自带 GITHUB_TOKEN), jq, claude(已登录订阅)。
# 需要的环境变量(workflow 注入):
#   PR_NUMBER, BASE_SHA, HEAD_SHA, BASE_REPO, GH_TOKEN

set -uo pipefail

# 在 cd 之前解析脚本目录:后面要读同目录的 review-prompt.md / 渲染器。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

: "${PR_NUMBER:?}"; : "${BASE_SHA:?}"; : "${HEAD_SHA:?}"; : "${BASE_REPO:?}"

STICKY="<!-- vitalstride-mac-claude-review -->"

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

# ---- 取 diff ------------------------------------------------------------
# 工作树是 checkout base 的,PR 的 HEAD 对象只能靠这次 fetch 才存在。因此 fetch
# 失败不能吞掉——否则 HEAD 取不到 → diff 为空 → 被误判成"无 diff pass",一次网络
# 抖动就能让 review 门在未审 diff 的情况下放绿灯(fail-open)。这里 fail-closed:
# fetch 失败、或 fetch 后 BASE/HEAD 对象仍缺失,一律 exit 1(宁可卡住不放行)。
if ! git fetch --no-tags --depth=100 origin "$BASE_SHA" "$HEAD_SHA" 2>/tmp/claude-fetch.err; then
    echo "[claude-review] ❌ git fetch 失败,无法取 PR diff"; cat /tmp/claude-fetch.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能取到 PR diff(git fetch 失败)。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
if ! git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null || ! git cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
    echo "[claude-review] ❌ fetch 后 BASE/HEAD 对象仍缺失,无法可靠取 diff"
    post_sticky "$STICKY
⚠️ 自动 review 无法取到完整 PR 提交对象。为安全起见 **暂不放行**,请重跑。"
    exit 1
fi
DIFF="$(git diff "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff "$BASE_SHA..$HEAD_SHA")"
CHANGED="$(git diff --name-only "$BASE_SHA...$HEAD_SHA" 2>/dev/null || git diff --name-only "$BASE_SHA..$HEAD_SHA")"

# 此处 DIFF 为空 = BASE/HEAD 对象都在但两者间确无差异(罕见但合法)。对象已确认
# 存在,空 diff 是真·无改动,可安全 pass。
if [ -z "$DIFF" ]; then
    post_sticky "$STICKY
✅ 无代码 diff,自动 review 通过。"
    echo "[claude-review] empty diff(对象已验证存在); pass"
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
b = sys.stdin.buffer.read()[:$MAX_BYTES]
sys.stdout.write(b.decode('utf-8', 'ignore'))
")"
    TRUNCATED="（diff 已截断至 ${MAX_BYTES} 字节；未覆盖部分请人工留意）"
fi

# ---- verdict schema -----------------------------------------------------
SCHEMA='{
  "type":"object","additionalProperties":false,
  "required":["verdict","summary","blockers","notes"],
  "properties":{
    "verdict":{"type":"string","enum":["pass","changes"]},
    "summary":{"type":"string"},
    "blockers":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","severity","why"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},
        "severity":{"type":"string","enum":["critical","high"]},"why":{"type":"string"}}}},
    "notes":{"type":"array","items":{"type":"object","additionalProperties":false,
      "required":["file","note"],
      "properties":{"file":{"type":"string"},"line":{"type":["integer","null"]},"note":{"type":"string"}}}}
  }
}'

# ---- review prompt ------------------------------------------------------
# prompt 规则的唯一真相是 scripts/ci/review-prompt.md(两道 review 门共用,
# codex-review.sh 读同一份)。要改 review 规则就改那个文件,不要改这里。
#
# 占位符替换走 python3 的纯文本 str.replace,**不经 shell 求值** —— 模板里的
# 反引号(`swift test`、`project.yml`、`cloudKitDatabase: .none` …)因此原样
# 送达 CLI。历史上 prompt 内联在双引号字符串里,未转义反引号被 bash 当命令替换
# 执行掉,规则文本在运行时凭空消失;抽成数据文件后该类事故结构上不可能发生。
PROMPT_TEMPLATE="$SCRIPT_DIR/review-prompt.md"
if ! PROMPT="$(CHANGED="$CHANGED" TRUNCATED="$TRUNCATED" DIFF="$DIFF" \
    python3 "$SCRIPT_DIR/render-review-prompt.py" "$PROMPT_TEMPLATE" 2>/tmp/claude-render.err)" \
    || [ -z "$PROMPT" ]; then
    echo "[claude-review] ❌ review prompt 渲染失败"; cat /tmp/claude-render.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能渲染 review prompt。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

echo "[claude-review] running claude on PR #$PR_NUMBER ($(printf '%s\n' "$CHANGED" | grep -c . | tr -d ' ') files)..."

RAW="$(printf %s "$PROMPT" | claude -p \
    --output-format json \
    --json-schema "$SCHEMA" 2>/tmp/claude-review.err)"
CLI_RC=$?

if [ "$CLI_RC" -ne 0 ] || [ -z "$RAW" ]; then
    echo "[claude-review] ❌ claude CLI 失败 (rc=$CLI_RC)"; cat /tmp/claude-review.err >&2 || true
    post_sticky "$STICKY
⚠️ 自动 review 未能完成(claude CLI 异常)。为安全起见 **暂不放行**,请人工检查或重跑。"
    exit 1
fi

# .structured_output 是已解析对象;.result 是同内容的 JSON 字符串,做兜底。
VERDICT_JSON="$(printf %s "$RAW" | jq -c '.structured_output // (.result | fromjson)' 2>/dev/null)"
if [ -z "$VERDICT_JSON" ] || [ "$VERDICT_JSON" = "null" ]; then
    echo "[claude-review] ❌ 无法解析 verdict"; printf %s "$RAW" | head -c 2000 >&2
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
        printf '## 🔴 自动 review:需要修改（%s 个阻塞项）\n\n' "$N_BLOCK"
    else
        printf '## ✅ 自动 review:通过\n\n'
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
    printf '\n\n<sub>由本地 claude 自动生成。critical/high = 阻塞合并。</sub>\n'
}
BODY="$(render)"

if [ "$VERDICT" = "changes" ] && [ "$N_BLOCK" -gt 0 ]; then
    post_sticky "$BODY"
    echo "[claude-review] ❌ verdict=changes, blockers=$N_BLOCK → exit 1"
    exit 1
fi

post_sticky "$BODY"
echo "[claude-review] ✅ verdict=pass → exit 0"
exit 0
