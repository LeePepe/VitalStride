---
description: "Task list for 003-substitute-exercise (训练中 AI 智能替代动作)"
---

# Tasks: 训练中 AI 智能替代动作 (Substitute Exercise)

**Input**: Design documents from `/specs/003-substitute-exercise/`

**Prerequisites**: [plan.md](./plan.md)（required）, [spec.md](./spec.md)（US1 + FR-001..007）

**Tests**: 包含测试任务——`spec.md` Edge Cases + SC-003 明确要求解析健壮性与 fallback 可达性（Quality Bar I）。

**Organization**: 仅 US1（P1）。按 Phase 分组，US1 为唯一 MVP。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: 所属 user story（本 feature 仅 US1）
- 每条含精确文件路径

## Quality Bars 引用（不重述，见 `.specify/memory/constitution.md`）

- **Bar D 错误处理（P0）**：AI / JSON / 反查失败一律 graceful degrade 到手动 picker，禁 `fatalError`/`try!`/`as!`（FR-004、SC-003）。
- **Principle V / Bar（AI）**：复用 `AIProviderChain`，不新建 provider、不引第三方 SDK（FR-002）。
- **Bar G I18n（P1）**：新字符串走 `String(localized:)` → xcstrings（FR-006）。
- **Bar I 测试覆盖（P1）**：新解析器 / 反查 helper round-trip 单测；新 view ≥ 2 Preview。
- **Bar B 隐私（P0）**：解析 / 错误日志不得含健康数值（FR-007，本功能仅用动作元数据）。

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 定位真实锚点、确认复用 API 签名，落地前不改代码。

- [ ] T001 [US1] 确认 ⋮ Menu / replace sheet 真实位置：`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`（`:89-100` Menu、`:72-85` contextMenu）承载「替换动作」入口；`VitalStride/Sources/ActiveWorkoutView.swift`（`:83-87` `.sheet(item: $exerciseToReplace)` → `ExercisePickerView`）承载呈现与 `workoutExercise.exercise` 写入。确认新入口经回调上抛、sheet 状态落在 session 视图。
- [ ] T002 [P] [US1] 确认复用 API 签名：`Packages/AIService/Sources/AIService/AIProviderChain.swift` 的 `chat(messages:model:)` + `makeDefault(zhipuAPIKey:)`，以及 `Models.swift` 的 `ChatMessage(role:content:)` / `ChatResponse.content`；参照现有调用点 `VitalStride/Sources/AIAnalysisService.swift:344`、`AIView.swift:286` 的接线方式（含 provider 注入 / 错误捕获）。
- [ ] T003 [P] [US1] 确认反查字段：`Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift` 的 `presetId: String?`（AI 引用 + 本地反查用），及 `muscleGroup` / `equipment` 供 prompt 构造；参照 `VitalStride/Sources/ExerciseSeeder.swift` 现有 `presetId` predicate 用法（`:117-120`、`:150-161`）。

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: US1 依赖的纯逻辑层——请求/响应模型、解析、反查、prompt builder。可脱离 UI 单测。

**⚠️ CRITICAL**: 本阶段完成前不接 UI。

- [ ] T004 [US1] 定义 substitute 请求/响应模型：当前动作输入（name / muscleGroup / equipment）+ AI 返回条目 `SubstituteSuggestion`（`exerciseId: String`, `reason: String`），置于 app 层小文件（如 `VitalStride/Sources/ExerciseSubstitute.swift`）（FR-003）。
- [ ] T005 [US1] 实现 JSON 解析器：解析 `[{exerciseId, reason}]`（FR-003）。健壮性：畸形 / 非预期 JSON → 抛可捕获错误不崩溃；候选 <3 → 返回实际数量；含当前动作本身 → 过滤掉（Edge Cases）。禁 `try!`/`as!`（Bar D）。在 `VitalStride/Sources/ExerciseSubstitute.swift`。
- [ ] T006 [US1] 实现 `ExerciseSeeder.findByPresetId(_:context:)` 反查 helper：按 `presetId` 从 SwiftData 取本地 `Exercise`，命中返回、未命中返回 `nil`（不崩溃，交由上层过滤 / fallback）（FR-003、Edge Cases）。在 `VitalStride/Sources/ExerciseSeeder.swift`。
- [ ] T007 [US1] 实现 prompt builder：以当前动作 name / muscleGroup / equipment 构造 `[ChatMessage]`（system 约束「仅返回同主肌群、非当前动作、结构化 JSON」+ user 内容），请求 3 个同肌群替代（FR-002）。复用 `AIProviderChain`，不新建 provider（Principle V）。日志不含健康数值（FR-007）。在 `VitalStride/Sources/ExerciseSubstitute.swift`。

**Checkpoint**: 解析 + 反查 + prompt 可独立单测，UI 层可开始接线。

---

## Phase 3: User Story 1 - AI 推荐同肌群替代动作 (Priority: P1) 🎯 MVP

**Goal**: 训练中 `⋮` → 「智能替代」→ 3 张 AI card → 点选替换当前动作；AI 不可用则回落手动 picker。

**Independent Test**: 训练中点某动作 `⋮` → 「智能替代」→ sheet 出 3 张 card（名+主肌群+理由）→ 点一张 → 当前动作被替换 + dismiss；断网 / 无 key 时出 inline 错误 + 跳预选 muscleGroup 的 `ExercisePickerView`。

### Tests for User Story 1 ⚠️（先写、先 FAIL）

- [ ] T008 [P] [US1] JSON 解析单测：valid（3 条）/ malformed（非 JSON）/ <3 条 / 含当前动作（自引用被过滤）四组用例，断言不崩溃且过滤正确。在 `VitalStrideTests/Sources/ExerciseSubstituteParseTests.swift`（FR-003、Edge Cases、Bar I）。
- [ ] T009 [P] [US1] 反查单测：`findByPresetId` 命中已 seed 的 presetId / 未命中未知 id 返回 `nil` 两组。在 `VitalStrideTests/Sources/ExerciseSeederFindTests.swift`（FR-003、Bar I）。
- [ ] T010 [P] [US1] Fallback 路径可达性测试：模拟 AI 不可用 / 空有效候选，断言逻辑进入 fallback 分支（暴露可观测状态）而非崩溃或静默（SC-003、Bar D）。在 `VitalStrideTests/Sources/ExerciseSubstituteParseTests.swift`。

### Implementation for User Story 1

- [ ] T011 [US1] 在 `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` 的 Menu（`:89-100`）与 contextMenu（`:72-85`）中，「替换动作」上方新增「智能替代」Button，经新 `onSubstitute` 回调上抛；保留现有「替换动作」全量 picker 入口不变（FR-001）。
- [ ] T012 [US1] 新增 `ExerciseSubstituteSheet`：loading / 结果（3 张 card：动作名 + 主肌群 + reason）/ 错误 三态；错误态含内嵌 inline 提示 + 「手动选择」按钮。在 `VitalStride/Sources/ExerciseSubstituteSheet.swift`（FR-001）。
- [ ] T013 [US1] 在 `VitalStride/Sources/ActiveWorkoutView.swift` 接线：新增 substitute 状态 + `.sheet` 呈现 `ExerciseSubstituteSheet`，触发时调 prompt builder → `AIProviderChain.chat` → 解析 → 反查（Phase 2）（FR-002）。
- [ ] T014 [US1] 选中替代 card 回调：更新 `workoutExercise.exercise = 所选`、dismiss sheet、触发 haptic。在 `VitalStride/Sources/ActiveWorkoutView.swift`（与 `:83-87` replace 写入并列）（FR-005）。
- [ ] T015 [US1] AI 不可用 / 空候选降级：`ExerciseSubstituteSheet` 错误态 → 一键跳 `VitalStride/Sources/ExercisePickerView.swift`，预选当前 `muscleGroup`；不静默失败、不崩溃（FR-004、SC-003、Bar D）。
- [ ] T016 [US1] 隐私日志核查：substitute 请求 / 解析 / 错误路径日志只记 provider 名 / 错误类别 / 候选数量，不写健康数值或原始响应（FR-007、Bar B）。跨 `ExerciseSubstitute.swift` 与 `ActiveWorkoutView.swift`。
- [ ] T017 [P] [US1] 新增 UI 字符串（「智能替代」/ 错误提示 / 「手动选择」等）到 `VitalStride/Resources/Localizable.xcstrings`，代码侧走 `String(localized:)`（FR-006、Bar G）。

**Checkpoint**: US1 完整可独立验证。

---

## Phase N: Polish & Cross-Cutting Concerns

- [ ] T018 [P] [US1] `ExerciseSubstituteSheet` 至少 2 个 Preview：有结果态（3 张 card）+ 错误/降级态。在 `VitalStride/Sources/ExerciseSubstituteSheet.swift`（Bar I）。
- [ ] T019 [US1] 走查 SC-001（3 次点击内完成替代）/ SC-002（推荐均同主肌群、非当前动作）/ SC-003（AI 不可用 100% 回落可用 picker）验收。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**：无依赖，先行。
- **Foundational（Phase 2）**：依赖 Phase 1；BLOCKS US1 实现。
- **US1（Phase 3）**：依赖 Phase 2 完成。
- **Polish（Phase N）**：依赖 US1 完成。

### Within User Story 1

- 测试（T008-T010）先写并 FAIL，再实现。
- 模型 / 解析（T004-T005）→ 反查（T006）→ prompt（T007）→ UI 接线（T011-T015）。
- T011（Menu entry）与 T012（sheet 视图）不同文件可并行；T013-T015 依赖 T012 + Phase 2。
- T016 隐私核查、T017 xcstrings 贯穿实现，末尾统一核查。

### Parallel Opportunities

- T002 / T003（Setup 只读确认）并行。
- T008 / T009 / T010（测试，不同断言）并行。
- T017（xcstrings）与代码任务并行；T018（Preview）独立并行。

---

## Parallel Example: User Story 1

```bash
# 先写测试（并行，须先 FAIL）：
Task: "JSON 解析单测 in VitalStrideTests/Sources/ExerciseSubstituteParseTests.swift"
Task: "反查单测 in VitalStrideTests/Sources/ExerciseSeederFindTests.swift"
Task: "Fallback 可达性测试 in VitalStrideTests/Sources/ExerciseSubstituteParseTests.swift"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Phase 1 Setup（定位锚点 + 确认 API 签名）。
2. Phase 2 Foundational（模型 / 解析 / 反查 / prompt，先单测 FAIL 后实现）。
3. Phase 3 US1（Menu entry → sheet → 替换写入 → fallback）。
4. **STOP & VALIDATE**：按 Independent Test + SC-001/002/003 验证。
5. Phase N Polish（Preview + 验收走查）。

---

## Notes

- [P] = 不同文件、无依赖。
- 全程复用 `AIProviderChain`，零新增 provider / 第三方 SDK（Principle V）。
- 任一 AI / 解析 / 反查失败都 MUST 落到手动 `ExercisePickerView`——Bar D 是 P0 ship blocker。
- 每个 task 或逻辑组完成后提交；不跑 `/speckit-implement`，交 Multica pipeline。
