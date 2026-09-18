# VitalStride — Agent Instructions

## Build & Test

### SPM Packages（优先使用）

`Packages/` 下的六个独立 SPM 包（VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, DesignKit）支持 `swift build` 和 `swift test`，无需 Xcode 项目、无需模拟器，秒级完成。

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
- **6 个 SPM local packages**：VitalModels、HealthKitService、AIService、VitalUI、TelemetryKit、DesignKit（均已注册到 `project.yml` 并接入 app target；TelemetryKit/DesignKit 为无本地依赖的独立包）
- **Swift 6 strict concurrency**
- **SwiftData** 存储训练数据 + HealthKit L2 缓存（`HealthCacheEntry`，本地隔离，`cloudKitDatabase: .none`）
- **HealthDataCache** 是纯内存 actor L1 缓存层

## Key Conventions

- HealthKit 健康数值禁止出现在任何日志中（隐私合规）
- 详见 CONTEXT.md 的架构决策

## Git Workflow (PR-required)

**This project uses a PR-required workflow.** `main` is only reached through GitHub Pull Requests that pass the required checks and review gate. The current Dev Team contract is captured in `docs/adr/0021-current-dev-team-delivery-contract.md` and overrides the older shorthand that treated Team Lead as the normal merger.

### Roles

| Role | What they do | Where they push |
|------|--------------|-----------------|
| **Planner Lead** | spec-driven feature 拆分 / DoR 补全；**author / commit / push 规划修订**，但不拥有实现权限 | `agent/<issue-key>-<task-id-short>` 规划 revision 或 issue-linked planning branch |
| **AI Reviewer** | **planning / DoR review** + **exact-candidate code review** | reviews planning artifacts and PRs; does not merge |
| **Team Lead (TL)** | accepts readiness, schedules work, owns recovery / Owner escalation, and closes lifecycle state; keeps issue/workdir/branch contract fail-closed | never pushes `main` directly |
| **Fullstack Engineer (FS)** | implement code + commit + publish the exact candidate PR before review, then refresh it as the exact revision changes | `github` remote `agent/<issue-key>-<task-id-short>` |
| **PR Manager** | owns final readiness, required-check supervision, merge/cleanup, and shipping handoff to the target branch | never pushes product code directly; owns the GitHub PR lifecycle |

> **Current Dev Team delivery contract (ADR-0021)**: the canonical pipeline is `Planner Lead ⇄ AI Reviewer → Team Lead → Fullstack Engineer ⇄ AI Reviewer → PR Manager → Team Lead`. Planner Lead authors, commits, pushes, and refines the exact planning revision without implementation authority; AI Reviewer validates the planning package and the exact candidate revision; Team Lead owns readiness, scheduling, recovery, and lifecycle closure; Fullstack Engineer publishes the exact candidate PR, refreshes the exact revision, and repairs supported in-scope findings directly; PR Manager owns final shipping, required-check supervision, merge/cleanup, and handoff. Missing workdir/branch/SHA proof, failed dispatch, or mismatched exact revision routes back to Team Lead instead of silent drift.

### Required status gates

- `main` is protected by a ruleset (`main protection`): required checks include `Lint & policy`, 6× `SPM …`, `App target`, and the required AI review gate.
- `claude-review` is paused; `kimi-review` is advisory-only and does not satisfy the required review gate.
- `pre-commit` blocks direct commits to `main`; `pre-push` performs the fast, agent-safe validation path.
- RepoInfra governance work uses `bash scripts/test-repoinfra.sh`; the optional local AppUI `xcodebuild` is not the default shipping proof.

### What this means for work

1. **This repository task remains within the current issue's authorized governance paths** — the allowlisted files are the bounded exception for this RepoInfra task, not a blank check for future product or infrastructure work.
2. **FS publishes the candidate PR before exact review** — not after a “merge-ready” claim.
3. **PR Manager owns final shipping** — they supervise required checks and the final merge/cleanup lifecycle.
4. **TL owns readiness / scheduling / recovery** — not the normal shipping merge path.
5. **Exact revision proof is mandatory** — local `HEAD`, remote branch OID, and PR `headRefOid` must match before a review or handoff claim is considered valid.
6. **Issue/workdir/branch validation stays fail-closed** — missing or mismatched `delivery_*` metadata or SHA proof routes back to Team Lead instead of continuing silently.

### Operational guidance

- Keep the issue/workdir/branch metadata coherent with the reviewed delivery contract.
- Do not treat a comment or assignment as proof of dispatch; cluster-level run evidence must exist.
- If a validation or review failure occurs, fix within the allowlisted governance files and publish a fresh exact revision instead of silently drifting.
- After a passing exact-revision verdict, hand the revision directly to PR Manager.

