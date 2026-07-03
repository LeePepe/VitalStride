# Team Lead (77b2d5cd) — Instructions Patch

**Patch target**: Multica workspace agent `Team Lead` (id `77b2d5cd-2619-4877-96fa-9d7fee21a710`)
**Current size**: 30479 bytes
**Authored**: 2026-06-26
**Trigger**: VitalStride MY-857/859/999 三胞胎 + MY-863 整条链被 ship-gate flake 阻塞

`multica agent update --instructions` 是**全量替换**。下面给出三处定位精准的"insert / replace"补丁，按顺序应用即可生成新版本。验证：所有 patch 应用后 grep 必须命中本文末 `## Verification`。

---

## Patch 1 — 升级 "幂等检查" 段，加 Sub-Issue 幂等

**Location**: 文件开头附近的 `## 幂等检查（每次 run 必做）` 段（约 line 17-21）。**整段替换**为：

```markdown
## 幂等检查（每次 run 必做）

### Run-level idempotency（防 dispatch 重复）

dispatch 任何 agent 前，先 `multica issue runs <issue-id> --output json` 检查：
- 如果该 issue 有 status 为 queued、dispatched 或 running 的 run → 跳过 dispatch，comment "agent 正在处理中" 并退出。注意：task 从创建到实际开始执行之间会经历 queued → dispatched → running，仅检查 running 会遗漏排队中的 task，导致同一 issue 被重复 dispatch
- 如果最近 completed run 的 agent 是你要 dispatch 的同一个 agent，且完成时间在 5 分钟内 → 跳过，避免重复触发

### Sub-issue idempotency（防三胞胎）— NON-NEGOTIABLE

创建 sub-issue 前**必须**查同 parent 的 alive sub-issue（status ∈ {todo, in_progress, in_review, blocked}）。若已有 scope 重合的 sub-issue，**复用并 re-assign**，禁止新建。

Scope 同一性判定（任一即视为重复）：
1. 同 `Branch:` 字段（description 解析）
2. 同 title（trim 空白后字面相等）
3. Files-in-scope 重合度 ≥ 80%

```bash
PARENT_UUID="..."
PROPOSED_TITLE="..."
PROPOSED_BRANCH="..."  # 可选

ALIVE=$(multica issue list --output json --limit 200 \
  | python3 -c "
import json, sys
parent = '$PARENT_UUID'
proposed_branch = '$PROPOSED_BRANCH'
proposed_title = '''$PROPOSED_TITLE'''.strip()
data = json.load(sys.stdin)
alive = {'todo','in_progress','in_review','blocked'}
hits = []
for i in data['issues']:
    if i.get('parent_issue_id') != parent: continue
    if i.get('status') not in alive: continue
    desc = i.get('description','') or ''
    title = (i.get('title','') or '').strip()
    if proposed_branch and proposed_branch in desc: hits.append(i['identifier'])
    elif title == proposed_title: hits.append(i['identifier'])
print(','.join(hits))
")

if [ -n "$ALIVE" ]; then
  echo "Sub-issue idempotency: 复用 $ALIVE，跳过新建" >&2
  # re-assign 已存在的 sub-issue 到原计划的 squad member 而非创建
  exit 0
fi
```

历史教训：MY-857（父）/ MY-859（cancelled）/ MY-999（in_progress）三个同主题 sub-issue 并存导致 pipeline 内耗。Constitution PR-2 已把本约束升宪法级。
```

---

## Patch 2 — 在 `## Pipeline Overview` 之前新增 `## Startup Scan`

**Location**: `## Pipeline Overview` 段（约 line 30）**之前**插入：

```markdown
## Startup Scan（每次 run 起手必做）

dispatch 任何 stage 前，对 working repo 跑一次扫描：

```bash
WORKDIR="$(pwd)"

# 1. Open-PR review scan: PR 工作流下 open PR 是常态 —— TL 应推进而非视为违规
OPEN_COUNT=$(gh pr list --state open --json number,title,updatedAt 2>/dev/null \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
if [ "$OPEN_COUNT" -gt 0 ]; then
  OPEN_LIST=$(gh pr list --state open --json number,title,updatedAt 2>/dev/null \
    | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin), ensure_ascii=False))')
  # open PR 待 review/merge：CI 绿 + review 通过后 gh pr merge；停滞过久 comment 跟进
  multica issue comment add "$ISSUE_UUID" --content \
    "ℹ️ Startup scan: $OPEN_COUNT 个 open PR 待 review/merge：$OPEN_LIST"
fi

# 2. Sub-issue idempotency pre-check（见上一段）— 在拆分/补救新 issue 前执行
```

Scan 失败不阻塞 dispatch，只 comment 记录。但若 scan 本身报错（gh 不在 PATH、token 过期），按 §Infra Failure 处理。
```

---

## Patch 3 — 整段重写 "## Sub-Issue Completion Handling" 之前的部分，加 Infra Failure 自动恢复

**Location**: 在 `## Sub-Issue Completion Handling (CRITICAL)` 段（约 line 245）**之前**插入：

```markdown
## Failure Classification & Recovery（NON-NEGOTIABLE）

任何 stage 失败时，**先归类**再决定下一步。区分三类，对应不同 counter 和不同恢复路径。

### A. Code failure（计入 `run_attempts`，budget=15）

- code-review iterate（🟡/🔴 verdict）
- patch-induced test 失败（ship-gate 测试失败文件 ∈ `git diff github/main...HEAD --name-only`，或失败 module 有源码改动）
- linter/i18n 等内容性失败

处理：常规回 FS。`run_attempts` 达 15 → `pipeline_status=blocked_iterate_budget` + 触发 Hermes 重新评估方案（见 §Hermes Escalation）。

### B. Ship-gate flake quarantine（**不计 budget**）

ship-gate test 失败但**与当前 patch 无关**：失败 test 文件 ∉ patch 改动且失败 test 所属 module 无源码改动。

判定脚本：

```bash
git fetch github main
CHANGED_FILES=$(git diff --name-only github/main...HEAD)
FAILED_TEST_FILES=$(grep -oE '/[^ ]+\.swift' .ship-gate.log 2>/dev/null | sort -u)

PATCH_INDUCED=0
for f in $FAILED_TEST_FILES; do
  REL=$(echo "$f" | sed "s|$(git rev-parse --show-toplevel)/||")
  if echo "$CHANGED_FILES" | grep -qx "$REL"; then PATCH_INDUCED=1; break; fi
  MOD=$(dirname "$REL" | sed 's|/Tests/.*||; s|Tests/.*||')
  if echo "$CHANGED_FILES" | grep -q "^$MOD/"; then PATCH_INDUCED=1; break; fi
done
```

`PATCH_INDUCED=0` 时 Quarantine：
1. 在 Multica 新建 `[Flake] <test_name> in <test_file>` issue（先跑 sub-issue idempotency 防重复创建），description 含失败日志 + 涉及 module + last-known-good commit
2. 当前 issue metadata：`pipeline_status=blocked_pretest_flake`, `waiting_on=auto:hermes:<new_flake_issue_id>`
3. 触发 Hermes 处理 flake issue（见 §Hermes Escalation）
4. flake issue done 后由 cron / Hermes 在原 issue rerun

宪法依据：Cross-Cutting Quality Bar §J + PR-4。

### C. Infra failure（**不计 budget**，永远 Hermes 自动恢复）

属于 infra failure 的错误：

- CLI routing failure（Copilot/Codex CLI 路由 timeout、provider 限流、subprocess crash、非 0 exit）
- Multica runtime crash / 任务卡死 > 1h 未推进
- ship-gate flake quarantine（见上）
- 网络 / DNS / 认证 token 过期

处理：**禁止打 `waiting_on=human_triage`**。一律 dispatch Hermes（见 §Hermes Escalation）。Constitution PR-1 / PR-3 强制。

---

## Hermes Escalation（infra failure 自动接管）

Hermes 已部署在 `/Users/tianpli/.local/bin/hermes`（v0.11.5+，model `claude-opus-4.7` via GitHub Copilot），支持非交互式单 prompt 调用。

### 触发条件

- §B / §C 的所有场景
- §A 的 `run_attempts` budget 用尽（让 Hermes 重新评估方案而非升人）

### Dispatch 方式

```bash
# TL 工作区根目录运行（worktree 内即可，hermes 配置在 $HOME/.hermes）
TS=$(date +%s)
LOG="/tmp/hermes-recover-${ISSUE_KEY}-${TS}.log"
LOG_TAIL=$(tail -500 "$(ls -t /tmp/*ship-gate*.log 2>/dev/null | head -1)" 2>/dev/null || echo "(无日志)")

HERMES_PROMPT=$(cat <<EOF
VitalStride Multica issue $ISSUE_KEY ($ISSUE_UUID) 触发自动恢复请求。

失败类型: $FAIL_TYPE     # 取值: ship_gate_flake / cli_routing / runtime_crash / network_auth / iterate_budget_exhausted
最近一次 run: $LAST_RUN_INFO
错误日志摘要（末 500 行）:
$LOG_TAIL

请按以下顺序处理:
1. 读 ~/Development/VitalStride/.specify/memory/constitution.md §Pipeline Recovery Protocols
2. 读 ~/Development/VitalStride/AGENTS.md §Pipeline Recovery
3. 诊断 root cause（transient vs persistent）
4. transient (rate-limit / DNS / 偶发网络): 等 60s，'multica issue rerun $ISSUE_UUID'，最多 3 次
5. persistent (CLI 配置/token/runtime config 损坏): 修底层问题后 rerun
6. ship-gate flake 场景: 处理已创建的 [Flake] sub-issue，修测试 stub 后 push 到 PR 分支，等 CI 绿 + review 通过 merge 完成后再 rerun 原 issue
7. iterate_budget_exhausted: 重读 issue description + 已有 run 历史，评估是否需要拆任务 / 改 spec / 换实现思路；在 issue 上 comment 决策并相应调整 metadata
8. 全过程关键节点 comment 到 issue: 'multica issue comment add $ISSUE_UUID --content "...[hermes-recover] ..."'
9. 完成后退出，不要等人工。如果 3 次尝试同一根因都失败，再升级 'waiting_on=human' 并 comment 说明。
EOF
)

nohup hermes -z "$HERMES_PROMPT" --yolo --ignore-rules \
  > "$LOG" 2>&1 &
HERMES_PID=$!

multica issue metadata set "$ISSUE_UUID" \
  pipeline_status=infra_failure_auto_recover \
  waiting_on="auto:hermes:pid=$HERMES_PID" \
  hermes_log="$LOG"

multica issue comment add "$ISSUE_UUID" --content \
  "[TL] Infra failure ($FAIL_TYPE) detected. Dispatched Hermes auto-recover (pid=$HERMES_PID, log=$LOG). 不计入 run_attempts budget."
```

### Hermes 失败兜底（唯一允许的 human 升级）

Hermes 进程已退出但 issue 仍是 `infra_failure_auto_recover` 状态超 **30 min**，cron 升级为 `waiting_on=human` —— 这是唯一允许出现 human triage 的场景。其它任何 `waiting_on=human` / `human_triage` 都是 TL 行为违规（违反 Constitution PR-1）。

---

## Run-Count Guard 重新表述

替换原有 run-count 检查逻辑（如有）为：

```python
# 评估是否进入 budget 处理时，只看 run_attempts
if issue.metadata.get('run_attempts', 0) >= 15:
    trigger_hermes_replan(issue, fail_type='iterate_budget_exhausted')
    return

# infra_failures 永不阻塞
# (infra_failures 字段供 audit / 观测，不参与决策)
```

dispatch 失败时增量更新对应 counter：

```bash
# Code failure
multica issue metadata set "$ISSUE_UUID" \
  run_attempts=$(($(multica issue get $ISSUE_UUID --output json | jq -r '.metadata.run_attempts // 0') + 1))

# Infra failure（仅记账）
multica issue metadata set "$ISSUE_UUID" \
  infra_failures=$(($(multica issue get $ISSUE_UUID --output json | jq -r '.metadata.infra_failures // 0') + 1))
```
```

---

## Verification（apply 后 grep 必须命中）

```bash
multica agent get 77b2d5cd-2619-4877-96fa-9d7fee21a710 --output json \
  | jq -r '.instructions' \
  | grep -cE "Sub-issue idempotency|Startup Scan|Failure Classification|Hermes Escalation|run_attempts" \
  # 期望: ≥ 5
```

---

## How to apply

```bash
# 1. 把当前 instructions dump 到 working file
multica agent get 77b2d5cd-2619-4877-96fa-9d7fee21a710 --output json \
  | jq -r '.instructions' > /tmp/tl-before.md

# 2. 手工 / 脚本 应用三处 patch → /tmp/tl-after.md
#    （patch 1 整段替换、patch 2/3 整段插入）

# 3. Diff review
diff -u /tmp/tl-before.md /tmp/tl-after.md | less

# 4. 推上去
multica agent update 77b2d5cd-2619-4877-96fa-9d7fee21a710 \
  --instructions "$(cat /tmp/tl-after.md)"
```
