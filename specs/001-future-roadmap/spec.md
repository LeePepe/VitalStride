# Feature Specification: VitalStride Future Roadmap (V2+ Unimplemented Features)

**Feature Branch**: `001-future-roadmap`

**Created**: 2026-07-04

**Status**: Roadmap (planning-only — 承接已删除的 `docs/DESIGN.md` V2+ 表，**不是** build authorization)

**Input**: `docs/DESIGN.md`（前分层时代的混合设计文档）已按 layered-agent-context 框架拆解：已实现的架构描述归 `CONTEXT.md`/宪法/ADR/`specs/000-baseline`，其 **V2+ 未实现规划**迁移至本文。所有功能已逐条对代码核实实现状态（见各 Story）。本文只承接"尚未启动"的功能，不重述已实现内容（见 §Not Migrated from DESIGN.md）。

---

## Roadmap Framing

这份 spec 是一个 **umbrella（伞形）roadmap**，不是单一 feature 的可执行规格。读它前先理解三条约定：

1. **planning-only，不是 ship 承诺**。本文记录 8 个已讨论但尚未启动的未来功能，按优先级排序 + 给方向性约束。它**不授权任何实现**，不排期。

2. **Fork 契约**。某个功能真正启动时，从本 roadmap **fork** 出独立目录 `specs/00N-<name>/`（编号从 `002` 起），届时才写可执行级别的 FR / Acceptance Scenarios / tasks，并录入 Multica issue。**在 fork 之前，这些功能不进 Multica**——所以"Multica 里查不到这 8 个功能的 issue"是**正确状态**，不是遗漏。

3. **`[deferred]` FR 语气约定**。本文的 Functional Requirements 用 `MUST`，但**全部带 `[deferred]` 标签**。其语义是「**当**该功能启动时，它 MUST 满足此约束」，而**不是**「现在必须实现」。任何 reviewer / agent 读到 `[deferred]` FR，不得将其视为当前 ship 义务或未完成缺陷。

> 这与 `specs/000-baseline-existing-codebase/` 是同一模板的两种合法变体：`000` 是 **as-built audit**（记录过去态已实现），`001` 是 **roadmap**（记录未来态未实现）。

---

## User Scenarios & Testing *(mandatory)*

8 个未实现功能按**风险与内聚度**聚为 3 个优先级 User Story（不是 8 个孤立 Story）。优先级依据见 §Assumptions（相对 DESIGN 原始"低/中/高"有重排）。

### User Story 1 - 力量训练录入能力增强 (Priority: P1)

扩展 V1 核心训练循环（对标 `000` 的 US1 per-set 录入），覆盖 4 个功能：手动补录、力竭组、超级组、多日训练计划。

**Why this priority**: 这一簇都直接增强已上线的核心训练录入，复用现有 `SetType` / `WorkoutTemplate` / `WorkoutSource` 实体，改动内聚在 VitalModels + app UI 层，**不引入新 package、不触碰宪法红线**，是风险最低、离核心价值最近的一簇。

**Independent Test**: 每个子功能可独立验证——选中一次训练做无设备补录 / 将某组标记为力竭并在历史区分显示 / 两个动作交替录入为超级组 / 从多日 Routine 发起某日训练。

**Acceptance Scenarios**（方向性，fork 时细化）:

1. **手动补录** — **Given** 用户未佩戴设备完成了一次训练，**When** 事后手动创建一次训练并逐组录入重量/次数，**Then** 该训练以 `WorkoutSource.recorded` 持久化，与设备记录的训练在历史中同等展示。
2. **力竭组 (Failure Set)** — **Given** 用户将某组练到力竭，**When** 标记该组为 failure 类型，**Then** 该组以 failure 类型持久化，且训练量统计规则与 working 组有明确区分（比照 warmup 不计入总量的既有处理）。
3. **超级组 (Superset)** — **Given** 用户想交替做两个动作，**When** 将两动作编为一个超级组，**Then** 二者以关联组形式录入与展示（类比现有 dropSet/pyramid 的子组关联 UI），组间休息规则适配交替节奏。
4. **多日 Routine** — **Given** 用户有一个多日训练计划，**When** 从某日计划发起训练，**Then** 该日的目标动作/组数预填，基于现有单层 `WorkoutTemplate` 扩展而非新建平行模型。

---

### User Story 2 - AI 与数据管道扩展 (Priority: P2)

覆盖多 AI Provider 扩展、导入去重增强。二者都触及**宪法约束热区**，需在实现前挂约束引用。

**Why this priority**: 强化产品差异化（多云 + 端侧 AI）与数据质量，但非核心必需；且都落在宪法约束边界上（Principle V 禁第三方 AI SDK / Principle I 隐私），需谨慎，故排 P2。

**Independent Test**: 设置页可切换多个云 provider 且失败自动降级 / Apple Watch + 码表双记录同一次骑行时不产生重复训练条目。

#### 2-A 多 AI Provider 扩展

**Given** 用户想用智谱以外的云模型，**When** 在设置页配置 DeepSeek / 通义 / OpenAI 兼容 endpoint，**Then** 新 provider 接入现有 `AIProviderChain`，失败时按链降级，全程走 OpenAI-compatible REST（**不引入任何第三方 AI SDK**）。

#### 2-B 导入去重增强 — ⚠️ 已部分实现，仅承接增强 delta

**关键**：基础去重**已在 `VitalStride/Sources/WorkoutListMerger.swift` 实现**，本 roadmap 只承接未做的增强部分。切勿重做已有代码：

| 维度 | 已实现（baseline，**勿重做**） | 本 roadmap 的 delta（未做，待 fork） |
|---|---|---|
| 去重机制 | 按 `healthKitUUID` **精确 UUID 去重**（`dedupCount` / `dedupedRecords`） | 时间窗口 ±5 分钟、同类型 workout 重叠匹配 |
| 数据处理 | 重复项直接过滤 | 重复时**保留 FIT/GPX 轨迹点/功率**，不新建 Workout |
| 前置验证 | — | 需真实数据验证 HealthKit `startDate/endDate` 与 FIT 时间戳精度差异 |

**Given** Apple Watch 与码表记录了同一次骑行，**When** 导入 FIT 文件，**Then** 系统在既有 UUID 精确去重之上，用时间窗口识别为同一次，保留 FIT 的轨迹/功率数据而不新建重复训练。

---

### User Story 3 - 训练类型与社交扩展 (Priority: P3)

覆盖有氧训练发起、社交/分享。这一簇最大范围扩张，离当前"个人健康数据收集"定位最远。

**Why this priority**: 有氧发起依赖 GPS/新数据流，社交分享触及数据出域面，二者都最可能被推翻或重估，优先级最低。

**Independent Test**: iOS 端发起一次跑步/骑行并记录 GPS 轨迹 / 将一次训练成果分享为不含原始健康数值的摘要。

**Acceptance Scenarios**:

1. **有氧发起** — **Given** 用户想在 iOS 端发起有氧训练，**When** 开始跑步/骑行，**Then** app 记录 GPS 轨迹并在结束时写入摘要到 HealthKit（比照现有力量训练发起路径）。
2. **社交/分享** — **Given** 用户想分享训练成果，**When** 生成分享内容，**Then** 分享 payload **不含原始 HealthKit 数值**（仅摘要/统计），满足隐私红线。

---

### Edge Cases

- **多 Provider**：所有云 provider 依次失败时的降级终点（回落到 AppleIntelligence 本地？还是显式错误）——沿用现有 chain 降级语义。
- **超级组**：编组后中途删除其中一个动作，剩余动作的组关联如何解除。
- **Routine**：某日计划被用户 skip / 提前完成，多日进度如何推进。
- **时间窗口去重**：两次真实不同的同类型训练恰好时间接近（<5min），避免误判为重复。
- **社交分享**：分享内容生成时，如何确保任何路径都不把心率/体重等原始数值带出域（Principle I）。

## Requirements *(mandatory)*

> 全部 FR 带 `[deferred]` — 语义为「当该功能启动时 MUST」，非当前 ship 义务（见 §Roadmap Framing）。

### Functional Requirements

**US1 — 训练录入增强**
- **FR-001 [deferred]**: 手动补录的训练 MUST 复用 `WorkoutSource.recorded`，不新建来源类型。
- **FR-002 [deferred]**: 力竭组 MUST 作为 `SetType` 新 case（`failure`）扩展现有枚举（现 `working/warmup/dropSet/pyramid`），量统计规则须显式定义。
- **FR-003 [deferred]**: 超级组 MUST 复用现有子组关联模型（dropSet/pyramid 的关联 UI 范式），不新建平行数据模型。
- **FR-004 [deferred]**: 多日 Routine MUST 扩展现有单层 `WorkoutTemplate`；若需新增 SwiftData `@Model`，MUST 走 ADR + 迁移评估（Constitution III/IV）。

**US2 — AI 与数据管道**
- **FR-005 [deferred]**: 新增 AI provider MUST 走 OpenAI-compatible REST via URLSession，**禁止引入第三方 AI SDK**（Constitution Principle V）。
- **FR-006 [deferred]**: 新 provider MUST 复用 `AIProviderChain` 扩展点接入降级链，不替换现有 chain。
- **FR-007 [deferred]**: provider 的 API key MUST 存 Keychain，禁止硬编码（Constitution Principle V）。
- **FR-008 [deferred]**: 去重增强 MUST 在既有 `WorkoutListMerger` UUID 精确去重**之上叠加**时间窗口策略（扩展，不替换）；重复时保留 FIT/GPX 额外数据。

**US3 — 训练类型与社交**
- **FR-009 [deferred]**: 有氧训练发起 MUST 比照现有力量训练发起路径写入 HealthKit 摘要；GPS 轨迹存储须评估 CloudKit 容量（比照 ADR-0003 降采样约定）。
- **FR-010 [deferred]**: 社交分享 payload MUST NOT 包含原始 HealthKit 数值（仅摘要/统计），满足 Constitution Principle I。

### Key Entities *(将被扩展/新增的实体，标 baseline 现状)*

- **SetType**（`Packages/VitalModels/.../Enums/SetType.swift`）：现 `working/warmup/dropSet/pyramid`；拟加 `failure`。
- **WorkoutTemplate**（`Packages/VitalModels/.../Models/WorkoutTemplate.swift`）：现单层单模板；拟扩为多日 Routine 基础。
- **WorkoutSource**（`Packages/VitalModels/.../Enums/WorkoutSource.swift`）：现 `recorded/imported/healthkit`；手动补录复用 `.recorded`。
- **AIProviderChain**（`Packages/AIService/.../AIProviderChain.swift`）：多 provider 扩展点。
- **WorkoutListMerger**（`VitalStride/Sources/WorkoutListMerger.swift`）：去重扩展点（已有 UUID 去重）。

## Success Criteria *(mandatory)*

> 方向性目标（「当功能交付时应达成」），技术无关、可测量。区别于 `000` 的 audit-style（已达成）。

- **SC-001**: 用户可为任意一组标记力竭，并在训练历史中与 working 组区分显示。
- **SC-002**: 用户可将两个动作编为超级组交替录入，组关联在 UI 中清晰可辨。
- **SC-003**: 用户可从多日训练计划发起某日训练并获得目标预填。
- **SC-004**: 至少 3 个云 AI provider 可在设置页切换，任一失败时自动按链降级，用户无感中断。
- **SC-005**: 在真实 Apple Watch + 码表双记录同一次训练的场景下，导入后不产生重复训练条目，且 FIT 轨迹/功率数据被保留。
- **SC-006**: 用户可分享训练成果，且分享内容经检查不含任何原始 HealthKit 数值。

## Assumptions

- **优先级重排说明**：本文优先级（P1/P2/P3）按**实现风险与内聚度**排，与 DESIGN 原始"低/中/高"（那是主观价值预估，且其"高=云 LLM"实际已实现）**不同**。依据：复用现有实体且零红线 → P1；触及宪法约束但仍在既有能力范围 → P2；引入新数据流/新出域面 → P3。
- 各功能启动时机由用户/产品决策驱动，本 spec **不排期**。
- 假设 baseline 实体（`SetType`/`WorkoutTemplate`/`WorkoutSource`/`AIProviderChain`/`WorkoutListMerger`）在功能启动时仍是扩展基础。

## Out-of-Scope (Roadmap Boundaries)

明确排除，防止把"已实现"当"要做"：

- **已实现的组类型** `dropSet` / `pyramid`（已在 `SetType`，非本 roadmap 范围）。
- **已实现的双 provider** Zhipu + AppleIntelligence（已在 `AIService`，本 roadmap 只扩展**更多** provider）。
- **已实现的 UUID 基础去重**（已在 `WorkoutListMerger`，本 roadmap 只做时间窗口增强）。
- **HealthKit Observer Query / BGHealthQuery 后台同步**：已在 `000-plan` 登记为 gap G-04，不在本 roadmap 重复。
- watchOS / macOS 独立体验：仍受 ADR-0002 约束。
- 任何未在原 DESIGN.md V2+ 表出现的新功能。

## Reference Map

未来 fork 子 spec 时的代码/文档锚点，避免重新考古：

| 主题 | 扩展点 / SoT |
|------|------|
| 组类型扩展（Failure/Superset） | `Packages/VitalModels/Sources/VitalModels/Enums/SetType.swift` |
| 多日 Routine 基础 | `Packages/VitalModels/Sources/VitalModels/Models/WorkoutTemplate.swift`、`TemplateExercise.swift` |
| 手动补录来源 | `Packages/VitalModels/Sources/VitalModels/Enums/WorkoutSource.swift` |
| 多 AI Provider 扩展点 | `Packages/AIService/Sources/AIService/AIProviderChain.swift`、`AIProvider.swift` |
| 去重增强扩展点 | `VitalStride/Sources/WorkoutListMerger.swift` |
| 宪法约束（AI 无第三方 SDK / 隐私） | `.specify/memory/constitution.md` Principle V / Principle I |
| 双数据源 / CloudKit 降采样 | `docs/adr/0003-healthkit-swiftdata-dual-data-source.md` |
| AI provider chain 决策 | `docs/adr/0005-ai-provider-chain.md` |
| 已实现基线 | `specs/000-baseline-existing-codebase/spec.md` |

## Not Migrated from DESIGN.md

DESIGN.md 大部分是**已实现架构描述**，已被现有 SoT 覆盖，**不迁入本文**（本文只承接未实现规划）。此表是 DESIGN 删除前的**迁移审计**，确保零信息丢失——每一块都能找到现归属：

| DESIGN.md 章节 | 不迁入 001 的原因 | 现归属 SoT |
|---|---|---|
| 项目定位 / 平台与版本 / 技术栈 | 已实现 | `.specify/memory/constitution.md`（平台）+ `CONTEXT.md`（Product Identity）+ ADR-0004 |
| 架构概览图 / L1+L2 缓存数据流 | 已实现 | `CONTEXT.md` + `Packages/HealthKitService/CONTEXT.md` + ADR-0003；`000` FR-003/004/005 |
| 导航结构（Tab/Sidebar/watch） | 已实现 | `000` spec US1/US2 + ADR-0002 |
| HealthKit 交互规则表 / 同步 Layer1 Anchor | 已实现 | ADR-0003；`000` FR-004 |
| 缓存隐私约束 / 撤权清除 / Telemetry 需求 | 已实现且是红线 | Constitution Principle I；`000` FR |
| 力量训练系统（working/warmup/dropSet/pyramid） | 已实现 | `SetType.swift`（仅 `failure`/`superset` 是 delta → 迁 001 US1） |
| AI 分析 V1 智谱 / Provider chain | 已实现 | ADR-0005；`000` FR（仅**多 Provider 扩展**迁 001 US2） |
| 图表系统 Swift Charts Mark 选型 | 已实现 | `000` FR-009（实现细节，代码即真相） |
| CloudKit 同步策略 | 已实现 | ADR-0003 |
| 文件导入 FIT/GPX 格式 | 已实现 | `000`（仅**去重增强 delta**迁 001 US2） |
| Observer Query Layer2（后台增量） | 未实现但已登记 | `000-plan` gap G-04（不在此重复） |

> 原则：**已实现 = 留在 CONTEXT/宪法/ADR/000；未实现 = 迁 001；已登记为 gap 的不重复迁。**
