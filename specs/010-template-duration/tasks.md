---
description: "Task list for WorkoutTemplate 预估训练时长"
---

# Tasks: WorkoutTemplate 预估训练时长

**Input**: Design documents from `specs/010-template-duration/`

**Prerequisites**: plan.md（必需）、spec.md（US1 + FR-001..005）

**Tests**: 本 feature 明确要求单测（SC-003，Quality Bar I）——纯函数须先写测试。

**Organization**: 仅 US1（P1）。VitalModels 任务用 `cd Packages/VitalModels && swift build && swift test` 验证；app target 展示任务不由本 agent 跑 xcodebuild。

## Format: `[ID] [P?] [Story] Description`

- **[P]**：可并行（不同文件、无依赖）
- **[US1]**：所属 user story
- 每条含精确文件路径

## Path Conventions

- VitalModels 包：`Packages/VitalModels/Sources/VitalModels/`、`Packages/VitalModels/Tests/VitalModelsTests/`
- App target：`VitalStride/Sources/`、`VitalStride/Resources/`

---

## Phase 1: Setup（Shared Infrastructure）

**Purpose**: 确认现有数据结构与展示落点，避免臆造字段。

- [ ] T001 [US1] 确认 `Packages/VitalModels/Sources/VitalModels/Models/WorkoutTemplate.swift`（`exercises: [TemplateExercise]?`）与 `TemplateExercise.swift`（`targetSets`）字段，明确 totalSets 求和来源
- [ ] T002 [US1] 确认 `VitalStride/Sources/StartWorkoutView.swift` 模板列表 `TemplateRow`（现展示"X 个动作"）为时长展示的插入点

**Checkpoint**: 数据字段与展示位置已确认，可动手实现。

---

## Phase 2: Foundational（VitalModels，swift test）

**Purpose**: 纯函数估算——所有 user story 展示的前置。**先测试后实现**（Quality Bar I）。

- [ ] T003 [US1] 在 `Packages/VitalModels/Tests/VitalModelsTests/WorkoutTemplateDurationTests.swift` 新建单测：空模板边界（无动作/无组 → 0，SC-003）；经验估算（totalSets×90s + 5min 过渡，FR-001）；historicalAverage 存在时优先历史值（SC-002）。先跑 `cd Packages/VitalModels && swift build && swift test` 确认 RED
- [ ] T004 [US1] 在 `Packages/VitalModels/Sources/VitalModels/WorkoutTemplate+Duration.swift` 新建 `estimatedDuration(historicalAverage:)` 纯函数（FR-001、FR-004）：有历史平均用之，否则按 totalSets×90s + 5min 过渡；空模板返回 0。跑 `cd Packages/VitalModels && swift build && swift test` 转 GREEN

**Checkpoint**: 估算纯函数通过全部单测（含空模板边界），可供 UI 消费。

---

## Phase 3: User Story 1 — 模板列表显示预估时长（Priority: P1）🎯 MVP

**Goal**: 模板列表在动作数旁展示"约 X 分钟"，用户按时间空档选模板。

**Independent Test**: 模板含 3 动作共 12 组 → 列表显示"约 ~23 分钟"（12×90s + 5min）；有历史实例时显示历史平均。

- [ ] T005 [US1] 在 `VitalStride/Resources/Localizable.xcstrings` 新增"约 X 分钟"可读格式字符串（FR-002、FR-005，Constitution VI 单源），供 `String(localized:)` 引用
- [ ] T006 [US1] 在 `VitalStride/Sources/StartWorkoutView.swift` 的 `TemplateRow` 调用 `estimatedDuration` 并以 `String(localized:)` 展示"约 X 分钟"于"X 个动作"旁（FR-002）；空模板时展示"—"
- [ ] T007 [P] [US1]（可选增强）在 `VitalStride/Sources/StartWorkoutView.swift` 查询该模板最近训练实例算历史平均、以 `fetchLimit` 约束后作参数注入纯函数（FR-003，有历史优先 SC-002）；查询留在 app target，VitalModels 保持无查询耦合

**Checkpoint**: US1 可独立验证——模板列表展示合理预估时长（SC-001），有历史用历史、无历史用经验（SC-002）。

---

## Phase 4: Polish

- [ ] T008 [P] [US1] 为 `StartWorkoutView` 模板行（含时长展示）补至少 2 个 SwiftUI Preview（含空模板与多动作场景），满足 Quality Bar I

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**：无依赖，立即开始
- **Foundational（Phase 2）**：依赖 Setup；阻塞 US1 展示
- **US1（Phase 3）**：依赖 Phase 2（`estimatedDuration` 就绪）
- **Polish（Phase 4）**：依赖 Phase 3

### Within Phase

- T003（测试 RED）→ T004（实现 GREEN），严格先测后实现
- T004 → T006（展示消费纯函数）
- T005（xcstrings）→ T006（引用字符串）
- T007 独立于 T006 主展示，可并行接线

### Parallel Opportunities

- T007、T008 标 [P]，与主展示任务或彼此不冲突时可并行
- T003 与 T004 不并行（同一函数 red→green）

---

## Implementation Strategy

### MVP First（US1 Only）

1. Phase 1 Setup 确认字段与展示位
2. Phase 2 Foundational：`estimatedDuration` 先测后实现（`swift test` 秒级验证）
3. Phase 3 US1：xcstrings + 模板行展示（可选接历史平均）
4. **STOP & VALIDATE**：模板列表显示"约 X 分钟"，空模板显示"—"
5. Phase 4 Polish：补 Preview

---

## Notes

- VitalModels 改动**必须**用 `cd Packages/VitalModels && swift build && swift test` 验证，禁止 xcodebuild（CLAUDE.md / Constitution III）
- 引用 Quality Bar I（新 public API round-trip 测试 + 新 view ≥2 Preview）、Quality Bar G（无硬编码用户可见字符串，走 xcstrings）
- 估算须纯函数、无副作用、可离线；历史查询留 app target 侧，`fetchLimit` 约束
- 不涉及 HealthKit 数值，无隐私面；无 schema 变更、无 ADR
