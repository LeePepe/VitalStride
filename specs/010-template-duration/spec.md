# Feature Specification: WorkoutTemplate 预估训练时长

**Feature Branch**: `010-template-duration`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-996（[PM][Hevy] WorkoutTemplate 显示预估训练时长）。模板列表只显示"X 个动作"，缺"约 25 分钟"时长估算，用户无法判断空档能否跑完。000-baseline 未覆盖（grep `estimatedDuration` 0 匹配），故立 feature spec。

**Related Issue**: [MY-996](multica://issue/MY-996)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 模板列表显示预估时长 (Priority: P1)

用户浏览模板时，希望看到"约 25 分钟"，快速判断当前时间空档能否跑完，而非只看动作数量。

**Why this priority**: 唯一核心价值——帮用户按时间选模板。纯计算 + 展示，无 schema 变更，风险低。

**Independent Test**: 模板含 3 动作共 12 组 → 列表显示"约 ~23 分钟"（12×90s + 5min 过渡）。

**Acceptance Scenarios**:

1. **Given** 模板有若干动作/组，**When** 查看模板列表，**Then** 显示预估时长（有历史平均则用历史，否则按 totalSets×90s + 5min 过渡）。
2. **Given** 该模板有历史训练实例，**When** 估算，**Then** 优先用历史平均时长（更准）。

### Edge Cases

- 空模板（无动作）：时长展示 0 或"—"。
- 历史匹配的判定（name/structure 匹配）——简化版可只按 name。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST 提供 `WorkoutTemplate.estimatedDuration(historicalAverage:)`：有历史平均用之，否则 `totalSets×90s + 5min 过渡`（纯函数，不改 schema）。
- **FR-002**: 模板列表 MUST 显示预估时长（可读格式"约 X 分钟"）。
- **FR-003**: SHOULD 查询该模板最近训练实例算历史平均（fetchLimit 约束）。
- **FR-004**: 估算 MUST 是纯函数、可单测。
- **FR-005**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **WorkoutTemplate+Duration**（extension）：estimatedDuration。
- 无新数据模型（纯计算 + 现有 template/workout 查询）。

## Success Criteria *(mandatory)*

- **SC-001**: 模板列表显示合理的预估时长。
- **SC-002**: 有历史时用历史平均、无历史时用经验估算。
- **SC-003**: estimatedDuration 有单测（含空模板边界）。

## Assumptions

- 经验值 90s/组 + 5min 过渡（issue 草案）。
- 历史匹配用简化策略（name 匹配），精确 structure 匹配作后续。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 新计算落点 | `Packages/VitalModels/.../WorkoutTemplate+Duration.swift`（新建） |
| WorkoutTemplate 模型 | `Packages/VitalModels/.../Models/WorkoutTemplate.swift` |
| 模板列表/选择 | `VitalStride/Sources/StartWorkoutView.swift` |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
