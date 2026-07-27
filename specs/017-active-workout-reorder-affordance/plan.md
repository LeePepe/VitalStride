# Implementation Plan — 017 Active Workout Exercise Reorder Affordance

**Parent issue**: MY-1344
**Sub-issue (impl)**: T001 — implementation issue key assigned by Team Lead after dual approval
**Spec**: `specs/017-active-workout-reorder-affordance/spec.md`
**Version**: v1 (2026-07-27)

## 1. Approach 概览

一次性最小 diff：在 `VitalStride/Sources/ActiveWorkoutView.swift` 的 `.toolbar` 里追加一个 `ToolbarItem`（`placement: .topBarTrailing`），当 `exercises.count > 1` 时渲染 SwiftUI `EditButton()`。SwiftUI 的 EditMode 环境值自动传播到 `List` → 系统在每行右侧渲染拖拽把手 → 用户拖拽触发已有 `.onMove` → 复用已有 `moveExercises(from:to:)`。

不改：`WorkoutExercise` schema、`moveExercises` 内部、`deleteExercise` 内部、`ActiveExerciseSection` 交互、FAB 逻辑、任何 SPM package。

## 2. Layer / File Impact

| Layer | 文件 | 变更类型 | 说明 |
|---|---|---|---|
| app target | `VitalStride/Sources/ActiveWorkoutView.swift` | ~10 行 SwiftUI 声明式代码 | 新增 `ToolbarItem` + `EditButton` + `exerciseCount > 1` 守卫；顺便把 `let exerciseCount = workout?.exercises?.count ?? 0` 提到 body 可用位置（若需要）。 |
| docs | `specs/017-active-workout-reorder-affordance/spec.md` | 新文件 | 从本 handoff 附件复制 |
| docs | `specs/017-active-workout-reorder-affordance/plan.md` | 新文件 | 从本 handoff 附件复制 |
| docs | `specs/017-active-workout-reorder-affordance/tasks.md` | 新文件 | 从本 handoff 附件复制 |

**不动**：
- `Packages/VitalModels/**`（含 `WorkoutExercise.swift` 的 `order` 属性）
- `Packages/HealthKitService/**`、`Packages/AIService/**`、`Packages/VitalUI/**`、`Packages/TelemetryKit/**`、`Packages/DesignKit/**`
- `VitalStrideMac/**`、`VitalStrideWatch Watch App/**`、`VitalStrideWidgets/**`
- `project.yml`、`VitalStride.xcodeproj/project.pbxproj`（不动 target 配置）
- `ActiveWorkoutView.swift` 内的 `moveExercises`、`deleteExercise`、`ActiveExerciseSection`、`workoutTimer`、`sessionStatsCard`、`compactInfoBand`、`exerciseList` 内部 List 结构

## 3. Design Decision — 为什么用 `EditButton`

Parent issue 指定「iOS 惯用法优先」，候选：
1. **`EditButton()` 在导航栏**（← 选中）：iOS 原生入口，SwiftUI 一行；自动切换 label；系统渲染拖拽把手；VoiceOver / Dynamic Type / 深浅色全部自动适配；范围最小；不新增手势耦合。
2. 长按拖拽（`.onLongPressGesture` + custom drag）：与 `.onMove` 语义重合但需自绘 handle；破坏 List 内其他手势；范围大。
3. Section header 菜单项「编辑顺序」：需扩 header UI；用户可发现性弱于 toolbar。

选 1，符合 §VII 范围克制 + parent 「iOS 惯用法优先」+「入口 hit target ≥44pt / VoiceOver 可用」验收标准（系统 EditButton 均已保证）。

## 4. Interaction 兼容性梳理（不写代码，只做设计断言）

| 交互 | Non-editing | Editing | 说明 |
|---|---|---|---|
| Row `.swipeActions` 删除 | 生效（滑出红色 Delete） | 系统改成 leading 删除圆圈 | SwiftUI 原生行为，无需干预 |
| Section header 菜单（Replace / Substitute / Delete） | 生效 | 用户不会点；即便点也无害 | 不 disable，避免超范围 |
| SetRow tap / 数值键盘 | 生效 | 用户不会点；即便点也无害 | 不 disable |
| FAB (`addExerciseButton`) | 生效 | 仍生效 | 允许 edit 中继续新增动作 |
| Large Mode toggle | 生效 | 生效 | 独立 toolbar item，不冲突 |
| 放弃 / 结束训练 toolbar | 生效 | 生效 | 独立 placement |

## 5. Toolbar Item 顺序（`.topBarTrailing`）

现状：只有 Large Mode toggle 在 `.topBarTrailing`。追加 EditButton 后（按声明顺序）：
```
[cancellationAction: 放弃]  …title…  [topBarTrailing: Edit]  [topBarTrailing: Aa toggle]  [confirmationAction: 结束训练]
```
EditButton 声明**放在** Large Mode toggle 之前——阅读顺序左→右为 Edit → Aa，视觉次序稳定。

## 6. Test Strategy

- 无新增单元测试：SwiftUI 声明式 toolbar item + `EditButton` 没有可单元测的纯逻辑；`moveExercises` 逻辑不变（原本也未单测，属既有 gap，不在本任务扩大范围）。
- xcodebuild build + test：走 pre-push hook 已跑的 `xcodebuild test` 保底既有回归。
- 手动 UI checklist：spec §7 列出 11 条；FS 交付时逐条勾选粘到 PR body。

若日后想为 reorder 加自动化 UI 测试，另立 issue（超本任务范围）。

## 7. Risks & Mitigations

| Risk | 概率 | 缓解 |
|---|---|---|
| SwiftData 未在 EditMode 之外触发 autosave，退出后顺序丢失 | 低 | `WorkoutExercise` 是 `@Model`，`order` 属性变更由 `modelContext` 自动持久化；如观察到问题则显式 `try? modelContext.save()` 但**不作为默认改动**（silent_model_save 规则约束）。手动 checklist 有「退出重进」步骤兜底。 |
| List style（`.plain`）不显示拖拽把手 | 低 | `.plain` List 支持 `.onMove` 与 EditMode 拖拽把手（iOS 16+）；如实测缺失，追加 `.environment(\.editMode, ...)` 显式驱动。 |
| EditMode 期间 SetRow 内部自定义手势冲突 | 低 | `ActiveExerciseSection`/`SetRow` 属于既有代码；如冲突则该问题独立于「加 EditButton」，另立 issue。 |
| Dynamic Type xxxLarge 下 toolbar 过挤 | 低 | 系统 ToolbarItem 自动 truncate/wrap；本任务不新增 `.frame` 覆盖。 |

## 8. Rollout / Backout

- 单一 PR，单文件源码改动（+ 3 spec 文件）。
- Backout = revert 单个 commit；无 schema / persistence 变更需要迁移。

