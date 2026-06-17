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
