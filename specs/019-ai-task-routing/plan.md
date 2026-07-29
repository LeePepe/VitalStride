# Implementation Plan: 按任务类型路由 AI + 反馈驱动动态调权

**Branch**: `019-ai-task-routing` | **Date**: 2026-07-29 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/019-ai-task-routing/spec.md`；决策源 [ADR-0016](../../docs/adr/0016-task-kind-ai-routing-feedback-weights.md)。

## Summary

引入 `AIRouter` 收口所有 AI 调用：caller 只声明 `AITaskKind`，router 按「任务身份 → 需求画像 → provider 能力（含设备档）」路由，底层仍委托现有 `AIProviderChain`。分四阶段交付（对齐 spec 四个 User Story）：US1 路由地基 + caller 迁移（修掉 10 处绕过 chain）→ US2 旁路信号采集 → US3 采样 shadow + Apple Evaluations 离线评估 → US4 per-(kind, 设备档) bandit 动态调权。发布前临时全量 log（带 `TEMP-PRELAUNCH` 注释，上架前清；FR-015~019），永久态回落到「只存 metadata + 分数」（宪法 I）。

## Technical Context

**Language/Version**: Swift 6（strict concurrency，宪法 II）

**Primary Dependencies**: 现有 `AIService` 包（`AIProviderChain` / `AppleIntelligenceProvider` / `ZhipuProvider`）；`FoundationModels`（端侧）；`Evaluations`（WWDC26，仅离线评估，US3）；无第三方 AI SDK（宪法 V）

**Storage**: `VitalModels` 内新增本地 SwiftData 实体（`RoutingSignal` / `BanditArmState`），`cloudKitDatabase: .none`（宪法 I）

**Testing**: `swift test`（AIService + VitalModels 包级，秒级）；app caller 迁移走 pre-push 全量 xcodebuild

**Target Platform**: iOS/macOS/watchOS 26+；端侧路由仅 A17 Pro/M1+，旧设备档 cloud-only

**Project Type**: mobile-app（XcodeGen + 6 SPM 包）

**Performance Goals**: 信号采集为旁路 best-effort，MUST NOT 增加用户可见 AI 调用延迟（FR-008）；shadow 采样触发误差 ≤±2%（SC-005）

**Constraints**: 无第三方 AI SDK；chain 顺序不反转；健康值临时例外期仅进本地 `.none` 库、绝不离设备（FR-018）

**Scale/Scope**: 5+ `AITaskKind` × 2 provider × 2 设备档；11 个 caller 迁移点

## Constitution Check

*GATE: Phase 0 前必过，Phase 1 设计后复检。*

- **原则 I（健康隐私零妥协）**: ⚠️ 本 feature 的核心风险点。缓解：(a) `RoutingSignal`/`BanditArmState` 落本地 `.none` 库；(b) 临时全量 log 仅发布前、带 `TEMP-PRELAUNCH` 注释、SC-007 grep 清零做 ship-gate；(c) 原始值绝不进云端 telemetry（FR-018）；(d) 禁用 Apple `logFeedbackAttachment`（会离设备，FR-019）。→ **PASS（带临时例外，有移除门禁）**
- **原则 II（Swift 6 strict concurrency）**: `AIRouter` / bandit 状态 / 实体均须 Sendable。→ PASS
- **原则 III（SPM 包优先）**: 路由核心落 `AIService`，实体落 `VitalModels`，不新建包。→ PASS
- **原则 V（AI 本地优先 + 国内 fallback，无第三方 SDK）**: 复用 chain 不替换；本 feature **强化**「顺序不反转」——把它从 1 个 caller 扩到全部。→ PASS
- **原则 VI（i18n）**: 本 feature 几乎无新 UI 文案；若 US3/US4 有调试面板，文案走 xcstrings。→ PASS（低风险）

无违规，Complexity Tracking 留空。

## Project Structure

### Documentation (this feature)

```text
specs/019-ai-task-routing/
├── spec.md              # 已完成
├── plan.md              # 本文件
├── data-model.md        # Phase 1（本次一并产出，见下）
└── tasks.md             # Phase 2（/speckit-tasks 产出）
```

> research.md / contracts/ / quickstart.md 本 feature 从略：无外部 API 契约（纯内部抽象），research 已由审计报告 + ADR-0016 承担，quickstart 由各阶段 Independent Test 承担。data-model 因引入 2 个持久化实体而保留。

### Source Code (repository root)

```text
Packages/AIService/Sources/AIService/
├── AITaskKind.swift              # 新：kind 枚举 + TaskRequirements 画像 + DeviceTier
├── AIRouter.swift                # 新：router + 中央策略表 + 委托 chain
├── AIRoutingSignal.swift         # 新：信号 DTO（Sendable，不含持久化）+ schemaValid 判定钩子
├── AIRoutingBandit.swift         # 新：per-(kind,tier) bandit（US4）
├── AIProviderChain.swift         # 现有：router 委托，不改语义
├── AppleIntelligenceProvider.swift / ZhipuProvider.swift  # 现有：不改
└── ...

Packages/VitalModels/Sources/VitalModels/Models/
├── RoutingSignalEntry.swift      # 新：本地 .none SwiftData 实体（US2）
└── BanditArmStateEntry.swift     # 新：本地 .none SwiftData 实体（US4）

VitalStride/Sources/  (app target — caller 迁移，US1)
├── AIView.swift / AIChatView.swift / AITrainingAdviceCard.swift
├── AIDataAnalysisSection.swift / DataSections/DataAISummaryState.swift
├── Overview/OverviewInsightsSection.swift / Overview/OverviewDynamicState.swift
└── ActiveWorkoutView.swift        # 已走 chain，改成走 router（统一入口）
```

**Structure Decision**: 三层落点，各自独立 `swift build/test`，一层一 commit：
1. **AIService**（路由核心 + bandit）—— depends_on 无，最先做，`swift test --package-path Packages/AIService`。
2. **VitalModels**（2 个本地实体）—— `swift test --package-path Packages/VitalModels`。
3. **app target**（11 caller 迁移）—— pre-push 全量 xcodebuild。

## Data Model（Phase 1 内联）

- **AITaskKind**（enum, AIService）: `chat / overviewInsights / trainingAdvice / dataTrend / substitute`（+ 未来可扩）。Sendable。
- **TaskRequirements**（struct, AIService）: `latency: {interactive|background}`、`quality: {low|medium|high}`、`structured: Bool`、`carriesHealthData: Bool`。中央策略表 `[AITaskKind: TaskRequirements]` 由 router 拥有。
- **DeviceTier**（enum, AIService）: `appleIntelligenceCapable | cloudOnly`。由现有可用性检查探测。
- **RoutingSignalEntry**（@Model, VitalModels, `.none`）: `kind: String, provider: String, deviceTier: String, latencyMs: Int, schemaValid: Bool, accepted: Bool?, timestamp: Date`。临时例外期附 `rawPromptDebug: String?` / `rawResponseDebug: String?`（TEMP-PRELAUNCH，上架前删字段+写入点）。
- **BanditArmStateEntry**（@Model, VitalModels, `.none`）: `kind: String, deviceTier: String, provider: String, count: Int, rewardSum: Double`（Beta/Thompson 参数派生）。主键 = (kind, deviceTier, provider)。

隐私不变量：两实体均 `cloudKitDatabase: .none`；永久态 `RoutingSignalEntry` **无** raw 字段——raw 字段是 TEMP-PRELAUNCH 增量，FR-017 要求上架前连同写入点一并移除。

## Complexity Tracking

> 无违规，留空。

## Phase / Dependency 概览（详见 tasks.md）

- **Phase 2 Foundational（阻塞全部）**: `AITaskKind` + `TaskRequirements` + `DeviceTier` + 中央策略表 + `AIRouter` 骨架（静态路由，委托 chain）。
- **US1（P1，MVP）**: 11 caller 迁移到 `aiRouter.execute(.<kind>,…)`；grep 断言 0 处直连。**交付即修掉架构债。**
- **US2（P1）**: `RoutingSignalEntry` + 旁路采集（含 TEMP-PRELAUNCH raw 字段 + 注释）；schemaValid/accepted 钩子。
- **US3（P2）**: 采样 shadow 双跑（fire-and-forget）+ Apple Evaluations 离线评估任务。
- **US4（P3）**: `BanditArmStateEntry` + `AIRoutingBandit`，静态先验初始化，接入 router 选择。

各阶段独立可测、可上线；US1 完成即达成 SC-001/002/004。
