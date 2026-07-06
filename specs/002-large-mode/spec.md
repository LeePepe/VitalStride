# Feature Specification: Active Workout 大字号模式 (Large Mode)

**Feature Branch**: `002-large-mode`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-997（[PM][Hevy] ActiveWorkoutView 加大字号模式）。Hevy "Now Lifting" 对标——健身房场景手机放远处看不清当前组重量×次数。000-baseline 未覆盖（grep `largeMode/focusMode` 0 匹配），故立 feature spec。

**Related Issue**: [MY-997](multica://issue/MY-997)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 健身房远距离读组数据 (Priority: P1)

用户训练时手机放在凳子/地面/靠墙，眼睛距离 0.6–1.5m，需要一眼看清当前组的目标重量和次数。当前所有字号 ≤ `.title3`、输入框 ~70pt 宽，距离外难辨识。

**Why this priority**: 这是本 feature 的唯一核心价值——workout-specific 的远距离可读性。是 Hevy 的差异化卖点，用户一进训练就能用、感知强。

**Independent Test**: iPhone 模拟器进 `ActiveWorkoutView` → 点 toolbar 大字号 toggle → weight/reps/timer 字号明显放大、输入框变宽 → 退出重进训练仍保持大字号。

**Acceptance Scenarios**:

1. **Given** 用户在训练中，**When** 点 toolbar 大字号 toggle，**Then** weight/reps 输入字号 ≥ 28pt、timer 显示 `.largeTitle`、exercise name `.title2`，切换有 `withAnimation(.easeInOut(0.2))` 过渡。
2. **Given** 大字号已开启，**When** 退出训练再次进入，**Then** 大字号状态保持（`@AppStorage` 持久化）。
3. **Given** 大字号开启，**When** SetRow 输入框放大（70→110pt，minHeight 60），**Then** tap target 仍 ≥ 44pt，无 layout 溢出。

### Edge Cases

- 系统 Dynamic Type 已调至最大时，大字号仍能进一步放大（本模式独立于系统字号，见 Assumptions）。
- 单侧（unilateral）weight 双输入框在大字号下横向空间是否溢出——需 Preview 双模式各验一次。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `ActiveWorkoutView` toolbar MUST 提供大字号 toggle，状态由 `@AppStorage("activeWorkoutLargeMode")` 持久化。
- **FR-002**: 大字号模式下 weight/reps 输入字号 MUST ≥ 28pt、timer MUST 用 `.largeTitle`、exercise name MUST 用 `.title2`。
- **FR-003**: SetRow 输入框在大字号下 MUST 自适应扩大（约 70→110pt）且 minHeight ≥ 60（保证 tap target ≥ 44pt，Constitution 无障碍）。
- **FR-004**: toggle 切换 MUST 有 `withAnimation` 平滑过渡。
- **FR-005**: 大字号仅作用于 `ActiveWorkoutView`，MUST NOT 影响其他页面或替代系统 Dynamic Type。
- **FR-006**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI，no_hardcoded_chinese）。

### Key Entities

- 无新数据模型。仅新增 `@AppStorage("activeWorkoutLargeMode"): Bool` 偏好 + `ActiveWorkoutView` 内的 conditional font/frame helper。

## Success Criteria *(mandatory)*

- **SC-001**: 大字号开启后，1.5m 距离可辨识当前组 weight×reps（人工验收）。
- **SC-002**: toggle 状态跨训练会话持久化。
- **SC-003**: 两种模式 Preview/snapshot 各渲染一次，无 layout 溢出。

## Assumptions

- 大字号是 **workout-specific 的"健身房模式"**，独立于系统 Accessibility Dynamic Type——用户可视力正常但想看清远处。二者叠加（系统已最大时本模式再放大）。
- 复用现有 `HapticManager`（toggle 触觉反馈）。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| Timer bar 字号 | `VitalStride/Sources/ActiveWorkoutView.swift:125-172` |
| SetRow 输入框宽度/字号 | `VitalStride/Sources/ActiveWorkoutView.swift:732-826` |
| toolbar 增加位置 | `ActiveWorkoutView.swift` 搜 `.toolbar` |
| 触觉反馈 | `Packages/VitalUI/.../HapticManager.swift` |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
| 无障碍 tap target | `.specify/memory/constitution.md`（Quality Bars） |
