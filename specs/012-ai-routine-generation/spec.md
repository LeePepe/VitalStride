# Feature Specification: AI 训练建议一键生成可执行 routine

**Feature Branch**: `012-ai-routine-generation`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-886（[PM][Fitbod] AI 训练建议一键生成可执行 routine）。现有「今日训练建议」只是 AI 返回的文本（标题/肌群/动作名），不能一键转可执行训练。Fitbod 核心价值是生成可直接开始的 routine。000-baseline 未覆盖，故立 feature spec。

**Related Issue**: [MY-886](multica://issue/MY-886)

**关联**: MY-1040（训练中单动作替代）是独立路径；本 feature 是训练前整套生成。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI 生成可执行 routine 并一键开始 (Priority: P1)

用户看 AI 训练建议时，希望 AI 直接给出带组数/次数/重量的 3-6 个动作，一键开始训练或存为模板，而非只看动作名文本。

**Why this priority**: 核心价值——把"文本建议"升级为"可执行 routine"。复用现有 AI infra + StartWorkoutView，扩展 AI 输出模型。

**Independent Test**: AI 训练建议卡 → 点"开始这次训练" → AI 返回的动作带 sets/reps 被物化成 ActiveWorkout，动作名匹配本地库。

**Acceptance Scenarios**:

1. **Given** AI 生成了含 sets/reps/weight 的 routine，**When** 点"开始这次训练"，**Then** routine 物化为可执行 ActiveWorkout（动作名匹配本地库）。
2. **Given** AI routine 就绪，**When** 点"存为模板"，**Then** 生成 WorkoutTemplate。
3. **Given** AI 返回的动作名无法匹配本地库，**When** 物化，**Then** 该动作仅展示不自动加入（优雅降级）。

### Edge Cases

- AI 返回旧格式（只有 exercises 字符串数组）→ fallback 兼容，UI 优先用新 routineExercises。
- AI 不可用 → 沿用现有错误处理，不崩溃。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `TrainingRecommendation` MUST 新增可选 `routineExercises: [RecommendedExercise]?`（name/targetSets/targetReps/targetWeight/note），保留 `exercises: [String]` 兼容旧缓存。
- **FR-002**: prompt MUST 要求返回 3-6 动作，各含 sets/reps/可选 weight/note，动作名优先匹配本地库。
- **FR-003**: MUST 新增物化层 `AIRoutineMaterializer`：按动作名反查本地 Exercise，构建可执行 Workout / WorkoutTemplate。
- **FR-004**: `AITrainingAdviceCard` MUST 加"开始这次训练" + "存为模板"入口。
- **FR-005**: MUST 复用 `AIProviderChain`（不引第三方 SDK，Constitution V）。
- **FR-006**: 无法匹配本地库的动作 MUST 优雅降级（展示但不自动加入），不崩溃、不静默丢弃。
- **FR-007**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **RecommendedExercise**（Codable/Sendable）：name/targetSets/targetReps/targetWeight/note。
- **TrainingRecommendation**：新增 routineExercises。
- **AIRoutineMaterializer**：AI 输出 → 可执行 Workout/Template 转换层。

## Success Criteria *(mandatory)*

- **SC-001**: AI routine 可一键物化为可执行训练，动作正确匹配本地库。
- **SC-002**: 可存为模板复用。
- **SC-003**: 旧格式缓存/无法匹配动作均优雅降级不崩溃。

## Assumptions

- AI infra（AIProviderChain）+ StartWorkoutView（空白/复制/模板 3 入口）已就绪。
- 小步版本：先做 routine 物化，不含复杂疲劳模型/器材偏好（issue 明确）。
- 动作库有稳定 name/id 供匹配。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| AI 建议卡 | `VitalStride/Sources/AITrainingAdviceCard.swift` |
| AI 输出模型 | `Packages/AIService/.../TrainingRecommendation.swift` |
| prompt 构建 | `VitalStride/Sources/AIAnalysisPrompts.swift`（buildTrainingAdviceMessages） |
| 物化层 | `VitalStride/Sources/AIRoutineMaterializer.swift`（新建） |
| 训练入口 | `VitalStride/Sources/StartWorkoutView.swift` |
| AI 约束 | `.specify/memory/constitution.md` Principle V |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
