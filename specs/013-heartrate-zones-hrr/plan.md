# Implementation Plan: 训练详情心率区间可视化 + HRR

**Branch**: `013-heartrate-zones-hrr` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `./spec.md`

**Constitution Version**: 2.0.0

---

## Summary

在训练详情中把心率区间分布从纯文本百分比升级为直观的**水平 stacked bar 可视化**（SwiftUI 原生 `Capsule`/`GeometryReader` 绘制，明确**不引入 Swift Charts** 等复杂依赖），并新增 **HRR（Heart Rate Recovery，训练后 1 分钟心率恢复）**：为 `WorkoutHeartRateStats` 增加 `heartRateRecovery1Min: Int?`，fetch 训练结束后 ~90s 时段心率、计算「训练末心率 − 结束后 ~60s 心率」，样本不足返回 `nil`。最后把区间条形 + HRR 组件扩展到 HealthKit 导入训练详情（当前完全无心率分析，P3）。

技术要点：纯读取 HealthKit 心率样本，**不新增任何持久化模型**（扩展现有 stats 值类型 + 复用 HealthKitService 查询模式），不涉及 CloudKit 同步变更。数据全程留设备内。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**:
- SwiftUI —— `Capsule` / `GeometryReader` 原生绘制水平条形（**NOT** Swift Charts；见 Assumptions & FR-001）
- `Packages/HealthKitService/` —— 训练结束后时段心率 fetch，复用现有 `HealthKitService.fetchData(for:dateRange:)` 查询模式

**Storage**: 读取 HealthKit 心率样本；**无新持久化模型**（既不新增 SwiftData 实体，也不写 CloudKit / NSUserDefaults）。`heartRateRecovery1Min` 仅为内存中 `WorkoutHeartRateStats` 的派生字段。

**Testing**: XCTest —— 覆盖 HRR 计算（正常样本 + 结束后样本不足 → `nil`）；隐私 grep 断言（无心率样本值进入日志）。

**Target Platform**: iOS 18+

**Project Type**: Mobile app（iOS，主 app target `VitalStride/`）

**Performance Goals**: 详情页展示流畅，条形绘制不阻塞主线程；HRR fetch 为一次性异步查询，不引入轮询。

**Constraints**: 心率样本值零日志（Constitution I / Bar B P0）；UI 字符串全部走 xcstrings（Constitution VI）。

**Scale/Scope**: 3 个现有视图/模型文件（`WorkoutHeartRateStats.swift`、`WorkoutDetailView.swift`、`HealthKitWorkoutDetailView.swift`）+ HealthKitService 查询复用 + xcstrings 增量；无新模块、无新 SPM 包。

## Constitution Check

*GATE: 必须在实现前通过，Phase 完成后复检。*

- **Principle I. 健康数据隐私零妥协 (NON-NEGOTIABLE) / Bar B（health privacy P0）—— 本 feature 最高优先级约束**：
  本 feature 直接处理 HealthKit 心率样本（含结束后时段 fetch）。心率样本值 **MUST NOT** 进入任何日志 / CloudKit / NSUserDefaults / 崩溃上报——仅允许记录元数据（样本数量、时间窗口、成功/失败）。对应 **FR-005 + SC-004**。
  **PASS（附显式说明）**：无新持久化模型 → 数据不落 CloudKit；HRR 计算与展示仅在内存进行。**并附一条 grep 验证任务**（Phase 2 / 测试），确保交付前可机器验证「无心率数值入日志」。
- **Principle VI. I18n：xcstrings 单源 + 无硬编码 (NON-NEGOTIABLE) / Bar G**：所有新增 UI 文案（HRR 标签、区间条形辅助文案）**MUST** 走 `String(localized:)` 引用 `VitalStride/Resources/Localizable.xcstrings`，zh + en 双语齐全。对应 **FR-006**。**PASS**。
- **Cross-Cutting Quality Bars — Bar I（tests）**：HRR 计算（正常 + 不足样本 nil 边界）必须有 XCTest 覆盖；隐私断言以 grep 风格测试兜底。**PASS**。
- **无新数据模型 → 无 ADR**：未改变 tech-context / 存储架构，不触发架构决策记录。

**结论**：无违规项，无需 Complexity Tracking。

## Project Structure

### Documentation (this feature)

```text
specs/013-heartrate-zones-hrr/
├── plan.md              # 本文件
├── spec.md              # 需求（US1/US2/US3、FR-001..006、SC-001..004）
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
VitalStride/
└── Sources/
    ├── WorkoutHeartRateStats.swift       # [改] 新增 heartRateRecovery1Min: Int? + HRR 计算/加载逻辑（US2）
    ├── WorkoutDetailView.swift           # [改] zoneDistribution 文本 → 水平 stacked bar（US1）+ HRR 展示（US2）
    └── HealthKitWorkoutDetailView.swift  # [改] 复用区间条形 + HRR 组件（US3，当前无心率分析）

Packages/HealthKitService/
└── Sources/HealthKitService/
    └── HealthKitService.swift            # [复用] fetchData(for:dateRange:) 心率查询模式，供结束后时段 HR fetch

VitalStride/Resources/
└── Localizable.xcstrings                 # [改] 新增 HRR / 区间条形文案（zh + en）
```

区间条形与 HRR 展示可抽为 `WorkoutDetailView.swift` 内的小型私有 SwiftUI 组件（或就近同目录轻量 view 文件），供 US3 复用；HRR 计算逻辑落在 `WorkoutHeartRateStats.swift` 内尽量纯函数化以便单测。

**Structure Decision**: 沿用主 app target `VitalStride/Sources/` 单目录布局，改动集中在三个已存在的锚点文件 + HealthKitService 查询复用 + xcstrings 增量。因涉及主 app target 源码（非 `Packages/` 独立包），app-target 验证走 `xcodebuild`（由执行者按 CLAUDE.md 规则后台运行）；HealthKitService 内的复用/新增若涉及包代码则以 `swift build/test` 验证。

## Complexity Tracking

*无违规项，本节留空。*
