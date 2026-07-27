# Feature Spec: ActiveExerciseSection「添加一组」按钮视觉重设计

**Spec ID**: 017-add-set-button-redesign
**Status**: Ready for planning review
**Origin**: Multica MY-1343 (parent) → MY-1348 (implementation) · Planning gate MY-1347
**Constitution refs**: §VII 范围克制、Cross-cutting: DesignKit tokens、Cross-cutting: 交互契约冻结

---

## 1. Background & Motivation

用户反馈：「添加一组的按钮看着也很奇怪，重新设计。」

当前实现（`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:221-242`）
是一个 `.borderless` 左对齐的平铺 List row：`plus.circle.fill` icon + 「添加一组」文案，
`.font(.subheadline)`、`frame(maxWidth: .infinity, alignment: .leading)`、`minHeight: 36`。
它作为每个动作 section 的最后一行出现，与上方 SetRow 数据行、下方 section 分隔视觉混同，
缺少「这是可点击的新增操作」的清晰信号，观感突兀/廉价。

本 spec 在**不改交互契约**的前提下重设计视觉，使其：
- 具备明确「可点击的次要操作」定位——一眼识别，但不抢过 SetRow 数据主体；
- 与 SetRow / section header / MY-1263 (D2) 建立的紧凑行密度节奏（normal ~36pt）协调；
- Large Mode (`activeWorkoutLargeMode`) 下同样协调（保留其更宽松的 padding 节奏）；
- 深/浅色主题下均通过 WCAG AA 对比度。

## 2. Scope

### 2.1 In scope

1. 重设计 `ActiveExerciseSection.addSetButton` 视觉（`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`）。
2. 走 DesignKit 现有 token（primary / neutrals / Radius / Space / TypeScale），零硬编码颜色 / 圆角 / 字号魔法数。
3. 覆盖 Normal + Large Mode 两种密度。
4. 覆盖 Light + Dark 两种主题。
5. Preview 覆盖 4 态：{normal, large} × {light, dark}。
6. 4 张 before/after 截图 + design review。
7. 落库本 spec 的三个文件（spec.md / plan.md / tasks.md）。

### 2.2 Out of scope

- `addSet()` 数据逻辑、`addSubSet()`、`copyToNext()`、`deleteSet()` — 不改。
- 「添加动作」FAB（`addExerciseButton`）— 独立 issue。
- 其它 List row（SetRow / SubSetRow / section header）— 不改。
- DesignKit 新增 token 或组件 — 禁。
- watchOS UI — 不在本 issue。
- 埋点调用点（`TelemetryService.shared.track(...)` / `Telemetry.*`）— 不改。

## 3. Interaction Contract (frozen — 红线)

以下四条为**冻结契约**，任何修改视为 spec 违规：

1. **点击行为**：点击 → `addSet()`。函数体不变，追加逻辑不变（沿用上一 main set 的 `weight` / `reps` / `setType` / `isUnilateral` / `weightRight`）。
2. **a11y label**：`.accessibilityLabel(String(localized: "添加一组", ...))` 保留。
3. **a11y hint**：`.accessibilityHint(String(localized: "在列表末尾插入新的一组", ...))` 保留。
4. **hit target**：≥ 44 × 44pt（`.frame(minHeight: 44)`）。本次从当前 `minHeight: 36` **提升到 44**，对齐 Apple HIG。

位置约束：仍在 List section 内，作为该 exercise 的最后一行。

## 4. Functional Requirements

- **FR-1** — 视觉具备明确「可点新增」识别度；FS 从下列 3 种 design direction 中自选一种落地：
  - **(a) Subtle-fill 行内按钮**（推荐）：`theme.primary.primarySubtle` 背景 + `Radius.inner` 圆角 + 水平/纵向 padding + `theme.primary.primaryText` 前景 + icon。
  - **(b) Dashed-border chip**：透明背景 + `theme.primary.primaryBorder` 1pt dashed stroke + `Radius.inner`。
  - **(c) Primary-tinted 图标 + 强化文本**：在现结构基础上升级为 `theme.primary.primary` 前景 + `.font(.callout.weight(.medium))`。
  - PR body 或 handoff comment 中说明所选 direction 及理由（design review 依据）。
- **FR-2** — 仅消费 DesignKit 现有 token（primary / neutrals / Radius / Space / TypeScale）。禁 `Color(red:green:blue:)` / `Color(hex:)` / `#RRGGBB` literal / `Font.system(size: N)` 魔法数 / 硬编码圆角常量。
- **FR-3** — `largeMode` 保留原有 2pt breathing 节奏或按新设计需要放宽；normal 保留 MY-1263 (D2) 紧凑节奏或按新设计需要微调。
- **FR-4** — hit target `.frame(minHeight: 44)`（本次从 36 提升到 44，HIG 硬要求）。
- **FR-5** — 采用具备按下态反馈的 `.buttonStyle`（`.borderless` 无 pressed feedback，需替换；可自定义 `AddSetButtonStyle: ButtonStyle` 在同文件内 `private` 声明）。
- **FR-6** — Dark mode 下 subtle-fill 背景与前景对比度 ≥ WCAG AA。

## 5. Non-Functional Requirements

- Swift 6 strict concurrency（若引入 `ButtonStyle` 需 `Sendable`；`struct` 优先）。
- 无硬编码中文字符串（复用现有 `String(localized: "添加一组", ...)` / `String(localized: "在列表末尾插入新的一组", ...)`）。
- 无健康数值触及（宪法 §I 无风险；本 UI 不接触 HealthKit）。
- 不新增独立文件；若引入自定义 `ButtonStyle`，在 `ActiveExerciseSection.swift` **同文件底部** `private` 声明。
- 不新增 target / dependency（`project.yml` / `.xcodeproj` 不改）。

## 6. Acceptance / Verification

### 6.1 Automatic (executable — 见 `tasks.md` A-1..A-9)

- iOS + macOS build 通过（`xcodebuild build ... -destination generic/...`）。
- 无并发规避（`@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)` 在改动文件中新增）。
- 无硬编码颜色（`Color(red:` / `Color(hex:` / `#RRGGBB`）。
- 无新增字体魔法数（diff 内新增行不得含 `Font.system(size:`）。
- 交互契约防回归（`addSet` / a11y label / a11y hint / hit target ≥44 grep 断言）。
- diff 范围硬限（只碰 `ActiveExerciseSection.swift` + 3 个 spec 文件）。
- spec 三文件存在。

### 6.2 Manual (PR body 必须包含)

- **AC-M1**：4 张 before/after 截图，覆盖 `{normal, large} × {light, dark}`（iPhone 16 Simulator）；并排 before/after，标注 design direction。
- **AC-M2**：一句话说明所选 design direction（a/b/c）及理由。
- **AC-M3**：手动点击回归——真实 workout 触发一次 addSet，确认新组沿用上一 main set 的 `weight` / `reps` / `setType` / `isUnilateral` / `weightRight`。

### 6.3 Design Review

走 AI Reviewer + design-reviewer sub-agent（若可用），CHANGES REQUESTED 时 FS 迭代。关注点：

- 「可点新增」视觉信号清晰（区别于 SetRow 数据行）；
- 与 SetRow / section header hierarchy 协调；
- Large Mode 不拥挤 / 不过大；
- 深浅色对比度 WCAG AA。

## 7. Rollout

单 stage、单 task（MY-1348）。走 Fullstack Engineer PR pipeline → PR 提交 → required CI 全绿 → auto-merge squash。

## 8. Risk / Rollback

- **风险**：极低。单文件、UI-only、无数据 migration、无 public API 变更。
- **回滚**：`git revert` 单 commit，或改回原 22 行 `addSetButton` 定义。
