# Feature Specification: 动作选择分区语义重映射

**Feature Branch**: `023-exercise-picker-section-remapping`

**Created**: 2026-08-26

**Status**: Candidate — pending ADR-0014 AI Reviewer and Team Lead approval

**Input**: 基于 catalog v5 的真实上游标签、导入链路与 1,558 条预置动作，落实 MY-1475 对现有 17 个 picker section 的逐项产品决策；保留全部动作，只精简用户可见分区。

## User Story 1 - 更清晰且可预测的动作分区 (Priority: P1)

用户打开动作选择器时，希望按有意义的训练器械或训练方式快速定位动作，同时不被含义模糊、数量较少或过细的 section 占满侧边索引。

**Why this priority**: 侧边索引是 1,558 条动作目录的主要导航入口；分区过多会直接降低查找效率。

**Independent Test**: 使用完整、未搜索、未筛选的 catalog v5，验证 1,558 条动作全部出现且只出现一次，最终只显示 12 个非空 section；再对搜索和每个肌群筛选验证只隐藏空 section，不改变动作的 section 归属。

### Acceptance Scenarios

1. **Given** 完整 catalog，**When** 打开 picker，**Then** 按固定顺序显示 12 个非空 section：Band、Barbell、Bodyweight、Cable、Dumbbell、EZ Barbell、Kettlebell、Leverage Machine、Machine、Smith Machine、Weighted、Other。
2. **Given** `assisted` 上游标签的 15 条动作，**When** 计算产品展示分区，**Then** 全部进入 Bodyweight；动作本身不删除、不改名、不改原始 Equipment。
3. **Given** `weighted` 上游标签的 36 条动作，**When** 计算产品展示分区，**Then** 保留独立 Weighted section；动作本身不删除、不改名、不猜测具体负重器械。
4. **Given** Medicine Ball、Rope、Sled Machine、Stability Ball 或既有 Other 成员，**When** 计算产品展示分区，**Then** 全部进入 Other。
5. **Given** 搜索词或肌群筛选使部分 section 没有结果，**When** 渲染 header、侧边索引和拖动预览，**Then** 只显示当前非空 section，且剩余动作保持未筛选时的稳定 section identity。

## Clarifications and Decisions

- `assisted` 与 `weighted` 均是固定上游快照的 `sourceData.equipment` 原始标签，不是本地按名称、动作数量或说明文本推导的分类。
- `assisted` 的 15 条动作以拉伸、徒手核心动作和辅助动作方式为主，没有统一器械；因此合并到 Bodyweight，不隐藏。
- `weighted` 的 36 条动作跨徒手加重、哑铃、药球、绳/杆负重等多种实现，但共同表达“外加负重、具体器械未统一”；数量足够且没有更准确的单一目标，因此保留 Weighted，不隐藏。
- 当前 17 个 section 的逐项决策与 29 个 Equipment 的完整映射见 `contracts/section-mapping.md`。
- Other 是显式维护的映射目标，不再由“少于 N 条”运行时阈值决定。
- 最终显示名称沿用现有英文/简中名称：Band/弹力带、Barbell/杠铃、Bodyweight/自重、Cable/绳索、Dumbbell/哑铃、EZ Barbell/EZ 曲杆、Kettlebell/壶铃、Leverage Machine/杠杆器械、Machine/固定器械、Smith Machine/史密斯机、Weighted/负重、Other/其他。

## Edge Cases

- 上游名称包含 “assisted” 或 “weighted” 但 Equipment 标签不同：以原始 Equipment 字段为准，不做名称推断。
- Equipment 标签为 `assisted`/`weighted` 但名称或说明未出现相应词：仍按明确映射处理；不在运行时修正上游数据。
- 用户自定义动作选择 `assisted`：进入 Bodyweight；选择任一 Other 接收的 Equipment：进入 Other；选择 `weighted`：进入 Weighted。
- 过滤后全部 section 为空：沿用既有 empty state，不显示侧边索引。
- 后续 catalog 数量变化：不会自动改变映射；合同测试只提示维护者重新审查产品映射。

## Functional Requirements

- **FR-001**: 完整 catalog MUST 显示恰好 12 个非空 picker section，顺序与名称遵守本 spec 的最终清单。
- **FR-002**: 现有 17 个用户可见 section MUST 分别得到“保留”或“合并到明确目标”的确定决策；本轮不隐藏任何动作。
- **FR-003**: `assisted` MUST 映射到 Bodyweight；`weighted` MUST 保持独立；`medicine_ball`、`rope`、`sled_machine`、`stability_ball` MUST 映射到 Other。
- **FR-004**: Other MUST 接收合同中列出的 17 个 Equipment 值，共 96 条当前 catalog 动作；不得使用运行时频率阈值决定归属。
- **FR-005**: Bodyweight MUST 接收 `bodyweight` 与 `assisted`，当前 catalog 共 376 条；Weighted MUST 保持 36 条。
- **FR-006**: 搜索、肌群筛选、单选/多选模式 MUST 只过滤 items；header、侧边索引和拖动预览 MUST 只包含当前非空 section。
- **FR-007**: `Equipment` MUST 继续保存原始器械标签；不得重写 catalog、Seeder、SwiftData 字段或 CloudKit schema。
- **FR-008**: `ExerciseSection` 的既有 public cases 与 raw values MUST 保持可用；被合并的 legacy cases 不再由 `Equipment.section` 产生。
- **FR-009**: section jump telemetry MUST 使用最终 section 的 canonical raw value，不记录动作名称、搜索文本或原始自由文本。
- **FR-010**: 既有搜索焦点、多选、滚动重置、索引拖动竞争抑制、44pt hit target 与 VoiceOver 本地化名称 MUST 保持不变。

## Success Criteria

- **SC-001**: 1,558 条 catalog 动作完整分布到 12 个非空 section，计数依次为 54、204、376、196、345、23、61、81、38、48、36、96，总和为 1,558。
- **SC-002**: `assisted=15` 全部进入 Bodyweight；`weighted=36` 全部留在 Weighted；Other 精确为 96。
- **SC-003**: 对任意搜索词或肌群筛选，输出 section 均非空，且每个动作的 section 与未过滤状态一致。
- **SC-004**: VitalModels layer verification 与 AppUI 目标测试通过；完整 App target required check 由交付 pipeline 执行。

## Out of Scope

- 修改上游固定快照、catalog v5、导入器、Seeder 或动作文本
- 删除或隐藏任何 preset/custom exercise
- 修改 `Equipment` raw values、持久字段、SwiftData/CloudKit schema
- 依据名称或说明文本猜测具体器械
- 重设计动作卡片、搜索栏、肌群 chips 或侧边索引视觉
- 修改 TelemetryKit 公共接口

## Constitution References

- Constitution §II Swift 6 Strict Concurrency
- Constitution §III SPM Package 优先
- Constitution §VI I18n xcstrings 单源
- Constitution §Development Workflow / Planning Review
- Constitution §Cross-Cutting Quality Bars A / H / I

## Baseline References

- `specs/000-baseline-existing-codebase/spec.md` — User Story 1 / Exercise entity
- `specs/021-exercise-catalog-replacement/` — catalog v5、原始 Equipment 与 Seeder 合同
- `specs/022-exercise-picker-section-consolidation/` — 已落地的 `ExerciseSection` seam 与 picker wiring
- `specs/020-exercise-picker-search-focus-fix/` — 搜索焦点与滚动回归面
