# Implementation Plan: 动作库扩充

**Spec**: [spec.md](./spec.md) · **Branch**: `014-exercise-library-expansion`

## 技术路径

整合而非替换。复用现有版本门控 seeder（`ExerciseSeeder`，按 `presetId` 增量 upsert）。
数据合并在离线脚本完成，运行时只解码新版 `exercises.json`。

## 按 layer 拆分（依赖只能向下）

| Task | Layer | 交付 | 依赖 |
|---|---|---|---|
| T001 | app target / tooling | 映射脚本：MIT 库 → 项目 schema，导出净新增合并进 `exercises.json`（v3） | 无，可立即开始 |
| T002 | VitalModels | `Exercise` 加 `mediaKey: String?` 媒体接入占位字段 + additive migration | 无，可与 T001 并行 |
| T003 | app target | `ExerciseSeeder` 解码 media 字段 + v3 增量 upsert；picker 预留 media 展示点（占位不渲染） | T001 + T002（Stage 2） |

## 关键决策

- **presetId 稳定**：MIT 库动作生成新 UUID 作 presetId，与现有 300 的 UUID 不冲突；现有 300 原样保留。
- **枚举映射 fallback**：MIT 的 bodyPart/target → `MuscleGroup`(chest/back/shoulders/legs/arms/core/fullBody)；
  equipment → `Equipment`(barbell/dumbbell/machine/bodyweight/cable/kettlebell)。映不动 → fallback 到
  最接近类 或 排除（脚本记日志，不产非法枚举）。
- **去重**：按 nameEn 归一化（小写/去空格）比对现有 300 + 库内自身，避免重复动作。
- **CloudKit-safe migration**：`mediaKey` 可选 + 默认 nil，纯 additive，现有同步数据零迁移（宪法 I/§VitalModels red_lines）。
- **媒体本次不落盘**：`mediaKey` 只存标识（如库内 exercise id），后续接 Gym Visual 授权时用它解析真实 URL/bundle 资源。

## 验证

- T001：脚本产出 `exercises.json` v3，`ExercisesJSONTests` 通过（结构/枚举合法/无重复 presetId）。
- T002：`swift test --package-path Packages/VitalModels` 通过。
- T003：`ExerciseSeederTests` 覆盖 v2→v3 升级路径（现有保留 + 新增插入 + 自定义不动）。
- app target：pre-push 全量 xcodebuild。

## Constitution refs

§I（隐私/CloudKit 同步范围）、§III（SPM 分层 + swift test）、§IV（XcodeGen 资源同步）。
