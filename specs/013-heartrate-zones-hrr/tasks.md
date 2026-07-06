---
description: "Task list template for feature implementation"
---

# Tasks: 训练详情心率区间可视化 + HRR

**Input**: Design documents from `/specs/013-heartrate-zones-hrr/`

**Prerequisites**: [plan.md](./plan.md)（必需）、[spec.md](./spec.md)（user stories）

**Tests**: 本 feature **显式要求测试**（HRR 计算 + 隐私 grep 断言，见 spec SC-004 / Bar I）。

**Organization**: 任务按 user story 分组，每个 story 可独立实现与验证。US1（P1）为 MVP。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无依赖）
- **[Story]**: 所属 user story（US1 / US2 / US3）
- 每条含精确文件路径

## Quality Bars（贯穿全程）

- **Bar B（health privacy P0，NON-NEGOTIABLE）**：心率样本值零日志 / 零 CloudKit / 零 NSUserDefaults（FR-005、SC-004）。
- **Bar I（tests）**：HRR 计算 + 隐私断言有 XCTest 覆盖。
- **Bar G（i18n）**：新增 UI 文案走 xcstrings（FR-006）。

---

## Phase 1: Setup（共享基础）

**Purpose**: 确认现状锚点，不写新代码。

- [ ] T001 [P] 确认 `WorkoutHeartRateStats` 当前形态（`averageHeartRate` / `maxHeartRate` / `zoneDistribution: [HeartRateZone]?` / `from(dataPoints:)` / `load(startDate:endDate:fetchHeartRate:)`），确定 HRR 字段与计算的落点 in `VitalStride/Sources/WorkoutHeartRateStats.swift`。
- [ ] T002 [P] 确认 HealthKitService 心率 fetch 模式（`fetchData(for:dateRange:)` + `HealthSampleType` 心率类型 + `DateInterval` 谓词），确认「训练结束后时段」HR 查询可复用现有模式 in `Packages/HealthKitService/Sources/HealthKitService/HealthKitService.swift`。
- [ ] T003 [P] 确认 `WorkoutDetailView` 现有区间分布展示位置（zoneDistribution 文本百分比）与 `HealthKitWorkoutDetailView` 当前无心率分析的现状 in `VitalStride/Sources/WorkoutDetailView.swift`、`VitalStride/Sources/HealthKitWorkoutDetailView.swift`。

---

## Phase 2: Foundational（阻塞性前置）

**Purpose**: HRR 计算内核 + 隐私护栏，US2/US3 依赖之。US1（纯 UI）不依赖本阶段，可并行起步。

**⚠️ CRITICAL**: HRR 相关 story（US2/US3）须待本阶段完成。

- [ ] T004 [US2] 实现 HRR 计算辅助逻辑：fetch 训练结束后 ~90s 时段心率，计算「训练末心率 − 结束后 ~60s 心率」得 `Int`，结束后样本不足 → 返回 `nil`（FR-002）。计算部分尽量抽为纯函数（输入已 fetch 的心率序列 → HRR），fetch 编排与计算分离，便于单测 in `VitalStride/Sources/WorkoutHeartRateStats.swift`。
- [ ] T005 [US2] 结束后时段心率 fetch 编排：复用 HealthKitService `fetchData(for:dateRange:)` 查询模式，构造「结束后 ~90s」`DateInterval` 注入既有 `load(...)` 风格闭包 in `VitalStride/Sources/WorkoutHeartRateStats.swift`（复用 `Packages/HealthKitService/`）。
- [ ] T006 [US2] 隐私护栏（Bar B / FR-005）：确保 HRR fetch/计算/编排路径**不 log 任何心率样本值**，仅允许元数据（样本数、时间窗、成功/失败）in `VitalStride/Sources/WorkoutHeartRateStats.swift`。

**Checkpoint**: HRR 计算内核就绪，UI story 可接入。

---

## Phase 3: User Story 1 - 训练详情心率区间可视化升级 (Priority: P1) 🎯 MVP

**Goal**: 本地训练详情把 zoneDistribution 从纯文本升级为水平 stacked bar / 条形。

**Independent Test**: 打开有心率数据的训练详情 → 区间分布显示为水平 stacked bar（非纯文本百分比）（SC-001）。

### Implementation for User Story 1

- [ ] T007 [US1] 将 `WorkoutDetailView` 心率区间分布从纯文本百分比升级为水平 stacked bar / 条形列表，用 SwiftUI 原生 `Capsule` / `GeometryReader` 绘制（**不引 Swift Charts**），按 `HeartRateZone.percentage` 分段、区间名/颜色区分（FR-001、SC-001）in `VitalStride/Sources/WorkoutDetailView.swift`。
- [ ] T008 [US1] 短时训练无区间数据（`zoneDistribution == nil`）时不显示条形（edge case）in `VitalStride/Sources/WorkoutDetailView.swift`。

**Checkpoint**: US1 独立可用 —— MVP 可交付。

---

## Phase 4: User Story 2 - HRR (训练后 1 分钟心率恢复) (Priority: P2)

**Goal**: 详情页展示训练后 1 分钟心率恢复值。

**Independent Test**: 结束后有心率样本 → 显示「1 分钟心率恢复：{n} bpm」；样本不足 → 不显示、不报错（SC-002）。

### Implementation for User Story 2

- [ ] T009 [US2] 为 `WorkoutHeartRateStats` 新增 `heartRateRecovery1Min: Int?` 字段，接入 Phase 2 计算结果（FR-002）in `VitalStride/Sources/WorkoutHeartRateStats.swift`。
- [ ] T010 [US2] `WorkoutDetailView` 在 HRR 有值时展示「1 分钟心率恢复：{n} bpm」，`nil` 时隐藏该项（不报错）（FR-003、SC-002、edge case）in `VitalStride/Sources/WorkoutDetailView.swift`。

**Checkpoint**: US1 与 US2 均独立可用。

---

## Phase 5: User Story 3 - HealthKit 导入训练也显示心率分析 (Priority: P3)

**Goal**: HealthKit 导入/列表打开的训练详情也具备区间条形 + HRR。

**Independent Test**: 打开 HealthKit 导入训练详情 → 出现心率区间条形 + HRR（当前完全无）（SC-003）。

### Implementation for User Story 3

- [ ] T011 [US3] `HealthKitWorkoutDetailView` 复用 US1 的区间条形组件 + US2 的 HRR 展示组件，接入其心率数据源（FR-004、SC-003）in `VitalStride/Sources/HealthKitWorkoutDetailView.swift`。

**Checkpoint**: 三个 story 均独立可用。

---

## Phase 6: Tests（Bar I）

**Purpose**: 覆盖 HRR 计算与隐私护栏。

- [ ] T012 [P] [US2] HRR 计算单测：正常样本 → 正确 HRR 值；结束后样本不足/稀疏 → `nil`（FR-002、SC-002 边界）in `VitalStrideTests/`（新增测试文件，目录源引用自动包含）。
- [ ] T013 [P] 隐私 grep 风格断言（Bar B / SC-004）：验证 HRR fetch/计算/展示路径无心率样本值进入日志（对相关源文件 grep `os_log`/`print`/`logger` 且不含心率数值变量）in `VitalStrideTests/`。

---

## Phase 7: Polish & Cross-Cutting

- [ ] T014 [P] SwiftUI Preview：为区间条形 + HRR 提供 ≥2 个 preview（有区间/无区间；有 HRR/HRR nil）in `VitalStride/Sources/WorkoutDetailView.swift`。
- [ ] T015 [P] i18n（Bar G / FR-006）：新增 HRR 标签、区间条形辅助文案的 zh + en 字符串 in `VitalStride/Resources/Localizable.xcstrings`，全部走 `String(localized:)`。
- [ ] T016 若 HealthKitService 内有任何复用相关的包代码改动，验证 `cd Packages/HealthKitService && swift build && swift test`（仅当触及包代码时）。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，可立即开始。
- **Foundational (Phase 2)**: 依赖 Setup；**阻塞 US2 / US3**（HRR 内核）。US1 为纯 UI，不依赖 Phase 2。
- **US1 (Phase 3)**: 依赖 Setup —— 与 Phase 2 可并行。
- **US2 (Phase 4)**: 依赖 Phase 2。
- **US3 (Phase 5)**: 依赖 US1 + US2 组件（复用）。
- **Tests (Phase 6)**: 依赖对应 story 实现。
- **Polish (Phase 7)**: 依赖所需 story 完成。

### User Story Dependencies

- **US1 (P1)**: Foundational 无关，最快可交付（MVP）。
- **US2 (P2)**: 依赖 Phase 2 HRR 内核；独立可测。
- **US3 (P3)**: 复用 US1/US2 组件；独立可测。

### Parallel Opportunities

- Phase 1 全部 `[P]` 任务并行。
- US1（Phase 3）与 Phase 2（HRR 内核）可由不同人并行推进。
- T012 / T013（测试）与 T014 / T015（preview/i18n）互不冲突，可并行。

---

## Implementation Strategy

### MVP First（US1 Only）

1. Phase 1 Setup。
2. Phase 3 US1（区间条形可视化）。
3. **STOP & VALIDATE**：独立验证 US1（SC-001）。
4. 可交付 / demo。

### Incremental Delivery

1. Setup → US1（MVP，区间条形）→ 验证 → 交付。
2. + Phase 2 Foundational + US2（HRR）→ 验证 → 交付。
3. + US3（HealthKit 导入详情复用）→ 验证 → 交付。
4. 每步不破坏前序 story。

---

## Notes

- `[P]` = 不同文件、无依赖。
- `[Story]` 标签用于可追溯性。
- **Bar B（P0）**：任何阶段禁止心率样本值入日志；交付前跑 T013 grep 断言兜底。
- 主 app target 改动由执行者按 CLAUDE.md 用后台 `xcodebuild` 验证；本文件不代跑 git / xcodebuild。
- 每个 story 独立完成、独立可测；避免跨 story 破坏独立性。
