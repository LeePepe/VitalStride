---
description: "Task list for AI 训练建议一键生成可执行 routine"
---

# Tasks: AI 训练建议一键生成可执行 routine

**Input**: Design documents from `/specs/012-ai-routine-generation/`

**Prerequisites**: plan.md（必需）、spec.md（用户故事）

**Tests**: 本 feature 明确要求测试（Bar I）——Codable 往返、向后兼容解码、物化命中/未命中。

**Organization**: 仅 US1（P1）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[US1]**: 归属用户故事 1
- 每条含精确文件路径

## Path Conventions

- AIService 模型 / 测试：`Packages/AIService/Sources/AIService/`、`Packages/AIService/Tests/AIServiceTests/`（改动仅涉及本包时用 `cd Packages/AIService && swift build && swift test` 验证）
- app 源码 / 测试：`VitalStride/Sources/`、`VitalStrideTests/`

---

## Phase 1: Setup（Shared Infrastructure）

**Purpose**: 确认现有锚点形状，避免误改。

- [ ] T001 [US1] 确认 `Packages/AIService/Sources/AIService/TrainingRecommendation.swift` 当前形状（`title`/`muscleGroups`/`exercises: [String]`/`reasoning`，`Codable & Sendable & Equatable`），确认无 `routineExercises`
- [ ] T002 [P] [US1] 确认 `Packages/AIService/Sources/AIService/AIProviderChain.swift` 为唯一 AI 出口（FR-005 / Constitution V），物化不新增 provider
- [ ] T003 [P] [US1] 确认 `VitalStride/Sources/StartWorkoutView.swift` 入口枚举 `WorkoutStartSource`（`.fromWorkout(Workout)` / `.fromTemplate(WorkoutTemplate)`）为物化目标；确认 `VitalModels` 的 `Exercise`（`nameEn`/`nameZh`）/ `Workout` / `WorkoutTemplate` 字段

**Checkpoint**: 锚点形状确认，Foundational 可开始。

---

## Phase 2: Foundational（Blocking Prerequisites）

**Purpose**: AI 输出模型扩展 + prompt 升级 + 物化层——所有 US1 UI 入口的前置。

**⚠️ CRITICAL**: 本阶段完成前，US1 UI 入口不可开始。

- [ ] T004 [US1] 在 `Packages/AIService/Sources/AIService/TrainingRecommendation.swift` 新增 `RecommendedExercise`（Codable / Sendable）：`name` / `targetSets` / `targetReps` / 可选 `targetWeight` / 可选 `note`（FR-001、Key Entities）
- [ ] T005 [US1] 在 `Packages/AIService/Sources/AIService/TrainingRecommendation.swift` 为 `TrainingRecommendation` 新增可选 `routineExercises: [RecommendedExercise]?`，保留 `exercises: [String]` 不动（FR-001，向后兼容旧缓存 + 边界场景）。验证：`cd Packages/AIService && swift build && swift test`
- [ ] T006 [US1] 更新 `VitalStride/Sources/AIAnalysisPrompts.swift` 的 `buildTrainingAdviceMessages`：要求 AI 返回 3-6 个动作，各含组数/次数/可选重量/可选备注，动作名优先命中本地动作库（FR-002）
- [ ] T007 [US1] 新建 `VitalStride/Sources/AIRoutineMaterializer.swift`：按 `RecommendedExercise.name` 反查本地 `Exercise`（`nameEn`/`nameZh` 双语匹配），命中则构建可执行 `Workout` / `WorkoutTemplate`（携带 sets/reps/weight），未命中动作 → 展示但不自动加入（show-not-add，FR-003 / FR-006，Bar D P0，不崩溃 / 不静默丢弃）

**Checkpoint**: 模型、prompt、物化层就绪，US1 UI 入口可开始。

---

## Phase 3: User Story 1 - AI 生成可执行 routine 并一键开始（Priority: P1）🎯 MVP

**Goal**: AI 训练建议卡给出带 sets/reps/weight 的 routine，一键开始或存为模板。

**Independent Test**: AI 建议卡 → 点「开始这次训练」→ routine 物化为 `ActiveWorkout`，动作名命中本地库；点「存为模板」→ 生成 `WorkoutTemplate`。

### Tests for User Story 1 ⚠️

> 先写测试并确认 FAIL，再实现。

- [ ] T008 [P] [US1] `Packages/AIService/Tests/AIServiceTests/TrainingRecommendationTests.swift`：`RecommendedExercise` + 含 `routineExercises` 的 `TrainingRecommendation` Codable 往返（SC-001）。验证：`cd Packages/AIService && swift build && swift test`
- [ ] T009 [P] [US1] `Packages/AIService/Tests/AIServiceTests/TrainingRecommendationTests.swift`：向后兼容解码——旧缓存 JSON（无 `routineExercises` 字段）应解码成功且 `routineExercises == nil`（FR-001，边界场景 / SC-003）。验证：`cd Packages/AIService && swift build && swift test`
- [ ] T010 [P] [US1] `VitalStrideTests/AIRoutineMaterializerTests.swift`：物化命中——动作名命中本地 `Exercise` → 构建出携带 sets/reps 的 `Workout` / `WorkoutTemplate`（SC-001）
- [ ] T011 [P] [US1] `VitalStrideTests/AIRoutineMaterializerTests.swift`：物化未命中——不可匹配动作被跳过（show-not-add），不崩溃、不静默丢弃可匹配部分（FR-006 / SC-003，Bar D P0）

### Implementation for User Story 1

- [ ] T012 [US1] 在 `VitalStride/Sources/AITrainingAdviceCard.swift` 增加「开始这次训练」入口：调用 `AIRoutineMaterializer` 物化为 `Workout` → 经 `StartWorkoutView` 的 `WorkoutStartSource.fromWorkout` 进入 ActiveWorkout（FR-004）
- [ ] T013 [US1] 在 `VitalStride/Sources/AITrainingAdviceCard.swift` 增加「存为模板」入口：物化为 `WorkoutTemplate`（FR-004 / SC-002）
- [ ] T014 [US1] 在 `VitalStride/Sources/AITrainingAdviceCard.swift` 处理旧格式 fallback：存在 `routineExercises` 时优先渲染可执行入口，否则回退旧文本展示（边界场景，Bar D P0）；AI 不可用沿用现有错误处理，不崩溃
- [ ] T015 [P] [US1] 在 `VitalStride/Resources/Localizable.xcstrings` 新增 UI 字符串（「开始这次训练」「存为模板」及降级提示），经 `String(localized:)` 引用（FR-007 / Constitution VI）

**Checkpoint**: US1 完整可用、可独立测试。

---

## Phase 4: Polish & Cross-Cutting Concerns

- [ ] T016 [P] [US1] `AITrainingAdviceCard` 增加 ≥2 个 SwiftUI Preview：可执行 routine 态 + 降级态（旧格式 / 含未匹配动作）
- [ ] T017 [US1] 全量验证：`cd Packages/AIService && swift build && swift test`；app target 改动经 xcodebuild（由维护者按 CLAUDE.md 后台执行）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**: 无依赖，立即开始
- **Foundational（Phase 2）**: 依赖 Setup —— BLOCKS US1 UI 入口
- **US1（Phase 3）**: 依赖 Foundational 完成
- **Polish（Phase 4）**: 依赖 US1 完成

### Within User Story 1

- 测试（T008-T011）先写并 FAIL，再实现
- 模型（T004-T005）→ prompt（T006）→ 物化层（T007）→ UI 入口（T012-T014）
- xcstrings（T015）可与 UI 入口并行

### Parallel Opportunities

- T002 / T003 并行（Setup 只读确认）
- T008 / T009（AIService 测试，同文件需串行写入但独立于 app 测试）与 T010 / T011（app 测试）跨模块并行
- T015 与 T012-T014 并行（不同文件）
- T016 独立

---

## Parallel Example: User Story 1

```bash
# 先写测试（跨模块并行）：
Task: "RecommendedExercise Codable 往返 in Packages/AIService/Tests/AIServiceTests/TrainingRecommendationTests.swift"
Task: "物化命中 in VitalStrideTests/AIRoutineMaterializerTests.swift"
Task: "物化未命中 show-not-add in VitalStrideTests/AIRoutineMaterializerTests.swift"
```

---

## Implementation Strategy

### MVP First（US1 Only）

1. 完成 Phase 1 Setup（确认锚点）
2. 完成 Phase 2 Foundational（模型 + prompt + 物化层，CRITICAL）
3. 完成 Phase 3 US1（卡片入口 + xcstrings）
4. **STOP & VALIDATE**：独立测 US1——一键开始 / 存为模板 / 降级不崩溃
5. Polish（Preview + 全量验证）

---

## Notes

- **Bar D（P0，优雅降级）**: 未匹配动作 show-not-add；旧格式 fallback 优先 `routineExercises`；AI 不可用不崩溃、不静默丢弃（FR-006、边界场景）
- **Principle V（AI 无第三方 SDK）**: 全程只经 `AIProviderChain`（FR-005）
- **Principle VI（I18n）**: 新增文案走 `String(localized:)` + xcstrings（FR-007）
- **Bar I（测试）**: Codable 往返 + 向后兼容解码 + 物化命中/未命中（SC-001 / SC-003）
- AIService 改动用 `swift build/test` 秒级验证；app target 改动由维护者按 CLAUDE.md 后台 xcodebuild
- [P] = 不同文件、无依赖；每完成一任务或逻辑组即提交
