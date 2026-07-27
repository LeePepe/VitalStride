# Feature Spec — 017 Active Workout Exercise Reorder Affordance

**Parent issue**: MY-1344
**Planning issue**: MY-1345
**Constitution refs**: §II Swift 6 strict concurrency、§V narrow 例外（无新例外）、§VII 范围克制
**ADR refs**: 无新增（复用 iOS 原生 EditMode）
**Version**: v1 (2026-07-27)

## 1. Background & Motivation

- `VitalStride/Sources/ActiveWorkoutView.swift` 的动作 `List / ForEach(exercises)` **已挂 `.onMove`**（约 722 行）并复用 `moveExercises(from:to:)`（约 1086 行），后者已经把重排结果写回 `WorkoutExercise.order`。
- 但整个视图 `grep EditButton|editMode|isEditing` 为空——**没有任何让用户进入拖拽重排的 UI affordance**。所以用户当前**不能** 更换动作顺序（这就是 MY-1344 的用户诉求）。
- 结论：底层数据 & SwiftUI 交互都齐了，缺的是「让用户触发重排」的入口。目标最小：在训练页导航栏加 iOS 惯用的 `EditButton`，进入 edit mode 时启用系统拖拽把手，其余交互不动。

## 2. In Scope

1. `VitalStride/Sources/ActiveWorkoutView.swift`：
   - 在训练页 `.toolbar` 里新增一个 `ToolbarItem`（放在 `.topBarTrailing`，与 Large Mode toggle 同侧）承载 `EditButton()`。
   - 当 `exercises.count > 1` 才显示该按钮（单动作时隐藏）。
   - 沿用已有 `.onMove { moveExercises(...) }`——不重写排序逻辑。
   - 保证 EditMode 状态**不干扰** `.swipeActions` 删除、section header 菜单、SetRow 内 tap/editing、以及 FAB（`safeAreaInset` 里的 addExerciseButton）。
2. 手动 UI 验证：进入训练 → 添加 ≥2 动作 → 点 Edit → 拖拽调换顺序 → 点 Done → 退出训练页 → 重新进入 → 顺序保持。
3. `specs/017-active-workout-reorder-affordance/{spec.md, plan.md, tasks.md}` — 归 T001 提交（内容 = 本 handoff 附件，落库时去掉 `my1345-` 文件名前缀）。

## 3. Out of Scope (explicit)

- **`WorkoutExercise` schema 或 `order` 属性任何改动**（VitalModels layer 冻结，不属本任务）
- **`moveExercises(from:to:)` 内部实现改动**（已实现，直接复用）
- **`deleteExercise` 的 order 收口逻辑改动**（已实现）
- **组内 `SetRow` / `SubSetRow` 的重排**（parent 显式 out-of-scope）
- **跨 workout / 模板（`WorkoutTemplate` / `TemplateExercise`）的排序**（parent 显式 out-of-scope）
- **新增拖拽手柄自定义 UI**（用系统 EditMode 提供的默认拖拽把手，`iOS 原生惯用法优先` per parent）
- **watchOS / macOS**（ActiveWorkoutView 仅 iOS 消费；watchOS `WatchInWorkoutView` 独立文件，不动）
- **埋点新增**（本 feature 不新增 TelemetryEvent；如需 `exerciseReordered` 事件另立 issue）

## 4. Interfaces / Behavior Contract

- **UI 入口**：`ToolbarItem(placement: .topBarTrailing)` 内 `EditButton()`；label 由 SwiftUI 系统提供（"Edit" / "Done" / 已本地化）。
- **可见性守卫**：SwiftUI conditional，只在 `(workout?.exercises?.count ?? 0) > 1` 时渲染该 ToolbarItem。
- **拖拽驱动**：进入 edit mode 后，List row 自动出现系统拖拽把手（`InsetGroupedListStyle` / `.plain` 均支持 `.onMove`）。既有 `.onMove { source, destination in moveExercises(from: source, to: destination) }` 无需修改。
- **持久化**：`moveExercises` 已把新 `order` 赋值到 `WorkoutExercise.order`；由 SwiftData `modelContext` 的既有自动写入保障退出重进后顺序保持——**本任务不新增 `try? modelContext.save()` 调用**（避免与既有 `silent_model_save` swiftlint 规则冲突，也保持 §VII 范围克制）。
- **兼容性**（不得破坏）：
  - `.swipeActions` 删除：EditMode 下 SwiftUI 系统会把 swipe 让位给系统删除圆圈，本身兼容；exit edit mode 后 swipe 恢复。
  - Section header 菜单 / SetRow tap / 数值键盘：仅在非 editing 状态生效，EditMode 期间用户不会去点它们，且不需要显式禁用。
  - FAB：`safeAreaInset` 里的 addExerciseButton **保持可点**（用户可能想在 editing 中新增动作后立即拖拽——不新增 EditMode-gated 隐藏，避免超范围）。

## 5. Functional Requirements

- **FR-1**：训练页顶部导航右侧出现 `Edit` 按钮（≥2 动作时）；tap 后进入 edit mode，按钮文字变为 `Done`；再 tap 退出。
- **FR-2**：edit mode 下，动作 List 每行右侧显示系统拖拽把手；用户拖动改变顺序后释放，`moveExercises(from:to:)` 触发，`WorkoutExercise.order` 被更新为 0..n-1 连续值。
- **FR-3**：退出训练页并重新进入同一 workout，动作顺序与最后一次拖拽结果一致（持久化验证）。
- **FR-4**：`exercises.count <= 1` 时 EditButton `ToolbarItem` 不渲染（`if exerciseCount > 1 { ... }` 守卫）。
- **FR-5**：EditButton 与既有 `.cancellationAction`（放弃）/ Large Mode toggle / `.confirmationAction`（结束训练）三个 ToolbarItem **不冲突**：placement 分工 + SwiftUI 自动布局；相同 side 时按声明顺序排列，视觉上 Edit 在 Large Mode toggle **之前**（先出现）。
- **FR-6**：EditButton hit target ≥44pt（SwiftUI ToolbarItem 默认满足；不新增 `.frame` 覆盖）。VoiceOver：SwiftUI `EditButton` 自带标准 accessibility label（"Edit" / "Done"），本任务不覆盖。
- **FR-7**：深/浅色 & Large Mode：EditButton 使用系统 tint，自动适配；Large Mode 只影响 timer/summary/list 字号，不影响 toolbar 布局；本任务不新增 Large Mode 分支。

## 6. Non-Functional Constraints

- **Swift 6 strict concurrency**：新增代码零 `@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)`（本任务仅新增 SwiftUI 视图声明式代码，不引入并发问题）。
- **红线**：§I 健康数据隐私——本任务不涉及 HealthKit 数值或日志；`moveExercises` 内部亦无日志。
- **范围克制（§VII）**：只加 ToolbarItem + 可见性守卫；不改 List 结构、`ActiveExerciseSection`、`moveExercises` 内部、`WorkoutExercise` schema。
- **本地化**：EditButton 是系统 label，无需新增 zh-Hans/en 字符串。

## 7. Acceptance / Verification (manual UI checklist + build)

```
# A-1 app target build（本任务改 app target 源，走 xcodebuild；不改 project.yml，无需 xcodegen）
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation

# A-2 app target test（既有测试不能回归）
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# A-3 静态断言：新增 EditButton toolbar item 存在且被 count>1 守卫（检查 EditButton() 邻近上下文）
grep -nE 'EditButton\(\)' VitalStride/Sources/ActiveWorkoutView.swift
grep -nB4 -A1 'EditButton\(\)' VitalStride/Sources/ActiveWorkoutView.swift \
  | grep -Eq '(exerciseCount|exercises.*count).*>[[:space:]]*1'

# A-4 未引入并发规避
! grep -nE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources/ActiveWorkoutView.swift

# A-5 未新增第二份 moveExercises（复用；1 处定义 + 1 处 .onMove）
[ "$(grep -cE 'private func moveExercises' VitalStride/Sources/ActiveWorkoutView.swift)" = "1" ]
[ "$(grep -cE '\.onMove[[:space:]]*\{' VitalStride/Sources/ActiveWorkoutView.swift)" = "1" ]

# A-6 diff 严格限制在 4 个 in-scope 文件（含未改 WorkoutExercise schema）
test -z "$(git diff --name-only origin/main...HEAD \
  | grep -Ev '^(VitalStride/Sources/ActiveWorkoutView\.swift|specs/017-active-workout-reorder-affordance/(spec|plan|tasks)\.md)$')"
```

**Manual UI checklist（build 通过后跑一次）**：
- [ ] 冷启动 → 开始新训练（blank）→ 空态无 Edit 按钮
- [ ] 添加 1 个动作 → 无 Edit 按钮（`> 1` 守卫）
- [ ] 添加第 2 个动作 → 出现 Edit 按钮
- [ ] tap Edit → 进入 editing，行右侧出现系统拖拽把手，label 变 Done
- [ ] 拖拽把动作 A 从位置 0 拖到位置 2 → 释放；顺序立刻更新
- [ ] tap Done → 退出 editing；顺序保持；swipe 删除仍可用
- [ ] 退出训练页（返回上级 tab）→ 从 History 或继续未完成训练重新进入同一 workout → 顺序仍为拖拽后的结果
- [ ] Large Mode 切换（textformat.size toggle）→ Edit 按钮仍存在、可点
- [ ] 深色模式（Settings → Dark）→ Edit 按钮可读、tint 正常
- [ ] Dynamic Type xxxLarge → Edit 按钮 hit target 仍 ≥44pt（系统保障）
- [ ] VoiceOver on → focus Edit 按钮时朗读 "Edit"，激活后朗读 "Done"

## 8. Open Questions / Risks

- **EditMode 与 SwipeActions 交互**：iOS 系统语义为 EditMode 时 swipe delete 被删除圆圈取代——**不需要**手动 disable；已由 SwiftUI 系统处理。
- **EditMode 与 FAB 覆盖**：FAB 在 `safeAreaInset` 里位于底部，与 editing 状态无耦合；无覆盖风险。
- **iPad / Landscape**：ActiveWorkoutView 目前主用于 iPhone；ToolbarItem 布局在 iPad 亦有效——不特别测试。
- **watchOS 无变更**：`WatchInWorkoutView` 独立，非本任务范围。

