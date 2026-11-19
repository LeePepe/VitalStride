---
layer: HealthKitService
role: HealthKit 数据读取、双层缓存、授权管理；app target 访问健康数据的唯一入口
paths: [Packages/HealthKitService]
test_paths: [Packages/HealthKitService/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/HealthKitService
depends_on: [VitalModels]
depended_by: [AppUI]
red_lines:
  - 健康数值禁止进任何日志（os_log/print/SDK）；仅可记录 sample type / 数量 / 时间范围（宪法 I）
  - L2 缓存（HealthCacheEntry）本地隔离，cloudKitDatabase:.none，不参与 CloudKit 同步（宪法 I）
  - 权限撤销即完整清除：invalidateAll() + 删除全部 HealthCacheEntry + removeAllAnchors() + 清零 telemetry 计数器（宪法 I）
  - L1 actor 缓存整桶替换（immutable pattern），禁止 in-place mutation
  - Swift 6 strict concurrency，Apple API 边界例外须在 ADR 记录（宪法 II）
roles:
  Types:   [HealthDataPoint, HealthSampleType, HealthWorkoutRecord]
  Repo:    [HealthKitAnchorStore, SwiftDataCachePersistence, HealthCachePersisting]
  Service: [HealthDataCache, HealthKitService, WorkoutSessionManager, HealthMetricsCalculator, TrainingLoadCalculator, SleepArchitectureAnalyzer, AerobicEfficiencyCalculator]
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

## 生理计算器与聚合器 (`roles.Service`)

所有计算器均为无状态的 `Sendable` 纯值类型，不触发 HealthKit 查询或日志输出（严格遵守宪法 I 零健康数值日志与宪法 II Swift 6 并发）：

- **`HealthMetricsCalculator`**:
  - `restingHeartRateSummary(from:asOf:calendar:)`: 单位 `bpm`（有效区间 `25...220`）。排除 `> asOf` 未来样本与 60 日窗口外样本，按日聚合计算 60 日每日均值基线 `baselineBPM`、7 日均值 `sevenDayAverageBPM` 与最新观测 `currentBPM`。
  - `hrvCorridor(from:standardDeviationMultiplier:asOf:calendar:)`: 单位 `ms` (SDNN，有效区间 `1...300`)。排除 `> asOf` 与 60 日窗口外样本；按日均值计算 60 日 `mean ± k·SD` 走廊 (`baselineMilliseconds`, `lowerBoundMilliseconds`, `upperBoundMilliseconds`)，并输出实测 `currentMilliseconds` 与 7 日滚动均值 `sevenDayAverageMilliseconds` 供 `isWithinCorridor` 非重言式判定。
  - `heartRateZones(from:maximumHeartRate:userAgeYears:clipIntervals:maxSampleGap:asOf:)`: 单位 `seconds`；按有效最大心率（显式指定 → Tanaka 年龄估算 `208 - 0.7 * age` → 实测峰值 → 默认 `190 bpm`）划分 Zone 1–5 (`<60%`, `60–70%`, `70–80%`, `80–90%`, `>=90%`)。支持 Apple Watch 瞬时点样本 (`startDate == endDate`，使用有界步长推导间隔)、合并同秒多源样本、单调时间轴扫描去重避免双源重复计时，以及可选 `clipIntervals` 训练窗口裁剪。
  - `heartRateRecovery(from:workouts:strengthWorkouts:asOf:)`: 单位 `bpm`；锚定最近已完成训练 (`endDate <= asOf`) 结束时刻附近的基线心率 `baselineBPM`（`[max(startDate, endDate - 120s), endDate + 15s]`），并在 `[+45s, +90s]` 与 `[+105s, +150s]` 有界窗口内取最接近 +60s / +120s 的样本计算下降量；缺失训后心率时保持 `nil`，绝不用历史静息心率充当训后恢复值。
  - `neatSnapshot(from:period:workouts:strengthWorkouts:asOf:calendar:)`: 默认按 `asOf` 所在单一日历天聚合（拒绝将 60 日历史累加进单日值），对跨边界或跨训练窗口的区间样本按时间比例裁剪，从非运动活动能量 (`nonExerciseActiveEnergy`)、非训练步数 (`nonWorkoutSteps`) 与非训练小时活动分布 (`hourlyNonWorkoutDistribution`) 中扣除并集的训练时间窗口，并纳入 `.appleStandTime` 站立时长与一致性评分。
  - `physiologicalSnapshot(...)`: 聚合五大生理域；只要任一域存在有效观测即返回可用快照并标记 `availableDomains`，缺失域保持 `isAvailable == false`（不整包返回 `nil`，也不伪造完美基线/零负债）。
- **`SleepArchitectureAnalyzer`**:
  - 按日历与傍晚 18:00 分界 (`nightAnchorDate`) 将跨午夜及夏令时切换的睡眠样本归入同一睡眠夜；输入顺序无关，排除 `> asOf` 样本。
  - 同一晚多源重叠区间按 `awake` 优先扣除、`asleepDeep > asleepREM > asleepCore > asleepUnspecified` 优先级去重归并，`inBed` 与全部睡眠/清醒区间取并集计算在床时长与睡眠效率。
  - `analyze` 返回最新睡眠夜结构（不把多晚累加为一晚）；`debtSummary` 在锚定 `asOf` 的 7 日 / 14 日日历窗口上计算累积睡眠负债，并显式输出观测夜数与缺失夜数 (`observedNightCount7d` / `missingNightCount7d` 等)。
- **`AerobicEfficiencyCalculator`**:
  - 单位：距离 `m`（兼容 `km` 单位转换）、速度 `km/h`、心率 `bpm`、`EF = (km/h) / bpm`、`VO2max = mL/(kg·min)`。
  - 将距离样本按有氧训练窗口或连续位移簇（间隔 `<= 20 min`）切分会话，剔除跨天睡眠/静坐空白；在最新有效会话内将前半程与后半程分别计算各自的真实配速与时间对齐心率（例如恒定心率下配速由 12 km/h 掉至 9 km/h 时准确输出 `25%` 有氧解耦率 `Pa:Hr`）。无距离或心率样本时仍保留 `<= asOf` 的 `vo2Max` 与 `vo2MaxTrend`。
- **`TrainingLoadCalculator`**:
  - 将有氧 Banister TRIMP 与力量训练 Session-RPE / 密度归一化负荷 (`strengthLoad`，约 `25–120` 负荷/小时) 统一到可比量纲，消除原始吨位 (`kg`) 直乘导致的量级失真。
  - 排除 `> asOf` 未来或未完成训练；通过 `StrengthWorkoutSummaryInput.healthKitUUID`（缺失 UUID 时回退到同类力量训练时间窗口重叠度）对 SwiftData 与 HealthKit 镜像力量训练去重；按日历天（含休息日 0 负荷）推进 7 日 `ATL` 与 42 日 `CTL` 指数加权衰减，并输出 `atlDelta7d`、`ctlDelta7d`、`ctlDelta14d`、`tsbDelta7d` 与最近 14 日 `recentTrajectory`。

## 平台

macOS 13+ 支持 HealthKit read-only（via iCloud Health sync）。iOS 和 macOS 使用相同查询路径。

## 依赖

- VitalModels（HealthCacheEntry 模型与生理指标 DTO）
