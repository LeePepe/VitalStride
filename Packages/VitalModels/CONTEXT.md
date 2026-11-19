---
layer: VitalModels
role: SwiftData @Model 定义 + 枚举 + ModelContainer 配置；全项目数据层基础
paths: [Packages/VitalModels]
test_paths: [Packages/VitalModels/Tests]
gate_tier: local-fast
build: swift build --package-path Packages/VitalModels
depends_on: []
depended_by: [HealthKitService, VitalUI, AppUI]
red_lines:
  - HealthKit L2 缓存模型（HealthCacheEntry / AvailableTypesEntry）必须 cloudKitDatabase:.none，禁止 CloudKit 同步（宪法 I）
  - AI 缓存模型（OverviewInsightCache / TrainingAdviceCache / DataAnalysisCache）必须 cloudKitDatabase:.none（宪法 I）
  - 仅训练数据（Workout/WorkoutExercise/ExerciseSet/Exercise/WorkoutTemplate/TemplateExercise/UserInterest）允许 CloudKit-synced
  - Swift 6 strict concurrency，禁止 @unchecked Sendable / nonisolated(unsafe) 绕过（宪法 II）
  - RoutingSignalEntry 永久字段清单 = {kind, provider, deviceTier, latencyMs, schemaValid, accepted, timestamp}；raw 调试字段已由 FR-017 / Stage 6e 永久移除，不得重新引入（宪法 I 永久态）
  - BanditArmStateEntry 永久字段清单 = {kind, deviceTier, provider, count, rewardSum, updatedAt}；不得追加任何健康/训练数值字段（宪法 I 永久态）
roles:
  Types:  [Enums, Models, DTOs]
  Config: [Persistence]
  Repo:   [Repo]
test: swift test --package-path Packages/VitalModels
owns: [Workout, Exercise, ExerciseSet, WorkoutTemplate, HealthCacheEntry, ModelContainerConfiguration, WorkoutSetManager]
---

# VitalModels Context

## 职责

全部 SwiftData @Model 定义 + 枚举 + ModelContainer 配置。是其他 package 和 app target 的数据层基础。

## SwiftData 存储分区

三个独立 `ModelConfiguration`，隔离 CloudKit 同步范围：

| 分区 | CloudKit | 模型 |
|------|----------|------|
| Training | ✅ 三端同步 | Workout, WorkoutExercise, ExerciseSet, Exercise, WorkoutTemplate, TemplateExercise, UserInterest |
| HealthCache | ❌ `cloudKitDatabase: .none` | HealthCacheEntry, AvailableTypesEntry |
| AICache | ❌ `cloudKitDatabase: .none` | OverviewInsightCache, TrainingAdviceCache, DataAnalysisCache |

CloudKit 容器：`iCloud.com.leepepe.VitalStride`

### 设计要点

- HealthCache 和 AICache 使用 `.none` 隔离，数据仅存本地磁盘，不参与 iCloud 同步
- 冲突策略：server wins（HealthKit 为权威源，本地可重新拉取）
- GPS 轨迹做降采样压缩控制 CloudKit 容量

## 训练数据模型

```
Workout (训练会话)
  ├── type: WorkoutType (strength)
  ├── startDate / endDate
  ├── source: .recorded | .imported | .healthkit
  └── exercises: [WorkoutExercise]
        ├── exercise: Exercise (动作引用)
        ├── order: Int
        └── sets: [ExerciseSet]
              ├── weight: Double (kg)
              ├── reps: Int
              ├── setType: .working | .warmup | .dropSet | .pyramid
              └── restDuration: TimeInterval?

Exercise (动作库)
  ├── name: LocalizedString (中/英)
  ├── muscleGroup / equipment / primaryMuscles / secondaryMuscles
  └── isCustom: Bool

WorkoutTemplate → TemplateExercise（训练模板）
```

## AI 缓存模型

三个 `@Model`，统一模式：`contentJSON: String` + `generatedAt: Date` + `expiresAt: Date` + `isExpired` 计算属性。

| 模型 | 唯一约束 | TTL | 用途 |
|------|---------|-----|------|
| OverviewInsightCache | cacheKey ("default") | 1h | 概览 Tab AI 卡片 |
| TrainingAdviceCache | cacheKey ("default") | 1h | 训练 Tab AI 推荐 |
| DataAnalysisCache | sampleType | 1h | 数据 Tab 趋势分析（按类型独立缓存） |

缓存读写逻辑在 app target 的 `AIAnalysisService`（ModelActor），此处只定义模型。

## 枚举

- SetType: working / warmup / dropSet / pyramid
- MuscleGroup, Equipment, Muscle（动作分类）
- TimeRange: day / week / month / year（图表时间范围）
- WorkoutSource: recorded / imported / healthkit
- WorkoutType: strength（可扩展）
- HeartRateZone, InsightSeverity, InsightDomain, MesocyclePhase（生理与四层建议枚举）

## 生理指标与四层建议 DTOs (`Sources/VitalModels/DTOs/PhysiologicalMetrics.swift`)

所有 DTO 为 `Codable + Sendable + Equatable` 纯值类型（归属 `roles.Types`），不包含 `@Model` 引用，严禁携带 `NaN` / `±Infinity`（初始化与解码统一做有限值/生理区间收敛）：

- **Heart**:
  - `RestingHeartRateSummary`: 单位 `bpm`；包含 `averageBPM`、最新观测 `currentBPM`、7 日均值 `sevenDayAverageBPM`、60 日每日均值基线 `baselineBPM` 及 `deltaFromBaselineBPM`。
  - `HRVCorridorSnapshot`: 单位 `ms` (SDNN)；包含 60 日基线均值 `baselineMilliseconds` 与上下走廊 `[lowerBoundMilliseconds, upperBoundMilliseconds]`，以及实测最新值 `currentMilliseconds` 与 7 日滚动均值 `sevenDayAverageMilliseconds`。`isWithinCorridor` 以实测 `currentMilliseconds` / `sevenDayAverageMilliseconds` 与 60 日走廊比较，无有效样本时为 `false`。
  - `HeartRateZoneDistribution`: 单位 `seconds` (`TimeInterval`)；记录 Zone 1–5 累计时长及有效最大心率 `resolvedMaximumHeartRateBPM`。
  - `HeartRateRecoveryMetric`: 单位 `bpm`；锚定最近已完成训练 `workoutEndDate` 结束时刻的 `baselineBPM`，以及训后 +60s / +120s 观测值与下降量 (`oneMinuteDropBPM` / `twoMinuteDropBPM`)。
- **Sleep**:
  - `SleepArchitectureSnapshot`: 单位 `seconds`；记录单晚（或归并后最新睡眠夜）的 `deepDuration`、`remDuration`、`coreDuration`、`awakeDuration`、`inBedDuration`、`totalSleepDuration` 与效率 `sleepEfficiency` (`0...1`)。
  - `SleepDebtSummary`: 单位 `seconds`；记录过去 7/14 个日历夜相对目标/个人基线的睡眠负债 `sevenDayDebt` / `fourteenDayDebt`，并显式携带观测夜数与缺失夜数 (`observedNightCount7d` / `missingNightCount7d` / `observedNightCount14d` / `missingNightCount14d` / `isAvailable`)，缺失夜不伪造健康零负债。
- **Steps & NEAT**:
  - `NEATActivitySnapshot`: 包含当日总步数 `dailySteps`、剔除训练窗口后的 `nonWorkoutSteps`、`nonExerciseActiveEnergy` (`kcal`)、被剔除的训练活动能量 `workoutActiveEnergyExcluded` (`kcal`)、`basalEnergy` (`kcal`)、站立时长 `standDuration` (`seconds`)、非训练活跃小时数 `activeNonWorkoutHourCount`、按小时非训练活动分布 `hourlyNonWorkoutDistribution` 与一致性得分 `hourlyMovementConsistency` (`0...1`)。
- **Aerobic & VO2max**:
  - `AerobicEfficiencySnapshot`: 有氧效率因子 `efficiencyFactor` (`(km/h) / bpm`)、前后半程解耦率 `aerobicDecouplingPercentage` (`%`)、最新 `vo2Max` (`mL/(kg·min)`) 及趋势 `vo2MaxTrend`。
- **Training Load & Actor-Safe Workout Projection**:
  - `StrengthWorkoutSummaryInput`: 力量训练纯值投影（`startDate`, `endDate`, `workingVolume` [kg], `setCount` [已完成正式组], `estimatedRPE` [0...10], `healthKitUUID`）。`Workout.makeStrengthWorkoutSummaryInput(defaultRPE:)` / `Workout.strengthSummaryInput` 在 `@Model` 所在上下文安全提取纯值，不跨 actor 泄露 `@Model` 实例，并保留 `healthKitUUID` 供 HealthKit 镜像去重。
  - `TrainingLoadSnapshot`: 归一化日训练负荷的 7 日 `acuteTrainingLoad` (`ATL`)、42 日 `chronicTrainingLoad` (`CTL`)、`trainingStressBalance` (`TSB = CTL - ATL`)、`acuteChronicWorkloadRatio` (`ACWR`)，以及 7d/14d 负荷变化率 (`atlDelta7d`, `ctlDelta7d`, `ctlDelta14d`, `tsbDelta7d`) 与 `recentTrajectory` (`[TrainingLoadDailyPoint]`)。
- **Aggregate & Four-Layer Report**:
  - `PhysiologicalSnapshot`: 聚合五大生理域并显式记录 `availableDomains: Set<InsightDomain>`，支持部分权限（如仅步数或缺失睡眠/HRV）优雅降级。
  - `L1SingleMetricInsight`, `L2CoupledInsight`, `L3ReadinessAndCycleInsight`, `L4HolisticNorthStarInsight`, `HolisticFourLayerReport`: 四层建议结构，保持向后兼容解码。

## 依赖

无外部依赖。
