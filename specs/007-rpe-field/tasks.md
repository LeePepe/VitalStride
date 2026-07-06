---
description: "Task list for 007-rpe-field — ExerciseSet RPE 字段"
---

# Tasks: ExerciseSet RPE 字段 (训练量化基础设施)

**Input**: Design documents from `/specs/007-rpe-field/`

**Prerequisites**: plan.md（必需）、spec.md（US1 + FR-001..006）

**Tests**: 本 feature 显式要求测试（FR-005、SC-002、SC-003 + Constitution Quality Bar I：新 public API 必须 round-trip 测试）。

**Organization**: 仅 US1（P1）。数据层（VitalModels）为 blocking 前置，app 层（SetRow + AIPromptBuilder）在其上。

## Format: `- [ ] T### [P?] [Story] Description`

- **[P]**：可并行（不同文件、无依赖）
- **[US1]**：所属 user story
- 每个 task 含精确文件路径

## Path Conventions

- 数据层（VitalModels 包）：`cd Packages/VitalModels && swift build && swift test`（**禁止 xcodebuild**，遵 CLAUDE.md / Constitution III）
- app 层（SetRow / AIPromptBuilder）：源码在 `VitalStride/Sources/`，编译验证走主 app target（本 tasks 不由 agent 跑 xcodebuild）

---

## Phase 1: Setup（Shared Infrastructure）

**Purpose**: 确认现状与测试入口，不改代码

- [ ] T001 [US1] 确认 `Packages/VitalModels/Sources/VitalModels/Models/ExerciseSet.swift` 当前字段形状（order/weight/reps/setType/restDuration/isCompleted/isUnilateral/weightRight）及其 Codable extension 结构（CodingKeys/init(from:)/encode(to:) 三处需同步新增字段）
- [ ] T002 [US1] 确认测试 target `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSetTests.swift` 存在且 `swift test` 可跑（对齐既有 `weightRight` / `isUnilateral` 的向后兼容用例写法）

**Checkpoint**: 现状与测试入口确认，可进入数据层实现。

---

## Phase 2: Foundational（数据层 — VitalModels，BLOCKING）

**Purpose**: RPE 字段的模型层 + 编解码 + 向后兼容，是 app 层任何工作的前置。

**⚠️ CRITICAL**: 本阶段完成前，US1 的 app 层 task 不能开始。

**验证方式**: `cd Packages/VitalModels && swift build && swift test`（NOT xcodebuild）。

- [ ] T003 [US1] 在 `Packages/VitalModels/Sources/VitalModels/Models/ExerciseSet.swift` 的属性块新增 `rpe: Int?`（`nil` = 未标注，有效语义 1-10），并在 `init` 增加 `rpe: Int? = nil` 参数与赋值（FR-001）
- [ ] T004 [US1] 在同文件 Codable extension 同步 `rpe`：`CodingKeys` 加 case；`init(from:)` 用 `decodeIfPresent` 读取（缺字段 → `nil`，向后兼容旧数据）；`encode(to:)` 用 `encodeIfPresent`（`nil` 时不写键）——与既有 `weightRight` 模式一致（FR-001、FR-004）
- [ ] T005 [P] [US1] 在 `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSetTests.swift` 增加 rpe 测试：init 默认 `nil`、init 保留传入值、encode/decode round-trip 保留 rpe、encode 在 rpe=nil 时省略键、**decode 缺 rpe 字段的旧 JSON 默认 `nil`**（覆盖 FR-005、SC-002 向后兼容）

**Checkpoint**: `swift test` 全绿，数据层就绪，app 层可开始。

---

## Phase 3: User Story 1 — 每组标注主观努力度（Priority: P1）🎯 MVP

**Goal**: 训练中在 SetRow Menu 选 RPE → 持久化到 `ExerciseSet.rpe` → AI prompt 能读到并携带 `@ RPE{n}`。

**Independent Test**: 训练中 SetRow Menu 选 "RPE 8" → `exerciseSet.rpe == 8` 持久化；未标注时 rpe 为 `nil` 不影响现有流程；AI 分析时 prompt set 描述含 `@ RPE8`。

### Implementation for User Story 1

- [ ] T006 [US1] 在 `VitalStride/Sources/ActiveWorkout/SetRow.swift` 的 Menu 块（现 `:122-187`，紧邻组类型 picker）新增 RPE `Picker`：选项暴露 6/7/8/9/10 + "未标注"（对应 `nil`），绑定 `exerciseSet.rpe`（FR-002）
- [ ] T007 [US1] 在同 Menu 处理 warmup 边界：`exerciseSet.setType == .warmup` 时可隐藏 RPE picker（热身通常 RPE < 6，spec Edge Case 草案）
- [ ] T008 [P] [US1] 在 `VitalStride/Resources/Localizable.xcstrings` 新增 RPE picker 相关用户可见字符串（picker label、"未标注"、各 RPE 选项文案如需），SetRow 侧用 `String(localized:comment:)` 引用——不得依赖文件顶部 `no_hardcoded_chinese` 豁免（FR-006、Constitution VI / Bar G）
- [ ] T009 [US1] 在 `VitalStride/Sources/AIPromptBuilder.swift` 的 `SetSnapshot`（`:26-30`）新增 `let rpe: Int?`，并在其构造点（`:264` 附近，从 `set.rpe` 取值）传入（FR-003）
- [ ] T010 [US1] 在 `VitalStride/Sources/AIPromptBuilder.swift` 的 set 描述拼接处（`:95` `setDescriptions.map`）当 `rpe != nil` 时追加 `@ RPE{n}`（`nil` 时不追加、无占位）（FR-003、FR-004）

### Tests for User Story 1

- [ ] T011 [P] [US1] AI prompt 携带 RPE 断言测试：给定含 rpe 的 set，构造出的 set 描述包含 `@ RPE{n}`；rpe=nil 时描述不含 `@ RPE`（覆盖 SC-003、FR-003）。放在 AIPromptBuilder 对应的 app-target 测试目录（`VitalStrideTests/`，目录源引用自动包含）

**Checkpoint**: US1 端到端可用——标注持久化 + AI prompt 携带 RPE，旧数据不受影响。

---

## Phase 4: Polish & Cross-Cutting

**Purpose**: 收尾质量项

- [ ] T012 [P] [US1] 确认 SetRow 相关 Preview 覆盖含 RPE 的 set 与 rpe=nil 的 set（Constitution Quality Bar I：新 SwiftUI view 至少 2 个 Preview；SetRow 为既有 view，此处补 RPE 变体 Preview）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，立即开始
- **Foundational (Phase 2)**: 依赖 Setup —— **BLOCKS** 所有 app 层 task
- **User Story 1 (Phase 3)**: 依赖 Phase 2（模型 rpe + Codable 就绪）
- **Polish (Phase 4)**: 依赖 Phase 3

### Within User Story 1

- 数据层 T003 → T004（同文件，顺序）；T005 测试可与 T004 并行编写但需 T003/T004 定型后跑绿
- app 层 UI（T006/T007）与 AI（T009/T010）不同文件，可并行；xcstrings T008 与 UI 并行
- T011（AI prompt 测试）依赖 T009/T010
- 模型 before UI/AI（Phase 2 before Phase 3）

### Parallel Opportunities

- T005（模型测试，独立文件）与 T003/T004 编写并行
- Phase 3 内：T006/T007（SetRow）‖ T008（xcstrings）‖ T009/T010（AIPromptBuilder）为三组不同文件，可并行
- T011、T012 标 [P]

---

## Parallel Example: User Story 1（Phase 3）

```text
# Phase 2 完成后，Phase 3 三组不同文件并行：
Task: "SetRow Menu 加 RPE picker + warmup 边界 in VitalStride/Sources/ActiveWorkout/SetRow.swift"
Task: "xcstrings 新增 RPE 字符串 in VitalStride/Resources/Localizable.xcstrings"
Task: "SetSnapshot 携带 rpe + set 描述追加 @ RPE{n} in VitalStride/Sources/AIPromptBuilder.swift"
```

---

## Implementation Strategy

### MVP（US1 only —— 本 feature 即 MVP）

1. Phase 1 Setup：确认模型现状 + 测试入口
2. Phase 2 Foundational：`rpe: Int?` + Codable + 向后兼容，`swift test` 绿（CRITICAL，blocks app 层）
3. Phase 3 US1：SetRow picker + xcstrings + AIPromptBuilder RPE
4. **STOP & VALIDATE**：Independent Test —— 标注持久化 + AI prompt 含 `@ RPE{n}` + 旧数据兼容
5. Phase 4 Polish

---

## Notes

- 数据层 task（T003-T005）验证命令：`cd Packages/VitalModels && swift build && swift test`（**禁止 xcodebuild**，遵 CLAUDE.md / Constitution III）
- app 层不由本 tasks 跑 xcodebuild
- 向后兼容是硬约束：SwiftData `rpe: Int?` 可选属性默认 `nil` 为 additive/lightweight，无需显式迁移；Codable 层 `decodeIfPresent` 保证旧 JSON 缺字段 → `nil`（FR-004、SC-002）
- i18n：新增用户可见字符串走 `String(localized:)` 单源，禁止硬编码（Constitution VI / Quality Bar G）
- Quality Bar I：新 public API `rpe` 必须 round-trip 测试（T005）；AI prompt 携带断言（T011）
- 每个 task 或逻辑组完成后 commit
