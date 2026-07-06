---
description: "Task list for 004-previous-set-hint"
---

# Tasks: 训练 SetRow 上次重量提示 (Previous)

**Input**: Design documents from `/specs/004-previous-set-hint/`

**Prerequisites**: [plan.md](./plan.md)（required）、[spec.md](./spec.md)（User Stories + FR）

**Tests**: 包含测试任务——repo 有 80% 覆盖要求 + Constitution Quality Bar I（新 public API 必须 round-trip 测试；新 SwiftUI view ≥2 Preview）。SC-003 明确要求 `PreviousSetLookup` 单测。

**Organization**: 按 spec User Story 组织。本 spec 只有一个 story（US1, P1）+ edge cases。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: 所属 user story（US1）
- 每个任务含精确文件路径（Quality Bar A 范围纪律）

## Path Conventions

- App target 源码：`VitalStride/Sources/`
- i18n 单源：`VitalStride/Resources/Localizable.xcstrings`
- 只读模型输入：`Packages/VitalModels/Sources/VitalModels/Models/`
- 测试：`VitalStrideTests/Sources/`

---

## Phase 1: Setup (定位与确认，既有项目)

**Purpose**: 定位改动点，确认模型字段，无需初始化脚手架

- [ ] T001 [P] 确认 `SetRow` / `ActiveExerciseSection` 现位置：`VitalStride/Sources/ActiveWorkout/SetRow.swift`（MY-874 已从 `ActiveWorkoutView.swift` L694-954 抽出）与 `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`（`ForEach(Array(sortedSets.enumerated())…)` 处渲染 `SetRow`）。记录抽出后锚点，避免改错文件（Quality Bar A）。
- [ ] T002 [P] 确认只读模型字段：`Packages/VitalModels/Sources/VitalModels/Models/Workout.swift`（`endDate`/`exercises`/`startDate`）、`WorkoutExercise.swift`（`exercise`/`sets`）、`ExerciseSet.swift`（`order`/`weight`/`reps`/`isUnilateral`/`weightRight`）、`Exercise.swift`（用于按 exercise 过滤）。确认 `WeightUnit` 定义位置 `VitalStride/Sources/UnitPreferencesSection.swift`。

**Checkpoint**: 锚点与字段确认完毕，可进入 Foundational。

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 实现可测试的历史查询 helper——所有 US1 展示逻辑依赖它

**⚠️ CRITICAL**: US1 展示任务开始前本 phase 必须完成

- [ ] T003 [US1] 新建 `VitalStride/Sources/PreviousSetLookup.swift`：定义 helper（`@MainActor` 查询上下文，值语义、无并发绕过），公开一个查询入口，输入当前 `Workout`、目标 `Exercise`（或其标识）、组 index，输出 `ExerciseSet?`。实现：`FetchDescriptor<Workout>` 按 `startDate` 倒序、`endDate != nil`、排除当前 workout（FR-002），`fetchLimit` 有界防无界遍历（FR-005），命中 workout 内定位同 exercise 的 `WorkoutExercise`、返回其 `sets` 中同 index 组；首次/越界返回 `nil`（FR-003）。抽为独立 helper 供 MY-1041 复用（FR-007）。**Files in scope**: `VitalStride/Sources/PreviousSetLookup.swift`。

**Checkpoint**: `PreviousSetLookup` 可编译、可被测试与视图调用。

---

## Phase 3: User Story 1 - 训练中看到上次同动作的重量×次数 (Priority: P1) 🎯 MVP

**Goal**: 训练中每个 `SetRow` 展示对应 index 的上次值"上次 {重量}{单位} × {次数}"（灰字/tertiary caption），首次/越界优雅缺省。

**Independent Test**: 记录一次含动作 X 的训练并完成 → 新训练加动作 X → `SetRow` 显示灰字"上次 60kg × 10"；动作 X 首次训练 → 无提示不报错。

### Tests for User Story 1 ⚠️

> **先写测试，确认 FAIL 后再实现（TDD）。对应 SC-003 / Quality Bar I。**

- [ ] T004 [P] [US1] 新建 `VitalStrideTests/Sources/PreviousSetLookupTests.swift`：round-trip 单测覆盖四类场景——(a) 找到（上一次已完成训练同 index 组返回正确 weight/reps）；(b) 未找到（该 exercise 首次训练返回 `nil`，FR-003）；(c) 越界（上次组数 < 当前 index 返回 `nil`，Acceptance #3）；(d) 单位换算（上次值按当前 `WeightUnit` 偏好换算，FR-004）。同时断言排除当前 in-progress workout（`endDate == nil`，FR-002）。用内存 `ModelContainer` 构造 fixture。**Files in scope**: `VitalStrideTests/Sources/PreviousSetLookupTests.swift`。

### Implementation for User Story 1

- [ ] T005 [US1] 在 `VitalStride/Sources/ActiveWorkout/SetRow.swift` 给 `SetRow` 新增 `previousSet: ExerciseSet?` 输入（默认 `nil`，保持既有调用不破）。在行值下方渲染 tertiary caption：有值时 `String(localized:)` 组装"上次 {重量}{单位} × {次数}"，按 `weightUnit` 换算显示（FR-001/FR-004）；unilateral 动作按左右重量呈现（复用 `isUnilateral`/`weightRight`，edge case）；`previousSet == nil` 时不渲染占位（FR-003）。**Files in scope**: `VitalStride/Sources/ActiveWorkout/SetRow.swift`。
- [ ] T006 [US1] 在 `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` 的 `ForEach(Array(sortedSets.enumerated())…)` 主组分支，为每个 `SetRow` 调 `PreviousSetLookup`（用 `mainSetNumber(upTo: index)` 对齐主组 index、`workoutExercise.exercise`、当前 `workout`），把结果作 `previousSet:` 传入 `SetRow`。SubSet 分支不加提示。**Files in scope**: `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`。
- [ ] T007 [P] [US1] 在 `VitalStride/Resources/Localizable.xcstrings` 新增"上次 …"字符串条目（含 `%@`/`%lld` 占位与 comment，中英双语），供 T005 `String(localized:)` 引用（FR-006 / Quality Bar G，Principle VI）。**Files in scope**: `VitalStride/Resources/Localizable.xcstrings`。

**Checkpoint**: US1 完整可用——训练中显示上次值，首次/越界优雅缺省，单位换算正确。MVP 达成。

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Preview 覆盖与质量收尾

- [ ] T008 [P] [US1] 在 `VitalStride/Sources/ActiveWorkout/SetRow.swift` 补 SwiftUI Preview：至少 2 个——(1) 有 `previousSet`（展示"上次 …" caption）、(2) 无 `previousSet`（缺省，无占位）；建议再加 unilateral 有上次值一例（Quality Bar I ≥2 Preview）。**Files in scope**: `VitalStride/Sources/ActiveWorkout/SetRow.swift`。
- [ ] T009 验证：`PreviousSetLookupTests` 全绿；`SetRow` 有上次值场景手动确认 caption 换算正确、首次/越界无占位。app target 改动用 `xcodebuild test`（CLAUDE.md 规则，后台 + 长 timeout）。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即可开始
- **Foundational (Phase 2)**: 依赖 Setup — BLOCKS US1 展示任务（T005/T006 依赖 T003 的 helper API）
- **User Story 1 (Phase 3)**: 依赖 Foundational
- **Polish (Phase 4)**: 依赖 US1 完成

### Within User Story 1

- 测试 T004 先写、确认 FAIL（TDD），再进实现
- T005（SetRow 渲染）与 T007（xcstrings）可并行（不同文件）；T005 引用的 key 需与 T007 一致
- T006（wiring）依赖 T003（helper）+ T005（`previousSet` 输入存在）
- T008 Preview 依赖 T005 的新输入
- Story 完成后再收尾

### Parallel Opportunities

- T001 / T002（Setup）并行
- T004（测试，独立文件）可与 T003 完成后并行推进实现
- T007（xcstrings）与 T005（SetRow）并行，注意 key 对齐
- T008 与 T009 前置就绪后可并行

---

## Parallel Example: User Story 1

```bash
# Setup 并行：
Task T001: "确认 SetRow / ActiveExerciseSection 位置"
Task T002: "确认 VitalModels 模型字段 + WeightUnit"

# US1 实现阶段并行（helper T003 完成后）：
Task T005: "SetRow 新增 previousSet 输入 + caption 渲染"
Task T007: "Localizable.xcstrings 新增 上次 字符串"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 Setup — 定位锚点、确认字段
2. Phase 2 Foundational — 实现 `PreviousSetLookup`（CRITICAL，blocks US1）
3. Phase 3 US1 — 先测试（T004 RED）→ 实现（T005/T006/T007 GREEN）
4. **STOP and VALIDATE**：独立验证 US1（Independent Test）
5. 就绪即可交付——本 feature 单 story，US1 即完整 MVP

### Incremental Delivery

本 feature 只有一个 P1 story：Setup + Foundational + US1 = 可交付增量；Polish（T008/T009）为质量收尾，不阻塞 US1 功能验证。

---

## Notes

- [P] = 不同文件、无依赖
- [US1] 标签映射到唯一 user story，保证可追溯
- FR-002/005/007 由 Phase 2（`PreviousSetLookup`）覆盖；FR-001/003/004/006 由 Phase 3 覆盖
- Quality Bar 引用：i18n = Bar G（Principle VI）、tests = Bar I、范围纪律 = Bar A
- `addSet()` 复制 lastMainSet 逻辑（`ActiveWorkoutView.swift`）与本功能正交，**不改**（spec Assumptions）
- 提交遵循 conventional commits，逐任务或逻辑组提交
