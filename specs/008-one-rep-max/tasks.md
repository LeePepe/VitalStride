---
description: "Task list for 008-one-rep-max"
---

# Tasks: 1RM 估算 + per-exercise 趋势曲线

**Input**: `specs/008-one-rep-max/plan.md` + `spec.md`

**Tests**: 包含（spec SC-003 要求单测；Constitution Quality Bar I 要求新 public API round-trip 测试）。

**Organization**: 按 user story 分组，US1（P1，MVP）可独立交付，US2（P2）为增量迭代。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: US1 / US2
- 每条含精确文件路径

---

## Phase 1: Setup（共享确认）

**Purpose**: 确认现有锚点，无需新建脚手架

- [ ] T001 确认 `Packages/VitalModels/Sources/VitalModels/Models/ExerciseSet.swift` 字段：`weight: Double` / `reps: Int` / `setType: SetType`（`SetType.working` 存在于 `Enums/SetType.swift`）——1RM 计算的输入基础
- [ ] T002 确认 `VitalStride/Sources/WorkoutDetailView.swift` 现有 exercise section 结构，定位 estimated 1RM 展示插入点（P1）

---

## Phase 2: Foundational（VitalModels，`swift test` 验证）

**Purpose**: 纯计算 helper，US1/US2 都依赖，必须先完成

**⚠️ CRITICAL**: 本 phase 未完成前，任何 user story 不能开工

- [ ] T003 [US1] 新建 `Packages/VitalModels/Sources/VitalModels/Extensions/ExerciseSet+OneRepMax.swift`：`estimatedOneRepMax`（Epley `weight×(1+reps/30)`，纯 computed）+ `isOneRepMaxCandidate`（`setType == .working` 且 `1...12 ~= reps` 且 `weight > 0`）过滤 helper（FR-001、FR-005）
- [ ] T004 [US1] 在 `Packages/VitalModels/Sources/VitalModels/Models/WorkoutExercise.swift` 增加 `bestEstimatedOneRepMax` computed 属性：取该动作全部 set 中 `isOneRepMaxCandidate` 者的最高 `estimatedOneRepMax`，无候选返回 nil（FR-002）
- [ ] T005 [P] [US1] 新建 `Packages/VitalModels/Tests/VitalModelsTests/OneRepMaxTests.swift`：Epley 公式断言（如 80kg×5 → ~93kg）+ 候选边界测试（warmup 排除、reps 0/13/>12 排除、weight≤0 排除、多组取最高）——SC-003；验证 `cd Packages/VitalModels && swift build && swift test`

**Checkpoint**: 计算层就绪，`swift test` 全绿后 UI story 可开工

---

## Phase 3: User Story 1 - 训练详情看到 estimated 1RM（Priority: P1）🎯 MVP

**Goal**: 训练详情每个动作显示本次最高 estimated 1RM，无候选组时隐藏

**Independent Test**: 记一次含 working 80kg×5 的训练 → 详情显示该动作 "Estimated 1RM: ~93kg"；仅 warmup/超范围组时该行不出现

- [ ] T006 [US1] 在 `VitalStride/Sources/WorkoutDetailView.swift` 每个 exercise section 读取 `WorkoutExercise.bestEstimatedOneRepMax`，有值时展示 estimated 1RM 行（FR-003、SC-001）
- [ ] T007 [US1] 无候选（warmup / 超范围 only）时该行隐藏，不显示占位（SC-002）
- [ ] T008 [P] [US1] 在 `VitalStride/Resources/Localizable.xcstrings` 新增 P1 字符串（"Estimated 1RM" label 等），app target 侧用 `String(localized:)` 引用（FR-006、Constitution VI / Bar G）

**Checkpoint**: US1 独立可用，MVP 可交付

---

## Phase 4: User Story 2 - per-exercise 1RM 趋势曲线（Priority: P2）

**Goal**: 动作详情按时间展示 estimated 1RM 趋势曲线

**Independent Test**: 某动作有多次历史训练 → 打开 1RM 趋势看到按时间排列的 Swift Charts 折线

- [ ] T009 [US2] 新建 `VitalStride/Sources/OneRepMaxTrendView.swift`：按时间聚合该动作历史训练的 `bestEstimatedOneRepMax`，历史查询遵守 `fetchLimit` 约束（呼应 MY-1077，plan Performance Goals）
- [ ] T010 [US2] 在 `OneRepMaxTrendView.swift` 用 Swift Charts 渲染 1RM 折线（复用 000 FR-009 图表基线；FR-004）
- [ ] T011 [US2] 无历史 / 单点数据降级展示（Edge Case：单点不画线、空态提示），从 `WorkoutDetailView.swift` 或动作详情提供入口
- [ ] T012 [P] [US2] 在 `VitalStride/Resources/Localizable.xcstrings` 新增趋势标题 / 空态字符串，`String(localized:)` 引用（FR-006、Bar G）

**Checkpoint**: US1 + US2 均独立可用

---

## Phase 5: Polish & Cross-Cutting

- [ ] T013 [P] 为 P1 展示与 P2 趋势视图各补 ≥ 2 个 SwiftUI Preview（有候选 / 无候选；多点 / 单点空态）——Constitution Quality Bar I
- [ ] T014 [P] 在 UI（详情或趋势视图）标注 1RM 估算性质 caveat：3-10 reps 最准、>15 reps 偏差大（spec Edge Cases、Assumptions），字符串走 xcstrings
- [ ] T015 复核所有新 UI 字符串无硬编码中/英（Constitution VI / Bar G）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup，**阻塞所有 user story**
- **US1 (Phase 3)** / **US2 (Phase 4)**: 均依赖 Phase 2；US2 复用 Phase 2 计算但独立可测
- **Polish (Phase 5)**: 依赖目标 story 完成

### User Story Dependencies

- **US1 (P1)**: Phase 2 完成后即可开工，不依赖 US2
- **US2 (P2)**: Phase 2 完成后即可开工；复用 `bestEstimatedOneRepMax` 但独立可测

### Within Each Story

- 测试（T005）先写、先失败，再实现（TDD）
- Extension/model（T003/T004）先于 UI（T006+）
- US1 完成再进 US2

### Parallel Opportunities

- T005（测试）与 T003/T004 写完后并行验证
- T008 / T012（xcstrings）与各自 story 的 UI 任务并行
- T013 / T014（Polish）跨 story 并行

---

## Parallel Example: Phase 2

```bash
# T003/T004 实现后，并行补测试并验证：
Task: "OneRepMaxTests.swift Epley + 候选边界" (T005)
# 验证命令（VitalModels 改动）：
cd Packages/VitalModels && swift build && swift test
```

---

## Implementation Strategy

### MVP First（US1 Only）

1. Phase 1 Setup
2. Phase 2 Foundational（`cd Packages/VitalModels && swift build && swift test` 全绿 — CRITICAL）
3. Phase 3 US1
4. **STOP & VALIDATE**: 独立验证 US1（详情显示 / 隐藏规则）
5. 可交付 MVP

### Incremental Delivery

1. Setup + Foundational → 计算层就绪
2. US1 → 独立验证 → 交付（MVP）
3. US2 → 独立验证 → 交付（趋势曲线）

---

## Notes

- VitalModels 改动统一用 `cd Packages/VitalModels && swift build && swift test` 验证，禁止 xcodebuild（Constitution III）
- [P] = 不同文件、无依赖
- 新 public API 必须有 round-trip 测试、新 view ≥ 2 Preview（Quality Bar I）
- 无硬编码用户可见字符串（Quality Bar G）
- 无健康隐私关切（训练数据，非 HealthKit 数值）
