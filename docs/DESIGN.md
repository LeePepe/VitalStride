# VitalStride 技术设计文档

## 项目定位

健康运动数据收集与 AI 分析 App。核心差异化：端侧 AI 训练分析。个人项目，非商用。

## 平台与版本

| 平台 | 最低版本 | 定位 |
|------|---------|------|
| iOS | 18.0+ | 全功能：训练记录、数据查看、AI 分析、文件导入 |
| macOS | 15.0+ | 查看 + 分析 + 文件导入（拖拽），不发起训练 |
| watchOS | 11.0+ | 力量训练实时录入（重量/次数）、实时数据展示 |

## 技术栈

| 层 | 选型 | 理由 |
|---|------|------|
| UI | SwiftUI | iOS 18+ 全功能，三端共享 |
| 数据存储 | SwiftData + CloudKit | 本地权威存储 + 三端同步 |
| 健康数据 | HealthKit | 读取 + 写入（仅 app 发起的训练） |
| 图表 | Swift Charts | Apple 原生，iOS 17+ 全功能（SectorMark、chartXSelection）|
| AI | Apple Intelligence (Foundation Models) | 端侧推理，零成本，离线可用 |
| 包管理 | Swift Package Manager | 标准选型 |
| 文件解析 | FIT SDK + GPX XML parser | 骑行数据导入 |

## 架构概览

```
┌─────────────────────────────────────────────────┐
│                   SwiftUI Views                  │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌────┐ ┌──────┐   │
│  │概览  │ │训练  │ │数据  │ │ AI │ │设置  │   │
│  └──┬───┘ └──┬───┘ └──┬───┘ └─┬──┘ └──┬───┘   │
├─────┼────────┼────────┼───────┼───────┼────────┤
│                 Service Layer                    │
│  ┌────────────┐ ┌──────────┐ ┌───────────────┐  │
│  │HealthKit   │ │Workout   │ │AI Analysis    │  │
│  │Service     │ │Service   │ │Service        │  │
│  └─────┬──────┘ └────┬─────┘ └───────┬───────┘  │
├────────┼─────────────┼───────────────┼──────────┤
│              Cache Layer (内存)                   │
│  ┌──────────────────┐                            │
│  │HealthDataCache   │  Swift actor, 按            │
│  │(in-memory only)  │  HealthSampleType 分桶      │
│  └────────┬─────────┘                            │
├───────────┼──────────────────────────────────────┤
│                 Data Layer                       │
│  ┌──────────┐  ┌───────────┐  ┌──────────────┐  │
│  │HealthKit │  │SwiftData  │  │CloudKit Sync │  │
│  │(Read+    │  │(Local     │  │(三端同步)     │  │
│  │ Write)   │  │ Store)    │  │              │  │
│  └──────────┘  └───────────┘  └──────────────┘  │
└─────────────────────────────────────────────────┘
```

**HealthDataCache** 位于 Service Layer 与 Data Layer 之间，是纯内存 actor 缓存。View 通过 HealthKitService 读取数据时优先命中缓存，cache miss 时由 Service 发起 bounded date-range fetch（冷启动）或 anchor query（增量刷新）拉取并回填缓存。缓存不参与 CloudKit 同步，不写入 SwiftData。

## 导航结构

### iOS (Tab Bar)

| Tab | 名称 | 内容 |
|-----|------|------|
| 1 | 概览 | 今日活动摘要、最近训练、周/月趋势图 |
| 2 | 训练 | 开始力量训练、训练历史（所有来源）、筛选搜索 |
| 3 | 数据 | 健康数据详情（心率、睡眠、体重等）、按类型分 section、时间范围图表 |
| 4 | AI | AI Insight 面板、训练分析报告、对话式问答 |
| 5 | 设置 | HealthKit 权限、单位偏好(kg/lb)、GPX/FIT 导入、数据导出 |

### macOS (Sidebar)

同 iOS tab 结构映射为 sidebar，去除"开始训练"入口。导入支持拖拽文件。

### watchOS

力量训练专用界面：动作列表 → 逐组录入（重量+次数）→ 组间休息倒计时。

## 数据源与存储策略

### HealthKit 交互规则

| 场景 | 读 HealthKit | 写 HealthKit | 存 SwiftData | 内存缓存 |
|------|:-----------:|:-----------:|:-----------:|:-----------:|
| 读取已有训练/健康数据 | ✅ | — | ❌ (直接查 HealthKit) | ✅ (HealthDataCache) |
| App 内发起力量训练 | — | ✅ (摘要) | ✅ (完整详细数据) | — |
| 导入 GPX/FIT 文件 | — | ❌ | ✅ (全部数据) | — |

### HealthKit 内存缓存层 (HealthDataCache)

纯内存 Swift actor 缓存，位于 Service Layer 与 HealthKit Data Layer 之间。

**数据流**：
```
View → HealthKitService → HealthDataCache (hit?) → [miss] → HealthKit Query → 回填 Cache → 返回 View
```

**冷启动 hydration 路径**：
app 启动后缓存为空，首次访问某 `HealthSampleType` 时按以下策略加载：
1. **Bounded date-range fetch**：按当前 View 可见时间范围（如"今日"、"本周"）使用 `nil` anchor 发起 `HKSampleQuery`，获取完整数据填充缓存
2. **Anchor 增量刷新**：首次加载完成后，记录新 anchor；后续 cache miss 或手动刷新时使用持久化 anchor 发起 `HKAnchoredObjectQuery` 拉取增量 delta
3. **Lazy loading**：仅加载当前可见时间范围的数据，用户切换时间范围（week → month）时按需拉取，避免全量历史加载

**设计要点**：
- 按 `HealthSampleType` 分桶，每桶持有 `[HealthDataPoint]`
- 整桶替换（immutable pattern），不做 in-place mutation
- 缓存生命周期 = app 进程，不跨启动持久化
- 不参与 CloudKit 同步，不写入磁盘

**隐私约束**：
- 缓存数据不离设备，不经网络传输
- 用户撤销 HealthKit 权限 → 立即执行完整清除：
  1. 清空全部内存缓存（`HealthDataCache.invalidateAll()`）
  2. 重置持久化 anchor state（`HealthKitAnchorStore.removeAllAnchors()`），清除 UserDefaults 中的 anchor tokens
  3. 清零已持久化的 telemetry 计数器（如 cache hit/miss 累计值）
- 日志禁止输出实际健康数值，仅可记录 sample type / 数量 / 时间范围

**Telemetry 需求**（由 MY-668 实现）：
- `healthkit_cache_hit` / `healthkit_cache_miss`（按 HealthSampleType）
- `healthkit_fetch_duration_ms`（单次 HealthKit 查询耗时）
- `healthkit_cache_refresh`（缓存刷新次数）
- 使用 OSSignpost / MetricKit，不依赖第三方 SDK

### HealthKit 同步策略（双层）

**Layer 1: Anchor Query（按需拉取）— 优先实现**
- 每次进入页面时，使用 HKAnchoredObjectQuery 拉取上次 anchor 之后的新增/修改样本
- anchor token 持久化到 UserDefaults（device-local，不参与 CloudKit 同步）
- 延迟极低（通常 <100ms），保证数据可用

**Layer 2: Observer Query + BGHealthQuery（后台增量）— 后续实现**
- 注册 HKObserverQuery 监听数据变更
- 配合 BGHealthMonitor 在后台拉取增量数据
- 保证 app 未打开时数据也保持最新

### CloudKit 同步

- SwiftData 启用 CloudKit 容器
- 三端（iOS/macOS/watchOS）自动同步
- GPS 轨迹数据做降采样压缩控制 CloudKit 容量
- 冲突策略：server wins（HealthKit 为权威源，本地数据可重新拉取）

## 文件导入

### 支持格式

| 格式 | 来源 | 包含数据 |
|------|------|---------|
| FIT | Garmin/Wahoo/码表 | GPS + 功率 + 踏频 + 心率 + 温度 + 速度 |
| GPX | 通用 GPS 轨迹 | GPS + 海拔 + 时间戳 |

### 导入所有训练类型

导入时解析文件中的 workout type，映射到 HKWorkoutActivityType。不限制类型 — 所有 HealthKit 支持的训练类型均可导入展示。

### 去重策略（⚠️ 暂不实现，记录设计）

导入的 FIT/GPX 数据可能与 HealthKit 已有训练重复（如 Apple Watch 也记录了同一次骑行）。

**设计方向（待数据验证后决定）：**
- 时间窗口匹配：同类型 workout ±5 分钟时间重叠视为重复
- 重复时：只保留 FIT/GPX 的额外数据（轨迹点、功率），不创建新 workout 记录
- 需要拿到真实数据后验证：HealthKit workout 的 startDate/endDate 与 FIT 文件的时间戳精度差异

## 力量训练系统

### 训练发起方式

| 方式 | 描述 |
|------|------|
| 空白训练 | 开始空训练，逐个添加动作 |
| 从历史复制 | 选择历史训练，预填上次重量/次数 |
| 从模板开始 | 选择预设模板，按计划执行 |

### 训练中交互流程

```
选择动作 → 录入一组（重量kg + 次数reps + 组类型）
  → 自动开始组间休息倒计时（默认90秒，可调）
  → 录入下一组（预填上次该动作数据）
  → ... 完成所有组
  → 换下一个动作
  → ... 完成所有动作
  → 结束训练 → 摘要写入 HealthKit + 详细数据存 SwiftData
```

### 组类型（V1）

| 类型 | 说明 |
|------|------|
| Working (正式组) | 正式训练组 |
| Warmup (热身组) | 热身组，不计入总训练量统计 |

### 动作库

- **预置动作**: ~100 个精选常用动作，JSON 文件内置
- **用户自定义**: 支持创建自定义动作
- **中英双语**: 跟随系统语言显示
- **分类维度**:
  - Muscle Group: 胸/背/肩/腿/臂/核心/全身
  - Equipment: 杠铃/哑铃/固定器械/自重/绳索
  - Primary/Secondary Muscles: 主要/次要目标肌肉

### 数据模型概览

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
              ├── setType: .working | .warmup
              └── restDuration: TimeInterval?

Exercise (动作库)
  ├── name: LocalizedString (中/英)
  ├── muscleGroup: MuscleGroup
  ├── equipment: Equipment
  ├── primaryMuscles: [Muscle]
  ├── secondaryMuscles: [Muscle]
  └── isCustom: Bool

WorkoutTemplate (训练模板)
  ├── name: String
  └── exercises: [TemplateExercise]
        ├── exercise: Exercise
        ├── targetSets: Int
        └── targetWeight: Double?
```

## AI 分析系统

### V1: Apple Intelligence（端侧）

- 框架：Foundation Models (iOS 18+)
- 运行位置：设备端，离线可用
- 功能范围：
  - 训练量趋势分析（"本周比上周多了20%"）
  - 恢复建议（"连续3天腿部训练，建议休息"）
  - 个人记录提醒（"卧推新 PR！"）
  - 训练模式识别（Core ML 模型）
  - 疲劳/表现预测

### V2: 云端 LLM（后续规划）

- 自然语言训练报告（"你的骑行 FTP 估算提升了 5%"）
- 训练计划建议
- 对话式问答（"我上个月骑行总距离多少？"）
- 可通过 raven proxy 接入，个人使用零成本

## 图表系统

### 选型：Apple Swift Charts（无第三方依赖）

利用 iOS 18+ 全部能力：

| 数据场景 | Chart Mark | 交互 |
|---------|-----------|------|
| 心率趋势 | LineMark + AreaMark 渐变 | chartXSelection 选中查看 |
| 骑行海拔 | AreaMark | 缩放/平移 |
| 训练时长/容量 | BarMark | 点击查看详情 |
| 周/月趋势 | LineMark + RuleMark 均值标注 | 时间范围切换 |
| 活动环 | 自定义 SwiftUI View (Circle + trim) | — |
| 肌肉群分布 | SectorMark (iOS 17+) | 点击展开 |

## 后续规划（V2+）

记录已讨论但 V1 暂不实现的功能：

| 功能 | 优先级 | 备注 |
|------|--------|------|
| 手动录入训练 | 低 | 不带设备时的补录 |
| 递减组 (Drop Set) | 中 | Set Type 扩展 |
| 力竭组 (Failure Set) | 中 | Set Type 扩展 |
| 超级组 (Superset) | 中 | 两个动作交替，需 UI 重构 |
| 有氧训练发起 | 低 | iOS 端发起跑步/骑行，依赖 GPS |
| 云端 LLM 分析 | 高 | 通过 raven proxy 接入 |
| 去重策略实现 | 中 | 需真实数据验证后设计 |
| 训练计划/周计划 (Routine) | 中 | 基于 Template 扩展为多日计划 |
| 社交/分享 | 低 | 训练成果分享 |
