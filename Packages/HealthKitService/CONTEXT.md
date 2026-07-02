---
layer: HealthKitService
role: HealthKit 数据读取、双层缓存、授权管理；app target 访问健康数据的唯一入口
depends_on: [VitalModels]
depended_by: []
red_lines:
  - 健康数值禁止进任何日志（os_log/print/SDK）；仅可记录 sample type / 数量 / 时间范围（宪法 I）
  - L2 缓存（HealthCacheEntry）本地隔离，cloudKitDatabase:.none，不参与 CloudKit 同步（宪法 I）
  - 权限撤销即完整清除：invalidateAll() + 删除全部 HealthCacheEntry + removeAllAnchors() + 清零 telemetry 计数器（宪法 I）
  - L1 actor 缓存整桶替换（immutable pattern），禁止 in-place mutation
  - Swift 6 strict concurrency，Apple API 边界例外须在 ADR 记录（宪法 II）
roles:
  Types:   [HealthDataPoint, HealthSampleType, HealthWorkoutRecord]
  Repo:    [HealthKitAnchorStore, SwiftDataCachePersistence, HealthCachePersisting]
  Service: [HealthDataCache, HealthKitService, WorkoutSessionManager]
test: swift test --package-path Packages/HealthKitService
owns: [HealthKitService, HealthDataCache, HealthKitAnchorStore, HealthSampleType]
---

# HealthKitService Context

## 职责

HealthKit 数据的读取、缓存、授权管理。App target 通过此 package 访问所有健康数据。

## 双层缓存架构

### L1: 纯内存 actor 缓存 (HealthDataCache)

- Swift actor，按 `HealthSampleType` 分桶持有 `[HealthDataPoint]`
- 整桶替换（immutable pattern），不做 in-place mutation
- 生命周期 = app 进程，不跨启动持久化
- TTL 默认 1 小时（可配置），过期数据**立即返回**同时后台刷新（stale-serve-then-refresh）
- 不参与 CloudKit 同步

### L2: SwiftData 持久化缓存 (HealthCacheEntry)

- SwiftData @Model，定义在 VitalModels package
- 使用独立 `ModelConfiguration("HealthCache", cloudKitDatabase: .none)` — 数据**仅存本地磁盘**
- 复合唯一约束：`(sampleType, coveredRangeStart, coveredRangeEnd)`
- 异步写回：HealthKit fetch 成功后在后台持久化到 L2（`persistInBackground()`）
- Generation guard：`invalidateAll()` 递增 generation 计数器，防止过期 persist 写入脏数据

### 数据读取路径

```
L1 hit → 返回
L1 miss → L2 load → L1 回填 → 返回
L2 miss → HealthKit fetch → L1+L2 回填 → 返回
```

冷启动时 `hydrate()` 从 L2 预加载 `overviewTypes`（步数、心率、睡眠、体重）到 L1。

### Telemetry 指标

| 指标 | 维度 | 说明 |
|------|------|------|
| `healthkit_cache_hit` | HealthSampleType | 缓存命中 |
| `healthkit_cache_miss` | HealthSampleType | 缓存未命中，触发 HealthKit fetch |
| `healthkit_fetch_duration_ms` | HealthSampleType | 单次 HealthKit 查询耗时 |
| `healthkit_cache_refresh` | HealthSampleType | 缓存刷新（anchor query 返回新数据） |

使用 OSSignpost，不依赖第三方 SDK。Telemetry 仅记录计数和耗时，**禁止记录实际健康数值**。

## HealthKit 同步策略

**Layer 1: Anchor Query（已实现）**
- 每次进入页面时 `HKAnchoredObjectQuery` 拉取增量
- anchor token 持久化到 UserDefaults（device-local）

**Layer 2: Observer Query + BGHealthQuery（后续）**
- 后台增量同步，保证 app 未打开时数据也保持最新

## 隐私约束

- L1 数据不离设备，L2 使用 `cloudKitDatabase: .none`
- 用户撤销 HealthKit 权限 → 立即清除全部缓存（L1 + L2 + anchor tokens + telemetry 计数器）
- **禁止在任何日志中输出实际健康数值**（心率值、体重值、步数等），仅可记录 sample type、数量、时间范围

## 支持的数据类型

`HealthSampleType` 枚举定义全部类型，`overviewTypes` = {stepCount, heartRate, sleepAnalysis, bodyMass}。
添加新类型 = 在枚举中加 case + 注册到 HealthKitService 即可。

## 平台

macOS 13+ 支持 HealthKit read-only（via iCloud Health sync）。iOS 和 macOS 使用相同查询路径。

## 依赖

- VitalModels（HealthCacheEntry 模型）
