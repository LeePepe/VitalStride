---
layer: AIService
role: AI 推理 Provider 抽象层；定义 AIProvider 协议 + ProviderChain + 输出结构（不含缓存）
depends_on: []
depended_by: []
red_lines:
  - 禁止引入 OpenAI/Anthropic/Google 等第三方 AI SDK；provider 走 OpenAI-compatible REST via URLSession（宪法 V）
  - API key 仅存 Keychain，禁止硬编码（宪法 V）
  - 新 provider = 实现 AIProvider 协议接入 chain，不替换、不新建包（宪法 III/V）
  - Apple Intelligence 本地优先 + 智谱 GLM fallback 的 chain 顺序不得反转（宪法 V）
  - Swift 6 strict concurrency，provider 须 Sendable（宪法 II）
roles:
  Types:   [Models, AIProvider, AIAnalysisResponse, DataAnalysis, TrainingRecommendation, OverviewInsight, AIServiceError, AITaskKind, RoutingSignal, ShadowSignal]
  Repo:    [KeychainHelper]
  Service: [AIProviderChain, ZhipuProvider, AppleIntelligenceProvider, AIRouter, AIRoutingBandit, RatioShadowSampler]
test: swift test --package-path Packages/AIService
owns: [AIProvider, AIProviderChain, ZhipuProvider, AppleIntelligenceProvider, AIRouter, AIRoutingBandit, RatioShadowSampler]
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

## 不在此 package 的内容

- AI 缓存（SwiftData 模型在 VitalModels，缓存逻辑在 app target `AIAnalysisService`）
- Prompt 构建（在 app target `AIAnalysisPrompts`）
- 概览动态布局（在 app target `Overview/`）

## 依赖

无外部依赖。
