# Feature Specification: 按任务类型路由 AI + 反馈驱动动态调权

**Feature Branch**: `019-ai-task-routing`

**Created**: 2026-07-29

**Status**: Draft

**Input**: 落地 [ADR-0016](../../docs/adr/0016-task-kind-ai-routing-feedback-weights.md)。现状（审计报告 `docs/reports/ai-audit-and-apple-models-2026-07-28.md`）：11 个 AI 调用点中 10 个直接 `ZhipuProvider(apiKey:)`，绕过 `AIProviderChain`，导致「端侧优先」只在换动作一个功能生效，违背宪法 V / `AIService/CONTEXT.md` 红线「chain 顺序不得反转」。目标：引入 `AIRouter`，让调用方只声明**任务身份**，由中央策略按**任务身份 → 需求画像 → provider 能力**路由，并用反馈随时间动态调权。

**Related ADR**: [ADR-0016](../../docs/adr/0016-task-kind-ai-routing-feedback-weights.md)（决策记录，本 spec 是其实现）

**Constitution refs**: 原则 V（AI 本地优先 + 国内 fallback，无第三方 SDK）、原则 I（健康数据隐私零妥协）、原则 II（Swift 6 strict concurrency）、原则 III（SPM 包优先）。

**关联**: `specs/012-ai-routine-generation`（可执行 routine，独立功能，但会成为 `AIRouter` 的一个 caller）；`specs/003-substitute-exercise`（唯一已走 chain 的现有 caller）。

---

## User Scenarios & Testing *(mandatory)*

> 说明：这是**平台/架构 feature**，"用户"多为**开发者/项目 owner**，价值以「行为契约 + 可观测性」体现，而非终端 UI。终端用户可见的变化仅为：AI 质量随时间变好、端侧场景更快/更省。

### User Story 1 - 所有 AI 调用统一走 AIRouter（Priority: P1）

作为项目 owner，我希望**每个** AI 功能都经由一个中央 `AIRouter` 发起调用、只声明自己的任务类型（chat / trainingAdvice / substitute / …），不再各自 `new ZhipuProvider`，这样「端侧优先」对所有功能真正生效，且路由逻辑一处收口。

**Why this priority**: 这是 ADR-0016 的地基，单独就修掉「10 处绕过 chain」的架构债，并为后续所有能力造好接缝。调用点从此不再改。

**Independent Test**: 全仓 grep 确认 0 处直接 `ZhipuProvider(apiKey:)`（除 chain/router 内部构造）；每个 AI 调用点改为 `aiRouter.execute(.<kind>, ...)`；静态策略下行为与迁移前等价（同任务选同 provider）。

**Acceptance Scenarios**:

1. **Given** 一个 A17 Pro/M1+ 设备且 Apple Intelligence 可用，**When** 调用 `.substitute`，**Then** 路由到端侧 `AppleIntelligenceProvider`。
2. **Given** 同设备，**When** 调用 `.chat`，**Then** 按需求画像路由到云端质量档（`ZhipuProvider`）。
3. **Given** 一个不支持 Apple Intelligence 的旧设备，**When** 调用任意 kind，**Then** 路由回退到云端，且不崩溃。
4. **Given** 迁移完成，**When** grep 调用点，**Then** 除 `AIRouter`/`AIProviderChain` 内部外无直接 provider 实例化。

### User Story 2 - 被动采集路由信号（Priority: P1）

作为项目 owner，我希望每次 AI 调用后系统被动记录一条**结构化信号**（任务类型、选中 provider、延迟、结构是否有效、用户是否采纳），以便日后分析升/降级，且不改变路由行为。

**Why this priority**: 无信号则无从谈动态调权。此阶段纯被动、零路由影响，风险最低。

**Independent Test**: 触发各 kind 调用，验证每次落一条信号记录；记录字段完整；路由决策与 US1 完全一致（信号采集不影响选择）。

**Acceptance Scenarios**:

1. **Given** 一次成功的 AI 调用，**When** 调用结束，**Then** 落一条含 `{kind, provider, latencyMs, schemaValid, deviceTier}` 的信号。
2. **Given** 一次输出解析失败（JSON schema 不匹配），**When** 记录信号，**Then** `schemaValid=false`。
3. **Given** 换动作场景用户退回手动选，**When** 记录信号，**Then** `accepted=false`（隐式行为信号）。

### User Story 3 - 采样 shadow 双跑 + 离线评估（Priority: P2）

作为项目 owner，我希望对**采样的一小部分**请求让候选 provider 也跑一遍（不阻塞用户），并能用 **Apple Evaluations 框架**对两边输出做离线打分，判断某 kind 是否该改路由。

**Why this priority**: 提供「provider A vs B 谁更好」的对比证据，为动态调权提供依据。采样控制成本。

**Independent Test**: 配置某 kind 采样率 N%，验证仅 N% 请求触发候选双跑；主 provider 结果先返回、候选 fire-and-forget；离线 Evaluations 任务能对采样对读入并产出分数。

**Acceptance Scenarios**:

1. **Given** `.trainingAdvice` 采样率 10%，**When** 跑 100 次，**Then** 约 10 次触发候选双跑，其余 0 次。
2. **Given** 一次交互式请求被采样，**When** 主 provider 返回，**Then** 用户**立即**拿到主结果，候选异步进行、不阻塞。
3. **Given** 一批采样对，**When** 跑 Apple Evaluations 离线任务，**Then** 每对得到 grader 分数，供人工/自动判定升降级。

### User Story 4 - 反馈驱动动态调权（bandit）（Priority: P3）

作为项目 owner，我希望路由权重按 **per-(kind, 设备档)** 的 bandit 随反馈自调：把每个 `(kind, provider)` 当臂，reward 由结构有效性 + 用户隐式行为（+ 可选离线评估分）加权，臂选概率即动态权重，出厂用等于现状的保守静态先验。

**Why this priority**: 最终目标，但依赖前三阶段的信号与评估。风险最高，最后开。

**Independent Test**: 用先验初始化，验证 Day-1 选择分布 == 静态策略；注入一串「provider A 连续高 reward」的合成信号，验证 A 的选择概率随之上升；旧设备档不因端侧不可用而被选。

**Acceptance Scenarios**:

1. **Given** bandit 以静态先验初始化，**When** 尚无反馈，**Then** 路由分布等于 US1 的静态策略（无行为回归）。
2. **Given** 某 (kind, provider) 持续获得高 reward，**When** 权重更新，**Then** 该臂选择概率单调上升（在探索项容许范围内）。
3. **Given** 设备不支持 Apple Intelligence，**When** bandit 选择，**Then** 端侧臂概率恒为 0（按设备档条件化）。

### Edge Cases

- **provider 全不可用**（旧设备 + 无云端 key）→ `AIRouter` 抛 `noProviderAvailable`，caller 优雅降级（沿用现有 chain 行为）。
- **未知/新增 kind 无策略条目** → 回退到一个安全默认画像（background + medium + 允许 fallback），并记一条告警信号，不崩溃。
- **shadow 候选 provider 报错** → 不影响已返回给用户的主结果；候选失败只落一条 `shadowFailed` 信号。
- **bandit 冷启动**（某臂零样本）→ 用先验，不做无依据探索导致质量骤降。
- **信号写入失败** → 绝不阻塞或拖慢用户可见的 AI 调用（信号是旁路，best-effort）。
- **设备档在会话中变化**（几乎不发生，但如低电量降频）→ 以调用时点的可用性为准。

## Requirements *(mandatory)*

### Functional Requirements

**路由核心**
- **FR-001**: 系统 MUST 提供 `AIRouter`，caller 仅通过 `execute(kind:messages:...)` 声明**任务身份**，不得传入 provider 或权重。
- **FR-002**: 系统 MUST 定义 `AITaskKind` 枚举，覆盖现有全部 AI 功能（至少：chat、overviewInsights、trainingAdvice、dataTrend、substitute）。
- **FR-003**: 系统 MUST 用一张**中央策略表**把 kind 映射到**需求画像**（延迟档 / 质量档 / 是否结构化 / 是否含健康数据），再匹配到 provider 能力；策略表由 router 拥有，不散落在 caller。
- **FR-004**: 系统 MUST 保留并复用现有 `AIProviderChain`；`AIRouter` 委托 chain 执行，不替换、不新建包（宪法 III/V）。
- **FR-005**: 路由权重 MUST 按 **(kind, 设备档)** 条件化；端侧臂在不支持 Apple Intelligence 的设备档上概率恒为 0（宪法 V 顺序不反转的强化，而非削弱）。
- **FR-006**: 迁移完成后，除 `AIRouter`/`AIProviderChain` 内部构造外，代码库 MUST NOT 再直接实例化具体 provider（`ZhipuProvider(apiKey:)` 等）。

**信号采集**
- **FR-007**: 每次 AI 调用结束后，系统 MUST 被动落一条**结构化信号**，至少含 `{kind, provider, deviceTier, latencyMs, schemaValid, accepted?}`。
- **FR-008**: 信号采集 MUST 为旁路 best-effort：其失败或耗时不得阻塞、拖慢或改变用户可见的 AI 调用与路由决策。
- **FR-009**: 结构有效性 MUST 客观可判（能否 decode 成目标 schema / 过 insight 白名单）；用户隐式行为（换动作是否采纳、聊天是否重试）MUST 作为 `accepted` 类信号来源。

**shadow + 离线评估**
- **FR-010**: 系统 MUST 支持**按 kind 配置采样率**触发候选 provider 双跑；主 provider 结果先返回用户，候选 MUST fire-and-forget、绝不阻塞交互请求。
- **FR-011**: 系统 SHOULD 用 **Apple Evaluations 框架**对采样对做**离线**打分（开发期/CI，非生产逐请求）；离线评估是可选增强，不得成为运行时路由的阻塞依赖。

**动态调权**
- **FR-012**: 系统 SHOULD 提供 per-(kind, 设备档) 的 bandit（ε-greedy 或 Thompson sampling），臂选概率即动态权重，reward 由 FR-009 信号（+ 可选 FR-011 分）加权。
- **FR-013**: bandit MUST 以**等于当前静态策略的保守先验**初始化，保证 Day-1 路由分布无行为回归。
- **FR-014**: 权重与 bandit 状态 MUST 持久化于**设备本地**存储（`cloudKitDatabase: .none`），不同步、不上云。

**隐私（发布前临时例外 + 永久红线）**
- **FR-015**: 系统 MUST 支持在信号/评估记录中**记录完整内容**（含 prompt/response 原始值）用于发布前的自用调试。**这是一个发布前临时例外**，仅因当前为单用户未发布状态。
- **FR-016**: 所有记录原始健康/训练数值的代码点 MUST 用统一注释标记 `// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）`，以便发布前一键 grep 清除。
- **FR-017（永久红线）**: **发布前** MUST 移除所有 `TEMP-PRELAUNCH` 标记的原始值记录，恢复到「信号/评估记录只含 metadata + 分数，绝不持久化含健康数值的 prompt/response」——即宪法 I 的最终生效状态。此项为 ship-gate 阻塞项。
- **FR-018**: 即便在临时例外期，含原始健康值的记录 MUST 仅落**设备本地** `.none` 存储，MUST NOT 进入云端 telemetry（Aptabase/GlitchTip 等）——临时例外只放宽「本地日志」，不放宽「离设备」。
- **FR-019**: Apple 的 `logFeedbackAttachment` / `LanguageModelFeedback`（打包完整 transcript 报 Apple）MUST NOT 用于本反馈回路——它会把原始健康数据送出设备，即使临时例外期也禁用。

### Key Entities *(include if feature involves data)*

- **AITaskKind**: AI 任务的身份枚举，caller 唯一声明的东西。属性：case 名。
- **TaskRequirements（需求画像）**: 一个 kind 的路由需求。属性：延迟档（interactive/background）、质量档（low/medium/high）、是否结构化、是否含健康数据。
- **DeviceTier（设备档）**: 端侧能力分档（如 appleIntelligenceCapable / cloudOnly）。决定端侧臂是否可选。
- **RoutingSignal（路由信号）**: 一次调用的旁路记录。属性：kind、provider、deviceTier、latencyMs、schemaValid、accepted?、timestamp；临时例外期附原始 prompt/response（TEMP-PRELAUNCH）。
- **BanditArmState（臂状态）**: per-(kind, deviceTier, provider) 的统计（计数 / reward 累积 / 分布参数）。本地持久化。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 迁移后，代码库中直接实例化具体 AI provider 的调用点数量 = **0**（router/chain 内部除外）；迁移前为 10。
- **SC-002**: 100% 的 AI 功能经 `AIRouter` 发起（可由 grep + 调用图验证）。
- **SC-003**: 每次 AI 调用产生**恰好一条** RoutingSignal（成功或失败均记；旁路失败不计入用户可见错误）。
- **SC-004**: 阶段 1 上线后，静态策略下各 kind 的 provider 选择与迁移前**逐一致**（无行为回归）。
- **SC-005**: shadow 采样触发率与配置采样率误差 ≤ ±2%（100 次抽样口径）；交互请求的用户可见延迟不因 shadow 增加（主结果先返回）。
- **SC-006**: bandit 以先验初始化时，Day-1 路由分布与静态策略的 KL 散度 ≈ 0（无反馈即无偏移）。
- **SC-007**: 发布前 grep `TEMP-PRELAUNCH` 命中数 = **0**（FR-017 ship-gate），且 RoutingSignal 持久化字段不含任何健康数值。

## Assumptions

- 当前处于**未发布、单用户（项目 owner 自用）**阶段——这是 FR-015/016 临时全量 log 例外成立的前提。一旦准备上架，FR-017 生效、例外作废。
- 复用现有 `AIProviderChain`（Apple Intelligence → 智谱）作为底层执行器，不新增第三方 AI SDK（宪法 V）。
- Apple **Evaluations 框架**（WWDC26，iOS 26+）用于**离线**评估；不假设它能做生产逐请求评分。
- Apple **没有**「喂用户操作 → 自动吐 provider 偏好」的现成一等 API；bandit 需自实现。规模变大时的升级路径是 **Core ML `MLUpdateTask`**（端侧训练一个偏好模型），但当前 kind×provider 规模下 bandit（计数器 + 分布）更划算，MLUpdateTask 记为**未来升级路径，不在本 spec 范围**。
- 设备档探测复用 `AppleIntelligenceProvider.isAvailable` 一类的现有可用性检查。
- 分阶段交付：US1（P1，地基）→ US2（P1，信号）→ US3（P2，shadow+离线评估）→ US4（P3，bandit）。每阶段独立可测、可上线。

## 层归属与红线（来自 AIService/CONTEXT.md + 宪法）

- **主 layer**: `AIService`（`AIRouter` / `AITaskKind` / `TaskRequirements` / bandit 逻辑；depends_on: 无）。红线：无第三方 AI SDK；不替换 chain；provider Sendable；chain 顺序不反转（本 spec 强化而非削弱）。**test**: `swift test --package-path Packages/AIService`。
- **RoutingSignal / BanditArmState 持久化**: `VitalModels`（本地 `cloudKitDatabase: .none` SwiftData 实体）。红线：健康数值不进 CloudKit/NSUserDefaults（宪法 I）——临时例外期原始值仅进 `.none` 本地库，永久态只存 metadata。**test**: `swift test --package-path Packages/VitalModels`。
- **caller 迁移**: app target（11 个调用点改走 `AIRouter`）。门禁走 pre-push 全量 xcodebuild。
- **跨层拆分**: AIService（路由核心）/ VitalModels（信号实体）/ app（caller 迁移）各自独立 `swift build/test`，一层一 commit——按 tasks.md 分阶段落。

## Reference Map

- ADR: `docs/adr/0016-task-kind-ai-routing-feedback-weights.md`（决策源）
- 审计报告: `docs/reports/ai-audit-and-apple-models-2026-07-28.md`（11 调用点清单 §1.2、ADR-0005 隐私 gap §1.5、Apple 模型能力 Part 2）
- 现有底层: `Packages/AIService/Sources/AIService/AIProviderChain.swift`、`AppleIntelligenceProvider.swift`、`ZhipuProvider.swift`
- 现有唯一 chain caller: `VitalStride/Sources/ActiveWorkoutView.swift:986`（substitute）
- 待迁移 caller: 见审计报告 §1.2 表
- 宪法: `.specify/memory/constitution.md`（原则 I / II / III / V）
