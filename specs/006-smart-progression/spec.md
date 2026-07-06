# Feature Specification: 智能渐进负荷建议 (Smart Progression)

**Feature Branch**: `006-smart-progression`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-1041（[PM][Fitbod] SetRow 加 Smart Progression）。Fitbod 对标——SetRow 纯空白录入，缺"基于上次完成情况自动建议下次重量/次数"。000-baseline 未覆盖（grep `nextWeight/建议重量` 0 匹配），故立 feature spec。**依赖 MY-864（specs/004 Previous 显示）的历史查询基础设施。**

**Related Issue**: [MY-1041](multica://issue/MY-1041)

**Depends on**: `specs/004-previous-set-hint`（MY-864）—— 复用 `PreviousSetLookup` 历史查询。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 每组开始前拿到渐进负荷建议 (Priority: P1)

用户开始某组前，希望 app 根据上次该动作的完成情况主动建议"下次该用多少重量/次数"（如上次 12/12/12/12 全达标 → 建议加重），而不用自己判断该不该加。

**Why this priority**: 本 feature 的核心——把 MY-864 的"历史展示"升级为"主动建议"，是健身渐进负荷（progressive overload）的算法辅助，用户黏性核心。

**Independent Test**: 有某动作的上次训练记录 → 新训练加该动作 → SetRow 显示"建议 {重量} × {次数}"chip → 点击一键填入输入框。

**Acceptance Scenarios**:

1. **Given** 上次该动作所有组都达目标次数上限，**When** 查看 SetRow 建议，**Then** 显示 `increaseWeight`（+2.5kg 小肌群 / +5kg 大肌群）建议 + 理由。
2. **Given** 上次最后一组掉到目标次数下限以下，**When** 查看建议，**Then** 显示 `maintain`（保持重量）。
3. **Given** 上次全部组低于下限，**When** 查看建议，**Then** 显示 `decreaseWeight`（-2.5kg）。
4. **Given** 显示了建议，**When** 用户点击建议 chip，**Then** 建议值填入 weight/reps 输入框；用户手动编辑视为"不接受建议"。

### Edge Cases

- 该动作无历史（首次）→ 不显示建议（依赖 MY-864 的缺省行为）。
- 上次数据不完整（部分组未填）→ 建议降级或不显示，不崩溃。
- 单侧（unilateral）动作的建议如何表达左右重量。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST 复用 MY-864 的 `PreviousSetLookup`（specs/004）查历史，不重复实现查询。
- **FR-002**: MUST 提供 `SmartProgressionAdvisor.suggest(previous:userPreferredRepRange:)` 返回 `ProgressionAdvice`（maintain / increaseWeight / increaseReps / decreaseWeight，各带 reason）。
- **FR-003**: 加重量增量 MUST 按 muscleGroup 区分（小肌群 +2.5kg / 大肌群 +5kg，草案可调）。
- **FR-004**: SetRow MUST 显示建议 chip，支持 **tap-to-fill**（点击填入输入框），编辑后视为覆盖建议。
- **FR-005**: 建议规则 MUST 是纯函数、可单测（输入历史完成情况 → 输出 advice）。
- **FR-006**: SHOULD 加 telemetry 跟踪建议接受率（`suggestionAccepted`/`suggestionOverridden`），仅记元数据不含健康数值（Constitution I）。
- **FR-007**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **ProgressionAdvice**（enum，Equatable）：maintain/increaseWeight/increaseReps/decreaseWeight + reason。
- **SmartProgressionAdvisor**：纯函数建议引擎（可测）。
- 复用 MY-864 的 `PreviousSetLookup` / `PreviousSetResult`。

## Success Criteria *(mandatory)*

- **SC-001**: 各完成情况场景（全达标/掉次数/全低于/中等）返回正确 advice 分级。
- **SC-002**: 用户可一键填入建议值。
- **SC-003**: `SmartProgressionAdvisor` 有单测覆盖全部规则分支。

## Assumptions

- **依赖 MY-864 先落地**：本 feature 在其 `PreviousSetLookup` 基础上加建议层——串行实现（先 004 后 006）。
- 规则草案保守起步，后续按 telemetry 接受率调整。
- MY-995（RPE 字段）若落地可作 advisor 第二代输入（用户报 RPE 有余力 → 加重）——本期不依赖。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 前置：历史查询 | `specs/004-previous-set-hint`（`PreviousSetLookup`） |
| SetRow 结构 | `VitalStride/Sources/ActiveWorkoutView.swift:738-960` |
| ExerciseSet 模型（weight/reps/setType） | `Packages/VitalModels/.../Models/ExerciseSet.swift` |
| 现有 last-workout 查询范式 | `VitalStride/Sources/AIPromptBuilder.swift:130`（sort by startDate desc + first） |
| telemetry | `Packages/TelemetryKit/`（仅元数据，Constitution I） |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
