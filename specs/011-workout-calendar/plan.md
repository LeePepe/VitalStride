# Implementation Plan: 训练历史日历视图

**Branch**: `011-workout-calendar` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-workout-calendar/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

在 `WorkoutListView` toolbar 增加 List/日历 segmented toggle。日历模式用 `LazyVGrid`（7 列）自绘当月月历，把当月有训练的日期背景高亮，支持上/下月导航；点某一天 → 展开当天训练列表 → 进 `WorkoutDetailView`。视图模式用 `@SceneStorage` 跨会话持久化，默认 List（保持现有默认行为）。日历数据完全复用现有统一训练查询（`WorkoutListMerger.merge` 产出的 `[UnifiedWorkout]`），按 `Calendar.current.startOfDay` 分组，不新增任何数据层 / SwiftData model。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency，见 Constitution II）

**Primary Dependencies**: SwiftUI（`LazyVGrid` 月历栅格、`@SceneStorage` 视图模式持久化、`Picker(.segmented)` toolbar 切换）+ 现有 `WorkoutListMerger` / `UnifiedWorkout` 统一训练源

**Storage**: 无新增。复用 `WorkoutListView` 现有 `@Query workouts` + HealthKit records 经 `WorkoutListMerger.merge` 得到的 `unifiedWorkouts`，按 `Calendar.current.startOfDay` 分组（纯内存派生，FR-005）

**Testing**: XCTest（day-grouping 纯函数分组 helper 单元测试）+ SwiftUI Preview（`WorkoutCalendarView` ≥2 预览）

**Target Platform**: iOS 18+（`project.yml options.deploymentTarget`）

**Project Type**: mobile app（iOS 主 target；macOS/watchOS companion，见 Constitution VII，本 feature 仅 iOS）

**Performance Goals**: 月历渲染流畅（一屏 ≤42 格 cell，`LazyVGrid` 懒加载）；切换视图模式无可感延迟

**Constraints**: 纯 UI 新增，零数据层改动；不引入新依赖；不改变现有 List 默认行为（FR-004）

**Scale/Scope**: 1 个新视图文件 + 1 个 `ViewMode` enum + `WorkoutListView` toolbar 一处 diff + xcstrings 若干新 key

## Constitution Check

*GATE: Phase 0 前必须通过，Phase 1 设计后复查。*

| 关注点 | 结论 |
|--------|------|
| Principle VI（i18n 单源） | 新增 UI 字符串全部走 `String(localized:)` 引用 `Localizable.xcstrings`（月份/星期标题、视图切换 label、日期无障碍标签），无同名 `.strings` 共存。✅ |
| Bar H（Accessibility） | 日历日期 cell hit target ≥44pt；上/下月导航按钮 ≥44pt；日期 cell 提供无障碍标签（"X 月 Y 日，N 次训练"）；装饰性高亮不单独宣读。✅ |
| Bar I（Tests/Previews） | day-grouping helper 为纯函数，附单元测试；`WorkoutCalendarView` ≥2 个 Preview（有训练 / 无训练）。✅ |
| Principle I（健康隐私） | 日历仅按日期聚合，不展示 / 不记录任何 HealthKit 数值；无日志。无隐私面。✅ |
| 新数据模型 / ADR | 无新 SwiftData model、无新 package、无 provider 变更 → 不需要 ADR。✅ |

**行为回归说明**：FR-004 要求 `@SceneStorage` 默认值为 List，等同现有唯一行为——日历为纯增量入口，不改变既有列表默认，无行为回归。

## Project Structure

### Documentation (this feature)

```text
specs/011-workout-calendar/
├── spec.md              # Feature 规格（已存在）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
VitalStride/
├── Sources/
│   ├── WorkoutListView.swift          # 现有列表视图（锚点 :10-196）
│   │                                  #   → toolbar 增加 List/日历 segmented picker（FR-001）
│   │                                  #   → @SceneStorage 视图模式（FR-004）
│   │                                  #   → 日历模式内嵌 WorkoutCalendarView
│   ├── WorkoutCalendarView.swift      # 【新建】LazyVGrid 7 列月历 + 月导航 + 点日期展开
│   │                                  #   ViewMode enum(list/calendar) + day-grouping helper
│   ├── WorkoutListMerger.swift        # 复用：merge → [UnifiedWorkout]（不改）
│   ├── Models/
│   │   └── UnifiedWorkout.swift       # 复用：startDate 供 startOfDay 分组（不改）
│   └── WorkoutDetailView.swift        # 复用：点日期 → 训练 → 详情落点（FR-003，不改）
└── Resources/
    └── Localizable.xcstrings          # i18n 单源，新增月历相关 key（FR-006 / Constitution VI）
```

**Structure Decision**: 沿用 baseline 既有布局——训练相关 UI 均在 app target `VitalStride/Sources/`（platform-specific，符合 Constitution III：view 留 app target，业务逻辑才进 packages）。本 feature 无业务逻辑下沉需求，`WorkoutCalendarView` 与其内联的 `ViewMode` + day-grouping helper 就近置于新文件；数据源、详情落点、i18n 单源全部复用现有锚点，无新增目录。

## Complexity Tracking

*无 Constitution 违规，无需填写。*
