# Feature Specification: ExerciseSet RPE 字段 (训练量化基础设施)

**Feature Branch**: `007-rpe-field`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-995（[PM][Hevy] ExerciseSet 加 RPE 字段）。Hevy 训练量化核心字段 RPE（主观努力度 1-10）完全缺失（grep 0 匹配）。是 auto-rest 调节/负荷统计/过训预警的基础设施。000-baseline 未覆盖，故立 feature spec。

**Related Issue**: [MY-995](multica://issue/MY-995)

**下游依赖方**: MY-1041（Smart Progression 第二代输入）、MY-866（RestTimer 按 RPE 调节）。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 每组标注主观努力度 (Priority: P1)

用户完成一组后，希望标注这组的努力程度（RPE 6-10），为后续训练负荷分析和智能建议提供量化基础。

**Why this priority**: 是训练量化的基础字段——多个下游功能（Smart Progression、auto-rest、负荷预警）依赖它。本身是数据层 + 简单 UI，风险低。

**Independent Test**: 训练中 SetRow Menu 选 RPE → 值持久化到 ExerciseSet → 训练详情/AI prompt 能读到。

**Acceptance Scenarios**:

1. **Given** 用户完成一组，**When** 在 SetRow Menu 选 "RPE 8"，**Then** `ExerciseSet.rpe` 持久化为 8。
2. **Given** 未标注 RPE，**When** 查看该组，**Then** rpe 为 nil（"未标注"），不影响现有流程。
3. **Given** 标注了 RPE，**When** AI 分析训练，**Then** prompt 的 set 描述含 "@ RPE8"。

### Edge Cases

- warmup 组通常 RPE < 6：可在 setType=warmup 时不显示 RPE picker（草案）。
- 旧数据 rpe=nil 的向后兼容（decode 默认 nil）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `ExerciseSet` MUST 新增 `rpe: Int?`（nil=未标注，有效 1-10），同步 CodingKeys/init/encode/decode。
- **FR-002**: SetRow Menu MUST 提供 RPE picker（暴露 6-10 + "未标注"，避免全列茫然）。
- **FR-003**: `AIPromptBuilder.SetSnapshot` MUST 携带 rpe，prompt set 描述加 "@ RPE{n}"（仅有值时）。
- **FR-004**: rpe=nil 的旧数据 MUST 向后兼容（decode 不报错、UI 不显示占位）。
- **FR-005**: `ExerciseSetTests` MUST 覆盖 rpe 的编解码/默认值。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **ExerciseSet**（`Packages/VitalModels/.../Models/ExerciseSet.swift`）：新增 `rpe: Int?`。
- **AIPromptBuilder.SetSnapshot**：新增 rpe 传递。

## Success Criteria *(mandatory)*

- **SC-001**: 用户可为任意组标注/清除 RPE，持久化正确。
- **SC-002**: 旧无 RPE 数据 100% 兼容，无迁移崩溃。
- **SC-003**: AI prompt 正确携带 RPE。

## Assumptions

- 是纯 SwiftData 字段扩展（`Int?` 可选，无需 schema 迁移评估——但若 SwiftData 要求，走 Constitution IV）。
- 下游 MY-1041/866 在此字段就绪后可增强，本 feature 不含它们。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| ExerciseSet 模型 | `Packages/VitalModels/.../Models/ExerciseSet.swift:5-14` |
| SetRow Menu | `VitalStride/Sources/ActiveWorkoutView.swift:829-879` |
| AI prompt set 描述 | `VitalStride/Sources/AIPromptBuilder.swift` |
| 下游依赖 | MY-1041（specs/006）、MY-866（specs/013） |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
