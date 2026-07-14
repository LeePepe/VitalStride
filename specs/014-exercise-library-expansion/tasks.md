# Tasks: 动作库扩充

**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)

依赖组：Stage 1（T001, T002 并行）→ Stage 2（T003）。

---

## [T001] [数据/tooling] MIT 库映射脚本 + 合并 exercises.json → v3

**Layer**: app target / tooling（`scripts/`, `VitalStride/Resources/exercises.json`）
**Stage**: 1 · **Blocked by**: None — 可立即开始

写离线脚本（对齐现有 `scripts/backfill_exercise_defaults.py` 风格），拉 hasaneyldrm/exercises-dataset
的结构化数据（**不含图/GIF**），映射到项目 schema，去重后把**净新增**动作合并进 `exercises.json`，
bump version 2 → 3。

**Acceptance**:
- [ ] 脚本把 MIT 库的 name/bodyPart(→muscleGroup)/equipment/primary+secondary muscles 映射到项目枚举，映不动的按 fallback 归类或排除并记日志。
- [ ] 按 nameEn 归一化去重（对现有 300 + 库内自身），无重复。
- [ ] 新增动作分配全新 UUID presetId，不与现有 300 冲突。
- [ ] 现有 300 动作条目原样保留（presetId/nameZh/默认重量不变）。
- [ ] 输出 `exercises.json` version=3，`ExercisesJSONTests` 通过（结构合法/枚举合法/presetId 唯一）。

**Out of scope**: 媒体导入、9 语言指令文本。

---

## [T002] [VitalModels] Exercise 加媒体接入占位字段（additive, CloudKit-safe）

**Layer**: VitalModels
**Stage**: 1 · **Blocked by**: None — 可与 T001 并行

给 `Exercise` @Model 加媒体接入占位字段 `mediaKey: String?`（默认 nil），用于未来解析授权媒体资源。
本次不导入任何媒体，仅预留接口。

**Acceptance**:
- [ ] `Exercise` 新增 `mediaKey: String?`（可选 + 默认 nil），init 增可选参数。
- [ ] additive migration：现有 CloudKit-synced 数据零迁移、同步不破坏。
- [ ] `swift test --package-path Packages/VitalModels` 通过。

**depends_on**: []（VitalModels 是底层，不得引入反向依赖）
**red_lines**（VitalModels/CONTEXT.md）:
- 仅训练数据（含 Exercise）允许 CloudKit-synced；加字段须可选+默认值保持同步安全（宪法 I）。
- Swift 6 strict concurrency，禁 @unchecked Sendable / nonisolated(unsafe)（宪法 II）。
**test**: `swift test --package-path Packages/VitalModels`

---

## [T003] [app target] Seeder 支持 v3 增量 upsert + 解码 media 字段 + picker 预留展示点

**Layer**: app target（`VitalStride/Sources/ExerciseSeeder.swift`, `ExercisePickerView.swift`）
**Stage**: 2 · **Blocked by**: T001（v3 数据）+ T002（mediaKey 字段）

`ExerciseSeeder.ExerciseDTO` 增 `mediaKey`（可选解码），走现有版本门控增量 upsert 处理 v2→v3：
现有保留、新增插入、自定义不动。picker/详情预留 media 展示点（mediaKey 为空时不渲染、无占位错误）。

**Acceptance**:
- [ ] `ExerciseDTO` 解码 `mediaKey`（缺省 = nil，向后兼容 v2 数据）。
- [ ] v2→v3 升级：现有 300 preset 保留，净新增插入，`isCustom` 动作不受影响。
- [ ] `ExerciseSeederTests` 覆盖升级路径（现有保留 + 新增计数 + 自定义不动）。
- [ ] picker/详情预留 media 展示点，mediaKey 空时 UI 正常（不渲染媒体）。
- [ ] pre-push 全量 xcodebuild 通过。

**Blocked by**: T001, T002
**Constitution refs**: §III（分层）、§IV（如动 project.yml 资源需 xcodegen generate）
