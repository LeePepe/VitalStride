# Implementation Plan — 017 Add-Set Button Redesign

**Spec**: `specs/017-add-set-button-redesign/spec.md`
**Tasks**: `specs/017-add-set-button-redesign/tasks.md`
**Parent issue**: MY-1343 · **Implementation sub-issue**: MY-1348 · **Planning gate**: MY-1347
**Status**: Ready for dual approval (AI Reviewer + Team Lead, ADR-0014)

---

## 1. Approach

单 layer 单 task。改动完全落在 `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` 的
`addSetButton` computed property（约 221-242 行）+ 底部 `#Preview` 扩展。零 SPM package 侵入
（`Packages/**` 不动），零 XcodeGen drift（`project.yml` / `.xcodeproj` 不动）。

若引入自定义 `AddSetButtonStyle: ButtonStyle`，声明在**同一文件底部** `private` scope，不新增独立文件、不 export。

## 2. Working Directory

FS 在 Multica daemon 提供的 `~/multica_workspaces/<workspace>/<task-id>/workdir/VitalStride/`
下的隔离 worktree 内工作。**禁 `cd ~/Development/VitalStride`**——用户主 checkout 不得污染。

- 权威 remote = `github`。
- 用 `git fetch github main` + `git diff github/main...HEAD` 校验 diff。
- `git push` 走 **normal push**（`git push -u github HEAD:$BRANCH`），让 `pre-push` hook 跑
  `xcodebuild test` 本地门（`AGENTS.md` §FS workflow 强制）。**禁 `--no-verify`**——绕过 pre-push
  等于放弃 AGENTS.md §182-200 定义的本地权威门。若 hook 因 daemon workdir 环境异常失败，先修
  hook / 环境，不要绕过。
- 目标 shell = macOS BSD grep + Swift 6 toolchain + Xcode。

## 3. SPM-only Hook 分析

改动路径集合 = `{VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift, specs/017-add-set-button-redesign/{spec,plan,tasks}.md}`。

- 无一路径匹配 `^Packages/` → **workspace guardrail rule #1（SPM-first）不适用**。
- 有 app target 源码改动 → 正确验证 = `xcodebuild build ...`（app target 层）。
- `swift build / swift test` 在本任务下**不足以覆盖**（改的是 app target，不是 SPM 包）。

## 4. Layer & Boundary

按 `AGENTS.md` Layer 索引：`VitalStride/` = app target（不属于任何 SPM layer，走 pre-push 全量 xcodebuild 门）。

- **改动落**：app target `ActiveWorkout` 目录内 1 个文件。
- **禁触**：
  - `Packages/DesignKit/**`（只消费现有 token，零新增）；
  - `Packages/VitalModels/**` / `Packages/HealthKitService/**` / `Packages/AIService/**` / `Packages/VitalUI/**` / `Packages/TelemetryKit/**`；
  - `VitalStride/Sources/ActiveWorkout/` 下其它文件（SetRow.swift / SubSetRow.swift / ActiveWorkoutView.swift / etc.）；
  - `VitalStrideWatch Watch App/**` / `VitalStrideMac/**` / `VitalStrideWidgets/**`；
  - `project.yml` / `VitalStride.xcodeproj/**`；
  - 埋点调用点（`TelemetryService.shared.track(...)`）。
- **函数体冻结**：`addSet()` / `addSubSet()` / `copyToNext()` / `deleteSet()`。

## 5. DesignKit Token Menu

允许消费的现有 token（从 `Packages/DesignKit/Sources/DesignKit/Color/Theme.swift` /
`Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift` 提取——AI Reviewer 修正：`Color/`
子目录是权威路径）：

- **颜色**：`theme.primary.{primary, primaryHover, primaryActive, primarySubtle, primaryMuted, primaryBorder, primaryText, onPrimary, ring}`；`theme.neutrals.{text1, text2, bg}`。
- **圆角**：`Radius.inner`（10）或 `Radius.card`（14）。
- **间距**：`Space.gap`（12）/ `Space.cardPadding`（16）/ 常见 4/8/12/16pt 间距（`EdgeInsets`）。
- **字体**：`Font.system(.callout | .subheadline | .body).weight(.medium | .semibold)` 或 `LargeWorkoutFonts.*`。

禁止：`Color(red:green:blue:)` / `Color(hex:)` / `#RRGGBB` literal / `Font.system(size: N)` 魔法数（除非直接引用 DesignKit `TypeScale`）/ 硬编码圆角常量（如 `.cornerRadius(8)` — 用 `Radius.inner`）。

## 6. Branch / Merge Strategy (from `AGENTS.md`)

- **Base**：`main` on `github` remote。
- **Feature branch**：`agent/my-1348-<task-id-short>`（Multica daemon 自动生成）。
- **Commit**：单 commit or 少量 logical commits；commit message 使用 conventional format。
- **Push**：`git push -u github HEAD:$BRANCH`（**不加 `--no-verify`**——pre-push hook 是本地权威门，
  `AGENTS.md` §182-200 强制）。
- **PR**：`gh pr create --base main --head "$BRANCH" --title "refactor(active-workout): addSetButton 视觉重设计 (MY-1348)"`。
- **Required CI**（服务端权威门）：`Lint & policy` + `SPM (6×)` + `App target` + `claude-review` + `codex-review` 全绿。
- **Merge**：GitHub auto-merge (squash)。TL 在 review PASS + `gh pr view --json state` 见 `MERGED` 后收尾。

## 7. Preview Coverage

在 `ActiveExerciseSection.swift` 底部**扩展或新增** `#Preview` block（若已有 preview 则扩展，避免破坏；若无则新增 private helper struct 承载），覆盖 4 态：

| # | mode   | scheme | 备注 |
|---|--------|--------|-----|
| 1 | normal | light  | ≥2 sets，观察 addSetButton 与 SetRow 视觉关系 |
| 2 | normal | dark   | 同上 |
| 3 | large  | light  | 验证 Large Mode 密度与 addSetButton 协调 |
| 4 | large  | dark   | 同上 |

## 8. Verification Command (per `AGENTS.md`, layer = app target)

**主验证（app target = `AGENTS.md` §82 强制 `xcodebuild test` 到 iPhone 16 Simulator）**：

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation
```

**补充构建冒烟（可选，非权威）**：`generic/iOS Simulator` build 可加速迭代反馈但不能替代 `test`。

**关于 `VitalStrideMac`**：`project.yml:140-166` 显示 `VitalStrideMac` target 的 `sources:` 仅
显式列出 `VitalStride/Sources/` 下少数根级文件（`ExerciseSeeder.swift` / `AIView.swift` /
`OnboardingView.swift` 等），**未包含** `VitalStride/Sources/ActiveWorkout/` 目录，因此
`ActiveExerciseSection.swift` **不在** `VitalStrideMac` 构建路径中。`xcodebuild build ... -scheme
VitalStrideMac` 对本 patch **不构成验证信号**，此前 §A-2 的宣称是错误的，已在 `tasks.md` 中撤除。
若未来 macOS 场景需真实验证，需先在 `project.yml` 显式添加 `ActiveWorkout/` 到 `VitalStrideMac.sources`
——那是另一个 issue 的范围。

（`Packages/` 无改动，禁用 `swift build/test`；SPM-only hook 不触发。）

## 9. Layer Red Lines

- **§I 健康数据隐私零妥协**：本改动不接触 HealthKit 数值，无风险。
- **DesignKit token 消费铁律**：见 §5。
- **Swift 6 strict concurrency**：若引入 `AddSetButtonStyle: ButtonStyle` 必须 `Sendable`（`struct` 天然满足）。
- **不可变优先**：`struct` 优先；无需 `class` / `actor`。

## 10. Test Policy

**Unit tests 免除**（本任务是纯视觉改动，无新增业务逻辑；`addSet()` 已冻结）。设计正确性由**手动 4 张截图 + design review** 承担；防回归由 `tasks.md` §A-6 grep 断言承担。

若 FS 抽取任何纯函数（非本 spec 预期），须补相应 XCTest 到 `VitalStrideTests/`。

## 11. Rollback

- 单文件回滚：`git revert <commit>` 或改回原 22 行 `addSetButton` 定义。
- 风险等级：极低。
- 兼容性：无 public API 变更，无数据 migration，watchOS / Widgets 不受影响。

## 12. Design-Time Freshness Guard

VitalStride 目前**未提供** `scripts/hooks/check-tasks-fresh` 脚本；ADR-0014 §3 提到的「设计期防腐机制」在本 repo 仅落地为约定（constitution + TL sync-check），未落地为独立可执行脚本。

本 spec 的三个文件（`spec.md` / `plan.md` / `tasks.md`）在 PR merge 后即代表 authoritative 源；后续任何 tasks 漂移由 AI Reviewer + TL 审 diff 拦截。

（此段回应 MY-1347 comment `97348ced` 的 gate 问题：hook is absent — explicitly stated per TL request.）
