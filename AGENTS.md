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
