# Feature Specification: 1RM 估算 + per-exercise 趋势曲线

**Feature Branch**: `008-one-rep-max`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-865（[PM][Strong] 1RM 估算 + per-exercise 趋势曲线）。Strong 标志功能，VitalStride 完全缺失（grep `oneRepMax/1RM` 0 匹配）。1RM 把 weight×reps 归一化为同一进步标尺。000-baseline 未覆盖，故立 feature spec。

**Related Issue**: [MY-865](multica://issue/MY-865)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 训练详情看到 estimated 1RM (Priority: P1)

用户完成训练后，希望看到每个动作的 estimated 1RM（如 "95kg"），把不同 weight×reps 组合归一化，判断是否进步。

**Why this priority**: 1RM 是力量进步最直观标尺。Phase 1（model 计算 + 详情展示）是最小可行、无依赖、纯计算，风险最低。

**Independent Test**: 记一次含某动作的训练（working 组 80kg×5）→ 训练详情显示该动作 "Estimated 1RM: ~93kg"（Epley）。

**Acceptance Scenarios**:

1. **Given** 某动作有 working 组数据，**When** 查看训练详情，**Then** 显示该动作本次最高 estimated 1RM（Epley: weight×(1+reps/30)）。
2. **Given** 只有 warmup/掉次组，**When** 计算 1RM，**Then** 按 `isOneRepMaxCandidate`（working + 1-12 reps + weight>0）过滤，无候选则不显示。

### User Story 2 - per-exercise 1RM 趋势曲线 (Priority: P2)

用户希望在动作详情看到 1RM 随时间的趋势曲线，可视化长期进步。

**Why this priority**: 趋势可视化价值高但依赖 Phase 1 计算 + 新页面（历史聚合 + Swift Charts），比 Phase 1 重，故 P2。

**Acceptance Scenarios**:

1. **Given** 某动作有多次历史训练，**When** 打开该动作 1RM 趋势，**Then** 按时间显示 estimated 1RM 曲线（Swift Charts）。

### Edge Cases

- 高次数（>15 reps）Epley 偏差大——issue 注明 3-10 reps 最准，UI 可标注估算性质。
- 无历史/单点数据的趋势曲线降级展示。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST 提供 `ExerciseSet.estimatedOneRepMax`（Epley: `weight×(1+reps/30)`）+ `isOneRepMaxCandidate`（working + reps 1-12 + weight>0）过滤 helper。
- **FR-002**: MUST 提供 `WorkoutExercise.bestEstimatedOneRepMax`（本次训练该动作最高 1RM）。
- **FR-003**: `WorkoutDetailView` 每个 exercise section MUST 显示 estimated 1RM（有候选时）。
- **FR-004 [P2]**: per-exercise 1RM 趋势曲线 MUST 按时间聚合历史、用 Swift Charts 渲染（复用 FR-014 图表基线）。
- **FR-005**: 1RM 计算 MUST 是纯函数、可单测。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **ExerciseSet+OneRepMax**（extension）：estimatedOneRepMax / isOneRepMaxCandidate。
- **WorkoutExercise.bestEstimatedOneRepMax**。
- 无新数据模型（纯计算 + 现有 Workout 历史查询）。

## Success Criteria *(mandatory)*

- **SC-001**: 训练详情正确显示各动作 estimated 1RM。
- **SC-002**: 过滤规则排除 warmup/超范围组。
- **SC-003**: 1RM 计算有单测（Epley 公式 + 过滤边界）。

## Assumptions

- Epley 公式（issue 指定），3-10 reps 最准。
- Phase 1（计算+详情）先落地，趋势曲线（Phase 3）作 P2 迭代。
- 历史查询遵循 fetchLimit 约束（呼应 MY-1077）。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| ExerciseSet 模型 | `Packages/VitalModels/.../Models/ExerciseSet.swift` |
| 新 helper 落点 | `Packages/VitalModels/.../Extensions/ExerciseSet+OneRepMax.swift`（新建） |
| 训练详情展示 | `VitalStride/Sources/WorkoutDetailView.swift` |
| 图表基线 | `000` FR-009（Swift Charts） |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
