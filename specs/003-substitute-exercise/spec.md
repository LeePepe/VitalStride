# Feature Specification: 训练中 AI 智能替代动作 (Substitute Exercise)

**Feature Branch**: `003-substitute-exercise`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-1040（[PM][Fitbod] ActiveWorkoutView 加 Substitute Exercise）。Fitbod 对标——训练中器械被占/想换变式时，从 300 个动作里手选决策成本高。现有「替换动作」调全量 picker，缺 AI 同肌群智能推荐。000-baseline 未覆盖，故立 feature spec。

**Related Issue**: [MY-1040](multica://issue/MY-1040)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI 推荐同肌群替代动作 (Priority: P1)

用户训练中遇到器械被占/不想做某动作，希望快速拿到 3 个同主肌群的替代建议，而不是从 300 个动作里自己筛。

**Why this priority**: 本 feature 的核心价值——降低训练中切换动作的决策成本，不打断节奏。现有全量 picker 是可用 fallback，本功能是决策辅助优化。

**Independent Test**: 训练中点某动作的 `⋮` Menu → 「智能替代」→ sheet 弹出 3 张 AI 推荐 card（动作名+主肌群+理由）→ 点一张 → 当前动作被替换 + dismiss。

**Acceptance Scenarios**:

1. **Given** 用户在训练中某动作上，**When** 点 `⋮` Menu 的「智能替代」，**Then** sheet 弹出并调 `AIProviderChain`，返回 3 个同主肌群、非当前动作的替代建议（各带一行推荐理由）。
2. **Given** AI 推荐 sheet 已显示，**When** 点某个替代 card，**Then** 当前 `workoutExercise.exercise` 替换为所选、sheet dismiss、触发 haptic。
3. **Given** AI 不可用（无 API Key / 网络失败），**When** 触发智能替代，**Then** 显示 inline 错误提示 + 一键跳到 `ExercisePickerView`（预选当前 muscleGroup）作为 fallback。

### Edge Cases

- AI 返回的 `exerciseId` 在本地动作库找不到对应 Exercise（反查失败）→ 跳过该条或整体回落到手动 picker。
- AI 返回少于 3 个 / 含当前动作本身 → 过滤后展示实际可用数量。
- AI 返回非预期 JSON 格式 → 不崩溃，回落 fallback。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `ActiveWorkoutView` 动作 `⋮` Menu MUST 新增「智能替代」入口（在「替换动作」上方），保留现有全量「替换动作」作 fallback。
- **FR-002**: 智能替代 MUST 复用现有 `AIProviderChain`（不新建 provider、不引第三方 SDK — Constitution V），prompt 含当前动作名/主肌群/器材，请求 3 个同主肌群替代。
- **FR-003**: AI 返回 MUST 结构化解析（如 JSON `[{exerciseId, reason}]`），按 `exerciseId` 反查本地 SwiftData Exercise。
- **FR-004**: AI 不可用时 MUST 提供 fallback：inline 错误 + 跳 `ExercisePickerView`（预选当前 muscleGroup），不得静默失败（Constitution 错误处理）。
- **FR-005**: 选中替代后 MUST 更新 `workoutExercise.exercise` 并 dismiss + haptic。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。
- **FR-007**: AI prompt/响应处理 MUST NOT 将用户健康数值写入日志（Constitution I；本功能仅用动作元数据，天然低风险，但解析日志需注意）。

### Key Entities

- 无新数据模型（复用现有 `Exercise` 的 `muscleGroup`/`equipment` 字段）。
- 新增视图 `ExerciseSubstituteSheet` + 可能的 `ExerciseSeeder.findByPresetId(_:)` 反查 helper。

## Success Criteria *(mandatory)*

- **SC-001**: 训练中 3 次点击内完成"动作 → 智能替代 → 选定新动作"，无需进全量 picker。
- **SC-002**: AI 推荐的替代均为同主肌群、非当前动作。
- **SC-003**: AI 不可用场景 100% 回落到可用的手动 picker，无死路/崩溃。

## Assumptions

- 与 MY-886（训练前 AI 生成整套 routine）是两条独立路径，本 feature 只做训练中单动作替代。
- AI infra（`AIProviderChain` Zhipu/AppleIntelligence）已就绪且被多处复用，无需新建。
- 动作库有稳定的 preset id 可供 AI 引用 + 本地反查。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 现有 replace 入口（Menu + sheet） | `VitalStride/Sources/ActiveWorkoutView.swift:596-613` / `:87-91` |
| 全量 picker（fallback 目标） | `VitalStride/Sources/ExercisePickerView.swift` |
| AI 扩展点 | `Packages/AIService/Sources/AIService/AIProviderChain.swift`、`AIProvider.swift` |
| Exercise 模型（muscleGroup/equipment） | `Packages/VitalModels/.../Models/Exercise.swift` |
| 动作反查 | `VitalStride/Sources/ExerciseSeeder.swift` |
| 宪法约束（AI 无第三方 SDK / 隐私） | `.specify/memory/constitution.md` Principle V / I |
