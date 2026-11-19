---
layer: AIService
role: AI 推理 Provider 抽象层；定义 AIProvider 协议 + ProviderChain + 输出结构（不含缓存）
paths: [Packages/AIService]
test_paths: [Packages/AIService/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/AIService
depends_on: []
depended_by: [AppUI]
red_lines:
  - 禁止引入 OpenAI/Anthropic/Google 等第三方 AI SDK；provider 走 OpenAI-compatible REST via URLSession（宪法 V）
  - API key 仅存 Keychain，禁止硬编码（宪法 V）
  - 新 provider = 实现 AIProvider 协议接入 chain，不替换、不新建包（宪法 III/V）
  - Apple Intelligence 本地优先 + 智谱 GLM fallback 的 chain 顺序不得反转（宪法 V）
  - Swift 6 strict concurrency，provider 须 Sendable（宪法 II）
roles:
  Types:   [Models, AIProvider, AIAnalysisResponse, DataAnalysis, TrainingRecommendation, OverviewInsight, AIServiceError, AITaskKind, RoutingSignal, ShadowSignal, FourLayerModels]
  Repo:    [KeychainHelper]
  Service: [AIProviderChain, ZhipuProvider, AppleIntelligenceProvider, AIRouter, AIRoutingBandit, RatioShadowSampler, OpenAICompatibleProvider, JevGatewayProvider, DeterministicFourLayerEngine, FourLayerAdviceEngine, UserAIModelConfiguration]
test: swift test --package-path Packages/AIService
owns: [AIProvider, AIProviderChain, ZhipuProvider, AppleIntelligenceProvider, OpenAICompatibleProvider, JevGatewayProvider, DeterministicFourLayerEngine, FourLayerAdviceEngine, AIRouter, AIRoutingBandit, RatioShadowSampler]
---

# AIService Context

## 职责

AI 推理的 Provider 抽象层。定义 `AIProvider` 协议和输出数据结构。不包含缓存逻辑（缓存在 app target 的 `AIAnalysisService` 中）。

## Provider 架构

### AIProvider 协议

```swift
public protocol AIProvider: Sendable {
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error>
}
```

### AIProviderChain（优先级链）

`AIProviderChain` 按优先级遍历多个 provider，第一个 `isAvailable()` 且调用成功的 provider 生效。
当前优先级：Apple Intelligence → 智谱 AI (GLM-4-Flash)。

添加新 provider = 实现 `AIProvider` 协议 + 在 `AIProviderChain.makeDefault()` 中注册。

### 当前 Provider

| Provider | 模型 | 说明 |
|----------|------|------|
| AppleIntelligenceProvider | Foundation Model (on-device) | iOS 18.1+，设备端推理，无需 API Key |
| ZhipuProvider | GLM-4-Flash (free) / GLM-4-Plus (paid) | 云端，OpenAI 兼容 REST API |

智谱 API：`https://open.bigmodel.cn/api/paas/v4/chat/completions`，API Key 存储在 Keychain。

### 可插拔模型与四层建议

`UserAIModelConfiguration` 使用 `PluggableAIProvider` 选择四种模式：

- `foundationModels`：Apple Intelligence → 可选 Zhipu → physiological deterministic fallback。
- `customOpenAICompatible` / `jevGateway`：显式选择的 remote → 可选 Zhipu → physiological
  fallback；不偷偷插入 Apple 覆盖显式选择。remote availability 要求明确 HTTP(S) endpoint、非空
  model ID 以及可读取的非空 Keychain key。Jev 仅在显式 `allowsUnauthenticatedGateway: true`
  且未声明 token/service 时允许匿名；配置了 service 却缺 key/访问失败不得降级匿名。
- `deterministicFallback`：仅 deterministic，不访问网络，即便传入 Zhipu key。

`AIProviderChain.makeDefault` / `AIRouter.makeDefault` 保持原来的 Apple → 可选 Zhipu，**不添加**
专用于生理数据的 fallback。配置 router 保持 Apple `maxQuality: .medium` 与设备能力 gate；
`RegisteredProvider.supportedTasks` 将 deterministic 限于 `.fourLayerAdvice`，其它 provider 默认
支持所有 task。直接 chain 中 deterministic 也仅接受可解码的 `PhysiologicalSnapshot`，其它
chat 输入抛 `noProviderAvailable`，不伪造成功。FourLayerAdviceEngine 才保证离线建议。

网络 provider 只用 `URLSession` REST/SSE；配置 Codable 只存 endpoint、model ID、Keychain service
和匿名 opt-in，不存 secret。public raw key/token 注入仅为瞬态内存使用，与现有 Zhipu 接口一致；
持久化只走 Keychain。`itemNotFound` 映射 `missingAPIKey`，locked/unexpected-data 等真实 Keychain
失败保留原错误，不记录 service/endpoint/model/secret/prompt/response。SSE 遇 `[DONE]` 或 finish_reason
结束，malformed data / 无终止标记的 EOF 为错误；consumer 终止取消 producer。chain 不因取消启动 fallback。

### 生理 wire 与 unknown 数据

`FourLayerModels.swift` 与 VitalModels `DTOs/PhysiologicalMetrics.swift` 同步，无 package dependency。
日期是默认 Codable 的 2001-01-01 起秒数；心率/HRR 为 bpm，HRV 为 ms；睡眠/站立/Zone 1–5
为秒，energy 为 kcal，EF 为 (km/h)/bpm，Pa:Hr 为百分比，VO2max 为 mL/(kg·min)，cap/efficiency
为 0...1。ATL/CTL 是归一化日训练 stress 的 7/42d EWMA，TSB=CTL−ATL，附 7/14d delta/trajectory。
`availableDomains` 与各 metric 的 availability/睡眠观测夜数共同判断缺失；未知 L1 的 `value` 为 nil、
severity 为 watch，不能用零负债/零负荷表示完美恢复。

两包 Tests/Fixtures 的五份 synthetic canonical JSON 具有相同 SHA-256。通过 #filePath 定位 source
fixtures（manifest exclude，不生成会遮蔽生产本地化 bundle 的 test Bundle.module）。各包独立 decode 并将实际
encode 的结果规范化后逐字节比对 fixture：仅规范化 Set 顺序、enum-key dictionary alternating-array
顺序与 JSON object key 顺序；不忽略字段/数值。覆盖 full/steps-only/all-missing、所有 enum case、
完整 report、strength projection 与 legacy optional/default 缺省；不引入跨包依赖。

### L1 → L4 规则及模型校验

L1 包含 RHR-baseline、HRV current/7d/60d、Zones1–5、HRR1/2、睡眠阶段/效率/7d14d debt/coverage、
NEAT/energy/stand、EF/Pa:Hr/VO2、ATL/CTL/TSB/ratio/trajectory delta。L3 的 autonomic/sleep/fatigue
各自缺失时保守取 40，不等于医学判断；缺关键域时 cap 至多 0.6。L2 将 Deep/REM/效率/debt ×
fatigue/Zone4–5，以及 movement/非运动支出 × heart/load recovery 的不匹配计入 readiness penalty。
没有 intake 或 body-composition 字段，不声称从支出算出热量平衡或身体成分变化。
mesocycle 优先过载 deload，其次 ATL 下降/TSB 回升的 realization、上升负荷的 intensification，
其余 accumulation；按 as-of 剔除未来 trajectory。阈值为 coaching heuristics，不做临床诊断。
L4 综合 recovery、movement、aerobic，输出非空叙事和 1–3 个行动。

固定 snapshot/as-of 的 fallback 完全确定，默认 report 时间取 snapshot.generatedAt（可显式覆盖）。
`FourLayerAdviceEngine` 使用包含完整字段、单位、范围与示例的 schema prompt；用独立 raw Decodable
读取响应，**在**公共 DTO clamp/default 前检查全部 L1 metric/domain、两条 coupling、必填 sub-scores、
raw 0...100 score、finite 0...1 cap、非空贡献/叙事与 1–3 非空 actions、匹配 as-of。缺字段/越界/空语义、
availability/network/parse 错误均 fallback。`generateCancellable` 传播 cancellation；source-compatible
非抛出 `generate` / `synthesize` 刻意在取消时立即返回本地建议，不重试模型。

### AIRouter（chain 的上层入口）

`AIRouter` 是 `AIProviderChain` 之上的任务感知路由层，暴露 `execute(kind:messages:model:)` / `executeStream(...)` 作为业务代码调用入口。语义：

1. 先按 `AITaskKind` + `DeviceTier` 选中 primary provider —— Stage 1 走静态策略（on-device-first + registration order），Stage 5 起可插入 `AIRoutingBandit` 的权重结果。
2. 选中后 **委托给 `AIProviderChain`** 执行；chain 的 Apple Intelligence → 智谱 GLM fallback 顺序不反转（宪法 V）。router 只影响入口选择，不重排 chain。
3. 旁路把每次调用的 `RoutingSignal` 发到注入的 `RoutingSignalSink`（FR-008 best-effort，默认 `NoOpRoutingSignalSink`），供 app 层做评估/学习。

### AIRoutingBandit（in-package 值类型策略）

`AIRoutingBandit` 是 `Sendable` value type，不是 provider —— 它只回答"当前 `(kind, tier)` 该先叫哪个 provider 名字"，不做 IO、不实现 `AIProvider`。核心特征：

- **ε-greedy**（Bayesian-smoothed posterior：`(priorStrength * priorMean + rewardSum) / (priorStrength + count)`）+ 可选 Thompson sampling 变体。所有随机分支走注入的 `DeterministicSampler`，测试可复现。
- **`staticPrior` = Stage 1 静态策略** —— `staticPriorFromRouterDefaults(...)` 从 `AIRouter.defaultPolicy` + provider 元数据构造出的 prior，其 `argmax` 与 Stage 1 首选一致；Day-1（`sum(count) == 0`）走纯 prior 无采样，KL≈0 零行为回归（FR-013 / SC-006）。
- **Reward = f(Bool, Bool?, Double?)**：pure reducer，从不吃 HealthKit 数值或响应文本，满足 FR-018 / 宪法 I。
- **存储解耦**：观测态由 `BanditArmStateRepository` 协议持有；具体存储（SwiftData 等）由 app 装配注入，本包不落地任何持久化实现（宪法 III）。

## 输出数据结构

| 类型 | 用途 | 字段 |
|------|------|------|
| `OverviewInsight` | 概览 Tab 动态卡片 | key, cardType, cardSize, title, content, suggestion?, iconName? |
| `TrainingRecommendation` | 训练 Tab 推荐 | title, muscleGroups, exercises, reasoning |
| `DataAnalysis` | 数据 Tab 趋势分析 | sampleType, summary, trend, suggestion? |

这些结构是 `Codable + Sendable`，AI 返回 JSON → decode 为对应类型。

## 已移除的 public API —— Stage 6d ship-gate 迁移说明（FR-017 / FR-018，宪法 I）

Stage 6d（PR #391）从本层**永久移除**下列 public API。它们的共同点是**承载原始
prompt / response 文本**（HealthKit 派生的健康数值会出现在其中），与 spec 019
FR-017 的上架红线直接冲突。本节是这批破坏性变更的常驻迁移说明。

### 被移除的符号

| 符号 | 原位置 | 原用途 |
|------|--------|--------|
| `AIRouter.init(rawDebugSink:)`（初始化器参数） | `AIRouter.swift` | 注入 raw debug 旁路 |
| `AIRouter.init(shadowPairSink:)`（初始化器参数） | `AIRouter.swift` | 注入 shadow raw pair 旁路 |
| `RawDebugPayload` | `RoutingSignal.swift` | 承载单次调用的 prompt / response 原文 |
| `LocalOnlyRawDebugSink` | `RoutingSignal.swift` | 接收 raw payload 的本地 sink 协议 |
| `ShadowPairPayload` | `ShadowSampling.swift` | 承载 shadow 双跑的 main / candidate 响应原文 |
| `LocalOnlyShadowPairSink` | `ShadowSampling.swift` | 接收 shadow pair 的本地 sink 协议 |
| `AIRoutingEvaluationSample` | `AIRoutingEvaluationSample.swift`（整文件删除） | 离线评分输入样本，含响应原文 |
| `AIRoutingEvaluationScore` | 同上 | 离线评分输出 |
| `AIRoutingGrader` | 同上 | 评分器协议 |
| `HeuristicAIRoutingGrader` | 同上 | 启发式评分器实现 |
| `AIRoutingEvaluator` | `AIRoutingEvaluator.swift`（整文件删除） | 批量评分入口 |
| `AppleEvaluationsGrader` | 同上 | Apple Evaluations 评分器（Stage 4，从未接入） |

### 无 deprecated shim，无等价替代

**刻意不提供 `@available(*, deprecated)` 过渡层。** 这些类型存在的唯一意义就是持有
原始健康值文本；保留任何形式的兼容 shim 等于保留 raw 承载者，ship-gate
（`scripts/ci/scan-temp-prelaunch.sh enforce`）照样红，与移除目的自相矛盾。

- **raw prompt / response 持久化**：由 FR-017 / FR-018 **永久退役**，无替代。原始
  文本此后不在本层被物化，因此既没有可注入的 sink，也没有可落盘的 payload。
- **离线评分（Stage 4 Apple Evaluations）**：整体退役，无替代。该能力从未接入任何
  调用方（无接入点），owner 于 2026-08-16 决策放弃。

### 调用方迁移

| 原写法 | 迁移后 |
|--------|--------|
| `AIRouter(..., rawDebugSink: mySink, ...)` | 删掉该实参；其余参数与语义不变 |
| `AIRouter(..., shadowPairSink: myPairSink, ...)` | 删掉该实参。**shadow 双跑本身保留**（FR-010），只是不再捕获原始输出文本 |
| 从 shadow pair 读取 main / candidate 响应原文 | 改用 `ShadowSignal` 的路由 metadata（provider、latency、成败、错误类别）。原始输出文本不再对外提供 |
| 构造评估样本送离线评分器打分 | 无迁移路径。将来若要恢复离线评估，MUST 新设计一个**不承载原始 prompt / response** 的样本 schema（只存 schema 校验结果、分数、路由 metadata），不得复活上表类型 |

两个初始化器参数原本都是 `= nil` 默认值，因此**未显式传参的调用点无需任何改动**。

### 影响面证据（PR #391，HEAD `fc64f20`）

- **本包外引用为 0**：以上全部符号名做全仓 `git grep`，排除 `Packages/AIService`
  后零命中。正对照（同一批搜索词在 base `423108c` 的 `Packages/AIService` 内）命中
  4 个文件，证明搜索词有效 —— 零命中不是搜索写错导致的假阴性。
- 本 SPM 包**不对外分发**，唯一消费者是本 repo 的 app target；PR #391 的
  `App target` CI check（xcodebuild 全量编译）为 SUCCESS，即 app 层确实不依赖这些
  API。
- 六个 SPM 包的 `swift build` / `swift test` CI check 全部 SUCCESS。

## 不在此 package 的内容

- AI 缓存（SwiftData 模型在 VitalModels，缓存逻辑在 app target `AIAnalysisService`）
- Prompt 构建（在 app target `AIAnalysisPrompts`）
- 概览动态布局（在 app target `Overview/`）

## 依赖

无外部依赖。
