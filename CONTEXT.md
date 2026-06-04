# VitalStride

健康运动数据收集与分析 App，支持 iOS / macOS / watchOS。核心差异化：AI 驱动的训练分析。

## Language

### 数据源与存储

**HealthKit Source**:
通过 HealthKit API 读取的健康与运动数据（心率、步数、睡眠、已有训练记录等）。
_Avoid_: Apple Health 数据、系统数据

**Imported Workout**:
通过 GPX/FIT 文件导入的训练数据。不回写 HealthKit，仅存 SwiftData。
_Avoid_: 外部数据、第三方数据

**Recorded Workout**:
在 app 内发起并完成的训练。摘要回写 HealthKit，详细数据存 SwiftData。
_Avoid_: 手动训练、本地训练

**Local Store**:
SwiftData + CloudKit 同步的本地数据库，存储 HealthKit 无法表达的数据（GPS 轨迹点、功率、踏频、力量训练逐组记录等）。
_Avoid_: 缓存、本地缓存（它是权威数据源，不是缓存）

### 训练模型

**Workout**:
一次完整训练会话，包含类型、开始/结束时间、总时长、总卡路里。
_Avoid_: Session、Activity

**Exercise**:
一个训练动作（如"平板卧推"）。属于动作库，可预置或用户自建。
_Avoid_: Movement、Action

**Set**:
一组训练记录，属于某个 Exercise 在某次 Workout 中的执行。包含重量(kg) + 次数(reps)。
_Avoid_: Rep（rep 是次数，不是组）

**Set Type**:
组的分类。V1 支持：正式组(Working)、热身组(Warmup)。
_Avoid_: 不要用 "set category"

**Workout Template**:
预定义的训练计划，包含动作列表和目标组数/重量。用户可从模板快速开始训练。
_Avoid_: Plan、Routine（Routine 留给未来周计划功能）

### 动作库

**Exercise Library**:
预置 + 用户自定义动作的集合。预置动作以 JSON 文件形式内置 app。
_Avoid_: 动作数据库

**Muscle Group**:
动作的目标肌肉群分类：胸/背/肩/腿/臂/核心/全身。
_Avoid_: Body Part

**Equipment**:
动作使用的器械类型：杠铃/哑铃/固定器械/自重/绳索。
_Avoid_: Tool、Gear

### AI 分析

**Insight**:
AI 生成的训练分析结论或建议。V1 使用 Apple Intelligence 端侧模型。
_Avoid_: Report、Recommendation

## Relationships

- 一次 **Workout** 包含一个或多个 **Exercise** 的执行
- 每个 **Exercise** 在一次 **Workout** 中包含一个或多个 **Set**
- 每个 **Set** 有一个 **Set Type**（Working / Warmup）
- 一个 **Exercise** 属于一个 **Muscle Group**，使用一种 **Equipment**
- 一个 **Exercise** 有 primaryMuscles 和 secondaryMuscles
- 一个 **Workout Template** 包含有序的 **Exercise** 列表及目标组数/重量
- **Imported Workout** 只存 **Local Store**，不触及 HealthKit
- **Recorded Workout** 摘要写入 HealthKit，详细数据存 **Local Store**
- **HealthKit Source** 数据通过 HealthKit API 直接查询，不持久化到 Local Store
- **Local Store** 通过 CloudKit 在 iOS/macOS/watchOS 三端同步

## Example Dialogue

> **Dev:** "用户从 Garmin 导入了一个 FIT 文件的骑行，这算 Imported Workout 对吧？HealthKit 里会多一条记录吗？"
> **Domain expert:** "对，是 Imported Workout。不会回写 HealthKit。FIT 里的 GPS 轨迹和功率数据存 Local Store。"

> **Dev:** "如果用户在 app 里做了一次卧推训练，HealthKit 会记录什么？"
> **Domain expert:** "HealthKit 只存一条 Recorded Workout 摘要 — 力量训练、45分钟、200卡。逐组的重量和次数只在 Local Store。"

> **Dev:** "macOS 端能看到力量训练的逐组数据吗？"
> **Domain expert:** "能，通过 CloudKit 同步。macOS 端不能发起训练，但能查看所有详细数据。"

## Flagged Ambiguities

- "训练记录" 可能指 Workout（一次会话）或 Set（一组数据）— 上下文区分，或明确说 "训练会话" vs "组记录"
- "同步" 在项目中有两个含义：HealthKit→Local Store 的数据拉取，和 CloudKit 的三端同步 — 前者称 "HealthKit Sync"，后者称 "CloudKit Sync"
- "导入" 既可指 FIT/GPX 文件导入，也可指 HealthKit 数据读取 — 统一：文件操作称 "Import"，HealthKit 称 "Sync"
