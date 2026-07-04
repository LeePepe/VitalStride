# Planner Lead (a771d078) — Instructions Patch

**Patch target**: Multica workspace agent `Planner Lead` (id `a771d078-7191-4967-b9d0-4dbf21b89421`)
**Current size**: 5619 bytes
**Authored**: 2026-06-26
**Trigger**: 复用 TL patch 的 sub-issue 幂等约束；防止 Planner 在拆分 / 细化时把 alive sub-issue 再创建一遍

`multica agent update --instructions` 是**全量替换**。下面给出两处定位精准的"insert / replace"补丁。

---

## Patch 1 — 在 `## 模式 1：拆分（Decompose）` 段开头插入幂等前置检查

**Location**: `## 模式 1：拆分（Decompose）` 这一行（约 line 46）**之后、`### 拆分原则`** 之前插入：

```markdown
### Sub-issue idempotency 前置检查（CRITICAL — NON-NEGOTIABLE）

拆分前**必须**先查同 parent 下的 alive sub-issue（status ∈ {todo, in_progress, in_review, blocked}）。若拟拆出的目标已有对应 alive sub-issue，复用并 comment 通知 TL，禁止新建。

Scope 同一性判定（任一即视为重复）：
1. 同 `Branch:` 字段
2. 同 title trim 后字面相等
3. 拟拆任务的影响模块/文件 ⊆ 已有 sub-issue 的影响范围

```bash
PARENT_UUID="<this-issue-uuid>"

EXISTING=$(multica issue list --output json --limit 200 \
  | python3 -c "
import json, sys
parent = '$PARENT_UUID'
data = json.load(sys.stdin)
alive = {'todo','in_progress','in_review','blocked'}
out = []
for i in data['issues']:
    if i.get('parent_issue_id') != parent: continue
    if i.get('status') not in alive: continue
    out.append({'id': i['identifier'], 'title': i.get('title',''), 'status': i.get('status')})
print(json.dumps(out, ensure_ascii=False))
")

# 拆分前在 comment 中报告已存在的 alive sub-issue:
multica issue comment add "$PARENT_UUID" --content "已检测到 alive sub-issue: $EXISTING — 拟拆分目标与之对照后选择复用/扩展/新建。"
```

历史教训：MY-857 拆出 MY-859 后被 cancelled，又拆出 MY-999；同 scope 并存导致 pipeline 内耗、commit 冲突。Constitution PR-2 已升宪法级。

**复用而非新建的处理路径**：
1. comment 在 parent issue 报告："目标 X 复用已有 sub-issue MY-NNN（status=in_progress），不新建"
2. 如需要补充信息：`multica issue update MY-NNN --description "<补全后内容>"`
3. assign parent 回 TL，由 TL re-dispatch 已有 sub-issue
```

---

## Patch 2 — 在 `## 调研模式` 之前插入 `## Cancelled / Failed sub-issue 处理`

**Location**: `## 调研模式` 段（约 line 122）**之前**插入：

```markdown
## Cancelled / Failed sub-issue 处理

发现 parent 下有 status ∈ {cancelled, blocked} 的 sub-issue 时：

1. **不要**简单地"重新拆一个新的"。这是 MY-857/859/999 三胞胎反模式。
2. 读 cancelled/blocked sub-issue 的 metadata（`blocked_reason`, `pipeline_status`, `waiting_on`）和最后 5 条 comment，理解失败原因
3. 分类：
   - **infra failure 已被 Hermes 接管**（metadata 有 `waiting_on=auto:hermes:*`） → 不要新建，等待自动恢复
   - **provider config / 早期实验失败被 cancelled**（如 `pipeline_status=blocked_provider_config`） → 在该 sub-issue 上 `multica issue status <id> todo` + comment 说明"复用并重 dispatch，原因 X 已修复"，让 TL 重新 dispatch；**禁止**新建同 scope sub-issue
   - **设计上确实需要全新方案**（前一个被验证为不可行）→ 才允许新建，但 description 必须显式 link 到被 cancelled 的 sub-issue 并说明差异

---
```

---

## Verification（apply 后 grep 必须命中）

```bash
multica agent get a771d078-7191-4967-b9d0-4dbf21b89421 --output json \
  | jq -r '.instructions' \
  | grep -cE "Sub-issue idempotency 前置检查|Cancelled / Failed sub-issue 处理|三胞胎"
  # 期望: ≥ 3
```

---

## How to apply

```bash
multica agent get a771d078-7191-4967-b9d0-4dbf21b89421 --output json \
  | jq -r '.instructions' > /tmp/planner-before.md

# 应用两处 patch → /tmp/planner-after.md

diff -u /tmp/planner-before.md /tmp/planner-after.md | less

multica agent update a771d078-7191-4967-b9d0-4dbf21b89421 \
  --instructions "$(cat /tmp/planner-after.md)"
```
