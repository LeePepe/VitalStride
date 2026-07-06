# Feature Specification: 训练 SetRow 上次重量提示 (Previous)

**Feature Branch**: `004-previous-set-hint`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-864（[PM][Strong] 训练 SetRow 显示上次重量提示）。Strong/Hevy 对标——训练中每组要凭记忆输入上次重量。000-baseline 未覆盖（grep `previous/lastWeight` 0 匹配），故立 feature spec。**是 MY-1041（Smart Progression）的前置基础设施**。

**Related Issue**: [MY-864](multica://issue/MY-864)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 训练中看到上次同动作的重量×次数 (Priority: P1)

用户训练中改某组重量时，希望直接看到"上次这个动作这一组做了多少"，照练或微调，而不用切到训练历史翻查或凭记忆。

**Why this priority**: Strong/Hevy 公认最实用的训练辅助 UX。是渐进负荷的决策起点，也是 MY-1041 Smart Progression 的数据基础——先有"历史查询 + 展示"，才能在其上做"智能建议"。

**Independent Test**: 记录一次含某动作的训练并完成 → 再开新训练加同一动作 → SetRow 显示灰字"上次 60kg × 10"。

**Acceptance Scenarios**:

1. **Given** 用户曾完成含动作 X 的训练，**When** 新训练中添加动作 X，**Then** 每个 SetRow 显示对应 index 的上次值"上次 {重量}{单位} × {次数}"（灰字/tertiary）。
2. **Given** 动作 X 从未训练过（首次），**When** 添加动作 X，**Then** SetRow 不显示上次提示（无占位、不报错）。
3. **Given** 上次训练该动作的组数少于当前组 index，**When** 查看多出的组，**Then** 该组无上次值（优雅缺省）。

### Edge Cases

- 重量单位偏好（kg/lb）：上次值按当前 `WeightUnit` 偏好换算显示。
- 单侧（unilateral）动作的上次值展示方式（左右重量）。
- 大量历史训练时的查询性能——需 fetchLimit / 按 exercise 索引，避免遍历全部历史（与 MY-1077 性能项呼应）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `SetRow` MUST 在有上次数据时显示灰字"上次 {重量} × {次数}"（tertiary foreground，caption 字号）。
- **FR-002**: 上次值查询 MUST 找该 exercise 上一次**已完成**训练（`endDate != nil`、排除当前训练）的同 index 组。
- **FR-003**: 首次训练该动作 / 组 index 越界时 MUST 优雅缺省（不显示、不崩溃）。
- **FR-004**: 上次值 MUST 按当前 `WeightUnit` 偏好换算显示。
- **FR-005**: 历史查询 MUST 有上限/索引，禁止无界遍历全部训练历史（性能，与 MY-1077 一致）。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。
- **FR-007**: 查询逻辑 SHOULD 抽为可测试的独立 helper（如 `PreviousSetLookup`），供 MY-1041 复用。

### Key Entities

- 无新数据模型（查询现有 `Workout`/`WorkoutExercise`/`ExerciseSet`）。
- 新增查询服务 `PreviousSetLookup`（可测），`SetRow` 新增 `previousSet: ExerciseSet?` 输入。

## Success Criteria *(mandatory)*

- **SC-001**: 训练中每个 SetRow 正确显示上次同 index 组的重量×次数。
- **SC-002**: 查询在有大量历史训练时不引入可感知卡顿（有 fetchLimit/索引）。
- **SC-003**: `PreviousSetLookup` 有单测覆盖（找到/未找到/越界/单位换算）。

## Assumptions

- 是 MY-1041 Smart Progression 的**前置**：本 feature 建"per-exercise 历史查询 + 展示"基础，MY-1041 在其上加"智能建议层"。
- `addSet()` 现有的复制 lastMainSet 逻辑（L637-650）与本功能正交（那是新增组的预填，本功能是展示上次值）。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| SetRow 输入框 | `VitalStride/Sources/ActiveWorkoutView.swift`（SetRow L694-954） |
| addSet 复制逻辑 | `ActiveWorkoutView.swift:637-650` |
| Workout/Exercise/Set 模型 | `Packages/VitalModels/.../Models/`（Workout/WorkoutExercise/ExerciseSet） |
| 重量单位偏好 | `Packages/VitalModels/.../Enums/`（WeightUnit） |
| 查询性能约束 | 呼应 MY-1077（无上限 @Query） |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
| 后续依赖 | MY-1041 Smart Progression（`specs/006` 待建） |
