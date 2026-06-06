# VitalStride Context

## Product Identity

VitalStride is a **health data collection + AI analysis** app. Strength training is one data source among many — the app's value is aggregating body data and providing AI-powered insights, not being a workout-only tool.

## Glossary

- **Health Data (健康数据)**: Any data readable from HealthKit — heart rate, steps, sleep, body mass, active energy, etc. This is the primary content of the Data Tab.
- **Workout Data (训练数据)**: Detailed exercise/set/rep data from in-app strength training sessions. Stored in SwiftData because HealthKit cannot represent per-set detail. Displayed in the Workout Tab.
- **Data Tab (数据 Tab)**: Tab 3 — a health data dashboard showing a summary card + grouped list of data types. NOT a training-specific view.

## Data Architecture Decisions

### HealthKit data is NOT cached in SwiftData

HealthKit is queried directly at read time. No `HealthSample` or `CachedHealthSample` SwiftData models. Rationale: HealthKit is already a local database with its own iCloud sync; duplicating it into SwiftData creates consistency risks, bloats CloudKit sync, and complicates privacy compliance when users revoke HealthKit permissions.

SwiftData stores only data that HealthKit cannot represent: `Workout`, `WorkoutExercise`, `ExerciseSet`, `Exercise`, `WorkoutTemplate`, `TemplateExercise`.

### In-Memory Cache Layer (HealthDataCache)

**选型结论：方案 B — 纯内存 actor 缓存，不使用 SwiftData 持久化。**

理由：
- **冷启动影响极小**：Anchor Query 延迟通常 <100ms，重新拉取成本可接受，不需要 SwiftData 持久化层来加速冷启动。
- **CloudKit 零风险**：纯内存方案无需考虑 CloudKit 同步隔离，无论未来是否启用 CloudKit 都不受影响。
- **实现复杂度低**：无需新 SwiftData model、无 migration、无缓存一致性维护。方案 A 的双层缓存（SwiftData + 内存字典）引入额外的失效逻辑和 schema 演进负担。
- **隐私合规简单**：数据仅存内存，app 终止自动清除；用户撤销 HealthKit 权限后清空 actor 状态即可，无需处理磁盘残留。

缓存层设计要点：
- 使用 Swift actor (`HealthDataCache`) 保证线程安全
- 按 `HealthSampleType` 分桶缓存 `HealthDataPoint` 数组
- Anchor Query 返回新数据时更新对应桶，整桶替换（immutable pattern）
- 缓存生命周期 = app 进程生命周期，不跨启动持久化
- View 层从 cache 读取，cache miss 时触发 HealthKit fetch 并回填

### 缓存层隐私合规约束

- **数据不离设备**：缓存数据仅存内存，不经任何网络传输，不写入磁盘文件
- **权限联动**：用户在系统设置中撤销 HealthKit 权限后，必须立即清空 `HealthDataCache` 全部缓存数据（调用 `invalidateAll()`），不保留只读副本
- **无日志泄露**：禁止在任何 log（os_log、print、第三方日志 SDK）中输出实际健康数值（心率值、体重值、步数等）。日志仅可记录 sample type、数量、时间范围等元数据
- **内存转储防护**：敏感健康数值在 actor 内部持有，不暴露为全局可访问状态

### 缓存层 Telemetry 需求

以下指标需在 MY-668 实现时埋点，本节仅定义需求：

| 指标 | 维度 | 说明 |
|------|------|------|
| `healthkit_cache_hit` | HealthSampleType | 缓存命中次数，用于衡量缓存有效性 |
| `healthkit_cache_miss` | HealthSampleType | 缓存未命中次数，触发 HealthKit fetch |
| `healthkit_fetch_duration_ms` | HealthSampleType | 单次 HealthKit 查询耗时（ms），用于衡量缓存带来的性能收益 |
| `healthkit_cache_refresh` | HealthSampleType | 缓存刷新次数（anchor query 返回新数据时） |

注意事项：
- Telemetry 仅记录计数和耗时，禁止记录实际健康数值
- 使用 OSSignpost 或自定义 MetricKit 上报，不依赖第三方 SDK

### macOS uses HealthKit for reading

macOS 13+ supports HealthKit (read-only, via iCloud Health sync). VitalStride's minimum is macOS 15.0, so the Data Tab uses the same HealthKit queries on both iOS and macOS. No platform-specific guards needed for data access.

### Single HealthKitService for all data types

One `HealthKitService` in `Shared/Services/` handles all HealthKit queries. Adding a new data type = registering a new type identifier, not creating a new file. Sleep (`HKCategoryType`) has special handling internally but the same external API.

## Data Tab Structure

### Summary Card (top)

2×2 grid of today's body metrics (complements Overview Tab's training summary):
- Steps (today)
- Resting heart rate (latest)
- Sleep (last night duration)
- Body weight (most recent)

### Grouped List

| Group | V1 Data Types |
|-------|---------------|
| 活动 (Activity) | 步数 (.stepCount), 活动能量 (.activeEnergyBurned) |
| 心脏 (Heart) | 心率 (.heartRate) |
| 身体测量 (Body) | 体重 (.bodyMass) |
| 睡眠 (Sleep) | 睡眠分析 (.sleepAnalysis) |

Tapping a row → Detail page.

### Detail Page (per data type)

- Time range Picker (day / week / month / year)
- Swift Charts graph with `chartXSelection` interaction
- Statistics summary (avg / max / min)
- No raw data point list in V1

## V1 Scope Boundaries

- 5 HealthKit data types (see table above)
- No background sync (Observer Query / BGHealthQuery deferred to V2)
- No data point list in detail pages
- Extensible: new types added via HealthKitService registration

## Project Structure: SPM Local Packages

The project uses XcodeGen + local SPM packages. Business logic lives in packages; app targets only contain platform-specific entry points and UI.

### Packages

| Package | Contents | Dependencies |
|---------|----------|-------------|
| VitalModels | SwiftData models (Workout, Exercise, etc.), enums, ModelContainerConfiguration | None |
| HealthKitService | HealthKitService, HealthDataPoint, HealthKitAnchorStore, HealthSampleType | VitalModels |
| AIService | AIProvider protocol, ZhipuProvider (智谱 GLM), ChatMessage/ChatResponse models | None |
| VitalUI | Shared UI components (DataStoreErrorView) | VitalModels |

### Rules

- App targets (iOS/macOS/watchOS) depend on packages, not on each other
- DataView + DataSections remain in app target (shared via project.yml), not in a package
- XcodeGen is retained for managing app targets, entitlements, and package references
- Adding a new AI provider = implementing `AIProvider` protocol in AIService package

## AI Architecture

### Provider

智谱 AI (GLM-4-Flash, free tier). OpenAI-compatible REST API via URLSession. No third-party SDK.

- Endpoint: `https://open.bigmodel.cn/api/paas/v4/chat/completions`
- Auth: `Authorization: Bearer <api-key>`
- Key stored in Keychain, not hardcoded

### AIService Package Interface

```swift
public protocol AIProvider: Sendable {
    func chat(messages: [ChatMessage], model: String?) async throws -> ChatResponse
    func chatStream(messages: [ChatMessage], model: String?) -> AsyncThrowingStream<ChatStreamChunk, Error>
}
```

Swappable: ZhipuProvider now, DeepSeek/OpenAI/通义 later — same protocol.
