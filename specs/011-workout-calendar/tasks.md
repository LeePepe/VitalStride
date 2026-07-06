---
description: "Task list for 训练历史日历视图"
---

# Tasks: 训练历史日历视图

**Input**: Design documents from `/specs/011-workout-calendar/`

**Prerequisites**: [plan.md](./plan.md)（required）, [spec.md](./spec.md)（user stories）

**Tests**: 本 feature 含测试任务（day-grouping helper 单元测试 + 持久化默认值验证），依据 spec Acceptance Scenarios + Constitution Bar I。

**Organization**: 单一 User Story（US1 P1），按 phase 组织，交付即 MVP。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[US1]**: 归属 User Story 1
- 所有路径为仓库根相对真实路径

---

## Phase 1: Setup

**Purpose**: 确认复用锚点，无新工程配置

- [ ] T001 [US1] 确认 `VitalStride/Sources/WorkoutListView.swift:10-196` 结构：toolbar 位置、`unifiedWorkouts` 计算属性、List 分区渲染，标定 segmented picker 与日历模式的插入点
- [ ] T002 [US1] 确认统一训练源形状：`VitalStride/Sources/WorkoutListMerger.swift` 的 `merge` 产出 `[UnifiedWorkout]`，`VitalStride/Sources/Models/UnifiedWorkout.swift` 暴露 `startDate` / `displayTitle`，作为日历分组输入

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 日历模式与列表模式都依赖的视图模式枚举 + 分组能力

**⚠️ CRITICAL**: US1 实现前必须完成

- [ ] T003 [US1] 在 `VitalStride/Sources/WorkoutCalendarView.swift` 定义 `ViewMode` enum（`list` / `calendar`，`String` raw、`CaseIterable`，供 `@SceneStorage` 与 segmented picker 使用）
- [ ] T004 [US1] 在 `VitalStride/Sources/WorkoutCalendarView.swift` 实现纯函数 day-grouping helper：把 `[UnifiedWorkout]` 按 `Calendar.current.startOfDay(for:)` 分组为 `[Date: [UnifiedWorkout]]`（FR-005，可测试、无副作用、不新增数据层）

**Checkpoint**: 视图模式与分组就绪，US1 可开工

---

## Phase 3: User Story 1 - 日历视图快速感知训练日 (Priority: P1) 🎯 MVP

**Goal**: toolbar 切到日历 → 当月训练日高亮 → 点日期看当天训练 → 进详情；视图模式跨会话持久化默认 List。

**Independent Test**: 训练 tab toolbar 切日历 → 当月有训练日期背景上色 → 点某天展开当天训练 → 进 `WorkoutDetailView`；离开再回保持上次模式。

### Tests for User Story 1 ⚠️（先写，先 FAIL）

- [ ] T005 [P] [US1] day-grouping helper 单元测试：跨天/同天多次训练/空输入下按 `startOfDay` 正确分组，桶计数与键正确（对应 T004；`VitalStrideTests/Sources/` 目录源引用自动包含）
- [ ] T006 [P] [US1] 视图模式持久化默认值验证：`@SceneStorage` 缺省解析为 `.list`（SC-003 / FR-004，断言默认 raw 值映射到 List）

### Implementation for User Story 1

- [ ] T007 [US1] `VitalStride/Sources/WorkoutListView.swift` toolbar 增加 List/日历 segmented `Picker`，绑定 `@SceneStorage` 视图模式（FR-001）；日历模式渲染 `WorkoutCalendarView`，列表模式保持现有 List 不变
- [ ] T008 [US1] `VitalStride/Sources/WorkoutListView.swift` 加 `@SceneStorage` 视图模式状态，默认 `.list`，不改变现有列表默认行为（FR-004 / SC-003）
- [ ] T009 [US1] `VitalStride/Sources/WorkoutCalendarView.swift` 实现 `LazyVGrid`（7 列）当月月历渲染：星期表头 + 当月日期格子，用 T004 分组结果把有训练日期背景高亮（FR-002 / SC-001）
- [ ] T010 [US1] `VitalStride/Sources/WorkoutCalendarView.swift` 月份导航：上/下月切换按钮 + 当前月份标题，切月后重算高亮（FR-002，Edge Case 跨月导航）
- [ ] T011 [US1] `VitalStride/Sources/WorkoutCalendarView.swift` 点击有训练日期 → 展开当天训练列表（含一天多次训练全部列出，Edge Case），每条经 `NavigationLink` 进 `WorkoutDetailView`（FR-003 / SC-002）
- [ ] T012 [P] [US1] `VitalStride/Resources/Localizable.xcstrings` 新增月历 UI 字符串（视图切换 label、月份/星期标题、日期无障碍标签），全部 `String(localized:)` 引用，无同名 `.strings` 共存（FR-006 / Constitution VI / Bar G）

**Checkpoint**: US1 完整可独立测试——List/日历切换、高亮、点日期进详情、模式持久化均可用

---

## Phase N: Polish & Cross-Cutting Concerns

- [ ] T013 [P] [US1] `VitalStride/Sources/WorkoutCalendarView.swift` 新增 ≥2 个 SwiftUI Preview（有训练数据 / 无训练数据两态，Bar I）
- [ ] T014 [US1] Accessibility 核查（Bar H）：日历日期 cell 与上/下月导航按钮 hit target ≥44pt；日期 cell 提供无障碍标签（"X 月 Y 日，N 次训练"）；装饰性高亮 `accessibilityHidden` 不重复宣读

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup —— BLOCKS US1
- **User Story 1 (Phase 3)**: 依赖 Foundational 完成
- **Polish (Phase N)**: 依赖 US1 完成

### Within User Story 1

- Tests（T005–T006）先写并 FAIL，再实现
- T003（ViewMode）+ T004（分组 helper）→ T007–T011
- T007（toolbar 切换）依赖 T003；T009–T011（日历渲染/导航/点选）依赖 T004
- T008 依赖 T003；T012 xcstrings 可与实现并行（不同文件）

### Parallel Opportunities

- T005 / T006 测试任务标 [P]，可并行
- T012（xcstrings）与视图实现不同文件，可并行
- T013（Previews）与 T014（a11y 核查）可并行
- 注意：T007–T011 多数改同一 `WorkoutCalendarView.swift` / `WorkoutListView.swift`，不标 [P]，顺序执行避免同文件冲突

---

## Parallel Example: User Story 1

```bash
# 先并行跑两个测试（应 FAIL）：
Task: "day-grouping helper 单元测试 in VitalStrideTests/Sources/"
Task: "视图模式持久化默认值验证（默认 List）"

# 实现期间 xcstrings 可与视图并行：
Task: "Localizable.xcstrings 新增月历字符串（FR-006）"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Phase 1 Setup：确认复用锚点
2. Phase 2 Foundational：ViewMode + 分组 helper（CRITICAL，阻塞 US1）
3. Phase 3 US1：toolbar 切换 → 日历渲染 → 点日期进详情 → 持久化
4. **STOP & VALIDATE**：按 Independent Test 独立验收
5. Phase N Polish：Previews + a11y 核查后交付

---

## Notes

- [P] = 不同文件、无依赖；同文件任务顺序执行
- 引用 Cross-Cutting Quality Bars：**Bar H**（Accessibility：hit target ≥44pt）、**Bar I**（新 view ≥2 Preview + 分组 helper 单元测试）、**Bar G**（i18n 无硬编码，走 xcstrings 单源）
- 纯 UI 新增，零数据层改动（FR-005）；不改现有 List 默认行为（FR-004）
- 无 git / xcodebuild 步骤由本 tasks 触发——交 Multica pipeline 执行
