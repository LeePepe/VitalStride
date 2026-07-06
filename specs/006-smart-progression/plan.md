# Implementation Plan: 智能渐进负荷建议 (Smart Progression)

**Branch**: `006-smart-progression` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `specs/006-smart-progression/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

把 `specs/004-previous-set-hint`（MY-864）的"历史展示"升级为"主动建议"：在 SetRow 上，
根据上次该动作的完成情况，通过一个纯函数引擎 `SmartProgressionAdvisor` 算出下次该用的重量/次数
（如上次全达标 → 建议加重），以 tap-to-fill chip 呈现，点击一键填入输入框。

技术取向：advisor 是**纯函数**，输入 004 已实现的 `PreviousSetResult` + 用户目标次数区间，输出
`ProgressionAdvice` 枚举——不做任何数据查询（查询完全复用 004 的 `PreviousSetLookup`），因此可全分支单测。
UI 只负责渲染 chip、tap-to-fill、把手动编辑判定为"覆盖建议"，并按 FR-006 记录仅含元数据的接受率 telemetry。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency，Constitution II）

**Primary Dependencies**: SwiftUI（SetRow chip）+ VitalModels（`ExerciseSet` / `MuscleGroup` 读取）
+ TelemetryKit（FR-006 接受率，仅元数据）

**Storage**: 无新增存储——历史读取完全经 004 的 `PreviousSetLookup`，本 feature 不落库、不新增 model

**Testing**: XCTest。`SmartProgressionAdvisor` 是纯函数 → 全规则分支单测（all-hit / drop-off /
all-below / mid / 越界 / 无历史），符合 Quality Bar I

**Target Platform**: iOS 18+（macOS/watchOS 复用，Constitution VII，不新增专属流程）

**Project Type**: Mobile app（XcodeGen 单 workspace + 6 SPM packages）

**Dependency（关键约束）**: **`specs/004-previous-set-hint` 必须先落地**——本 feature 在其
`PreviousSetLookup` / `PreviousSetResult` 之上加建议层，**串行实现（先 004 后 006）**。004 未交付前
006 的 Foundational / US1 任务全部 blocked。

**Performance / Scale**: 建议计算是内存纯函数，成本可忽略；查询性能约束继承 004（fetchLimit / 索引）。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle VI（I18n xcstrings 单源）**: ✅ PASS — 所有新增建议文案（chip 文字、理由）走
  `String(localized:)` 引用 `Localizable.xcstrings`（FR-007），无硬编码。
- **Principle I（健康数据隐私零妥协）**: ✅ PASS — 本 feature 只读训练数据（`ExerciseSet` 的
  weight/reps/setType），不触碰 HealthKit 数值；FR-006 telemetry **只记元数据**
  （`suggestionAccepted` / `suggestionOverridden` 事件 + advice 分类），**禁止**把重量/次数值写进 telemetry
  或日志——对应 **Quality Bar B**（健康隐私 P0，任何数值进 log/CloudKit/NSUserDefaults = 🔴 FAIL）。
- **Quality Bar I（Test Coverage）**: ✅ 计划满足 — 新 public API（`SmartProgressionAdvisor.suggest` +
  `ProgressionAdvice`）有 round-trip / 全分支单测；新 SwiftUI chip 至少 2 个 Preview。
- **Quality Bar G（I18n）**: 新增用户可见字符串一律 catalog 化，避免硬编码 finding。
- **Principle II（Strict Concurrency）**: advisor 为 `Sendable` 纯值语义，不引入
  `@unchecked` / `nonisolated(unsafe)`。

初查无违规。

## Project Structure

### Documentation (this feature)

```text
specs/006-smart-progression/
├── plan.md              # 本文件
├── spec.md              # 需求真理之源
└── tasks.md             # /speckit-tasks 输出（US1 P1）
```

### Source Code (repository root)

```text
VitalStride/Sources/ActiveWorkout/
├── SetRow.swift                     # 现有 SetRow（spec 锚点 ActiveWorkoutView.swift:738-960
│                                    #   已重构落地于此文件）——加建议 chip + tap-to-fill + 覆盖判定
└── SmartProgressionAdvisor.swift    # 新增：纯引擎 + ProgressionAdvice 枚举（见 Structure Decision）

Packages/VitalModels/Sources/VitalModels/
├── Models/ExerciseSet.swift         # 读取 weight/reps/setType（不改）
└── Enums/MuscleGroup.swift          # 读取 muscleGroup 决定增量档位（小 +2.5kg / 大 +5kg，不改）

Packages/TelemetryKit/Sources/TelemetryKit/
└── TelemetryEvent.swift             # FR-006 接受率事件（仅元数据）

VitalStride/Resources/Localizable.xcstrings   # FR-007 新增建议文案

# 依赖（不在本 feature 交付，必须先存在）
VitalStride/Sources/…                # 004 的 PreviousSetLookup / PreviousSetResult
```

**Structure Decision**：`SmartProgressionAdvisor` 逻辑本身是纯函数，理论上可住进 `Packages/VitalModels`
（无平台耦合、便于 `swift test` 秒级验证）。但它的**输入类型 `PreviousSetResult` 由 004 定义、且 004 将其
放在 app target**（004 spec Key Entities：`PreviousSetLookup` 为查询 helper，`SetRow` 新增
`previousSet` 输入，均随 SetRow 在 app target）。为与 004 的放置决策保持一致、避免把 004 的 app-target 类型
反向拉进 package 造成耦合倒置，**advisor 与 004 保持同层——落在 app target
`VitalStride/Sources/ActiveWorkout/SmartProgressionAdvisor.swift`**，与它消费的 `PreviousSetResult` 同侧。
若后续 004 把 `PreviousSetResult` 下沉到 VitalModels，则 advisor 可一并下沉（届时 advisor 纯函数天然适配
`swift test`）——此耦合已在 Complexity Tracking 记录。SetRow 的 chip / tap-to-fill 修改就地在
`ActiveWorkout/SetRow.swift`，不新建 View 文件层级。

## Complexity Tracking

> 无 Constitution 违规。仅记录一处放置耦合供后续审视。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| advisor 放 app target 而非 VitalModels package | 输入 `PreviousSetResult` 是 004 的 app-target 类型；跟随 004 放置决策，避免把 app-target 类型拉进 package 造成依赖倒置 | 直接放 VitalModels 会强制 004 先把 `PreviousSetResult` 下沉；本期串行交付不引入该跨-feature 重构，保持与 004 同层最简。004 若后续下沉该类型，advisor 一并下沉 |
