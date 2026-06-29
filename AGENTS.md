# VitalStride — Agent Instructions

## Build & Test

### SPM Packages（优先使用）

`Packages/` 下的五个独立 SPM 包（VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit）支持 `swift build` 和 `swift test`，无需 Xcode 项目、无需模拟器，秒级完成。

**改动仅涉及 Packages/ 时，必须用 swift build/test 验证，禁止用 xcodebuild。**

```bash
cd Packages/VitalModels && swift build && swift test
cd Packages/HealthKitService && swift build && swift test
```

### 主 App Target（仅在必要时）

主 app（VitalStride/、VitalStrideMac/、VitalStrideWatch/）没有顶层 Package.swift，必须用 xcodebuild。但要遵守以下规则：

1. **destination 用 generic** — 避免设备连接超时：
   ```bash
   xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
     -destination 'generic/platform=iOS Simulator' \
     -skipPackagePluginValidation
   ```
2. **后台执行 + 长 timeout** — xcodebuild 首次 SPM resolve 可能需要 2-3 分钟，不要用前台短 timeout
3. **只在改动涉及 app target 源码时才跑 xcodebuild** — 如果只改了 Packages/ 下的代码，swift build/test 就够了
4. **运行测试**：
   ```bash
   xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -skipPackagePluginValidation
   ```

### XcodeGen

项目使用 `project.yml` + XcodeGen。修改 target 配置后需重新生成：

```bash
xcodegen generate
```

测试目录（VitalStrideTests/）使用目录源引用，新增测试文件自动包含，无需手动添加。

## Architecture

- **XcodeGen 项目**：`project.yml` 定义 targets，`xcodegen generate` 生成 `.xcodeproj`
- **5 个 SPM local packages**：VitalModels、HealthKitService、AIService、VitalUI、TelemetryKit（TelemetryKit 尚未注册到 `project.yml`，当前仅作为独立包使用，待集成 issue 添加到 app target）
- **Swift 6 strict concurrency**
- **SwiftData** 存储训练数据 + HealthKit L2 缓存（`HealthCacheEntry`，本地隔离，`cloudKitDatabase: .none`）
- **HealthDataCache** 是纯内存 actor L1 缓存层

## I18n

- UI 字符串用 `String(localized: "key", comment: "...")` 或 `NSLocalizedString("key", ...)` 引用 strings 文件
- 源代码硬编码中文字面量会被 SwiftLint 标 warning（非 error）
- 添加新 key 后同步更新 zh-Hans.lproj 和 en.lproj
- 工具：`python3 scripts/i18n_extract_hardcoded.py` 识别需要迁移的，`python3 scripts/i18n_check_lproj_parity.py` 检查覆盖率

## Key Conventions

- HealthKit 健康数值禁止出现在任何日志中（隐私合规)
- 详见 CONTEXT.md 的架构决策

## Git Workflow (no-PR)

**This project uses a no-PR workflow.** The public GitHub remote (`github`) is the source of truth for `main`, but agent feature branches never live there. They live in the LOCAL bare repo only. See `docs/adr/0001-no-pr-workflow.md` for full rationale.

### Roles

| Role | What they do | Where they push |
|------|--------------|-----------------|
| **Fullstack Engineer (FS)** | implement code + commit | LOCAL bare repo `agent/<issue-key>-<task-id-short>` |
| **Team Lead (TL)** | rebase FS branches onto `github/main`, resolve trivial conflicts, push `main` | `github` remote (public), `main` only |
| **AI Reviewer** | review FS commits in the bare repo | (does not push) |

**Hard rule (enforced by `scripts/hooks/pre-push`):**
> Only `main` may be pushed to public remotes (`github` / `gitlab`). Pushing any other branch to `github` is rejected by the hook.

### FS workflow

The Multica daemon already created your worktree at `<task-dir>/workdir/`. **Do NOT create another worktree.** Just `cd` into the workdir and work there.

1. **Resolve issue identifier**:
   ```bash
   ISSUE_UUID=$(grep "Issue ID:" .agent_context/issue_context.md | awk '{print $3}')
   ISSUE_KEY=$(multica issue get "$ISSUE_UUID" --output json \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'].lower())")
   TASK_ID_SHORT=${MULTICA_TASK_ID:0:8}
   BRANCH="agent/${ISSUE_KEY}-${TASK_ID_SHORT}"
   BARE=$(cd "$(git rev-parse --git-common-dir)" && pwd)
   ```

2. **Implement + commit** as usual on whatever branch the daemon checked out for you (it's already a fresh branch off `origin/main`).

   **Commit message 必须包含 issue key**（如 `MY-852`），可在 subject 或 body 任意位置。pre-push hook 会校验；多个 commit 则每个都必须包含。这样 retro/审计工具能通过 grep `MY-\d+` 关联 commit ↔ issue。

   ```bash
   git commit -m "feat: ExercisePickerView 多选批量添加 (MY-852)"
   # 或 body 引用:
   git commit -m "feat: 多选 picker" -m "Implements MY-852."
   ```

3. **Push your work to the LOCAL bare repo**:
   ```bash
   git push "$BARE" HEAD:refs/heads/$BRANCH
   ```
   The pre-push hook will run `xcodebuild test` (or `swift build/test` for SPM-only changes). If it fails, fix and retry.

4. **Comment + assign back to TL** so TL can pick it up:
   ```bash
   COMMIT_SHA=$(git rev-parse HEAD)
   multica issue comment add "$ISSUE_UUID" --content "Pushed to \`$BRANCH\` (commit \`${COMMIT_SHA}\`). Ready for TL merge."
   multica issue assign "$ISSUE_UUID" "Team Lead"
   ```

**Never** `git push github` anything. **Never** `gh pr create`. The hook will block it.

### TL workflow (merging FS work into `main`)

When you receive an issue with state `in_review` and an FS comment reporting a branch:

1. **Locate the latest FS branch** for this issue:
   ```bash
   BARE=$(cd "$(git rev-parse --git-common-dir)" && pwd)
   ISSUE_KEY=$(multica issue get "$ISSUE_UUID" --output json \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'].lower())")
   git fetch "$BARE" "+refs/heads/agent/${ISSUE_KEY}-*:refs/heads/agent/${ISSUE_KEY}-*"

   # Pick the latest by committerdate
   LATEST_BRANCH=$(git for-each-ref --sort=-committerdate \
     --format='%(refname:short)' "refs/heads/agent/${ISSUE_KEY}-*" | head -1)
   LATEST_SHA=$(git rev-parse "$LATEST_BRANCH")
   ```

2. **Verify against FS comment SHA** (latest comment from FS should mention the SHA). If mismatch, comment + reassign FS to clarify.

3. **Sync `github/main`** and rebase the FS branch on top:
   ```bash
   git fetch github main
   git checkout "$LATEST_BRANCH"
   git rebase github/main
   ```

4. **Conflict policy (B2)**:
   - **Trivial conflicts** (different lines, import additions, separate methods, format-only): resolve yourself, continue.
   - **Semantic conflicts** (same line, deletion of changed code, logic-overlapping): abort the rebase, comment with the conflict details, reassign back to FS:
     ```bash
     git rebase --abort
     multica issue comment add "$ISSUE_UUID" --content "Semantic conflict in <file>:<line>; needs FS rework."
     multica issue assign "$ISSUE_UUID" "Fullstack Engineer"
     ```

5. **Push HEAD to `github main`**:
   ```bash
   git push github HEAD:refs/heads/main
   ```
   The pre-push hook validates `xcodebuild test` again. If push fails (build error after merge, or non-fast-forward race with another TL):
   - Decide yourself how to recover: re-fetch and re-rebase, split commits, or hand back to FS.
   - The bare repo's local `main` does not need updating — daemon uses `origin/main` for new worktrees.

6. **Close the issue**:
   ```bash
   multica issue status "$ISSUE_UUID" done
   ```

### Common pitfalls

- **Bare repo path** is whatever `git rev-parse --git-common-dir` resolves to inside the worktree. Always compute it fresh — never hardcode.
- **`MULTICA_TASK_ID`** is provided by the daemon as an env var (full UUID; we use the first 8 chars).
- **GitHub access tokens** are still valid (TL needs them to push `main`). Don't unset `gh` auth.
- The `github` remote name is by convention; some clones may use `origin`. The hook accepts either as long as the URL contains `github.com`.

## Pipeline Recovery

> 这一节定义 pipeline 失败时的恢复路径。**所有失败路径都自动化，禁止 `waiting_on: human_triage`**。
> 唯一例外：constitution P0 违规（例如健康数据隐私破坏）才升人工。其它一律走 Hermes auto-dispatch。

### Ship-gate flake quarantine（pre-push test 失败）

TL push `github main` 时 pre-push hook 跑 `xcodebuild test` / `swift test`。失败时**不要无脑 retry / 不要回 FS**——先判定是不是当前 patch 引入的：

```bash
# 1. 拿到当前 ship 范围（FS branch vs github/main）
git fetch github main
CHANGED_FILES=$(git diff --name-only github/main...HEAD)

# 2. 解析 hook 输出，找到失败 test 所属的文件路径
#    （xcodebuild test 输出形如 "FILE:LINE: error: -[Suite testMethod] : ..."）
FAILED_TEST_FILES=$(grep -oE '/[^ ]+\.swift' .ship-gate.log | sort -u)

# 3. 判定 patch-induced vs pre-existing flake
PATCH_INDUCED=0
for f in $FAILED_TEST_FILES; do
  REL=$(echo "$f" | sed "s|$(git rev-parse --show-toplevel)/||")
  if echo "$CHANGED_FILES" | grep -qx "$REL"; then PATCH_INDUCED=1; break; fi
  # 同 module 下源码改动也算 patch-induced
  MOD=$(dirname "$REL" | sed 's|/Tests/.*||; s|Tests/.*||')
  if echo "$CHANGED_FILES" | grep -q "^$MOD/"; then PATCH_INDUCED=1; break; fi
done
```

**分支决策**：

- `PATCH_INDUCED=1` → 正常 retry（最多 5 次 in 同 issue），重复失败回 FS
- `PATCH_INDUCED=0` → **Quarantine 路径**：
  1. **不**计入当前 issue 的 run-count budget
  2. 在 Multica 开新 issue `[Flake] <test_name> in <test_file>`，description 引用失败日志、所属 module、最近一次让它过的 commit
  3. 把当前 issue 的 metadata 设为 `pipeline_status=blocked_pretest_flake`，`waiting_on=auto:hermes:<new_flake_issue_id>`
  4. 自动触发 Hermes（见下节）去处理新 flake issue
  5. 当前 ship issue 在 flake issue done 后由 cron 自动 unblock 重 dispatch（不要让 TL 阻塞）

### Infra-failure auto-escalation（Hermes 接管）

下列错误是 **infra failure**，不算 code 问题，**不计入 run-count guard**：

- CLI routing failure（Copilot/Codex CLI 返回非业务错误：路由 timeout、provider 限流、subprocess crash、`exit 128`）
- Multica runtime crash / 任务卡死 > 1h 未推进
- ship-gate flake quarantine 路径（见上一节）
- Network / DNS / 认证 token 过期

**处理**：TL 不打 human_triage，而是 dispatch Hermes 子代理处理。Hermes 已安装在 `/Users/tianpli/.local/bin/hermes`（v0.11.5，model `claude-opus-4.7` via GitHub Copilot），支持非交互式 `hermes -z` 单 prompt 调用。

```bash
# 在 TL 工作区根目录运行
HERMES_PROMPT="VitalStride Multica issue $ISSUE_KEY ($ISSUE_UUID) 触发 infra failure。
错误类型: $FAIL_TYPE
错误日志摘要: $LOG_TAIL_500
最近 run: $LAST_RUN_INFO

请按以下顺序处理:
1. 读 .specify/memory/constitution.md §Pipeline Recovery Protocols
2. 读 AGENTS.md §Pipeline Recovery
3. 诊断 root cause（区分 transient vs persistent）
4. transient: 等 60s 后用 'multica issue rerun $ISSUE_UUID' 重 dispatch，最多 3 次
5. persistent: 修底层问题（CLI 配置、token、runtime config），修复后 rerun
6. 全过程 comment 到 issue: multica issue comment add $ISSUE_UUID --content '...'
完成后退出，不要等人工回复。"

nohup hermes -z "$HERMES_PROMPT" --yolo --ignore-rules \
  > "/tmp/hermes-infra-$ISSUE_KEY-$(date +%s).log" 2>&1 &
HERMES_PID=$!

multica issue metadata set "$ISSUE_UUID" \
  pipeline_status=infra_failure_auto_recover \
  waiting_on="auto:hermes:pid=$HERMES_PID" \
  hermes_log="/tmp/hermes-infra-$ISSUE_KEY-$(date +%s).log"
```

**Hermes 失败兜底**：Hermes 进程退出但 issue 仍是 `infra_failure_auto_recover` 状态超 30 min → cron 升级为 `waiting_on=human`（这才是允许人工介入的唯一时机）。

### Run-count guard 分类

`run_count_guard` 区分两类计数器：

| Counter | 触发条件 | 默认 budget | 超限行为 |
|---------|----------|-------------|---------|
| `run_attempts` | code-review iterate、test 失败、patch-induced ship-gate fail | 15 | 升 `pipeline_status=blocked_iterate_budget` + Hermes auto-dispatch 重新评估方案（拆任务 / 换思路 / 改 spec） |
| `infra_failures` | CLI routing fail、runtime crash、quarantined flake、network/auth | ∞（不计） | 永远走 Hermes auto-recover，不阻塞 issue |

TL dispatch 前必须把失败归类到正确 counter，并在 `multica issue runs` 评估时只比对 `run_attempts`。

### Startup scan（每次 pipeline 起手）

TL 在 dispatch 任何 stage 前跑：

```bash
# 1. 检查 no-PR 工作流违规（不应有 open PR）
OPEN_PRS=$(gh pr list --state open --json number,title,updatedAt 2>/dev/null)
if [ "$(echo "$OPEN_PRS" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" -gt 0 ]; then
  multica issue comment add "$ISSUE_UUID" --content "⚠️ Startup scan: $OPEN_PRS 个 open public PR 与 no-PR 工作流冲突，记录但不阻塞当前 task。详: $(echo "$OPEN_PRS" | head -200)"
  # 不阻塞，继续 dispatch
fi

# 2. 检查同 parent 的 sibling sub-issue（防三胞胎）— 详 §Sub-issue 幂等
```

### Sub-issue 幂等

任何阶段（Planner Lead 拆分、TL fast-path bug-fix 拆分、补救新 issue）创建 sub-issue 前都要：

```bash
PARENT_UUID="$1"
PROPOSED_TITLE="$2"
PROPOSED_BRANCH="$3"   # 可选

# 查同 parent 的所有 alive sub-issue
ALIVE=$(multica issue list --output json --limit 200 \
  | python3 -c "
import json, sys
parent = '$PARENT_UUID'
proposed_branch = '$PROPOSED_BRANCH'
data = json.load(sys.stdin)
alive_statuses = {'todo', 'in_progress', 'in_review', 'blocked'}
matches = []
for i in data['issues']:
    if i.get('parent_issue_id') != parent: continue
    if i.get('status') not in alive_statuses: continue
    desc = i.get('description','') or ''
    title = i.get('title','') or ''
    if proposed_branch and proposed_branch in desc: matches.append(i['identifier'])
    elif title.strip() == '$PROPOSED_TITLE'.strip(): matches.append(i['identifier'])
print(','.join(matches))
")

if [ -n "$ALIVE" ]; then
  echo "复用已有 sub-issue: $ALIVE（跳过创建）" >&2
  exit 0  # 上层应 reassign 而非 create
fi
```

Scope 同一性判定（任一即视为重复）：
1. 同 `Branch:` 字段
2. 同 title（trim 后）
3. Files-in-scope 重合度 ≥ 80%（拆分阶段才有这个字段）

<!-- SPECKIT START -->
## Spec-Driven Development (spec-kit)

VitalStride 使用 [spec-kit](https://github.com/github/spec-kit) 管理产品 spec / plan / tasks。Agent 在做任何改动前应阅读：

1. **`.specify/memory/constitution.md`** —— 项目宪法，含 7 条 Core Principles + Cross-Cutting Quality Bars。**这是 reviewer 唯一权威 finding 源**，不在这里的约束不能作为 PR block 理由。
2. **`specs/000-baseline-existing-codebase/spec.md`** —— 当前已实现内容（FR-001 ~ FR-016 + NFR）。新功能与 baseline 的关系应该在新 spec 里说清。
3. **`specs/000-baseline-existing-codebase/plan.md`** —— 已知 gap（G-01 ~ G-08）与处理路径。
4. **`docs/adr/`** —— 7 个已落地的架构决策记录。新方向冲突时先写新 ADR 推翻。
5. 本文件（`AGENTS.md`）—— build/test/git 操作手册。

**新 feature 流程**：`/speckit-specify` → `/speckit-plan` → `/speckit-tasks`，然后通过 `multica-quick-issue` 入 Multica project `7adf8b88`。**`/speckit-implement` 不使用** —— 实现由 Multica TL → FS → Reviewer pipeline 完成（Constitution §Development Workflow）。

**写 spec/plan/tasks 必须**：reference Constitution 章节，不要重述规则。issue 标题 `[T###] [Story] Brief description`。
<!-- SPECKIT END -->
