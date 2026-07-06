# Feature Specification: RestTimer 按 setType 自动切换休息时长

**Feature Branch**: `009-rest-by-settype`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-866（[PM][Strong] RestTimer 按 setType 自动切换休息时长）。Rest Timer 时长全局统一，未按 setType（warmup/working/dropSet/pyramid）区分。Strong/Hevy 都按 setType 自动切换。000-baseline 未覆盖，故立 feature spec。

**Related Issue**: [MY-866](multica://issue/MY-866)

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 休息时长按组类型自动调整 (Priority: P1)

用户完成一组后，希望休息倒计时按组类型自动给合适时长（drop set 极短、working 组较长），而非全局统一，减少手动调整。

**Why this priority**: 核心价值——按训练科学的 setType 差异化休息，复用现有 RestTimer 基础设施，风险低。

**Independent Test**: 完成一个 dropSet 组 → RestTimer 启动约 15s；完成一个 working 组 → 约 120s。

**Acceptance Scenarios**:

1. **Given** 用户完成某组且未手动设 restDuration，**When** RestTimer 启动，**Then** 用该组 setType 的默认时长（warmup 45 / working 120 / dropSet 15 / pyramid 75，草案）。
2. **Given** 用户手动设了该组 restDuration，**When** RestTimer 启动，**Then** 优先用手动值（手动 > setType 默认）。

### User Story 2 - 设置页自定义各 setType 休息偏好 (Priority: P3)

用户希望在设置页调整每种 setType 的默认休息时长。

**Why this priority**: 增强灵活性但非必需，默认值已覆盖多数场景，故 P3。

### Edge Cases

- setType 变更后已设的手动 restDuration 是否保留（手动优先，不自动覆盖）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST 提供 `SetType.defaultRestDuration`（warmup 45 / working 120 / dropSet 15 / pyramid 75 秒，草案可调）。
- **FR-002**: 完成组启动 RestTimer 时 MUST 用 `exerciseSet.restDuration ?? setType.defaultRestDuration`（手动优先，fallback setType 默认）。
- **FR-003 [P3]**: 设置页 SHOULD 提供各 setType 休息时长偏好自定义。
- **FR-004**: `defaultRestDuration` MUST 是纯映射、可单测。
- **FR-005**: 新增 UI 字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI）。

### Key Entities

- **SetType+RestDuration**（extension）：defaultRestDuration。
- 复用现有 `ExerciseSet.restDuration`、`RestLiveActivityManager`。

## Success Criteria *(mandatory)*

- **SC-001**: 各 setType 完成组后 RestTimer 时长符合默认表。
- **SC-002**: 手动设置的时长优先于 setType 默认。
- **SC-003**: defaultRestDuration 映射有单测。

## Assumptions

- RestTimer 基础设施（`RestLiveActivityManager` 接受 duration 参数）已就绪，本 feature 只改 caller 传入的时长来源。
- 可选与 MY-995 RPE 联动（RPE 高→延长休息），但本期不依赖。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| 新映射落点 | `Packages/VitalModels/.../Extensions/SetType+RestDuration.swift`（新建） |
| RestTimer 启动 caller | `VitalStride/Sources/ActiveWorkoutView.swift`（搜 `startRest`） |
| RestTimer 基础设施 | `VitalStride/Sources/RestLiveActivityManager.swift` |
| restDuration 字段 | `Packages/VitalModels/.../Models/ExerciseSet.swift` |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
