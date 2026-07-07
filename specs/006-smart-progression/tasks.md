---
description: "Task list for 006-smart-progression (US1 P1)"
---

# Tasks: 智能渐进负荷建议 (Smart Progression)

**Input**: Design documents from `specs/006-smart-progression/`

**Prerequisites**: plan.md（必读）、spec.md（US1 + FR-001..007）、`specs/004-previous-set-hint/spec.md`（依赖）

**Tests**: 含测试任务——spec SC-003 显式要求 `SmartProgressionAdvisor` 单测覆盖全部规则分支。

**Organization**: 仅 User Story 1（P1）。004 已交付的 `PreviousSetLookup.previousMainSet(currentWorkout:exercise:mainSetIndex:in:) -> ExerciseSet?`（单组、按主组 index 查询）作为输入前置存在——advisor 消费的是调用方逐 index 收集得到的 `[ExerciseSet]`（上次该动作的主组序列），**004 未定义 `PreviousSetResult` 聚合类型**，不依赖它。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: US1（本 feature 唯一 story）
- 描述含真实文件路径

---

## Phase 1: Setup（共享前置）

**Purpose**: 确认依赖就位

- [ ] T001 [US1] **⚠️ 阻塞确认**：核对 `specs/004-previous-set-hint` 已交付，且 `PreviousSetLookup.previousMainSet(currentWorkout:exercise:mainSetIndex:in:) -> ExerciseSet?`
  已存在于 app target（`VitalStride/Sources/PreviousSetLookup.swift`），作为本 feature 的**唯一历史输入**。
  **注意：004 交付的是按 index 查单组的 `previousMainSet`，不含 `PreviousSetResult` 聚合类型**——本 feature 由调用方逐 `mainSetIndex`（0,1,2… 直到返回 `nil`）收集出上次该动作的主组序列 `[ExerciseSet]` 喂给 advisor。
  004 未落地前，Phase 2 / Phase 3 全部 blocked（见 Dependencies 段）。确认 `ExerciseSet` weight/reps/setType
  与 `MuscleGroup` 可读：`Packages/VitalModels/Sources/VitalModels/Models/ExerciseSet.swift`、
  `Packages/VitalModels/Sources/VitalModels/Enums/MuscleGroup.swift`。

**Checkpoint**: 004 依赖确认存在 → 可进入 Foundational。

---

## Phase 2: Foundational（阻塞前置）

**Purpose**: 纯建议引擎——US1 UI 依赖它

**⚠️ CRITICAL**: 本阶段完成前 US1 无法开始；且整阶段 **blocked by specs/004**（复用其查询结果）

- [ ] T002 [US1] 定义 `ProgressionAdvice` 枚举（`maintain` / `increaseWeight` / `increaseReps` /
  `decreaseWeight`，各携带 `reason`；`Equatable`）于
  `VitalStride/Sources/ActiveWorkout/SmartProgressionAdvisor.swift`。FR-002。
- [ ] T003 [US1] 实现纯引擎 `SmartProgressionAdvisor.suggest(previousMainSets:userPreferredRepRange:)`
  于 `VitalStride/Sources/ActiveWorkout/SmartProgressionAdvisor.swift`——输入上次该动作的主组序列 `[ExerciseSet]`（由调用方逐 index 调 004 `previousMainSet` 收集）
  + 用户目标次数区间，输出 `ProgressionAdvice`。规则（FR-002 / FR-005）：所有组达次数上限 → `increaseWeight`；
  最后一组低于下限 → `maintain`；全部组低于下限 → `decreaseWeight`；其余 → `maintain`；空序列（无历史）→ 优雅缺省不建议。加重增量按
  `MuscleGroup` 区分（小肌群 +2.5kg / 大肌群 +5kg，FR-003）。**不做任何查询**——历史一律复用 004
  `PreviousSetLookup.previousMainSet`（FR-001）。纯函数、无副作用、`Sendable`。

**Checkpoint**: advisor 可独立 `swift`-级单测 → US1 UI 可接入。

---

## Phase 3: User Story 1 - 每组开始前拿到渐进负荷建议（Priority: P1）🎯 MVP

**Goal**: SetRow 依据上次完成情况显示"建议 {重量} × {次数}"chip，tap-to-fill 一键填入。

**Independent Test**: 有某动作上次记录 → 新训练加该动作 → SetRow 出现建议 chip → 点击填入 weight/reps 输入框。

### Tests for User Story 1 ⚠️（先写，先失败）

- [ ] T004 [P] [US1] `SmartProgressionAdvisor` 单测覆盖**全部规则分支**于
  `Packages/VitalModels/Tests/…` 或 app-target 测试目录 `VitalStrideTests/Sources/SmartProgressionAdvisorTests.swift`
  （与 advisor 同侧）：all-hit → `increaseWeight`、drop-off（末组掉下限）→ `maintain`、all-below →
  `decreaseWeight`、mid（区间内）→ `maintain`，及小/大肌群增量档位、无历史 / 越界优雅缺省。SC-001、SC-003。

### Implementation for User Story 1

- [ ] T005 [US1] 在 `VitalStride/Sources/ActiveWorkout/SetRow.swift` 加建议 chip：调用方逐 `mainSetIndex` 调 004
  `PreviousSetLookup.previousMainSet(...)` 收集上次主组序列 `[ExerciseSet]`，非空时调
  `SmartProgressionAdvisor.suggest(...)` 渲染"建议 {重量} × {次数}"chip
  + 理由；首次训练 / 无历史（收集为空）→ **不显示 chip**（复用 004 的缺省行为，FR 边界）。FR-004。
- [ ] T006 [US1] chip **tap-to-fill**：点击把建议 weight/reps 填入输入框；用户后续手动编辑该组 →
  判定为"覆盖建议"（override）。就地于 `VitalStride/Sources/ActiveWorkout/SetRow.swift`。FR-004、SC-002。
- [ ] T007 [P] [US1] 新增建议 UI 文案（chip 文字、各 advice 理由）到
  `VitalStride/Resources/Localizable.xcstrings`，一律 `String(localized:)` 引用，禁止硬编码。
  FR-007、Quality Bar G。
- [ ] T008 [US1] FR-006 接受率 telemetry：接受（tap-fill 未被后续编辑）记 `suggestionAccepted`、
  被手动改记 `suggestionOverridden`，于 `Packages/TelemetryKit/Sources/TelemetryKit/TelemetryEvent.swift`
  加事件、SetRow 触发上报。**仅记元数据**（advice 分类 / 接受与否），**禁止写入实际重量/次数值**。
  Constitution I、Quality Bar B。

**Checkpoint**: US1 端到端可用——有历史即出建议、可一键填、接受率可观测。

---

## Phase 4: Polish

- [ ] T009 [P] [US1] SetRow 建议态 Preview ≥ 2（有建议加重 / 无历史无 chip）于
  `VitalStride/Sources/ActiveWorkout/SetRow.swift`。Quality Bar I。

---

## Dependencies & Execution Order

### Cross-Feature（关键）

- **Blocked by `specs/004-previous-set-hint`（`PreviousSetLookup.previousMainSet`）**——
  004 是本 feature 的历史查询与输入基础，**必须先交付（串行：先 004 后 006）**。004 未落地前
  T002–T009 全部 blocked。本 feature **不重复实现任何历史查询**（FR-001）；多组序列由调用方逐 index 复用 004 的单组查询收集。

### Phase Dependencies

- **Setup (T001)**: 无内部依赖；确认 004 就位后放行
- **Foundational (T002–T003)**: 依赖 Setup；BLOCKS US1
- **US1 (T004–T008)**: 依赖 Foundational（advisor 就绪）
- **Polish (T009)**: 依赖 US1 完成

### Within User Story 1

- 测试 T004 先写、先失败，再进实现
- T002（枚举）→ T003（引擎）→ T005/T006（UI 接入）
- T007（xcstrings）、T004（测试）可与实现并行 [P]

### Parallel Opportunities

- T004、T007 标 [P]，与主实现不同文件可并行
- T009 Preview 在 US1 收尾后并行

---

## Quality Bars 引用（不重述，见宪法 Cross-Cutting Quality Bars）

- **B（健康隐私 P0）**: telemetry / 日志禁含任何重量·次数等训练数值以外的健康数值；FR-006 仅元数据。
- **G（I18n）**: 建议文案全部 catalog 化，无硬编码。
- **I（Test Coverage）**: advisor 全分支单测 + SetRow ≥ 2 Preview。

## Notes

- [P] = 不同文件、无依赖
- advisor 纯函数——所有规则边界必须有单测（SC-003）
- 每个 task 或逻辑组完成后提交
- 手动编辑判定 override 是接受率 telemetry 的语义基础，勿省略
