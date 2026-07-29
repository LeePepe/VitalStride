# VitalStride — AI 使用审计 + Apple 端侧模型调研报告

**日期**: 2026-07-28
**范围**: (1) 现有代码库 AI 使用全盘点 — 已用 / 可加 / 基础设施；(2) Apple 端侧模型（Foundation Models 等）能用的部分 + 迁移建议。
**方法**: 两个并行调研 agent 通读 `Packages/AIService/` + `VitalStride/Sources/` 全部 AI 相关文件 + `docs/adr/` + `specs/`，关键结论已回读源码逐条核实。

> **一句话结论**: AI 基础设施设计是对的（Apple 端侧优先 + 云 fallback 的 provider chain），但**实际只有 1/11 的 AI 入口真正走了 chain**，其余 10 处直连云端智谱；且 **ADR-0005 声称的健康数据脱敏根本没实现**，原始体重/心率明文发往云端。最高性价比的下一步是：把结构化输出迁到 Apple Foundation Models 的 `@Generable` 端侧生成，顺带把 10 处直连收编进 chain，一举拿下隐私 + 可靠性两个收益。

---

## Part 1 — 现有 AI 使用审计

### 1.1 AI 基础设施（AIService 包）

AI 抽象住在 `Packages/AIService/Sources/AIService/`，零第三方 AI SDK 依赖（Constitution 原则 V）。

- **Provider 协议**（`AIProvider.swift`）: 极简 2 方法 — `chat(messages:model:)` + `chatStream(messages:model:)`。消息是朴素 `{role, content}`。**注意**: ADR-0005 文字描述的是「产出 typed AIAnalysisResponse」的接口，但真实协议是通用 chat；结构化输出靠「prompt 里塞 JSON 要求 + app 层 decode」实现，不是协议层保证。
- **Provider chain**（`AIProviderChain.swift`）: `makeDefault(zhipuAPIKey:)` 构建有序链 — **`apple_intelligence` 在前，`zhipu` 在后**（有 key 才加）。`chat()` 按序尝试、跳过不可用的、返回首个成功；全失败抛最后一个错。`chatStream()` 只用第一个可用 provider（流式**无**中途 fallback）。
- **具体 provider**:
  - `AppleIntelligenceProvider.swift` — Apple `FoundationModels` 端侧（`SystemLanguageModel.default` / `LanguageModelSession`）。仅 iOS 26 / macOS 26 且框架可用时 `isAvailable == true`；无 API key；model id `"apple-intelligence"`。
  - `ZhipuProvider.swift` — 云端，智谱 BigModel OpenAI-兼容 REST（`open.bigmodel.cn/api/paas/v4/chat/completions`）。默认 `glm-4-flash`，可选 `glm-4-plus`；Keychain 存 key；支持非流 + SSE 流式 + token 计量。
- **结构化输出类型**（均 `Codable + Sendable`，从模型 JSON decode）: `OverviewInsight`、`AIAnalysisResponse`、`TrainingRecommendation`、`DataAnalysis`、`SubstituteSuggestion`（app 层）。
- **app 侧编排层** `AIAnalysisService.swift`（SwiftData `ModelActor`）: TTL 缓存（默认 3600s）、stale-while-revalidate、一次 JSON parse retry 后优雅降级、`noProviderAvailable` 时回吐缓存。

### 1.2 ⚠️ 关键架构发现 — chain 几乎没被用

**只有 Exercise Substitute（`ActiveWorkoutView.swift:986`）调了 `AIProviderChain.makeDefault`。其余每个 AI 功能都直接 `ZhipuProvider(apiKey:)`。**（已逐行核实，11 个调用点）

| 调用点 | 走 chain? |
|---|---|
| `ActiveWorkoutView.swift:986`（Substitute） | ✅ `AIProviderChain.makeDefault` |
| `AIView.swift:313` | ❌ 直连 Zhipu |
| `AIChatView.swift:133` | ❌ 直连 Zhipu |
| `AITrainingAdviceCard.swift:318` | ❌ 直连 Zhipu |
| `AIDataAnalysisSection.swift:187, 451` | ❌ 直连 Zhipu |
| `Overview/OverviewInsightsSection.swift:39` | ❌ 直连 Zhipu |
| `Overview/OverviewDynamicState.swift:61, 125, 176` | ❌ 直连 Zhipu |
| `DataSections/DataAISummaryState.swift:86` | ❌ 直连 Zhipu |

**后果**:
1. Apple 端侧推理实际只在 1 个功能可达；其余全云端、无 key 就硬失败。
2. 违背 `AIService/CONTEXT.md` 红线「Apple Intelligence 本地优先 + 智谱 fallback 的 chain 顺序不得反转」——大多数入口**根本没进 chain**。

### 1.3 已经用了 AI 的地方

| 功能 | 文件 | 做什么 | 喂给模型的数据 | Provider |
|---|---|---|---|---|
| Overview 智能卡片 | `Overview/OverviewInsightsSection.swift`、`OverviewDynamicState.swift`、`Models/OverviewInsight+CardParsing.swift` | 生成 5-8 张自适应首页卡 + "距上次有何变化" 标题；校验 size×type 白名单 | 今日步数、活动能量、静息心率(bpm)、昨夜睡眠(h)、最新体重(kg)、近期训练数、分肌群频率 + 历史 insight | 直连 Zhipu |
| AI 聊天助手 | `AIView.swift`、`AIChatView.swift` | 流式训练/健康问答；API key + 隐私同意双门；clear/retry/cancel | `AIPromptBuilder.buildSystemContext`（近 14 天训练数、肌群分布、平均 HR、睡眠、体重）+ 完整对话 | 直连 Zhipu 流式 |
| 快速分析（周报/恢复/PR 检测） | `AIView.swift`、`AIQuickAnalysisCard.swift`、`AIPromptBuilder` | 三个一键自由文本分析；PR 检测先本地算 PR 再请模型点评 | **每组明细**: 精确 weight×reps、RPE、组类型、每次训练量、日期/时长；健康快照 | 直连 Zhipu |
| 今日训练建议 | `AITrainingAdviceCard.swift`、`AIAnalysisPrompts.buildTrainingAdviceMessages` | 推荐今日肌群 + 动作 + 理由（JSON）；带缓存；考虑恢复时机 | 近 30 天/10 次训练：肌群频率、距上次天数、训练摘要 | 直连 Zhipu（经 AIAnalysisService） |
| 分指标趋势分析 | `AIDataAnalysisSection.swift`、`DataSections/DataAISummaryState.swift`、`buildCategoryTrendMessages` | 每个健康指标的趋势 + 摘要 + 建议；步数/HR/睡眠/体重/能量分类 prompt；并行(≤3) | **仅聚合统计**（count、区间、avg/min/max/latest、7d-vs-7d %）— 明确禁止编造日级明细 | 直连 Zhipu（经 AIAnalysisService） |
| 智能换动作 | `ExerciseSubstitute.swift`、`ExerciseSubstituteSheet.swift`、`ActiveWorkoutView.swift:977-1041` | 训练中给 3 个同肌群替代 + 理由；`exerciseId`→本地 Exercise，确定性同肌群过滤，降级到手动选 | 仅动作元数据：名称、肌群、器械（**无健康值**） | ✅ `AIProviderChain`（唯一真 chain 用户） |
| 设置/配置 | `AISettingsSection.swift` | 展示 provider（智谱，固定）、API key 输入/清除（Keychain）、模型选择（Flash/Plus）、撤销隐私同意 | — | Keychain + UserDefaults |

Prompt 组装在两个 i18n 豁免文件：`AIPromptBuilder.swift`（聊天 + 快速分析上下文 + HealthKit 拉 HR/步数/睡眠/体重）、`AIAnalysisPrompts.swift`（insights、训练建议、分类趋势、从代码围栏抽 JSON）。全部中文 prompt + locale 指令按 zh/en 回复。

### 1.4 可以加 AI 的地方（尚未建）

| 机会 | 屏幕/数据基础 | 可行性 | 备注 |
|---|---|---|---|
| AI 建议一键「开始这次训练」 | `AITrainingAdviceCard` 已返回肌群+动作名；`StartWorkoutView` 已存在 | 高（**spec 已写**） | `specs/012-ai-routine-generation`（FR-001…007，Draft）。给 `TrainingRecommendation` 加 `routineExercises`(sets/reps/weight) + `AIRoutineMaterializer`。未实现 |
| 自然语言/语音记组 | 训练中记组（`ActiveWorkoutView`）、键盘重设计 017-* | 中 | 解析 "3x5 100kg RPE8" → `WorkoutSet`。Apple 端侧最贴隐私姿态；本地动作库已可做名称匹配 |
| 休息计时/下组教练提示 | 实时休息计时（ADR-0006）、每组 RPE（spec 007） | 中 | 按当前 session RPE 趋势建议休息时长/配重；数据全本地 |
| 选动作页的动作教学问答 | `ExercisePickerView` / 动作库（300+，spec 014） | 高 | 聊天基础设施已有；喂动作元数据；低隐私风险，chain/端侧皆可 |
| 多日周期化计划生成 | `WorkoutTemplate`、roadmap US1 多日 Routine | 中高 | 训练建议扩到多 session；roadmap 001 标 `WorkoutTemplate` 为扩展点 |
| 历史 & 日历的 PR/进步叙事 | 训练历史、日历（spec 011）、1RM（008）、smart progression（006） | 高 | `detectPotentialPRs` 已本地算 PR，只有点评是 AI；可在历史页而不只 AI tab 呈现 |
| Overview 过度训练/异常预警 | Overview 已喂 HR/睡眠/步数/体重 + 训练频率 | 高 | 恢复 prompt（`buildRecoveryPrompt`）已存在；升级为主动 Overview 卡而非手动点 |
| 跨指标相关性（睡眠↔表现） | 健康缓存 + 训练量都可得 | 中 | 喂配对周序列；需比现有单指标更丰富的聚合 |
| 隐私安全的分享摘要 | roadmap US3 FR-010（分享 payload 须排除原始 HealthKit 值） | 中低 | AI 起草分享文案；须守「无原始值」红线 |
| 加更多 provider + 端侧默认全覆盖 | `AIProviderChain` 扩展点、roadmap US2-A | 中 | roadmap 001 FR-005/006/007（deferred）：加 DeepSeek/Qwen/OpenAI 兼容端点。同时是把 10 处直连收编进 chain 的好时机 |

### 1.5 ⚠️ 隐私姿态（重点）

**红线（Constitution 原则 I）：健康/训练数值禁止出现在任何日志。** — 代码里**遵守**：所有日志只出 ms、count、error 类别、sample-type 字符串、bool，无一处 interpolate 体重/HR/睡眠/步数。✅

**但云端数据流是宽的、未脱敏的。** 因为 10/11 功能直连 Zhipu，以下**原始值明文**发往智谱云端服务器：
- Overview/聊天/快速分析 prompt 含**精确值** — `体重kg × reps @ RPE`、每次总量、平均 HR(bpm)、睡眠小时、体重kg、步数（`AIPromptBuilder.swift:108` 实测发 `\(set.weight)kg×\(set.reps)`）。
- 分指标趋势路径（`AIDataAnalysisSection`/`DataAISummaryState`）**最克制** — 只发聚合统计，不发日级原始样本。
- Substitute **不发任何健康数据** — 只动作名/肌群/器械。

**🔴 需要向你上报的重大差异**: **ADR-0005:42 声称**「进入 prompt 的健康值在发往智谱前**已脱敏**：精确心率/体重被**分桶**、标识符**剥离**；Apple Intelligence 因为在端侧才看原始值」。**代码里根本没有任何分桶/脱敏**（`AIPromptBuilder.swift` / `AIAnalysisPrompts.swift` grep `bucket|sanitiz|脱敏` = 0 命中，原始值直接发）。**ADR 描述的隐私姿态是设想，未落地。** 而唯一在端侧（可合法看原始值）的 Apple Intelligence 只用在 Substitute，而 Substitute 本就不发健康数据——所以「端侧优先保隐私」的收益在最需要它的健康数据功能上**完全没兑现**。

**用户侧控制（存在且合理）**: AI tab 双门 —（a）Keychain 已配 key +（b）显式隐私同意（`aiPrivacyConsentKey`），同意屏点名智谱/BigModel 并说明训练+健康数据将发往第三方服务器（`AIView.swift:103-159`）。可在设置撤销（会取消进行中的分析/流式）。key 仅设备内 Keychain。

### 1.6 相关 ADR / spec

- **ADR-0005 — AI ProviderChain（Apple Intelligence 优先，Zhipu fallback）**[Accepted]: 核心 AI 决策。**但其声称的 prompt 脱敏未实现（见 1.5）。** 唯一 AI 架构 ADR。
- ADR-0004 — 五个本地 SPM 包：把 AIService 立为隔离包。
- `specs/003-substitute-exercise`[Draft] — 已建的换动作功能。FR-002 复用 chain / 无第三方 SDK，FR-007 无健康值进日志。
- `specs/012-ai-routine-generation`[Draft] — 把训练建议从文本升级为可执行 routine。**未实现**，是最现成的下一个 AI 功能。
- `specs/001-future-roadmap`[规划] — US2-A 多 provider 扩展（FR-005/006/007 全 deferred）；US3 FR-010 分享须排除原始 HealthKit 值。

---

## Part 2 — Apple 端侧模型可用部分（2026）

*现状锚点：app 已有 `AppleIntelligenceProvider` 接进 chain（Apple 端侧优先于云端 Zhipu），targets iOS 26 / macOS 26，用 `LanguageModelSession` 的 `respond(to:)` / `streamResponse(to:)`。以下是「还能用什么 + 完整集成长什么样」。*

### 2.1 Foundation Models 框架（Apple Intelligence 端侧 LLM）

**是什么**: `FoundationModels`（WWDC 2025 发布，OS-26 波次）给 app 直接访问驱动 Apple Intelligence 的 **~30 亿参数**端侧 LLM。无 API key、无服务器、无 per-token 成本、离线可用。

**API 形状**（与 app 已用一致）:
- `SystemLanguageModel.default` — 端侧模型句柄；用前查 `.availability` / `isAvailable`。
- `LanguageModelSession(instructions:)` — 有状态 session；`respond(to:)` 一次性，`streamResponse(to:)` 流式。**流式发的是累积快照**（非 token 增量）—— app 的流式代码已在 diff 快照成增量，正确。
- **Guided generation** — 给 Swift 类型标 `@Generable`、字段标 `@Guide(...)`，模型用约束解码直接产出合法实例。**无 JSON 解析、无 schema-mismatch 失败**。
- **Tool calling** — 类型 conform `Tool`，模型自主调用并把结果折回对话。支持一轮多次调用。

**可用性**:
- **OS**: iOS/iPadOS/macOS/visionOS/**watchOS**/tvOS 26。
- **设备**: 仅 Apple Intelligence 机型 — **iPhone 15 Pro/Pro Max（A17 Pro）及以后**、全 M 系 iPad/Mac（**M1** 起）。旧设备返回 `.unavailable`，必须 fallback 云端。
- **端侧 vs Private Cloud Compute（PCC）**: 默认全端侧；PCC 提供更大模型 + 更大上下文，仍在 Apple 隐私保证下。开发者框架一等路径是端侧模型。

**约束**:
- **上下文窗口 ~4,096 token**/session（instructions + prompt + transcript + response 共享）。**这是最大的设计约束。** iOS 26.4 加了 `contextSize` / `tokenCount(for:)` + `Transcript` 剪枝。PCC ~32K。
- **延迟**: A17 Pro/M 系首 token 延迟不错，但吞吐低于云端前沿模型；适合短摘要/分类，不适合长文生成。
- **护栏**: 内置安全护栏可能拒答；iOS 26.4 降了误报。须显式处理拒答/护栏错误。
- **语言**: 多语含**中文(zh-Hans)** —— 对本双语 app 直接相关。**注意**: CJK token 昂贵，**~1 字 ≈ 1 token**，中文 prompt 吃 4K 窗口比英文快 3-4×。端侧中文做摘要/抽取够好，但细腻长文生成一般不如云端智谱。

**成本对比**: 端侧 = 免费/私密/离线/零 key。现 `ZhipuProvider` = 网络依赖 + 延迟波动 + key 管理 + 健康数据离设备 + per-call 成本。Foundation Models 把这些全翻面。

**2026 更新（WWDC 2026, 6/9）**: Apple **把框架开放给任意 LLM provider** — 实现 `LanguageModel` / `LanguageModelExecutor`，任何后端都能 drop-in 到同一 `LanguageModelSession` API。Anthropic 发了 `ClaudeForFoundationModels` Swift 包（Claude Sonnet/Opus 走同一 API；**targets OS-27 波次 / Xcode 27**）。**战略含义**: 同一 `LanguageModelSession` 抽象将来能同时front 端侧/PCC/Claude/Zhipu —— 与 app 自己的 `AIProvider` chain 收敛。

### 2.2 健身相关的其它 ML

| 能力 | 框架 | 给你什么 |
|---|---|---|
| **自定义端侧模型** | **Core ML** | 跑任意 `.mlpackage`（ANE/GPU）。训练产物的部署目标 |
| **2D 人体姿态** | **Vision** `VNDetectHumanBodyPoseRequest` | 每帧 19 关节 + 置信度（iOS 14 起）。手机摄像头做计次/动作评估的基础 |
| **3D 人体姿态** | **Vision** `VNDetectHumanBodyPose3DRequest` | 单张 2D 图出 17 关节 3D 骨架，不需 ARKit（WWDC23）。关节角/深度分析（深蹲深度、肘角） |
| **运动/计次分类** | **Create ML `MLActivityClassifier`** + **Core Motion** | 用 Watch 加速度/陀螺训时序分类器识别动作 + 计次；导出 Core ML 跑在 Watch |
| **派生健康指标（Apple 已算）** | **HealthKit** | Apple 已算并存 **VO₂max / 心肺健康**、自动训练检测、心率区间、静息/步行 HR、HRV 等 |

**关键「买 vs 造」线**: HealthKit **免费**给你 VO₂max、训练自动检测、心肺分类 —— **别自己重算**。自定义 Core ML/Create ML 只留给 Apple **不**给的：**力量训练计次 + 动作姿势评估**。

### 2.3 对本 app 的具体机会

app 的云端输出已是 `Codable` 结构（`TrainingRecommendation`、`DataAnalysis`、`OverviewInsight`）—— **几乎 1:1 映射到 `@Generable`。**

- **A. 端侧训练摘要/洞察（最高价值、最低风险）**: Foundation Models。喂紧凑预聚合的训练摘要 → 得自然语言摘要/洞察。可行性**高**（provider 已存在，就是当前 chat 路径）。隐私收益**大**（健康数不离设备）。注意 4K/CJK 预算，先聚合别 dump 逐组历史。
- **B. `@Generable` 结构化训练建议**: 给现有 `TrainingRecommendation`/`DataAnalysis`/`OverviewInsight` 加 `@Generable`/`@Guide`，模型直接产实例。可行性**高** —— 干掉端侧路径「从云端文本解析 JSON」的脆弱步骤（云端路径保留 `Codable`）。隐私 + 可靠性双赢。
- **C. 端侧换动作**: Foundation Models + **tool calling**，把动作库暴露成 `Tool` 让模型从真实 DB 选而非幻觉动作名。可行性**高**，任务小。
- **D. Vision 姿态计次/动作检查**: `VNDetectHumanBodyPose(3D)Request` 走**手机/iPad 摄像头** + 关节角启发式/小 Core ML 分割计次。可行性**中**（真 CV/产品工作）。**手机/iPad，非 Watch**（无摄像头）。隐私收益大（视频全端侧）。
- **E. Watch 运动计次**: Create ML `MLActivityClassifier` 训 Core Motion 数据 → Core ML 上 Watch。可行性**中低**（要采集标注每动作数据集，自由重量准确率是真难点）。本组最高投入。
- **F. 健康数据趋势/异常**: 两层 —（1）端侧确定性统计（滚动均值、z-score、PR 检测），**无需 ML，先做这个**；（2）Foundation Models **叙述**趋势。统计层可行性**高**。

**建议排序**: **先 B 和 A**（现有 provider 的精修，立刻兑现隐私+可靠性），**再 C**（tool calling），**再 F**。D、E 是净新功能，单独排期。

### 2.4 对 VitalStride 的迁移考量

**现状是好底子**: `makeDefault` 已把 `apple_intelligence` 放前、`isAvailable` 门控、`zhipu` fallback —— 形状正确。剩下是深度不是架构。

1. **可用性门控**: `isAvailable` 现查 `SystemLanguageModel.default.isAvailable`。收紧为查 `.availability` 并分支具体 `.unavailable` 原因（设备不合格 / 未启用 Apple Intelligence / 模型下载中 / 护栏拒答），对「未启用」给友好提示而非静默 fallback。
2. **采用 guided generation**: 给三个结构体加 `@Generable`/`@Guide`，端侧走 `respond(to:generating:)`。云端保 `Codable`，两 provider 满足同一 `AIProvider` 协议。**这是主要代码改动，消除一类解析失败。**
3. **上下文窗口纪律**: 每次端侧调用前算 token 预算。iOS 26.4+ 用 `tokenCount(for:)`/`contextSize` 预检；预聚合健康/训练数据让 prompt 远低于 4K —— **中文尤其**（1 字≈1 token，快 3-4×）。多轮聊天截断/摘要历史。
4. **watchOS**: 框架列 watchOS 26 为目标，但 Watch 上跑 LLM 要谨慎（最弱的 AI 机型、电/热受限）。**建议**: 生成式功能跑在 iPhone/iPad/Mac，Watch 留给采集（HealthKit、Core Motion）+ 轻量 Core ML 分类器，生成式摘要交给配对手机。运行时实测 Watch 可用性别假设。
5. **中文质量**: 端侧擅长 zh-Hans 摘要/抽取/分类，但细腻长文教练文本云端智谱仍可能更好。**务实策略**: 结构化输出 + 短摘要走端侧，长文中文聊天保云端作质量档，经 chain（或 per-feature 偏好）选择。
6. **前瞻（OS-27 波次）**: WWDC 2026 的 provider-agnostic 协议 + `ClaudeForFoundationModels` 意味着 app 将来能把自己的 `AIProvider` chain 统一到 Apple `LanguageModelSession` 后面（端侧/PCC/Claude/Zhipu 一个 session API）。要到 OS-27 / Xcode 27 才可动，但值得朝这设计 —— app 的 `AIProvider` 协议概念上正平行于 Apple 的新 provider 协议。

### 2.5 汇总表

| Apple 能力 | 框架 | 最低 OS/设备 | VitalStride 用例 | 隐私收益 | 可行性 |
|---|---|---|---|---|---|
| 端侧 LLM 摘要/聊天 | FoundationModels `LanguageModelSession` | iOS/macOS 26；A17 Pro/M1+ | NL 训练摘要、洞察叙述 | 高 | 高（provider 已有） |
| Guided 结构化输出 | FoundationModels `@Generable`/`@Guide` | iOS/macOS 26；A17 Pro/M1+ | 三个结构体免 JSON 解析 | 高 | 高 |
| Tool calling | FoundationModels `Tool` | iOS/macOS 26；A17 Pro/M1+ | 从真实动作库换动作 | 中 | 高 |
| 2D/3D 姿态 | Vision `VNDetectHumanBodyPose(3D)Request` | iOS 14 / 17(3D)；手机摄像头 | 视频计次+动作检查 | 高 | 中 |
| 运动分类 | Create ML `MLActivityClassifier` + Core Motion→Core ML | watchOS；需训练数据 | Watch 计次/动作检测 | 高 | 中低 |
| 派生健康指标 | HealthKit（内置） | iOS/watchOS；广 | 读 VO₂max/心肺/训练检测 | 高 | 高（已算好） |
| 趋势/异常叙述 | 端侧统计 + FoundationModels | iOS/macOS 26；A17 Pro/M1+ | 检测 PR/异常并叙述 | 高 | 高 |
| Provider 无关 session（未来） | FoundationModels `LanguageModel`/`Executor` | OS-27 / Xcode 27 | 统一端侧+PCC+Claude+Zhipu | 高 | 未来 |

### 2.6 一处需标注的不确定性

搜索到版本框架有冲突：**OS-26 波次（iOS/macOS 26）是 Foundation Models 落地且 app 当前 target 处**；WWDC 2026 的 provider-agnostic API 和 `ClaudeForFoundationModels` 包 **target OS-27 波次 / Xcode 27**。本报告把可落地集成放在 26 波次，provider-agnostic session 标为前瞻。

---

## Part 3 — 给你的行动建议（优先级）

1. **🔴 修 ADR-0005 与代码的隐私差异**（当下就该定夺）: 要么真做脱敏/分桶（在 `AIPromptBuilder`/`AIAnalysisPrompts` 发云端前对原始值分桶），要么改 ADR-0005 承认「云端发原始值、靠端侧优先 + 用户显式同意作为隐私边界」。现状是 ADR 承诺了没兑现的东西 —— reviewer/审计角度是个洞。**建议开一个 [Arch] issue 追这个决策。**
2. **🟠 把 10 处直连 `ZhipuProvider` 收编进 `AIProviderChain`**: 一次机械但高价值的重构 —— 让 Apple 端侧优先真正对所有 AI 功能生效，兑现 CONTEXT.md 红线。可按功能拆成多个 app-target issue。
3. **🟢 落地 `@Generable` 端侧结构化输出（Part 2 建议 B）**: 给三个结构体加 `@Generable`，端侧路径免 JSON 解析。隐私 + 可靠性双赢，是「用起 Apple 模型」最现成的一步。
4. **🟢 兑现 `specs/012-ai-routine-generation`**: AI 建议→一键开始训练，spec 已写好，是最现成的新 AI 功能。
5. **🔵 探索性（单独排期）**: Vision 姿态计次/动作检查（Part 2-D）是差异化功能，但是净新 CV 工作。

> 若要把上面 1-4 落成 Multica issue，随时说一声，我按 layer 拆好派给 Dev Team。

---

*报告生成: 2026-07-28。基础设施与调用点结论已回读源码核实（chain 调用点 11 处、ADR-0005:42 脱敏声称 vs 0 处实现、`AIPromptBuilder.swift:108` 发原始 weight×reps）。Apple 模型部分含 2026-07 web 调研，来源见下。*

### Apple 模型调研来源

- [Foundation Models — Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels)
- [Apple Newsroom — Foundation Models framework (Sept 2025)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences)
- [Meet the Foundation Models framework — WWDC25 session 286](https://developer.apple.com/videos/play/wwdc2025/286)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [What's new in the Foundation Models framework — WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241)
- [Bring an LLM provider to the Foundation Models framework — WWDC26 session 339](https://developer.apple.com/videos/play/wwdc2026/339)
- [Apple Newsroom — Next generation of Apple Intelligence & Siri (June 2026)](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more)
- [Detecting Human Body Poses in Images — Apple Developer Documentation](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)
- [Explore 3D body pose and person segmentation in Vision — WWDC23](https://developer.apple.com/videos/play/wwdc2023/111241)
- [MLActivityClassifier — Apple Developer Documentation](https://developer.apple.com/documentation/createml/mlactivityclassifier)
