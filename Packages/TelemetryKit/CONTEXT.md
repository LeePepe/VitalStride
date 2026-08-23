---
layer: TelemetryKit
role: 埋点抽象层；TelemetryEvent 定义 + TelemetryProvider 协议 + actor TelemetryService 分发
depends_on: []
depended_by: [AppUI]
red_lines:
  - Telemetry 仅记录计数 / 耗时 / 元数据；禁止上报实际健康数值（心率/体重/步数等）（宪法 I）
  - 第三方 telemetry SDK 仅限自建 Aptabase，且只能作为 provider 消费强类型 TelemetryEvent（宪法 V narrow 例外 / ADR-0015 supersedes ADR-0011）；禁止 AI 第三方 SDK 与任何接受原始健康数值的 provider API
  - DEBUG 构建不发送 analytics（ADR-0015 §Decision.3）
  - Swift 6 strict concurrency，Event/Provider 须 Sendable，分发走 actor（宪法 II）
roles:
  Types:   [TelemetryEvent, TelemetryProvider]
  Service: [TelemetryService, ConsoleTelemetryProvider]
test: swift test --package-path Packages/TelemetryKit
owns: [TelemetryEvent, TelemetryProvider, TelemetryService, ConsoleTelemetryProvider]
---

# TelemetryKit Context

## 职责

轻量埋点抽象层。定义结构化 `TelemetryEvent` + `TelemetryProvider` 协议，并由 `actor TelemetryService`
把事件分发到已注册的 provider。不含 UI、不含业务逻辑、不落库。

> **集成状态**：已注册到 `project.yml`（`packages:` + iOS/macOS/watchOS 三个 app target
> + VitalStrideTests 依赖）。仍是无本地依赖的独立包（不依赖其它 layer），埋点调用点接入见 ADR-0007。

## 架构

### TelemetryEvent（Types）

`enum TelemetryEvent: Sendable, Equatable` —— 埋点事件的封闭集合。事件用
`TelemetryIdentifier`（`ExpressibleByStringLiteral` 的 Sendable value type）标识。

**隐私约束（宪法 I 投影）**：事件 payload 只承载计数 / 耗时 / sample type 等元数据，
**绝不承载实际健康数值**。CONTEXT.md §缓存层 Telemetry 需求 里的四个指标
（`healthkit_cache_hit` / `_miss` / `_fetch_duration_ms` / `_refresh`）即按此约束设计。

### TelemetryProvider（Types）

```swift
public protocol TelemetryProvider: Sendable {
    func track(_ event: TelemetryEvent)
}
```

上报后端的抽象。`ConsoleTelemetryProvider`（基于 `os`）是默认实现，可换成 MetricKit /
OSSignpost 等，不引第三方 SDK。

### TelemetryService（Service）

```swift
public actor TelemetryService {
    public func register(_ provider: any TelemetryProvider)
    public func track(_ event: TelemetryEvent)
}
```

`actor` 保证并发安全的事件分发：`register` 挂载 provider，`track` 把事件 fan-out 给全部已注册 provider。

## 依赖

无本地 layer 依赖（`depends_on: []`）。纯 Foundation + os。

## 约束

- 新 provider = 实现 `TelemetryProvider`，不改 `TelemetryService`。
- 新事件 = 扩 `TelemetryEvent` case，保持 `Sendable`/`Equatable`。
- 任何埋点新增前先核对宪法 I：payload 不得含健康数值。
