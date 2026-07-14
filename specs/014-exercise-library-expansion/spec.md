# Feature Specification: 动作库扩充（整合 hasaneyldrm/exercises-dataset）

**Feature Branch**: `014-exercise-library-expansion`

**Created**: 2026-07-14

**Status**: Draft

**Input**: 用户请求「用 [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)（1324 动作，MIT）加到动作库中，评估整合还是替换」。评估结论：**整合，不替换**。

**Related Issue**: parent 见 Multica（本 spec fork 自需求，未在 001-future-roadmap 中，独立立项）。

**License**: 数据集代码/结构/文字为 **MIT**，可商用。练习媒体（图/GIF）为 Gym Visual 版权，**本次不导入**（需单独授权），仅在 schema 预留接入接口。

---

## 决策：整合 vs 替换

**结论：整合（extend），不替换。** 理由（basis: main，已读码确认）：

| 维度 | 替换的问题 | 整合的做法 |
|---|---|---|
| 训练历史引用 | 现有 300 动作的 `presetId`（UUID）被 `WorkoutExercise`/`TemplateExercise` 引用，替换即断引用、丢历史 | 现有 300 动作原样保留，presetId 不变 |
| 中文精校名 | 新库无 `nameZh` 精校，退化为机翻 | 现有精校名保留；新增项补 zh |
| 默认重量 | 新库无 `defaultWeight*`，丢手工调值 | 现有保留；新增项保守默认或留空 |
| 枚举一致性 | 新库 category/bodyPart/equipment 词表与项目自有 `MuscleGroup`(7)/`Equipment`(6) 不一致 | 加映射层，映不动的归类或丢弃 |
| 媒体价值 | GIF 不能随包分发（版权），替换拿不到额外价值 | 媒体本次不导入，仅预留接口 |
| 现有 seeder | — | `ExerciseSeeder` 已支持版本门控增量 upsert（按 presetId 去重），天然适配整合 |

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 动作库覆盖广度扩充 (Priority: P1)

用户在动作选择器（ExercisePickerView）中，希望能找到更多动作（尤其小众器械/孤立动作），
而不是被限制在现有 300 个内。

**Why this priority**: 核心价值 = 覆盖广度。纯数据 + 现成 seeder 增量插入，低风险、可独立交付。

**Independent Test**: 全新安装 → 动作库动作数显著多于 300（合并去重后净新增，目标 +≥600）；
现有 300 个动作（如「杠铃卧推」）仍在、名称/默认重量不变。

**Acceptance Scenarios**:

1. **Given** 全新安装，**When** seeder 运行，**Then** 动作总数 = 现有 300 + MIT 库净新增（经去重与枚举映射）。
2. **Given** 已装旧版（seedVersion=2，含 300 preset），**When** 升级到 v3，**Then** 现有 300 动作
   presetId/nameZh/默认重量不变，新增动作被增量插入，用户自定义动作（isCustom）不受影响。
3. **Given** MIT 库某动作的 equipment/muscleGroup 无法映射到项目枚举，**When** 生成合并数据，
   **Then** 该动作按 fallback 规则归类或被排除（不产生非法枚举值导致解码失败）。

### User Story 2 - 媒体接入接口预留 (Priority: P2)

用户（未来）希望动作带演示 GIF。本次不导入媒体，但数据模型与 UI 需预留接口，
便于后续接入 Gym Visual 授权媒体时零迁移。

**Why this priority**: 避免未来加媒体时再做一次 CloudKit schema 迁移。低成本预留。

**Acceptance Scenarios**:

1. **Given** Exercise 模型，**When** 加入媒体接入接口，**Then** 新增字段为可选 + 有默认值
   （additive，CloudKit-safe），现有数据零迁移、不破坏同步。
2. **Given** 动作详情/选择器 UI，**When** 媒体接口为空，**Then** UI 正常显示（不渲染媒体、无占位错误），
   预留后续填充点。

---

## 范围边界

**In scope**:
- MIT 库 → 项目 schema 的映射脚本（名称、muscleGroup、equipment、primary/secondary muscles）
- 净新增动作合并进 `exercises.json`，bump 到 v3
- `Exercise` 加媒体接入占位字段（`mediaKey: String?` 或等价），additive migration
- `ExerciseSeeder` 支持 v3 增量 upsert

**Out of scope**:
- 图片/GIF 媒体导入（版权 + 分发，需 Gym Visual 授权，另立 issue）
- 9 语言分步指令文本（本次仅结构化字段；如需 instructions 另议）
- 替换现有 300 动作

---

## Constitution refs

- **§I 健康数据隐私**：Exercise 属训练数据，允许 CloudKit-synced；加字段须可选+默认值保持同步安全。
- **§III SPM Package 优先**：模型改动落 VitalModels，用 `swift test` 验证；数据/seeder 落 app target。
- **§IV XcodeGen**：如新增资源文件需同步 project.yml。
