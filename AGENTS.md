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
| **Planner Lead** | spec-driven feature 拆分 / DoR 补全（**不写代码**：只写契约级描述，禁内联可编译 Swift 片段；引用符号前先 `git show`/`grep` 核验存在，见 Constitution §DoR 硬合同）；**author / commit / push 规划修订**，但不拥有实现权限 | `agent/<issue-key>-<task-id-short>` 规划 revision 或 issue-linked planning branch |
| **AI Reviewer** | **planning / DoR review** + **exact-candidate code review**（ADR-0014 / ADR-0021） | reviews planning artifacts and PRs; does not merge |
| **Team Lead (TL)** | accepts readiness, schedules work, owns recovery / Owner escalation, and closes lifecycle state; keeps issue/workdir/branch contract fail-closed | never pushes `main` directly |
| **Fullstack Engineer (FS)** | implement code + commit + publish the exact candidate PR before review, then refresh it as the exact revision changes | `github` remote `agent/<issue-key>-<task-id-short>` |
| **PR Manager** | owns final readiness, required-check supervision, merge/cleanup, and shipping handoff to the target branch | never pushes product code directly; owns the GitHub PR lifecycle |

> **Current Dev Team delivery contract (ADR-0021)**: the canonical pipeline is `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`. Planner Lead authors, commits, pushes, and refines the exact planning revision without implementation authority; AI Reviewer validates the planning package and the exact candidate revision; Team Lead owns readiness, scheduling, recovery, and lifecycle closure; Fullstack Engineer publishes the exact candidate PR, refreshes the exact revision, and repairs supported in-scope findings directly; PR Manager owns final shipping, required-check supervision, merge/cleanup, and handoff. Missing workdir/branch/SHA proof, failed dispatch, or mismatched exact revision routes back to Team Lead instead of silent drift.

> **Planning Review / 双批准门（ADR-0014）**：Planner Lead 对 spec-driven feature 做拆分 / DoR
> 补全后，下游 stage 派发前须 **AI Reviewer + Team Lead 两方都批准**（同 code review 的
> ✅ APPROVED / 🟡 CHANGES REQUESTED verdict）。任一方 CHANGES REQUESTED → 回 Planner 修订。
> 批准后由 **TL 派发**（Planner/Reviewer 不自行派发）；Planner Lead 仍保留规划修订发布责任，不在实现层接管 FS 代码。bug-fix fast-path（TL 直接拆）不走此门。
> **谁触发 Planner**：spec-driven issue 缺 spec/plan/tasks 或跨 layer 需拆分时，**TL @mention
> Planner Lead** 去做 speckit 拆分。只有本质需要人的任务才升级 human。**"物理设备验证" 不是纯视觉改动的默认门**：token 迁移 / 配色 / 圆角 / 间距
> 等无逻辑变更，验收走**模拟器 light/dark 截图或 SnapshotTesting**（Constitution §Quality Bars K），不写死真机、不因
> "无真机" 升级 human。真机升级仅限模拟器测不了的能力（触觉 / 传感器 / 后台唤醒 / 真机性能）。详见 Constitution
> §Issue Tracker、`docs/adr/0014-restore-planner-review-dual-approval.md`。

> `main` cannot be pushed to directly (branch protection + `pre-commit` block). The only path to
> `main` is a merged PR whose required checks are green, and the final merge/cleanup phase is owned by PR Manager.

### FS workflow

The Multica daemon already created the preserved worktree at the task's `delivery_work_dir`. **Do NOT create another worktree.** Work only in that preserved checkout.

1. **Resolve and verify the persisted delivery identity**
   ```bash
   ISSUE_UUID="<issue-id>"
   ISSUE_JSON=$(multica issue get "$ISSUE_UUID" --output json)
   DELIVERY_WORK_DIR=$(printf '%s' "$ISSUE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('delivery_work_dir',''))")
   DELIVERY_REPO_URL=$(printf '%s' "$ISSUE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('delivery_repo_url',''))")
   DELIVERY_BRANCH=$(printf '%s' "$ISSUE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('delivery_branch',''))")
   DELIVERY_BASE_SHA=$(printf '%s' "$ISSUE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('delivery_base_sha',''))")
   
   # Verify all metadata values exist
   [ -n "$DELIVERY_WORK_DIR" ] && [ -n "$DELIVERY_REPO_URL" ] && [ -n "$DELIVERY_BRANCH" ] && [ -n "$DELIVERY_BASE_SHA" ] || exit 1
   
   # Compare workdir, normalized repository identity, branch, and base planning tree
   cd "$DELIVERY_WORK_DIR" || exit 1
   CURRENT_ORIGIN=$(git remote get-url origin)
   CURRENT_BRANCH=$(git branch --show-current)
   python3 -c "import sys,re
def parse_github_repo(u):
    u = u.strip()
    m = re.match(r'^(?:https?://github\.com/|git@github\.com:|ssh://git@github\.com/)([\w.-]+)/([\w.-]+?)(?:\.git)?/?$', u)
    return (m.group(1).lower(), m.group(2).lower()) if m else None
orig = parse_github_repo(sys.argv[1])
decl = parse_github_repo(sys.argv[2])
sys.exit(0 if orig and decl and orig == decl else 1)
" "$CURRENT_ORIGIN" "$DELIVERY_REPO_URL" || exit 1
   [ "$CURRENT_BRANCH" = "$DELIVERY_BRANCH" ] || exit 1
   git diff --quiet "$DELIVERY_BASE_SHA" -- specs/025-dev-team-delivery-contract || exit 1
   
   # Verify parent issue assignment remains Dev Team squad
   PARENT_ID=$(printf '%s' "$ISSUE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('parent_issue_id',''))")
   [ -n "$PARENT_ID" ] || exit 1
   PARENT_JSON=$(multica issue get "$PARENT_ID" --output json)
   PARENT_ASSIGNEE_TYPE=$(printf '%s' "$PARENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('assignee_type',''))")
   PARENT_ASSIGNEE_ID=$(printf '%s' "$PARENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('assignee_id',''))")
   [ "$PARENT_ASSIGNEE_TYPE" = "squad" ] && [ "$PARENT_ASSIGNEE_ID" = "741fb417-c6b0-4df7-b505-03396ccbf77b" ] || exit 1
   ```
   If any `delivery_*` value is missing or mismatched, or parent assignment is lost, stop and return the issue to Team Lead recovery; do not synthesize a new branch or drift away from the preserved worktree.

2. **Implement and commit inside the preserved branch**
   ```bash
   git status --short
   git add <files>
   git commit -m "docs: repair delivery governance wording"
   ```
   Keep the diff within the issue's authorized paths only; do not touch product code, live role config, or any inherited planning artifacts.

3. **Push the preserved branch and publish or update the candidate PR**
   ```bash
   git push -u origin "$DELIVERY_BRANCH"
   PR_NUM=$(gh pr view --json number --repo LeePepe/VitalStride --jq '.number' 2>/dev/null || true)
   if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
     gh pr edit "$PR_NUM" --base main --repo LeePepe/VitalStride
   else
     gh pr create --base main --head "$DELIVERY_BRANCH" --fill --repo LeePepe/VitalStride
   fi
   gh pr view --json number,headRefName,headRefOid,url --repo LeePepe/VitalStride
   ```
   The PR is the candidate PR; it is not a shipping approval. Required checks run in CI, while the exact-review gate remains independent. The create-or-update flow must exist before exact review; a branch push alone is not a valid candidate PR publication.

4. **Publish the exact-SHA AI Reviewer request, then verify its run**
   ```bash
   CURRENT_TRIGGER_ID="<current-trigger-comment-id>"  # resolve from the active turn's trigger comment; do not reuse a prior parent from another turn
   
   # Preflight checks: compare local HEAD, remote branch OID, PR headRefOid, and verify parent Dev Team assignment
   LOCAL_SHA=$(git rev-parse HEAD)
   REMOTE_SHA=$(git ls-remote origin "refs/heads/${DELIVERY_BRANCH}" | awk '{print $1}')
   PR_HEAD_SHA=$(gh pr view --json headRefOid --repo LeePepe/VitalStride --jq '.headRefOid')
   [ "$LOCAL_SHA" = "$REMOTE_SHA" ] && [ "$LOCAL_SHA" = "$PR_HEAD_SHA" ] || exit 1
   git diff --quiet "$DELIVERY_BASE_SHA" -- specs/025-dev-team-delivery-contract || exit 1
   
   PARENT_JSON=$(multica issue get "$PARENT_ID" --output json)
   [ "$(printf '%s' "$PARENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('assignee_id',''))")" = "741fb417-c6b0-4df7-b505-03396ccbf77b" ] || exit 1
   
   printf '%s\n' \
     "Candidate revision: $LOCAL_SHA" \
     "Preserved delivery proof:" \
     "- workdir: $DELIVERY_WORK_DIR" \
     "- repo: $DELIVERY_REPO_URL" \
     "- branch: $DELIVERY_BRANCH" \
     "- base: $DELIVERY_BASE_SHA" \
     "- local HEAD = remote branch OID = PR headRefOid" \
     "This is the exact-candidate review request." \
     "" \
     "[@AI Reviewer](mention://agent/24ff66eb-ee5c-4ab4-bd40-5714b6a789f9)" > reply.md
   RESULT=$(multica issue comment add "$ISSUE_UUID" --parent "$CURRENT_TRIGGER_ID" --content-file ./reply.md --output json)
   rm ./reply.md
   # Verify that AI Reviewer run reaches queued, dispatched, or running; stop and route exact failure evidence to Team Lead if not reached
   echo "$RESULT" | jq -e '.trigger_outcomes[] | select(.target_id == "24ff66eb-ee5c-4ab4-bd40-5714b6a789f9" and (.status == "queued" or .status == "dispatched" or .status == "running"))'
   ```
   The exact-review request must carry the candidate SHA and the identity proof; a generic PR URL or bare assignment is not valid proof of dispatch. The mention must create a queued/dispatched/running Reviewer run before the candidate is treated as review-ready, and the parent must be the current trigger comment rather than a stale ID from an earlier turn. If dispatch fails or trigger outcome is missing, preserve valid state and route exact evidence to Team Lead.

5. **After a passing verdict, recheck the reviewed SHA and hand off to PR Manager**
   ```bash
   CURRENT_TRIGGER_ID="<current-trigger-comment-id>"  # resolve from this turn's trigger comment; do not reuse the earlier step 4 trigger
   
   # Verify that the triggering comment contains a valid passing AI Reviewer verdict for LOCAL_SHA
   LOCAL_SHA=$(git rev-parse HEAD)
   TRIGGER_COMMENTS_JSON=$(multica issue comment list "$ISSUE_UUID" --thread "$CURRENT_TRIGGER_ID" --tail 30 --compact --output json)
   printf '%s' "$TRIGGER_COMMENTS_JSON" | python3 -c "import json,sys,re
comments = json.load(sys.stdin)
if not isinstance(comments, list): comments = [comments]
target_id = sys.argv[1]
local_sha = sys.argv[2]
target = next((c for c in comments if c.get('id') == target_id), None)
if not target:
    sys.exit(1)
if target.get('author_id') != '24ff66eb-ee5c-4ab4-bd40-5714b6a789f9':
    sys.exit(1)
content = target.get('content', '')
verdict_matches = re.findall(r'(?m)^(?:[-*]\s*)?\*{0,2}Verdict:?\*{0,2}\s*:?\s*\*{0,2}(.*?)\*{0,2}\s*$', content)
if len(verdict_matches) != 1:
    sys.exit(1)
verdict = verdict_matches[0].strip(' *`')
if verdict not in ('PASS', 'PASS WITH FOLLOW-UP'):
    sys.exit(1)
rev_matches = re.findall(r'(?m)^(?:[-*]\s*)?\*{0,2}Reviewed revision:?\*{0,2}\s*:?\s*\*{0,2}`?([a-f0-9]{40})`?\*{0,2}\s*$', content)
if len(rev_matches) != 1 or rev_matches[0] != local_sha:
    sys.exit(1)
" "$CURRENT_TRIGGER_ID" "$LOCAL_SHA" || exit 1
   
   # Preflight checks: compare local HEAD, remote branch OID, PR headRefOid, and verify parent Dev Team assignment
   REMOTE_SHA=$(git ls-remote origin "refs/heads/${DELIVERY_BRANCH}" | awk '{print $1}')
   PR_HEAD_SHA=$(gh pr view --json headRefOid --repo LeePepe/VitalStride --jq '.headRefOid')
   [ "$LOCAL_SHA" = "$REMOTE_SHA" ] && [ "$LOCAL_SHA" = "$PR_HEAD_SHA" ] || exit 1
   git diff --quiet "$DELIVERY_BASE_SHA" -- specs/025-dev-team-delivery-contract || exit 1
   
   PARENT_JSON=$(multica issue get "$PARENT_ID" --output json)
   [ "$(printf '%s' "$PARENT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('assignee_id',''))")" = "741fb417-c6b0-4df7-b505-03396ccbf77b" ] || exit 1
   
   printf '%s\n' \
     "Reviewed revision: $LOCAL_SHA" \
     "Identity proof:" \
     "- workdir: $DELIVERY_WORK_DIR" \
     "- repo: $DELIVERY_REPO_URL" \
     "- branch: $DELIVERY_BRANCH" \
     "- base: $DELIVERY_BASE_SHA" \
     "- local HEAD = remote branch OID = PR headRefOid" \
     "This is the final exact-SHA handoff to PR Manager." \
     "" \
     "[@PR Manager](mention://agent/2cb1cc4f-c50d-40d8-b75b-f29c66552de1)" > reply.md
   RESULT=$(multica issue comment add "$ISSUE_UUID" --parent "$CURRENT_TRIGGER_ID" --content-file ./reply.md --output json)
   rm ./reply.md
   # Verify that PR Manager run reaches queued, dispatched, or running; stop and route exact failure evidence to Team Lead if not reached
   echo "$RESULT" | jq -e '.trigger_outcomes[] | select(.target_id == "2cb1cc4f-c50d-40d8-b75b-f29c66552de1" and (.status == "queued" or .status == "dispatched" or .status == "running"))'
   ```
   Only after verifying a genuine AI Reviewer PASS / PASS WITH FOLLOW-UP verdict for `LOCAL_SHA` and confirming that local SHA, remote branch OID, and PR `headRefOid` match the approved review does Fullstack Engineer hand the exact reviewed revision to PR Manager. The handoff must be an explicit PR Manager mention with the exact SHA, parent Dev Team preservation, and verified downstream run evidence; a generic statement about “handing off” is not sufficient. If dispatch fails, preserve valid state and route exact evidence to Team Lead.

**Do** use the preserved `delivery_branch` and exact-candidate worktree. **Never** push `main` directly, and never claim review or shipping PASS without the exact-SHA proof and a real downstream run.

### TL workflow (readiness, recovery, and lifecycle closure)

When the issue is in `in_progress` / `in_review`, Team Lead owns the delivery contract proof and recovery loop, not the normal merge gate:

1. **Verify the exact candidate and workdir proof**
   ```bash
   git rev-parse HEAD
   git ls-remote origin "refs/heads/${DELIVERY_BRANCH}"
   gh pr view <PR_NUM> --json number,headRefName,headRefOid,url
   ```
   Confirm the exact SHA is the same local HEAD, pushed branch OID, and PR `headRefOid`. If any value mismatches, or if dispatch failed on an unchanged candidate, the issue routes directly to Team Lead recovery. Team Lead recovers and revalidates proof/run evidence for unchanged candidates, while a fresh exact candidate SHA is required only after authorized content changes.

2. **Check the issue/branch/workdir contract**
   - confirm `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha` exist and match the preserved worktree
   - confirm the candidate PR was published from the correct agent branch and not from `main`
   - confirm the immutable planning folder at `delivery_base_sha` still matches the approved baseline and has not changed

3. **Coordinate the review handoff**
   - Fullstack Engineer publishes the exact candidate PR and exact-SHA AI Reviewer request, then repairs supported in-scope findings directly
   - AI Reviewer owns the exact-revision review and planning/DoR review verdict
   - PR Manager owns the final shipping/merge/cleanup step only after a passing exact-revision verdict
   - Team Lead keeps the issue fail-closed, verifies the downstream run exists, and escalates ambiguous or exceptional failures

4. **Recovery and escalation rules**
   - if workdir metadata, branch identity, or SHA proof is missing or mismatched, or if dispatch fails, preserve valid state and route directly to Team Lead recovery
   - supported in-scope review findings (`CHANGES_REQUESTED` or `FAIL`) route directly through the `Fullstack Engineer ⇄ AI Reviewer` refinement loop without Team Lead intervention
   - conflicting evidence, policy disagreements, permission/infrastructure issues, repeated repair, failed dispatch, and merge conflicts go directly to Team Lead escalation; they are not treated as normal shipping work
   - PR Manager owns the final merge-ready approval and required cleanup; Team Lead does not own the normal merge gate or suppress the final handoff to PR Manager
   - a candidate PR alone is not closure evidence; only a verified PR Manager handoff proving delivery and cleanup may close the lifecycle

> Team Lead is not the normal merge or shipping owner. The shipping owner is `PR Manager`; Team Lead owns readiness, scheduling, recovery, escalation, and lifecycle closure.

5. **Close the issue only after PR Manager delivery evidence**
   ```bash
   multica issue status "$ISSUE_UUID" done
   ```
   This status is allowed only after the issue has a passing exact-revision verdict and a verified PR Manager handoff proving the reviewed SHA was shipped and cleaned up. If the review or dispatch is still blocked, keep the issue in `blocked`/`in_progress` and escalate instead of closing.

### Common pitfalls

- **Never push `main` directly** — branch protection and the PR-required contract require shipping through the repository's normal PR path.
- **Persisted delivery metadata is authoritative** — do not rederive a new branch from `MULTICA_TASK_ID` when the issue already includes `delivery_branch` and `delivery_work_dir`.
- **GitHub access tokens** must be valid; do not unset `gh` auth without a documented repo-identity reason.
- The `github` remote name is by convention; some clones use `origin`, and either is valid as long as the repository URL remains the same.

## Pipeline Recovery

> This section defines the fail-closed recovery path for repository governance and shipping failures. The canonical rule remains: fix the invalid state within the approved delivery contract, keep the exact-SHA / issue / workdir proofs intact, and route conflicting evidence or authority problems back to Team Lead recovery instead of creating a silent merge path.

### Required recovery routing

- **Review-induced findings (`CHANGES_REQUESTED` / `FAIL`)**: Fullstack Engineer repairs supported in-scope findings directly and publishes a fresh exact candidate revision. The review cycle repeats through `Fullstack Engineer ⇄ AI Reviewer` with the same scope and exact SHA proof.
- **Missing or mismatched identity proof, failed dispatch, conflicting evidence, permissions/infrastructure issues, policy disagreement, repeated repair, or merge/branch ambiguity**: Team Lead owns the recovery escalation. Preserve valid candidate state and worktree evidence; revalidate proof and downstream runs without invalidating unchanged worktree/commit/PR content, and reserve new candidate SHAs for authorized content repairs. Do not silently drift to a new branch or duplicate candidate PR.
- **Clear implementation-owned code / build / test / lint / required-check failures after a passing exact review**: route through `PR Manager → Fullstack Engineer ⇄ AI Reviewer → PR Manager` as the normal shipping repair loop. Team Lead stays in the recovery path only for governance, permission, identity, dispatch, policy, or repeated-repair issues.
- **PR Manager shipping/cleanup**: only after a passing exact-revision verdict and a verified PR handoff proving the reviewed SHA was shipped and cleaned up.
- **No normal Team Lead merge/cleanup ownership**: Team Lead validates readiness, scheduling, recovery, and lifecycle closure; PR Manager owns shipping and cleanup. There is no alternate merge path.

### PR-2 / PR-3 operational controls

- **PR-2: sub-issue idempotency / duplicate sibling prevention**: before creating sub-issues, Planner Lead / Team Lead must check all alive (`todo`/`in_progress`/`in_review`/`blocked`) sub-issues under the same parent. If scope overlaps (same branch, matching title trim, or ≥80% overlapping files), reuse the existing sub-issue rather than creating a duplicate sibling.
- **PR-3: run-count guard classification (`run_attempts` vs `infra_failures`)**:
  - `run_attempts` (budgeted, default 15): code-review iterations, patch-induced test/build failures, and implementation refinements.
  - `infra_failures` (unbudgeted): CLI routing errors, runtime crashes, quarantined flakes, auth, network, and platform infrastructure faults.
  Do not count infrastructure failures against the implementation run-attempt budget.

### Exact-revision proof required before any handoff

Before a review or handoff claim is treated as valid, the issue must satisfy all of the following:

- `delivery_repo_url`, `delivery_work_dir`, `delivery_branch`, and `delivery_base_sha` are present and match the preserved worktree
- local `HEAD` equals the remote branch OID and the PR `headRefOid`
- the candidate branch is the preserved agent branch, not `main`
- the immutable planning baseline at `delivery_base_sha` remains unchanged

If any proof is missing or mismatched, stop and route the issue back to Team Lead recovery instead of continuing silently.

### Ship-gate failure classification

When required checks fail:

- treat the failure as a patch-induced gate issue and route back to Fullstack Engineer for direct repair when the diff or adjacent module clearly caused it
- treat the failure as an open governance / policy / infrastructure issue when the evidence is ambiguous, unrelated to the patch, or blocked by repo identity / dispatch / review mismatches
- never turn a failed gate into a Team Lead merge path or silent approval; only a verified PR Manager handoff proves final shipping and cleanup

### Lifecycle closure

The issue remains `in_progress` or `blocked` until all of the following are true:

1. the exact revision has passed independent AI review
2. the local/remote/PR SHA proof still matches the reviewed revision
3. PR Manager has produced the verified shipping/cleanup handoff for the same SHA

Only then is a terminal lifecycle change allowed. Otherwise, keep the issue open and escalate.

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
