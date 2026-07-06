# Implementation Plan: HRV 基线 + 异常检测 + 晨间提醒

**Branch**: `005-hrv-baseline-anomaly` | **Date**: 2026-07-04 | **Spec**: [`./spec.md`](./spec.md)

**Input**: Feature specification from `specs/005-hrv-baseline-anomaly/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

在既有数据页 HRV chart 上叠加"个人化基线 + 异常检测"层：

1. **基线计算**（US1 P1）：滚动 30 天 HRV（`heartRateVariabilitySDNN`）均值 ± 标准差 + `sampleCount`；`sampleCount < 14` 判为不可信、不产出基线也不触发任何 alert（避免新用户误报，SC-004）。
2. **异常分级**（US1 P1）：按今日 HRV 相对基线的 `percentDeviation` 分级 `.normal / .mildLow / .significantLow / .critical`（阈值 -10 / -20 / -30%）。纯函数、可测。
3. **数据页可视化**（US1 P1）：Swift Charts `RuleMark` 画基线横线 + 显著低区阴影 + 今日相对偏差标注。
4. **晨间本地提醒**（US2 P2，可选增强）：`MorningHealthCheckScheduler` 在 `.significantLow` / `.critical` 时发**本地通知**（`UNUserNotificationCenter`，复用 `RestNotificationScheduler` infra），文案定性、绝不含数值；`.mildLow` 仅 in-app banner；设置页开关默认开。

技术取向：优先纯 Sendable structs + actor，落在既有 `HealthKitService` package；**不新增持久化 `@Model`**（基线从既有 cache 即时算得）。若确需新增 `@Model` 或新 SPM package，走 ADR（见 Complexity Tracking）。

## Technical Context

**Language/Version**: Swift 6.0，strict concurrency（Principle II）

**Primary Dependencies**: SwiftUI + Swift Charts（`RuleMark` / `RectangleMark` 阴影）+ `UNUserNotificationCenter`（本地通知）+ `HealthKitService`（HRV 读取，经既有 L1/L2 缓存）；可选 `AIService`（`AIProviderChain`，FR-010）

**Storage**: 读取 HealthKit `heartRateVariabilitySDNN`，走既有 `HealthDataCache` / `HealthCacheEntry` 缓存链路；**不新增持久化模型**（基线为即时派生量）。若引入新 `@Model` → 需 ADR（FR-008）

**Testing**: XCTest（`swift test`，`HealthKitService` package 内可无模拟器秒级验证基线数学与分级阈值）

**Target Platform**: iOS 18+

**Project Type**: Mobile app（iOS 主 target + SPM packages）

**Performance Goals**: N/A（每用户少量 HRV 样本，30 天滚动窗口，非热路径）

**Constraints**: 隐私 P0 — HRV 数值不入日志 / CloudKit / NSUserDefaults；晨间通知仅本地（无 APNs）；push 文案不含数值

**Scale/Scope**: per-user HRV 样本（数十~数百点级），单用户本地计算

## Constitution Check

*GATE：Phase 0 前必须通过；Phase 1 设计后复检。按编号引用 `.specify/memory/constitution.md`，不重述。*

| 约束 | 判定 | 说明 |
|------|------|------|
| **Principle I / Quality Bar B（P0 健康隐私）** | ✅ PASS（显式注记） | HRV 数值 **MUST NOT** 进 log（os_log/print）、CloudKit、NSUserDefaults（FR-007）。晨间提醒为**本地通知**（`UNUserNotificationCenter`，无 APNs），数据不离设备 — 与 Principle I"数值不离设备"一致。push/banner 文案 **MUST NOT** 含具体 HRV 数值（FR-005），仅定性描述。基线为即时派生量，不落任何可同步存储。 |
| **Principle II / Bar C（P0 strict concurrency）** | ✅ PASS | `HRVBaseline` / `HRVAnomaly` 为 Sendable struct；`HRVBaselineService` 为 actor。不引入 `@unchecked Sendable` / `nonisolated(unsafe)`。 |
| **Principle III / IV（SPM 优先 / XcodeGen SoT）** | ⚠️ DECISION GATE | FR-008：**若**新增 SwiftData `@Model` **或**新 SPM package（如 `RecoveryKit`）→ **必须先写 ADR**。默认方案（复用 `HealthKitService`、零新 `@Model`）无需 ADR。见 Complexity Tracking 与 Foundational 决策 task。 |
| **Principle V（AI 本地优先 + fallback）** | ✅ PASS（可选） | FR-010 可选 AI 建议 **必须**复用 `AIProviderChain`，不引第三方 SDK；失败 fallback 模板文案。 |
| **Principle VI / Bar G（i18n 单源）** | ✅ PASS | 新增 UI/通知字符串走 `String(localized:)` 引用 `Localizable.xcstrings`（FR-009），提供 zh + en。 |
| **Bar D（P0 错误处理）** | ✅ PASS | 无 `fatalError`/`try!`/`as!`；HRV 缺失 / 样本不足 graceful degradation（无基线态）。 |
| **Bar I（P1 测试 / Preview）** | ✅ PASS | 新 public API（基线/分级）round-trip 测试；新 SwiftUI view ≥ 2 Preview。 |

**Gate 结论**：默认结构（`HealthKitService` + 零新 `@Model`）下全部 PASS。唯一未决项是 FR-008 的结构决策 —— 一旦选择新增 `@Model`/新 package，则 ADR 成为 Phase 2 的阻塞前置。

## Project Structure

### Documentation (this feature)

```text
specs/005-hrv-baseline-anomaly/
├── plan.md              # 本文件
├── spec.md              # source of truth
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

真实锚点（引自 spec Reference Map）：

```text
Packages/HealthKitService/Sources/HealthKitService/
├── HealthSampleType.swift              # heartRateVariabilitySDNN 采集类型（既有）
├── HRVBaseline.swift                   # 新增：Sendable struct（rollingMean/rollingStdDev/sampleCount/referenceDate）
├── HRVAnomaly.swift                    # 新增：Sendable struct（today/baseline/percentDeviation/severity/suggestionKey）
└── HRVBaselineService.swift            # 新增：actor — computeBaseline() / detectAnomaly()

Packages/HealthKitService/Tests/HealthKitServiceTests/
├── HRVBaselineTests.swift              # 新增：基线数学 + <14 抑制
└── HRVAnomalyTests.swift               # 新增：分级阈值 -10/-20/-30%

VitalStride/Sources/
├── DataSections/HealthSampleTypeInfo.swift   # :33 heartRateVariabilitySDNN — 数据页 HRV chart 锚点（叠加 RuleMark/阴影）
├── RestNotificationScheduler.swift           # 既有本地通知 infra（UNUserNotificationCenter，复用）
├── MorningHealthCheckScheduler.swift         # 新增：晨间检测 + 本地通知触发（US2）
└── SettingsView.swift                        # "HRV 异常提醒" 开关（默认开）

VitalStride/Resources/
└── Localizable.xcstrings                      # 新增 zh + en 字符串（图表标注 + 通知文案 + 设置项）

Packages/AIService/Sources/AIService/
└── AIProviderChain.swift               # 可选（FR-010）：个性化建议，复用 chain
```

**Structure Decision**：默认将 `HRVBaseline` / `HRVAnomaly`（Sendable struct）+ `HRVBaselineService`（actor）放入既有 **`HealthKitService`** package —— 它已持有 HRV 采集类型与缓存链路，基线是其上的即时派生逻辑，`swift test` 可无模拟器秒级验证（符合 CLAUDE.md 的"改动仅涉及 Packages/ 用 swift test"）。数据页可视化与晨间调度因 platform-specific 留在 app target（`VitalStride/Sources/`），复用 `RestNotificationScheduler`。

**ADR 依赖（FR-008）**：以上默认结构**不新增** `@Model`、**不新增** package，故无需 ADR。若 Foundational 决策 task（见 tasks.md）判定需要持久化基线或独立 `RecoveryKit` package，则 **ADR 先行、阻塞后续实现** —— 此为 Principle III/IV 的硬门禁。

## Complexity Tracking

> 仅当结构决策触发新增 `@Model` / 新 package 时填写并强制走 ADR。

| Violation | Why Needed | Simpler Alternative Rejected Because | 门禁 |
|-----------|------------|--------------------------------------|------|
| 新增 SwiftData `@Model`（持久化基线快照） | 若要跨启动缓存基线避免重算，或记录历史异常 | 默认方案即时从既有 HRV 缓存算得，样本量小、无性能压力 → 默认**不需要** | **需 ADR**（Principle IV / FR-008），未批不得实现 |
| 新增 SPM package `RecoveryKit` | 若未来扩成 Recovery Score（HRV+RHR+sleep+strain）复合域 | 本 feature 范围窄，`HealthKitService` 已足够承载；过早分包增加耦合面 | **需 ADR**（Principle III / FR-008），本 feature 默认拒绝，留待复合域再评 |
