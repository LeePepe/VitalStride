---
description: "Task list for HRV baseline + anomaly detection + morning notification"
---

# Tasks: HRV 基线 + 异常检测 + 晨间提醒

**Input**: `specs/005-hrv-baseline-anomaly/`（plan.md 必读、spec.md 用户故事）

**Prerequisites**: plan.md ✅、spec.md ✅

**Tests**: 本 feature 显式要求测试（基线数学 / 分级阈值 / <14 抑制 / 隐私 grep，SC-004/SC-005）。测试**先行**（RED → GREEN）。

**Organization**: 按 US1（P1，MVP）/ US2（P2）分组，各自可独立交付。

**Quality Bars**（引用 `.specify/memory/constitution.md`，不重述）：**Bar B 健康隐私 = P0**（HRV 数值不入 log/CloudKit/NSUserDefaults；push 文案无数值）、**Bar I 测试/Preview = P1**、**Bar G i18n = P1**、**Bar C strict concurrency = P0**。

## Format: `[ID] [P?] [Story] Description`

- **[P]**：可并行（不同文件、无依赖）
- **[Story]**：US1 / US2 / FOUND（foundational）/ SETUP / POLISH

---

## Phase 1: Setup（共享前置）

- [ ] T001 [SETUP] 确认 `Packages/HealthKitService/.../HealthSampleType.swift` 已含 `heartRateVariabilitySDNN` 且经既有 `HealthDataCache` 可读取历史样本（30 天窗口足量）；记录读取 API 形态供基线 service 复用。
- [ ] T002 [SETUP] 定位数据页 HRV chart 现有渲染位置（`VitalStride/Sources/DataSections/HealthSampleTypeInfo.swift:33` 及其对应 chart view），确认可挂 `RuleMark`/阴影 overlay 的注入点。
- [ ] T003 [P] [SETUP] 确认本地通知 infra `VitalStride/Sources/RestNotificationScheduler.swift`（`UNUserNotificationCenter`，已请求 `.alert`/`.sound`）可复用于晨间提醒，记录其调度 API。

---

## Phase 2: Foundational（阻塞前置 — 所有故事依赖）

**⚠️ CRITICAL**：本阶段完成前，任何 US 不得开工。

### 决策门禁（FR-008，最先执行）

- [ ] T004 [FOUND] **结构决策 task**：确定 `HRVBaseline`/`HRVAnomaly`/`HRVBaselineService` 放置位置。默认 = 既有 `HealthKitService` package + **零新 `@Model`**（基线即时派生）。**若**判定需新增 SwiftData `@Model` **或**新 SPM package（如 `RecoveryKit`）→ **先撰写并落地 ADR（`docs/adr/`）再继续，ADR 阻塞 T005-T007**（Principle III/IV，Bar E）。默认路径无需 ADR，直接进 T005。

### 基线 + 异常核心（纯函数 / 可测）

- [ ] T005 [P] [FOUND] 新增 `HRVBaseline` Sendable struct（`rollingMean` / `rollingStdDev` / `sampleCount` / `referenceDate`）于 `Packages/HealthKitService/Sources/HealthKitService/HRVBaseline.swift`。
- [ ] T006 [P] [FOUND] 新增 `HRVAnomaly` Sendable struct（`today` / `baseline` / `percentDeviation` / `severity` / `suggestionKey`）+ `Severity` 枚举（`.normal/.mildLow/.significantLow/.critical`）于 `Packages/HealthKitService/Sources/HealthKitService/HRVAnomaly.swift`。
- [ ] T007 [FOUND] 新增 `HRVBaselineService` actor 于 `Packages/HealthKitService/Sources/HealthKitService/HRVBaselineService.swift`：`computeBaseline()`（滚动 30 天均值±std + sampleCount，**`sampleCount < 14` 返回 nil/untrusted 态**，FR-001）；`detectAnomaly()`（按 `percentDeviation` 分级，阈值 -10/-20/-30%，FR-002）。依赖 T005/T006。**Bar B**：内部禁止 log HRV 数值。

**Checkpoint**：基线与分级可独立单测通过（`cd Packages/HealthKitService && swift test`）。

---

## Phase 3: User Story 1 - 个人化基线 + 数据页可视化（P1）🎯 MVP

**Goal**：≥14 天数据 → 数据页 HRV chart 显示基线横线 + 显著低区阴影 + 今日相对偏差。

**Independent Test**：有 ≥14 天 HRV 的用户打开数据页 → 见 `RuleMark` 基线 + 阴影 + 偏差标注；<14 天 → 无基线、无告警。

### Tests for US1（先写、先失败）⚠️

- [ ] T008 [P] [US1] `HRVBaselineTests.swift`（`Packages/HealthKitService/Tests/HealthKitServiceTests/`）：基线数学 round-trip（已知样本 → 期望 mean/std/sampleCount）。
- [ ] T009 [P] [US1] `HRVAnomalyTests.swift`（同目录）：分级阈值边界（-9%/.normal、-15%/.mildLow、-25%/.significantLow、-35%/.critical）。
- [ ] T010 [P] [US1] `<14` 抑制测试（SC-004）：`sampleCount = 13` → `computeBaseline` 返回 untrusted / `detectAnomaly` 不产异常。

### Implementation for US1

- [ ] T011 [US1] 数据页 HRV chart overlay：在 `VitalStride/Sources/DataSections/HealthSampleTypeInfo.swift:33` 对应 chart view 叠加基线 `RuleMark` + 显著低区阴影（`RectangleMark`/`AreaMark`）+ 今日相对偏差标注（FR-003）。依赖 T007。
- [ ] T012 [US1] `<14` 样本态处理（SC-004）：chart 不画基线、不显示告警，回退到既有孤立数值展示（graceful，Bar D）。
- [ ] T013 [P] [US1] 新增图表标注 zh + en 字符串到 `VitalStride/Resources/Localizable.xcstrings`（`String(localized:)`，FR-009 / Bar G）：基线/今日偏差/低区标签。

**Checkpoint**：US1 独立可用 —— MVP 可交付（数据页基线可视化，无需通知）。

---

## Phase 4: User Story 2 - HRV 异常晨间本地提醒（P2）

**Goal**：HRV 显著低于基线时早晨发本地提醒建议降强度；开关可关；`.mildLow` 仅 in-app banner。

**Independent Test**：模拟今日 HRV `.significantLow` → 晨检发本地通知（文案无数值）；关开关 → 不发；`.mildLow` → 仅 banner。

### Tests for US2（先写、先失败）⚠️

- [ ] T014 [P] [US2] severity gating 测试：`.significantLow`/`.critical` → 触发通知路径；`.mildLow` → 仅 banner、不发 push（FR-005 分级门控，spec AS-3）。
- [ ] T015 [P] [US2] 开关关闭抑制测试：settings toggle off → `MorningHealthCheckScheduler` 不发 push（SC-003）。

### Implementation for US2

- [ ] T016 [US2] 设置页新增 "HRV 异常提醒" 开关（**默认开**，可关）于 `VitalStride/Sources/SettingsView.swift`；持久化开关状态（**注意**：仅存布尔开关，**禁止**存任何 HRV 数值，Bar B / FR-007）。
- [ ] T017 [US2] 新增 `MorningHealthCheckScheduler`（`VitalStride/Sources/MorningHealthCheckScheduler.swift`）：晨间检测调 `HRVBaselineService.detectAnomaly()`，`.significantLow`/`.critical` 且开关开 → 经 `RestNotificationScheduler` infra 发**本地通知**（`UNUserNotificationCenter`，无 APNs，FR-004）。复用 T003 记录的调度 API。
- [ ] T018 [US2] push/banner 文案**仅定性**（"显著偏低/略偏低/建议休息"），**MUST NOT 含数值**（FR-005 / Bar B）；`.mildLow` → 仅 in-app banner（spec AS-3）。
- [ ] T019 [P] [US2] 通知 + banner + 设置项 zh + en 字符串入 `Localizable.xcstrings`（FR-009 / Bar G）。
- [ ] T020 [P] [US2] **[optional]** FR-010：异常触发时可选调 `Packages/AIService/.../AIProviderChain.swift` 生成个性化建议（结合训练量/睡眠/RHR），失败 fallback 模板文案；**必须复用 chain 不引第三方 SDK**（Principle V）。默认可跳过。

**Checkpoint**：US1 + US2 均独立可用。

---

## Phase 5: Polish & Cross-Cutting

- [ ] T021 [P] [POLISH] **隐私 grep 断言 task（SC-005 / Bar B = P0）**：grep 全 feature 改动源（`HRVBaselineService`/`MorningHealthCheckScheduler`/chart overlay），断言无任何 os_log/print 输出 HRV 数值、无 HRV 值写 NSUserDefaults/CloudKit；只允许 severity/时间范围等元数据。作为 CI 可复现检查记录。
- [ ] T022 [P] [POLISH] 数据页 HRV chart view ≥ 2 个 SwiftUI Preview（有基线态 + <14 无基线态；含低区异常态），Bar I。
- [ ] T023 [P] [POLISH] 复核 `Localizable.xcstrings` zh + en 完整（图表 + 通知 + 设置），无硬编码可见字符串（Bar G）。
- [ ] T024 [POLISH] `cd Packages/HealthKitService && swift build && swift test` 全绿；app target 改动经 xcodegen 生成后按 CLAUDE.md 后台 xcodebuild 验证。

---

## Dependencies & Execution Order

### Phase 依赖

- **Setup (P1 阶段)**：无依赖，立即开始。
- **Foundational (P2 阶段)**：依赖 Setup。**T004 决策门禁最先**；若触发 ADR，则 ADR 阻塞 T005-T007。**阻塞所有 US。**
- **US1 (P3)**：依赖 Foundational。MVP。
- **US2 (P4)**：依赖 Foundational；与 US1 正交，可并行；集成时复用 US1 的 `detectAnomaly`。
- **Polish (P5)**：依赖目标 US 完成。

### Story 内顺序

- 测试先行（RED）→ 实现（GREEN）。
- struct（T005/T006）→ service（T007）→ view/scheduler。

### Parallel Opportunities

- T005 / T006 并行（不同文件）。
- US1 测试 T008/T009/T010 并行；US2 测试 T014/T015 并行。
- xcstrings 任务 T013/T019 与实现并行。
- Foundational 完成后，US1 与 US2 可由不同人并行推进。

## Parallel Example: US1

```bash
# US1 测试并行（先失败）：
Task: "HRVBaselineTests 基线数学 round-trip"
Task: "HRVAnomalyTests 分级阈值边界"
Task: "<14 样本抑制测试 (SC-004)"
```

## Implementation Strategy

### MVP First（US1 Only）

1. Phase 1 Setup → 2. Phase 2 Foundational（**先过 T004 决策/ADR 门禁**）→ 3. Phase 3 US1 → **STOP & VALIDATE**：数据页基线可视化独立可用 → 交付 MVP。

### Incremental Delivery

Setup + Foundational → US1（MVP，数据页基线）→ US2（晨间本地提醒，可选 AI）→ Polish（隐私 grep + Preview + i18n 复核）。

## Notes

- **Bar B（P0）贯穿全程**：HRV 数值绝不进 log/CloudKit/NSUserDefaults/push 文案。T021 grep 是硬验收。
- FR-008 决策门禁（T004）：默认零新 `@Model`/零新 package → 无 ADR；一旦偏离默认，ADR 先行且阻塞。
- 改动仅涉及 `Packages/` 用 `swift test`；app target 改动才 xcodebuild（CLAUDE.md）。
- 每个 task 或逻辑组后提交；任意 checkpoint 可停下独立验证。
