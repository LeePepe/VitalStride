# Tasks — 017 Active Workout Exercise Reorder Affordance

**Parent**: MY-1344 | **spec**: `spec.md`（本目录） | **plan**: `plan.md`（本目录）
**Version**: v1 (2026-07-27)

> **Contract**: 本文件 §Files in scope / §Files NOT to touch / §Acceptance 段落**逐字复制**到对应 sub-issue description。任何漂移均视为 gate 失败。
> 本 feature 只有 1 个实现任务（app target 单文件 diff + 3 个 spec md），不需要拆分。

---

## T001 — ActiveWorkoutView 训练页新增 EditButton（复用 .onMove / moveExercises）

**Status**: stage 1, `todo`, **undispatched（等 AI Reviewer + TL 双批准后 TL 派 Dev Team）**
**Blocks**: 无
**Depends on**: 无
**Parallelizable**: 无（唯一任务）

### Files in scope
- `VitalStride/Sources/ActiveWorkoutView.swift`（app target；追加 `ToolbarItem` + `EditButton` + `exercises.count > 1` 守卫；~10 行 diff）
- `specs/017-active-workout-reorder-affordance/spec.md`（新；内容 = 本轮 handoff 附件 `my1345-spec.md`）
- `specs/017-active-workout-reorder-affordance/plan.md`（新；内容 = 本轮 handoff 附件 `my1345-plan.md`）
- `specs/017-active-workout-reorder-affordance/tasks.md`（新；内容 = 本轮 handoff 附件 `my1345-tasks.md`）

### Files NOT to touch
- `Packages/VitalModels/**`（`WorkoutExercise.swift` `order` schema 冻结）
- `Packages/HealthKitService/**`、`Packages/AIService/**`、`Packages/VitalUI/**`、`Packages/TelemetryKit/**`、`Packages/DesignKit/**`（本 feature 不跨包）
- `VitalStrideMac/**`、`VitalStrideWatch Watch App/**`、`VitalStrideWidgets/**`（其它 app targets）
- `project.yml`、`VitalStride.xcodeproj/project.pbxproj`（无 build setting / dependency 变更）
- `ActiveWorkoutView.swift` 内 `private func moveExercises(from:to:)`（复用，禁改内部）
- `ActiveWorkoutView.swift` 内 `private func deleteExercise(_:)`（保持既有 order 收口逻辑）
- `ActiveExerciseSection` / `SetRow` / `SubSetRow` 组件（不改子视图交互）

### Public signatures / API
none — internal-only change（app target 视图私有）
- 新增：`ActiveWorkoutView.body` 的 `.toolbar { ... }` 内追加一个 `ToolbarItem(placement: .topBarTrailing)`，内容为 `if exerciseCount > 1 { EditButton() }`（伪码，具体 diff FS 决定）
- 不新增 public 类型、struct、init、修饰符

### Layer 归属
- **layer**: app target（不属任何 SPM layer；per AGENTS.md "app target 只放平台入口 + UI，**不属于任何 layer**"）
- **red_lines**（§Constitution 投影）：
  - §I 健康数据隐私：本任务无 HealthKit 交互
  - §II Swift 6 strict concurrency：新增代码零并发规避（`@preconcurrency` / `@unchecked Sendable` / `nonisolated(unsafe)` 禁用）
  - §VII 范围克制：不改子视图 / schema / package / project.yml
- **test 命令**（frontmatter）：
  ```
  xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -skipPackagePluginValidation
  ```

### Verification command（executable, workdir-root-relative）

```bash
# V-1 build
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation

# V-2 既有 test 回归
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# V-3 EditButton 存在且被 exercises count > 1 守卫（检查 EditButton() 邻近上下文）
grep -nE 'EditButton\(\)' VitalStride/Sources/ActiveWorkoutView.swift
grep -nB4 -A1 'EditButton\(\)' VitalStride/Sources/ActiveWorkoutView.swift \
  | grep -Eq '(exerciseCount|exercises.*count).*>[[:space:]]*1'

# V-4 未新增第二份 moveExercises 逻辑；.onMove 仍是 1 处；且 moveExercises 函数体与 origin/main 逐行相等
[ "$(grep -cE 'private func moveExercises' VitalStride/Sources/ActiveWorkoutView.swift)" = "1" ]
[ "$(grep -cE '\.onMove[[:space:]]*\{' VitalStride/Sources/ActiveWorkoutView.swift)" = "1" ]
diff -u \
  <(git show origin/main:VitalStride/Sources/ActiveWorkoutView.swift \
      | sed -n '/^    private func moveExercises/,/^    }$/p') \
  <(sed -n '/^    private func moveExercises/,/^    }$/p' \
      VitalStride/Sources/ActiveWorkoutView.swift)

# V-5 未引入并发规避
! grep -nE '@preconcurrency|@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)' \
     VitalStride/Sources/ActiveWorkoutView.swift

# V-6 diff 严格限制在 4 个 in-scope 文件（allowlist）
test -z "$(git diff --name-only origin/main...HEAD \
  | grep -Ev '^(VitalStride/Sources/ActiveWorkoutView\.swift|specs/017-active-workout-reorder-affordance/(spec|plan|tasks)\.md)$')"

# V-7 spec/plan/tasks 三文件到位
[ -f specs/017-active-workout-reorder-affordance/spec.md ] \
  && [ -f specs/017-active-workout-reorder-affordance/plan.md ] \
  && [ -f specs/017-active-workout-reorder-affordance/tasks.md ]
```

### Functional acceptance criteria

- **AC-1**：`(workout?.exercises?.count ?? 0) > 1` 为真时训练页 `.topBarTrailing` 出现 `Edit` 按钮；tap 后 label 变 `Done`，list 每行右侧出现系统拖拽把手。
- **AC-2**：edit mode 下拖拽调换任意两个动作位置 → 松手后顺序立即更新；tap `Done` 退出 edit mode，顺序保持。
- **AC-3**：退出训练页并重新进入同一未完成 workout，动作顺序 = 最后一次拖拽结果（持久化生效，`WorkoutExercise.order` 已被更新为 0..n-1 连续值）。
- **AC-4**：`exercises.count <= 1`（空态 / 单动作）时 EditButton toolbar item 不渲染。
- **AC-5**：**兼容性**——退出 edit mode 后 `.swipeActions` 删除、section header 菜单、SetRow tap/数值键盘、FAB（addExerciseButton）全部功能未回归。
- **AC-6**：**视觉/无障碍**——深色 & 浅色下 EditButton 可读；Large Mode 切换不影响 EditButton；Dynamic Type xxxLarge 下 hit target ≥44pt（系统保障，无需自定义 frame）；VoiceOver focus 时朗读 "Edit"/"Done"（系统默认）。
- **AC-7**：**范围克制**——V-4 ~ V-6 全部通过（未改 `moveExercises` 内部、未改 packages、未改 project.yml、未改其它 app targets）。

### Manual UI checklist（FS 交付时粘到 PR body）

- [ ] 空态：无 Edit 按钮
- [ ] 1 动作：无 Edit 按钮
- [ ] ≥2 动作：出现 Edit 按钮
- [ ] tap Edit → editing / label = Done / 出现拖拽把手
- [ ] 拖 A 从 0 → 2 → 顺序更新
- [ ] tap Done → 退出 editing / 顺序保持
- [ ] 退出训练页 → 重新进入 → 顺序保持
- [ ] Large Mode toggle → Edit 仍可点
- [ ] 深色模式 → Edit 可读
- [ ] Dynamic Type xxxLarge → Edit hit target OK
- [ ] VoiceOver：朗读 Edit / Done

### Test 策略

- 无新增单元测试（SwiftUI 声明式 toolbar item + `EditButton` 无独立可单测纯逻辑；`moveExercises` 已存在且本任务不改内部）
- Xcode 既有测试 suite 走 `xcodebuild test` 保底既有回归
- Manual UI checklist 11 条为最终验收
- 若未来要加 UI 自动化测试，另立 issue（超本任务范围）

---

## 后续（本 feature 之外）

- 若想为 reorder 加埋点（`Telemetry.exerciseReordered(fromIndex:toIndex:)`），另立 issue
- 若想加自动化 UI 测试覆盖 EditMode + drag，另立 issue
- 组内 SetRow 重排（parent 显式 out-of-scope）→ 另立 issue

