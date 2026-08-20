# Feature Specification: 动作选择分区收敛

**Feature Branch**: `022-exercise-picker-section-consolidation`

**Created**: 2026-08-20

**Status**: Draft — pending ADR-0014 planning review

**Input**: 动作选择器的器械分区过多。完整动作目录中少于 10 个动作的分区应合并到一个稳定的“其他”分区；分区应由独立属性驱动，并且可见分区图标不得重复。

## User Story 1 - 更少且稳定的动作分区 (Priority: P1)

用户打开动作选择器时，希望看到数量适中的稳定分区，而不是为只有 1–8 个动作的器械占用单独 section 和侧边索引位置。

**Independent Test**: 使用 catalog v5 的 1,558 条动作打开未过滤的动作选择器，验证原 29 个器械 bucket 收敛为 17 个 picker section；13 个不足 10 条的器械 bucket 共 30 条动作全部进入“其他”。

### Acceptance Scenarios

1. **Given** 完整、未过滤 catalog，**When** 计算 picker section，**Then** 每个原始器械 bucket 少于 10 条的动作进入“其他”，其余 16 个 bucket 保持独立，最终为 17 个 section。
2. **Given** 用户切换肌群筛选或输入搜索词，**When** 某个 section 当前只剩少于 10 个结果，**Then** 该动作仍留在原 section，不因当前过滤结果动态并入“其他”。
3. **Given** 用户自定义动作选择了一种低频器械，**When** 它出现在 picker，**Then** 它通过同一稳定映射进入“其他”，不创建新的独立 section。
4. **Given** 搜索结果只包含一个低频器械动作，**When** 渲染结果，**Then** 只显示“其他”section，搜索、选择与滚动行为正常。

## User Story 2 - 可区分的分区图标 (Priority: P1)

用户通过右侧索引、section header 和拖动预览识别分区时，希望每个分区有唯一图标，避免多个 section 使用同一个符号而无法快速区分。

**Independent Test**: 对 `ExerciseSection.allCases` 检查 icon 非空且集合大小等于 case 数；在 iPhone 16 Simulator 验证 header、索引和拖动预览均使用 section icon。

### Acceptance Scenarios

1. **Given** 17 个 picker section，**When** 读取其 SF Symbol，**Then** 17 个值全部非空且互不重复。
2. **Given** 用户滚动或拖动侧边索引，**When** 高亮 section 改变，**Then** header、索引高亮和预览弹窗显示同一 section 的 label 与 icon。
3. **Given** VoiceOver 开启，**When** 聚焦侧边索引项，**Then** 朗读 section 的本地化名称，而不是原始 equipment 值或重复 icon 名称。

## Clarifications

- “少于 10”按完整、未搜索、未筛选的 catalog 统计；阈值为严格 `< 10`，恰好 10 条的 `rope` 保持独立。
- 当前 catalog 中低频器械为 `elliptical_machine`、`hammer`、`skierg_machine`、`stationary_bike`、`stepmill_machine`、`tire`、`trap_bar`、`upper_body_ergometer`、`olympic_barbell`、`wheel_roller`、`bosu_ball`、`resistance_band`、`roller`，合计 30 条动作。
- 新属性是稳定的计算属性，不写入 SwiftData/CloudKit；section 由 `Exercise.equipment` 映射得到，避免 schema 迁移与已有用户数据回填。
- `Equipment` 继续表达原始器械语义；picker 的分组、索引、图标和 section telemetry 改用 `ExerciseSection`。

## Edge Cases

- catalog 后续升级使某个 bucket 跨过 10 条边界：catalog contract test 必须失败，要求维护者显式更新 `ExerciseSection` 映射与预期分布，禁止运行时静默改组。
- 肌群筛选使所有 section 为空：保持既有 empty state，不渲染侧边索引。
- 多个动作具有相同名称或同一动作有多种来源：section 只由 equipment 映射，不参与身份或去重。
- 自定义动作没有 preset ID：仍按 equipment 映射 section，不依赖 catalog source metadata。

## Functional Requirements

- **FR-001**: 系统 MUST 提供独立于 `Equipment` 的 `ExerciseSection` 值类型；case 集固定为 `assisted`、`band`、`barbell`、`bodyweight`、`cable`、`dumbbell`、`ezBarbell`、`kettlebell`、`leverageMachine`、`machine`、`medicineBall`、`rope`、`sledMachine`、`smithMachine`、`stabilityBall`、`weighted`、`other`。
- **FR-002**: `Exercise` MUST 暴露稳定的 `section` 计算属性；不得新增持久化字段或改变 SwiftData/CloudKit schema。
- **FR-003**: 当前 catalog 中原 bucket 数量严格少于 10 的 13 个 equipment MUST 映射到 `other`；恰好 10 条及以上的 bucket MUST 保持独立。
- **FR-004**: picker 的 section 身份 MUST 在搜索、肌群筛选、单选/多选模式之间保持稳定，不得按过滤后的可见数量重新计算阈值。
- **FR-005**: 未过滤 catalog MUST 得到 17 个 section；`other` MUST 包含 30 条动作，且任何 section 均不得少于 10 条。
- **FR-006**: `ExerciseSection` 的每个 case MUST 提供英文/简体中文名称与非空 SF Symbol；所有 SF Symbol MUST 一一唯一。
- **FR-006a**: `ExerciseSection` raw value MUST 使用 canonical lowercase ASCII snake_case，确保现有 `TelemetryIdentifier(validating:)` 可无损接受。
- **FR-007**: section header、右侧索引、拖动预览、scroll anchor、drag state 与可见 section state MUST 全部使用 `ExerciseSection`，不再使用 `Equipment` 作为 UI section ID。
- **FR-008**: `exercisePickerSectionJump` telemetry MUST 继续使用强类型 canonical identifier；from/to 改为 section raw value，禁止自由文本和动作名称。
- **FR-009**: 既有搜索焦点、多选、滚动重置、索引拖动竞争抑制、44pt hit target 与固定网格 inset 行为 MUST 保持不变。

## Success Criteria

- **SC-001**: 未过滤 1,558 条 catalog 从 29 个 equipment bucket 收敛为 17 个 picker section，`other=30`。
- **SC-002**: `Set(ExerciseSection.allCases.map(\.sfSymbol)).count == ExerciseSection.allCases.count`，且所有 symbol 非空。
- **SC-003**: 搜索与每个肌群筛选下，同一动作的 `section` 始终等于未过滤状态的 section。
- **SC-004**: VitalModels build/test、目标 app tests、完整 App target required check、`claude-review` 与 `codex-review` 全绿。

## Out of Scope

- 修改 29-case `Equipment` taxonomy、合并原始 equipment 值或更改动作的设备元数据
- 修改动作主次肌肉、名称、说明、媒体或 catalog 来源
- 新增用户自定义 section、section 编辑 UI 或设置项
- 将 section 写入 bundled catalog、SwiftData 或 CloudKit
- 重设计动作卡片、搜索栏或肌群筛选 chips

## Constitution References

- Constitution §II Swift 6 Strict Concurrency
- Constitution §III SPM Package 优先
- Constitution §VI I18n xcstrings 单源
- Constitution §Development Workflow / Planning Review
- Constitution §Cross-Cutting Quality Bars H / I / K

## Baseline References

- `specs/000-baseline-existing-codebase/spec.md` — User Story 1 / Exercise entity
- `specs/021-exercise-catalog-replacement/spec.md` — catalog v5 数量与 equipment 数据合同
