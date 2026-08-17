# Feature Specification: 动作目录全量替换

**Feature Branch**: `021-exercise-catalog-replacement`

**Created**: 2026-08-17

**Status**: Approved

**Input**: 以 `hasaneyldrm/exercises-dataset` 固定快照完整替换所有可匹配动作的数据，补齐全部上游动作与十种语言文本；VitalStride 独有动作不删除、不改动。

**Supersedes**: `specs/014-exercise-library-expansion/` 的“只扩充、过滤不支持器械、丢弃语言文本”数据策略。既有稳定 UUID、中文动作名、默认值与媒体占位的兼容承诺继续有效。

## User Story 1 - 统一且完整的动作数据 (Priority: P1)

用户希望动作目录完整采用一个固定、可复现的数据源，而不是继续维护部分导入、字段缺失和错误主次肌肉映射的混合目录。

**Independent Test**: 从 catalog v4 生成 v5 后，验证固定快照的 1,324 个 source ID 全部且仅出现一次；现有训练引用仍指向同一 SwiftData preset；VitalStride 独有和自定义动作未改变。

### Acceptance Scenarios

1. **Given** 固定上游快照包含 1,324 条记录，**When** 生成 catalog v5，**Then** 1,324 个 source ID 全部存在，8 对同名不同 ID 的记录均保留，另保留 234 条 VitalStride 独有 preset，总数为 1,558。
2. **Given** 一个动作同时存在于 v4 和上游，**When** 升级到 v5，**Then** 英文名、粗分类、器械、主要肌肉和次要肌肉采用上游派生值；稳定 UUID、中文名、默认重量/次数、`mediaKey`、训练关系和模板关系保持不变。
3. **Given** 一个上游动作当前不存在，**When** 生成并 seed v5，**Then** 它以确定性 UUIDv5 新增；中文动作名回退英文，默认重量保持空值。
4. **Given** 一个 preset 仅属于 VitalStride 或一个动作由用户自定义，**When** 运行 v5 迁移，**Then** 其全部既有字段保持不变。
5. **Given** 普通下拉类动作的上游 `target=lats`、`muscle_group=biceps`，**When** 生成 app 字段，**Then** `primaryMuscles=[lats]`，`secondaryMuscles` 保持上游顺序，绝不把 `muscle_group` 当主要肌肉。

## User Story 2 - 可追溯的多语言完整快照 (Priority: P1)

维护者需要离线、可审查、可重复生成的动作数据，并保留上游所有文本与来源字段，后续 UI 才能可靠消费。

**Independent Test**: 使用固定 commit 和 SHA-256 连续运行生成器两次，catalog 和 reconciliation report 字节一致；每条上游记录的十种语言说明和步骤完整存在。

### Acceptance Scenarios

1. **Given** 上游 commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd`，**When** 读取源 JSON，**Then** SHA-256 必须等于 `656634224b8977b99a6d765470ee123260d4979715eaa4e7c0b7c8bb0d79f93d`，否则停止且不写输出。
2. **Given** 合法快照，**When** 生成 catalog，**Then** `en/es/fr/hi/it/ko/pl/ru/tr/zh` 的 `instructions` 与 `instruction_steps` 全部保存在 bundled JSON，不复制到 SwiftData。
3. **Given** 上游提供媒体路径、媒体 ID、时间和 attribution，**When** 生成 catalog，**Then** 只保存元数据；仓库和 App bundle 不新增图片/GIF二进制。
4. **Given** 同一输入连续生成两次，**When** 比较产物，**Then** catalog 与 reconciliation report 字节相同。

## Edge Cases

- 上游不同 source ID 共享相同规范化名称：全部保留；最多一个继承既有 VitalStride UUID，其他使用确定性 UUIDv5。
- VitalStride 侧规范化名称产生多义匹配或 UUID 碰撞：生成失败，不猜测。
- catalog v5 存在重复 stable ID、重复 source ID、未知来源或语言缺失：Seeder 在任何 SwiftData 写入前拒绝。
- SwiftData save 失败：回滚 context，不升级 `seedVersionKey`，下次启动重试。
- stored version 与 bundle 相同但数据库缺少 preset：按完整 ID 集恢复缺项，不因“已有任意 preset”提前返回。

## Functional Requirements

- **FR-001**: 生成器 MUST 固定上述 commit 和 SHA-256，禁止读取 moving `main`。
- **FR-002**: catalog v5 MUST 包含 1,324 条 upstream-backed 和 234 条 VitalStride-only 记录，总计 1,558。
- **FR-003**: 每个 upstream-backed row MUST 保留上游全部字段并标记来源；每个 VitalStride-only row MUST 显式标记为 VitalStride 来源。
- **FR-004**: app `primaryMuscles` MUST 由上游 `target` 派生；`secondaryMuscles` MUST 由 `secondary_muscles` 派生并仅移除与 primary 完全相同的重复项。
- **FR-005**: `Equipment` MUST 覆盖上游全部 28 个精确值并保留六个既有 raw value 的解码兼容性。
- **FR-006**: 匹配 preset 的稳定 UUID、中文名、默认重量、默认次数、`mediaKey` 和关系 MUST 保持不变。
- **FR-007**: VitalStride-only preset 与自定义动作 MUST 不被 v5 canonical migration 修改或删除。
- **FR-008**: 十种语言说明/步骤 MUST 保存在 bundled catalog，MUST NOT 复制到 CloudKit-synced `Exercise`。
- **FR-009**: 媒体路径与 attribution MUST 作为 metadata 保留；图片/GIF二进制 MUST NOT 下载、打包或展示。
- **FR-010**: Seeder MUST 先验证后变更、只执行一次最终 save、失败 rollback，并仅在 save 成功后更新 catalog version。
- **FR-011**: 生成器单测与 muscle validator MUST 进入 required `Lint & policy` CI job。

## Success Criteria

- **SC-001**: reconciliation report 精确得到 1,135 UUIDv5 matches、66 original-name matches、123 new upstream、234 VitalStride-only、0 ambiguity、0 collision。
- **SC-002**: Cable Pulldown 回归值为 primary `lats`、secondary `biceps, forearms`。
- **SC-003**: v4→v5 后，已有 workout/template 引用的 preset 对象身份及关系保持不变。
- **SC-004**: 连续两次生成产物字节一致，所有本地/CI验证命令通过。

## Out of Scope

- 动作详情页或任何说明 UI
- 新增除既有中文名以外的本地化动作名称
- 下载、打包或显示上游图片/GIF
- 超出忠实使用上游 `target`/`secondary_muscles` 的逐动作解剖学再审校
- 删除、筛选或标记 VitalStride 独有动作

## Constitution References

- Constitution §II Swift 6 Strict Concurrency
- Constitution §III SPM Package 优先
- Constitution §IV XcodeGen Source of Truth
- Constitution §VI I18n xcstrings 单源
- Constitution §Development Workflow / PR-Required Workflow

## Design Reference

- `docs/superpowers/specs/2026-08-17-exercise-catalog-replacement-design.md`
