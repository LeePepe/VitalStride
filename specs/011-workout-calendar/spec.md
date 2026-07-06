# Feature Specification: 训练历史日历视图

**Feature Branch**: `011-workout-calendar`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-908（[PM][Strong] 训练历史增加日历视图）。训练历史只有 List 视图，缺日历打点。Strong 的 Workout Calendar 是高频功能。000-baseline 未覆盖（grep 无日历组件），故立 feature spec。

**Related Issue**: [MY-908](multica://issue/MY-908)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 日历视图快速感知训练日 (Priority: P1)

用户希望在训练历史切换到日历视图，一眼看到"这个月哪些天练了"，而非只能滚动列表。

**Why this priority**: 核心价值——按月聚合的训练日视觉感知。复用现有训练数据，纯 UI 新增，不改数据层。

**Independent Test**: 训练历史 toolbar 切到日历 → 当月有训练的日期高亮 → 点某天 → 显示那天的训练 → 点进详情。

**Acceptance Scenarios**:

1. **Given** 有训练历史，**When** toolbar 切到日历视图，**Then** LazyVGrid 月历渲染，有训练的日期背景上色。
2. **Given** 日历视图，**When** 点有训练的日期，**Then** 显示那天训练列表，点击进 `WorkoutDetailView`。
3. **Given** 切换过视图模式，**When** 离开再回训练 tab，**Then** 保持上次视图模式（`@SceneStorage` 持久化），默认 List。

### Edge Cases

- 一天多次训练：点击展开列表。
- 跨月导航（上/下月切换）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `WorkoutListView` toolbar MUST 提供 List/日历切换（segmented picker）。
- **FR-002**: 日历视图 MUST 用 LazyVGrid(7 列) 渲染当月，有训练的日期高亮，支持月份切换。
- **FR-003**: 点击有训练的日期 MUST 显示当天训练，可进详情。
- **FR-004**: 视图模式 MUST 用 `@SceneStorage` 持久化，默认 List（不改变现有默认行为）。
- **FR-005**: 日历数据 MUST 复用现有训练查询（按 `Calendar.current.startOfDay` 分组），不新增数据层。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- 无新数据模型。新增视图 `WorkoutCalendarView` + `ViewMode` enum（list/calendar）。

## Success Criteria *(mandatory)*

- **SC-001**: 日历正确高亮所有有训练的日期。
- **SC-002**: 点击日期能进入当天训练详情。
- **SC-003**: 视图模式跨会话持久化，默认 List。

## Assumptions

- 用 LazyVGrid 自绘月历（选项 A，issue 推荐），非 DatePicker（不支持自定义高亮）。
- 复用 `unifiedWorkouts`（SwiftData + HealthKit 双源）。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 训练列表 | `VitalStride/Sources/WorkoutListView.swift:10-196` |
| 新日历视图 | `VitalStride/Sources/WorkoutCalendarView.swift`（新建） |
| 统一训练源 | `WorkoutListMerger` / `UnifiedWorkout` |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
