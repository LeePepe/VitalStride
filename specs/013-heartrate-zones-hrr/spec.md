# Feature Specification: 训练详情心率区间可视化 + HRR

**Feature Branch**: `013-heartrate-zones-hrr`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-885（[PM][Athlytic] 训练详情补齐心率区间可视化与 HRR）。已能算训练期均值/最高心率和区间分布，但 HealthKit 导入训练详情无心率分析，本地详情也缺 HRR（Heart Rate Recovery，训练后 1 分钟心率下降）。000-baseline 未覆盖 HRR，故立 feature spec。

**Related Issue**: [MY-885](multica://issue/MY-885)

**隐私**: 涉及 HealthKit 心率数据。Constitution Principle I：心率样本值不入日志。数据留设备内合规。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 训练详情心率区间可视化升级 (Priority: P1)

用户看训练详情时，希望心率区间分布从纯文本百分比升级为直观的条形可视化。

**Why this priority**: 现有数据（zoneDistribution）已具备，只需升级展示。低风险、纯 UI，是最快可交付部分。

**Independent Test**: 打开有心率数据的训练详情 → 区间分布显示为水平 stacked bar（非纯文本百分比）。

**Acceptance Scenarios**:

1. **Given** 训练有心率区间数据，**When** 查看详情，**Then** zoneDistribution 显示为水平 stacked bar / 条形列表（SwiftUI 原生 Capsule/GeometryReader）。

### User Story 2 - HRR (训练后 1 分钟心率恢复) (Priority: P2)

用户希望看到 HRR（训练结束后 1 分钟心率下降值），判断恢复质量。

**Why this priority**: Athlytic 标志指标，但需额外 fetch 训练后时段心率 + 计算，比 US1 复杂，故 P2。

**Acceptance Scenarios**:

1. **Given** 训练结束后有心率样本，**When** 查看详情，**Then** 显示"1 分钟心率恢复：{n} bpm"（训练末心率 − 结束后 ~60s 心率）。
2. **Given** 结束后心率样本不足，**When** 计算 HRR，**Then** 返回 nil、不显示该项（不报错）。

### User Story 3 - HealthKit 导入训练也显示心率分析 (Priority: P3)

用户希望从 HealthKit 导入/列表打开的训练详情也有心率区间 + HRR（当前完全没有）。

**Why this priority**: 覆盖面扩展，但依赖 US1/US2 的组件复用，故 P3。

### Edge Cases

- 结束后心率样本缺失/稀疏 → HRR nil。
- 短时训练无区间数据 → 不显示可视化。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `WorkoutDetailView` 心率区间 MUST 从纯文本升级为水平 stacked bar / 条形（SwiftUI 原生，不引复杂 Charts 依赖）。
- **FR-002**: `WorkoutHeartRateStats` MUST 新增 `heartRateRecovery1Min: Int?`，fetch 训练结束后 ~90s 心率，计算训练末心率 − 结束后 ~60s 心率；样本不足返回 nil。
- **FR-003**: `WorkoutDetailView` MUST 显示 HRR（有值时）。
- **FR-004 [P3]**: `HealthKitWorkoutDetailView` MUST 复用心率区间 + HRR 组件（当前无心率分析）。
- **FR-005**: 心率样本值 MUST NOT 写入日志（Constitution I 零日志），仅可记元数据。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **WorkoutHeartRateStats**：新增 heartRateRecovery1Min。
- 无新数据模型（扩展现有 stats + HealthKit fetch）。

## Success Criteria *(mandatory)*

- **SC-001**: 训练详情心率区间显示为可视化条形。
- **SC-002**: 有结束后心率数据时正确显示 HRR。
- **SC-003**: HealthKit 导入训练也有心率分析。
- **SC-004**: 全流程无心率样本值进入日志（可 grep 验证）。

## Assumptions

- 本地训练详情已有平均/最高心率 + 文字版区间（升级展示，非从零）。
- 用 SwiftUI 原生绘制条形（issue 明确不引复杂 Charts）。
- HealthKit 结束后时段 fetch 复用现有 HealthKitService 查询模式。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 心率统计 | `VitalStride/Sources/WorkoutHeartRateStats.swift` |
| 本地训练详情 | `VitalStride/Sources/WorkoutDetailView.swift` |
| HealthKit 训练详情 | `VitalStride/Sources/HealthKitWorkoutDetailView.swift` |
| HealthKit 查询 | `Packages/HealthKitService/`（心率 fetch 模式） |
| 隐私约束（心率不入日志） | `.specify/memory/constitution.md` Principle I |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
