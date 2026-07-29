---
description: "Task list for 019-ai-task-routing"
---

# Tasks: 按任务类型路由 AI + 反馈驱动动态调权

**Input**: `specs/019-ai-task-routing/`（spec.md + plan.md）；决策源 `docs/adr/0016-*`。

**Tests**: spec 要求包级单测（AIService/VitalModels 秒级 `swift test`）。测试任务已内联，遵循「先写测试→FAIL→实现」（宪法 TDD 倾向）。

**Organization**: 按 User Story 分组，每组独立可测、可上线。按 layer 拆分（一层一 commit，各自 `swift build/test`），对齐 `AGENTS.md`「按 layer 收窄」。

**Multica dispatch 映射**: 每个 `[Story]` 分组 → 一个 Multica parent/sub-issue；同 Phase 内标 `--stage N` 形成 barrier。Stage 顺序 = Foundational(1) → US1(2) → US2(3) → US3(4) → US4(5)。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: 所属 User Story（US1..US4）

---

## Phase 1: Setup

- [ ] T001 确认 `specs/019-ai-task-routing/` spec+plan 已合入 main（dispatch 前置门禁，见流程说明）。无代码改动。

---

## Phase 2: Foundational（阻塞全部 US）— layer: AIService

**Purpose**: 路由核心类型 + 静态 router 骨架。**⚠️ 完成前任何 US 不能开工。**

- [ ] T002 [P] 新建 `Packages/AIService/Sources/AIService/AITaskKind.swift`：`AITaskKind` 枚举（chat/overviewInsights/trainingAdvice/dataTrend/substitute）、`TaskRequirements` 画像 struct（latency/quality/structured/carriesHealthData）、`DeviceTier` 枚举。全部 Sendable（宪法 II）。
- [ ] T003 [P] 写测试 `AITaskKindTests`：枚举 CaseIterable 覆盖、`TaskRequirements` 值语义。先 FAIL。
- [ ] T004 新建 `AIRouter.swift`：持有中央策略表 `[AITaskKind: TaskRequirements]` + 设备档探测（复用 `AppleIntelligenceProvider.isAvailable`）+ `execute(kind:messages:model:)`，静态匹配到 provider 后**委托现有 `AIProviderChain`**（不改 chain 语义，FR-004）。依赖 T002。
- [ ] T005 写测试 `AIRouterStaticRoutingTests`：给定 (kind, 设备档) 断言选中 provider；旧设备档端侧臂概率=0（FR-005）；未知 kind 回退安全默认 + 告警（Edge Case）。先 FAIL。
- [ ] T006 跑 `swift test --package-path Packages/AIService` 全绿；一层一 commit。

**Checkpoint**: 静态 router 可用，行为可预测，等价于「把 chain 顺序按 kind 条件化」。

---

## Phase 3: User Story 1 — 所有 AI 调用统一走 AIRouter（P1）🎯 MVP — layer: app target

**Goal**: 11 个 caller 改走 `aiRouter.execute(.<kind>,…)`，消灭 10 处直连 `ZhipuProvider`。
**Independent Test**: 全仓 grep 0 处直接 `ZhipuProvider(apiKey:)`（router/chain 内部除外）；各 kind 选择与迁移前逐一致。

- [ ] T007 [US1] 迁移 `Overview/OverviewInsightsSection.swift` + `Overview/OverviewDynamicState.swift`（3 处）→ `.overviewInsights`。
- [ ] T008 [P] [US1] 迁移 `AIView.swift` + `AIChatView.swift` → `.chat`。
- [ ] T009 [P] [US1] 迁移 `AITrainingAdviceCard.swift` → `.trainingAdvice`。
- [ ] T010 [P] [US1] 迁移 `AIDataAnalysisSection.swift`（2 处）+ `DataSections/DataAISummaryState.swift` → `.dataTrend`。
- [ ] T011 [US1] 迁移 `ActiveWorkoutView.swift:986`（现走 `makeDefault`）→ `.substitute` 统一入口（去掉直接 chain 构造）。
- [ ] T012 [US1] 全仓断言：grep `ZhipuProvider(apiKey:` 命中仅 router/chain 内部（SC-001=0）；调用图确认 100% 经 router（SC-002）。
- [ ] T013 [US1] 跑 app pre-push 全量 xcodebuild + 手动冒烟各 AI 功能，行为等价（SC-004）。

**Checkpoint**: 架构债清除。端侧优先对所有功能生效。**此处可停并上线（MVP）。**

---

## Phase 4: User Story 2 — 被动采集路由信号（P1）— layer: VitalModels + AIService

**Goal**: 每次调用落一条旁路结构化信号。
**Independent Test**: 各 kind 触发后各落一条信号；字段完整；路由决策不受影响。

- [ ] T014 [P] [US2] 新建 `Packages/VitalModels/.../Models/RoutingSignalEntry.swift`：`@Model`，`cloudKitDatabase: .none`；字段 kind/provider/deviceTier/latencyMs/schemaValid/accepted?/timestamp。**含 TEMP-PRELAUNCH raw 字段** `rawPromptDebug/rawResponseDebug: String?`，字段上方挂注释 `// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）`（FR-015/016）。
- [ ] T015 [P] [US2] 写测试 `RoutingSignalEntryTests`：`.none` 配置断言、无健康数值进 CloudKit/UserDefaults（宪法 I 投影）。先 FAIL。
- [ ] T016 [US2] AIService 侧：`AIRouter.execute` 收尾发一条 `RoutingSignal`（旁路 best-effort，失败不阻塞，FR-008）；`schemaValid` 由 caller 传入的 decode 结果钩子判定（FR-009）。依赖 T004。
- [ ] T017 [US2] app 侧：把「换动作是否采纳 / 聊天是否 regenerate」接成 `accepted` 信号（FR-009 隐式行为）。
- [ ] T018 [US2] TEMP-PRELAUNCH 写入点：把 raw prompt/response 写进信号，每个写入点挂同款注释（FR-016）。**FR-018 断言：raw 只进本地 `.none` 库，不进 Aptabase/GlitchTip。**
- [ ] T019 [US2] 跑 `swift test`（VitalModels + AIService）全绿；一层一 commit。

**Checkpoint**: 有信号可分析；路由零行为变化（SC-003）。

---

## Phase 5: User Story 3 — 采样 shadow + Apple Evaluations 离线评估（P2）— layer: AIService

**Goal**: 采样双跑（不阻塞用户）+ 离线打分。
**Independent Test**: 配采样率 N%，仅 N% 触发候选；主结果先返回；Evaluations 离线任务能读采样对产分。

- [ ] T020 [P] [US3] `AIRouter` 加**按 kind 采样率**配置 + 采样判定（无 `Math.random` 依赖问题：用注入的确定性采样器便于测试）。
- [ ] T021 [US3] 实现 shadow 双跑：主 provider 结果**先返回**，候选 provider fire-and-forget，候选失败只落 `shadowFailed` 信号（FR-010 + Edge Case）。依赖 T016。
- [ ] T022 [P] [US3] 写测试 `ShadowSamplingTests`：100 次抽样触发率 ≈ 配置值 ±2%（SC-005）；交互请求主结果不被候选阻塞。先 FAIL。
- [ ] T023 [US3] 接入 **Apple `Evaluations` 框架**：定义评估数据集（读采样对）+ grader，产出离线分数；**仅离线/CI，非运行时**（FR-011）。加可用性 gate（iOS 26+，不可用则跳过，不阻塞）。
- [ ] T024 [US3] 跑 `swift test --package-path Packages/AIService` 全绿；一层一 commit。

**Checkpoint**: 有「A vs B」对比证据，喂给 US4。

---

## Phase 6: User Story 4 — 反馈驱动动态调权 bandit（P3）— layer: VitalModels + AIService

**Goal**: per-(kind, 设备档) bandit 随反馈自调；Day-1 == 静态策略。
**Independent Test**: 先验初始化选择分布==静态；注入高 reward 序列臂概率上升；旧设备档端侧臂恒 0。

- [ ] T025 [P] [US4] 新建 `Packages/VitalModels/.../Models/BanditArmStateEntry.swift`：`@Model`，`.none`；(kind, deviceTier, provider) + count + rewardSum。
- [ ] T026 [P] [US4] 新建 `Packages/AIService/.../AIRoutingBandit.swift`：ε-greedy 或 Thompson sampling；reward = schemaValid + accepted(+ 可选离线分) 加权；**保守静态先验 = 现静态策略**（FR-013）。
- [ ] T027 [P] [US4] 写测试 `AIRoutingBanditTests`：先验下 Day-1 分布≈静态（KL≈0，SC-006）；高 reward 单调抬升；端侧不可用档臂概率=0（FR-012/013）。先 FAIL。
- [ ] T028 [US4] `AIRouter` 选择改为查 bandit 权重（回落静态先验）；bandit 状态读写 `BanditArmStateEntry`（本地持久化，FR-014）。依赖 T004/T026。
- [ ] T029 [US4] 跑 `swift test`（两包）全绿；一层一 commit。

**Checkpoint**: 权重动态自调，无冷启动质量骤降。

---

## Phase 7: Polish & 发布前门禁（Cross-Cutting）

- [ ] T030 [P] 更新 `Packages/AIService/CONTEXT.md`：记录 `AIRouter` 为 chain 的上层入口（roles/owns 补 `AIRouter`/`AIRoutingBandit`）；frontmatter 一致性过防腐 hook。
- [ ] T031 **（发布前 ship-gate，FR-017/SC-007）**: grep `TEMP-PRELAUNCH` 命中数=0 —— 移除 `RoutingSignalEntry` 的 raw 字段 + 所有 raw 写入点，恢复「只存 metadata + 分数」（宪法 I 永久态）。**此项阻塞上架，未发布前保持 open。**
- [ ] T032 [P] 校验 `RoutingSignalEntry`/`BanditArmStateEntry` 持久化字段永久态不含任何健康数值（宪法 I）。

---

## Dependencies & Execution Order

- **Phase 2 Foundational** 阻塞全部 US。
- **US1（P1）** 独立，完成即 MVP + 清架构债。
- **US2（P1）** 依赖 Foundational；与 US1 可并行（不同文件），但信号采集需 router 存在。
- **US3（P2）** 依赖 US2（复用信号旁路）。
- **US4（P3）** 依赖 US2（reward 信号）+ 可选 US3（离线分）。
- **T031** 是发布前门禁，独立于功能推进，长期 open 到准备上架。

### Multica stage 映射

| Stage | 内容 | 对应 |
|---|---|---|
| 1 | Foundational（AIService 核心类型 + router 骨架） | T002-T006 |
| 2 | US1 caller 迁移（app） | T007-T013 |
| 3 | US2 信号采集（VitalModels + AIService） | T014-T019 |
| 4 | US3 shadow + Evaluations（AIService） | T020-T024 |
| 5 | US4 bandit（VitalModels + AIService） | T025-T029 |
| — | Polish + ship-gate | T030-T032（T031 长 open） |

## Notes

- 一层一 commit；跨 2+ layer 的 story 已在任务级按 layer 切开（US2/US4 各含 VitalModels + AIService 子任务）。
- TEMP-PRELAUNCH 是**受控临时例外**：仅本地 `.none`、带统一注释、SC-007 grep 清零做 ship-gate。宪法 I 的最终生效状态由 T031 保证。
- Apple `logFeedbackAttachment`/`LanguageModelFeedback` **禁用**（FR-019，会离设备）。
- Core ML `MLUpdateTask` 是 bandit 的**未来升级路径**，不在本 spec/tasks 范围。
