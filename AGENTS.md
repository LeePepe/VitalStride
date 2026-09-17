# VitalStride — Agent Instructions

## Agent 读取契约（Read Contract）

任务开始前，按你要碰的东西先读对应文档 —— 不读就动手 = 违规。这张表是**薄索引**，
内容留在被指向的文档里，按需下钻（渐进展开），不要一次性预读全部。

| 你要做的事 | 必读（前置） | 拿什么 |
|---|---|---|
| 任何任务 | `.specify/memory/constitution.md` | 7 条不可违反的红线（先确认不踩） |
| 了解已实现基线 / 回归基准 | `specs/000-baseline-existing-codebase/spec.md`（+ `plan.md` 看 gap） | 已实现功能意图、验收标准、已知 gap（不可改） |
| 决定做未来功能 / V2+ 规划 | `specs/001-future-roadmap/spec.md`（+ `plan.md` 看扩展点与 fork 顺序） | 未来功能意图、优先级、宪法预检、复用锚点（umbrella，启动时 fork 出 `specs/002-*`） |
| 改全局架构 / 跨层设计 | `CONTEXT.md`（顶层，含 `canonical_roles`） | 架构决策、数据流、layer 划分、类角色顺序 |
| 改 `Packages/**` | `Packages/CONTEXT.md`，再按其中 route 下钻 | 命中 package 的职责 / 依赖 / red_lines / gate |
| 改 app target / app tests / `project.yml` | `VitalStride/CONTEXT.md`（AppUI frontmatter） | 跨平台 app layer 的路径归属 / 依赖 / red_lines / CI gate |
| 改 `Prototype/**` | `Prototype/CONTEXT.md` | 隔离边界 / DesignKit-only 依赖 / build 命令 |
| 改 CI/workflow、hooks/scripts、fastlane、repo lint/security/spec-kit tooling | `RepoInfra/CONTEXT.md` | RepoInfra owned/excluded paths、角色边界、fast test 命令 |
| build / test / git 操作 | 本文件（AGENTS.md） | 命令手册、PR 工作流 |
| 架构方向冲突 | `docs/adr/` | 已落地决策；要推翻先写新 ADR |

## 最外层索引（Root Routes）

业务逻辑住 `Packages/`（6 个本地 SPM 包）。app target/tests 与 XcodeGen 真理源归 `AppUI`，
独立视觉原型归 `Prototype`，repository automation/config 归 `RepoInfra`。治理、spec、设计证据
以及 generated/cache/log/local-secret 路径是显式 exclusions。layer ownership 与 gate 速度正交。

| 最外层范围 | 首个 context | 节点类型 |
|---|---|---|
| `Packages/**` | `Packages/CONTEXT.md` | index：再展开六个 package layer |
| app roots、app tests、`project.yml` | `VitalStride/CONTEXT.md` | AppUI leaf |
| `Prototype/**` | `Prototype/CONTEXT.md` | Prototype leaf |
| CI/workflow、scripts/hooks/tests、fastlane、repo policy/config、Spec Kit tooling | `RepoInfra/CONTEXT.md` | RepoInfra leaf |

**渐进展开**：先读本表定位最外层 context；只有命中 `Packages/**` 时再读取
`Packages/CONTEXT.md` 的下一层 route。不要从顶层预读六个 package contexts。

**按 layer 收窄范围**：
- 改动只落 1 个 layer → 一个任务直接做。
- 跨 2+ layer → 太大，按 layer 拆成 N 个独立可 `swift build/test` 的子任务（一层一 commit）。
- 单层内仍很大 → 按技术切面再拆：纯逻辑 → 输入/校验 → 处理/编排 → 输出转换 → fixture → 文档 → 迁移。
- **收尾遗留记为新任务，不回头扩大当前任务。**

**两条依赖轴**（同一原则「依赖只能向下」）：
- **层间**（包）：各层 frontmatter 的 `depends_on`。反向即违规（如 VitalModels 不得 import HealthKitService）。
- **层内**（类角色）：各层 `roles` + 顶层 `CONTEXT.md` 的 `canonical_roles`。低角色类不得 import 高角色类
  （如 VitalModels 的 `Models/` 不得依赖 `Persistence/`）。

## 分层修复约定

lint/test 失败信号带 `{layer, red_lines}`。无论谁来修：
- 只在失败所在 layer 内改；根因在别层则记新任务，不跨层改。
- 带着该层 red_lines 修（别为了过测试踩红线，例：把健康数值打进 debug 日志违反宪法 I）。
- 修完跑该层 `test`（frontmatter 里的命令）验证再交。
- red_lines 是宪法的**投影**，不新增独立规则；宪法变则同步各层 frontmatter。

## Build & Test

### RepoInfra（fast only）

RepoInfra 改动运行 `bash scripts/test-repoinfra.sh`。该命令验证 path coverage/frontmatter、
shell/Python syntax 与 tooling tests，不运行 app `xcodebuild`；分钟级 app gate 仍由 required CI 执行。

### SPM Packages（优先使用）

`Packages/` 下的六个独立 SPM 包（VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, DesignKit）支持 `swift build` 和 `swift test`，无需 Xcode 项目、无需模拟器，秒级完成。

**改动仅涉及 Packages/ 时，必须用 swift build/test 验证，禁止用 xcodebuild。**

```bash
cd Packages/VitalModels && swift build && swift test
cd Packages/HealthKitService && swift build && swift test
```

### 主 App Target（仅在必要时）

`AppUI` 没有顶层 Package.swift，完整验证必须用 xcodebuild。但要遵守以下规则：

1. **destination 用 generic** — 避免设备连接超时：
   ```bash
   xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
     -destination 'generic/platform=iOS Simulator' \
     -skipPackagePluginValidation
   ```
2. **本地完整验证可选，required CI 必跑** — FS 按改动风险决定是否在本地执行；`App target` required check 不可绕过
3. **只在改动涉及 AppUI 时才考虑 xcodebuild** — 如果只改了 Packages/ 下的代码，swift build/test 就够了
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

## TestFlight 自动发布

`.github/workflows/testflight.yml` 每 6 小时检查一次 main，若自上次成功发布后有新 commit，就在
self-hosted runner `vitalstride-mac` 上 build + 上传 TestFlight（内部测试）。手动兜底：Actions →
testflight → Run workflow（`force=true` 忽略"无新提交"检查）。

- **发布点记录**：moving tag `testflight/last-released`（累积式；build 失败/关机期间不丢 commit）。
- **签名**：project.yml 保持 Automatic + `DEVELOPMENT_TEAM 4Z8GG667QD`；archive 用
  `-allowProvisioningUpdates` + App Store Connect API key 非交互签名（app + widget 扩展两个 bundleID）。
- **build number**：查 TestFlight 现存最大值 +1，archive 时 `xcargs` 注入，不写回 project.yml。
- **fastlane**：`fastlane/Fastfile` 的 `ios beta` lane（Homebrew 装 fastlane）。

**需要的 GitHub Secrets**（一次性，值来自 App Store Connect API Key）：

| Secret | 来源 |
|---|---|
| `ASC_KEY_ID` | ASC → Users and Access → Integrations → API Key 的 Key ID |
| `ASC_ISSUER_ID` | 同页 Issuer ID |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXX.p8`（.p8 只能下载一次，妥善保管；prod 密钥禁入 repo） |

## Architecture

- **XcodeGen 项目**：`project.yml` 定义 targets，`xcodegen generate` 生成 `.xcodeproj`
- **6 个 SPM local packages**：VitalModels、HealthKitService、AIService、VitalUI、TelemetryKit、DesignKit（均已注册到 `project.yml` 并接入 app target；TelemetryKit/DesignKit 为无本地依赖的独立包）
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

## Git Workflow (PR-required)

**This project uses a PR-required workflow.** All code reaches `main` only via a GitHub Pull
Request that passes the required status checks. `main` is protected by a **ruleset** (`main
protection`): required checks = `Lint & policy` + 6× `SPM …` + `App target` +
`codex-review-target`. A red required check blocks auto-merge. `claude-review` is paused;
`kimi-review` posts advisory findings but is intentionally non-required. Human approving-review
count is 0. See
`docs/adr/0009-pr-required-workflow.md` for full rationale (supersedes ADR-0001).

### Roles

| Role | What they do | Where they push |
|------|--------------|-----------------|
| **Planner Lead** | spec-driven feature 拆分 / DoR 补全（**不写代码**：只写契约级描述，禁内联可编译 Swift 片段；引用符号前先 `git show`/`grep` 核验存在，见 Constitution §DoR 硬合同） | 不 push；产出 sub-issue + @mention 交回 |
| **AI Reviewer** | **planning / DoR review** + **exact-candidate code review**（ADR-0014 / ADR-0021） | reviews planning artifacts and PRs; does not merge |
| **Team Lead (TL)** | accepts readiness, schedules work, owns recovery / Owner escalation, and closes lifecycle state; keeps issue/workdir/branch contract fail-closed | never pushes `main` directly |
| **Fullstack Engineer (FS)** | implement code + commit + publish the exact candidate PR before review, then refresh it as the exact revision changes | `github` remote `agent/<issue-key>-<task-id-short>` |
| **PR Manager** | owns final readiness, required-check supervision, merge/cleanup, and shipping handoff to the target branch | never pushes product code directly; owns the GitHub PR lifecycle |

> **Current Dev Team delivery contract (ADR-0021)**: the canonical pipeline is `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`. Planner and AI Reviewer loop before TL dispatch; Fullstack Engineer publishes the exact candidate PR, refreshes the exact revision, and repairs in-scope review findings directly; AI Reviewer re-checks the exact revision; PR Manager owns final shipping/merge cleanup; Team Lead owns readiness, scheduling, recovery, and lifecycle closure. Missing workdir/branch/SHA proof or a failed dispatch routes back to Team Lead instead of silent drift.

> **Planning Review / 双批准门（ADR-0014）**：Planner Lead 对 spec-driven feature 做拆分 / DoR
> 补全后，下游 stage 派发前须 **AI Reviewer + Team Lead 两方都批准**（同 code review 的
> ✅ APPROVED / 🟡 CHANGES REQUESTED verdict）。任一方 CHANGES REQUESTED → 回 Planner 修订。
> 批准后由 **TL 派发**（Planner/Reviewer 不自行派发）。bug-fix fast-path（TL 直接拆）不走此门。
> **谁触发 Planner**：spec-driven issue 缺 spec/plan/tasks 或跨 layer 需拆分时，**TL @mention
> Planner Lead** 去做 speckit 拆分——不升级给 human owner、不 @Hermes（本 workspace 无 Hermes）。
> 只有本质需要人的任务才升级 human。**"物理设备验证" 不是纯视觉改动的默认门**：token 迁移 / 配色 / 圆角 / 间距
> 等无逻辑变更，验收走**模拟器 light/dark 截图或 SnapshotTesting**（Constitution §Quality Bars K），不写死真机、不因
> "无真机" 升级 human。真机升级仅限模拟器测不了的能力（触觉 / 传感器 / 后台唤醒 / 真机性能）。详见 Constitution
> §Issue Tracker、`docs/adr/0014-restore-planner-review-dual-approval.md`。

> `main` cannot be pushed to directly (branch protection + `pre-commit` block). The only path to
> `main` is a merged PR whose required checks are green.

### FS workflow

The Multica daemon already created your worktree at `<task-dir>/workdir/`. **Do NOT create another worktree.** Just `cd` into the workdir and work there.

1. **Resolve issue identifier**:
   ```bash
   ISSUE_UUID=$(grep "Issue ID:" .agent_context/issue_context.md | awk '{print $3}')
   ISSUE_KEY=$(multica issue get "$ISSUE_UUID" --output json \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'].lower())")
   TASK_ID_SHORT=${MULTICA_TASK_ID:0:8}
   BRANCH="agent/${ISSUE_KEY}-${TASK_ID_SHORT}"
   ```

2. **Implement + commit** as usual on whatever branch the daemon checked out for you (it's already a fresh branch off `origin/main`).

   **Commit message 建议**（非强制）在 subject 或 body 引用 issue key（如 `MY-852`），方便 retro/审计工具用 grep `MY-\d+` 关联 commit ↔ issue。分支名 `agent/<issue-key>-<task-id>` 已带 issue key，即使 commit 未引用也可追溯。**hook / CI 不再校验 commit message 是否含 key。**

   ```bash
   git commit -m "feat: ExercisePickerView 多选批量添加 (MY-852)"
   # 或 body 引用:
   git commit -m "feat: 多选 picker" -m "Implements MY-852."
   ```

3. **Push your branch to `github` and open a PR**:
   ```bash
   git push -u github HEAD:$BRANCH
   gh pr create --base main --head "$BRANCH" \
     --title "<type>: <summary> (MY-XXX)" \
     --body "Implements MY-XXX. <what changed + test plan>"
   ```
   The pre-push hook runs fast touched-package/Prototype/RepoInfra validation and lint. It does not run the
   minutes-scale AppUI `xcodebuild` unless `RUN_XCODEBUILD=1`; required CI always runs `App target`.

4. **Publish the candidate PR and hand off to AI Reviewer / PR Manager**:
   ```bash
   PR_URL=$(gh pr view "$BRANCH" --json url -q .url)
   multica issue comment add "$ISSUE_UUID" --content "Opened candidate PR: ${PR_URL}. Awaiting exact revision review and PR Manager shipping handoff."
   ```

**Do** push `agent/*` to `github` and open the candidate PR. **Never** push `main` directly — branch
protection and the `pre-commit` hook block it. Team Lead owns readiness and recovery; PR Manager owns final shipping and merge/cleanup after the exact review verdict.

### TL workflow (readiness, recovery, and lifecycle closure)

When the issue is in `in_progress` / `in_review` and a candidate PR is present, Team Lead owns the delivery contract proof and recovery loop, not the shipping/merge gate itself:

1. **Verify the exact candidate and workdir proof**:
   ```bash
   git rev-parse HEAD
   git ls-remote origin "refs/heads/${BRANCH}"
   gh pr view "$PR_NUM" --json number,headRefName,headRefOid,url
   ```
   Confirm the exact SHA is the same local HEAD, pushed branch OID, and PR `headRefOid`. If any value mismatches, the issue routes back to FS for a fresh exact candidate and then back to Team Lead for recovery gating.

2. **Check the issue/branch/workdir contract**:
   - confirm `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha` are present and match the preserved worktree
   - ensure the candidate PR was published from the correct agent branch and not from `main`
   - confirm the immutable planning folder at `delivery_base_sha` still matches the approved baseline and has not been edited

3. **Coordinate the review handoff**:
   - Fullstack Engineer publishes the exact candidate PR and repairs supported in-scope findings directly
   - AI Reviewer owns the exact-revision review and planning/DoR review verdict
   - PR Manager owns the final shipping/merge/cleanup step after the review verdict is green
   - Team Lead only closes the lifecycle, keeps the issue fail-closed, and escalates ambiguous or exceptional failures

4. **Recovery and escalation rules**:
   - if required checks fail, the review is `CHANGES_REQUESTED`, or the dispatch/identity proof is invalid, route back to FS or an explicit recovery path instead of shipping
   - if the workdir, branch, or SHA proof is mismatched or missing, do not continue silently; re-open the issue under Team Lead recovery and require a fresh exact candidate
   - PR Manager owns the final merge-ready approval and required cleanup; Team Lead does not own the normal merge gate or clear shipping approvals on behalf of implementation work

> Do not treat Team Lead as the normal merge or shipping owner. The shipping owner is `PR Manager`; Team Lead owns readiness, scheduling, recovery, escalation, and lifecycle closure.

5. **Close the issue**:
   ```bash
   multica issue status "$ISSUE_UUID" done
   ```

> The repository still requires the exact-revision proof and the PR-required workflow. Team Lead must validate that the worktree, branch, SHA, and review evidence are coherent before closing the lifecycle; no merge or cleanup is performed under the Team Lead role outside the PR Manager gate.

### Common pitfalls

- **Never push `main` directly** — branch protection and required PR workflow require the change to be reviewed and merged through the repository's normal PR path.
- **`MULTICA_TASK_ID`** is provided by the daemon as an env var (full UUID; we use the first 8 chars).
- **GitHub access tokens** must be valid (FS needs them to push `agent/*` + open PRs; PR Manager owns the final merge/cleanup gate). Do not unset `gh` auth without a documented repo-identity reason.
- The `github` remote name is by convention; some clones may use `origin`. Commands accept either
  as long as the URL contains `github.com`.

## Pipeline Recovery

> 这一节定义 pipeline 失败时的恢复路径。**所有失败路径都自动化，禁止 `waiting_on: human_triage`**。
> 唯一例外：constitution P0 违规（例如健康数据隐私破坏）才升人工。其它一律走 Hermes auto-dispatch。

### Ship-gate flake quarantine（required CI test 失败）

required CI 的 `App target` / `SPM …` check 失败时**不要无脑 retry / 不要回 FS**——先判定是不是当前 patch 引入的：

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
# 1. Review 待处理的 open PR（PR 工作流下是正常状态，非违规）
OPEN_PRS=$(gh pr list --state open --json number,title,updatedAt 2>/dev/null)
if [ "$(echo "$OPEN_PRS" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')" -gt 0 ]; then
  # open PR 是 PR 工作流的常态 —— TL 负责检查是否仍处于正确的 review/ship 轨道，必要时催促 PR Manager/FS 完成清晰的 handoff；不得将 merge/cleanup 视为 TL 责任
  multica issue comment add "$ISSUE_UUID" --content "ℹ️ Startup scan: $OPEN_PRS 个 open PR 正在 review/ship 流程中。详: $(echo "$OPEN_PRS" | head -200)"
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
3. **`specs/000-baseline-existing-codebase/plan.md`** —— 已知 gap（G-01 ~ G-09）与处理路径。
4. **`specs/001-future-roadmap/spec.md`** —— V2+ 未来功能 roadmap（承接原 `docs/DESIGN.md`）。是 **umbrella / planning-only** spec：功能启动时 fork 出 `specs/00N-<name>/` 才写可执行 spec + tasks + Multica issue，此前**不入 Multica**。
5. **`docs/adr/`** —— 9 个已落地的架构决策记录。新方向冲突时先写新 ADR 推翻。
6. 本文件（`AGENTS.md`）—— build/test/git 操作手册。

**新 feature 流程**：`/speckit-specify` → `/speckit-plan` → `/speckit-tasks`，然后通过 `multica-quick-issue` 入 Multica project `7adf8b88`。**`/speckit-implement` 不使用** —— 实现由 `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead` 的 canonical Dev Team pipeline 完成（Constitution §Development Workflow）。若新功能已列在 `001-future-roadmap` roadmap 里，从 `001` **fork**（复制方向性 FR 到 `specs/002+`）而非从零 specify。

**写 spec/plan/tasks 必须**：reference Constitution 章节，不要重述规则。issue 标题 `[T###] [Story] Brief description`。
<!-- SPECKIT END -->
