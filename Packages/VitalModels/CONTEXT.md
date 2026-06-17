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

## 依赖

无外部依赖。
