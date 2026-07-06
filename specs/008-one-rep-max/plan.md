# Implementation Plan: 1RM 估算 + per-exercise 趋势曲线

**Branch**: `008-one-rep-max` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `specs/008-one-rep-max/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

把 estimated 1RM 引入训练详情：以 Epley 公式 `weight×(1+reps/30)` 作为 `ExerciseSet` 与 `WorkoutExercise` 上的**纯计算 helper**（无新数据模型、无存储改动）。P1 在 `WorkoutDetailView` 每个动作 section 展示本次最高 estimated 1RM，仅在存在候选组（working + reps 1-12 + weight>0）时显示。P2 迭代在动作详情按时间聚合历史训练、用 Swift Charts 渲染 per-exercise 1RM 趋势曲线。所有计算落在 VitalModels（`swift build/test` 可秒级验证），UI 字符串走 xcstrings 单源。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**: VitalModels（纯 extension，无本地依赖变更）+ SwiftUI + Swift Charts（复用 000 FR-009 图表基线）

**Storage**: 无新增。纯计算，读取现有 Workout / WorkoutExercise / ExerciseSet 历史，趋势查询走既有 SwiftData query。

**Testing**: XCTest。Epley 公式 + `isOneRepMaxCandidate` 过滤边界为纯函数，在 VitalModels 内 `swift test` 验证（无需模拟器）。

**Target Platform**: iOS 18+

**Project Type**: Mobile app（XcodeGen + 6 SPM local packages）

**Performance Goals**: P2 趋势历史聚合查询必须遵守 `fetchLimit` 约束（呼应 MY-1077），避免全表扫描。

**Constraints**: 1RM 计算须为纯函数、可单测（FR-005）；高次数（>15 reps）Epley 偏差大，UI 需标注估算性质。

**Scale/Scope**: 1 个新 extension 文件 + 1 个 WorkoutExercise computed 属性 + P1 详情展示 + P2 趋势视图；单动作历史通常十到百量级。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle III（SPM Package 优先）**: 1RM 计算 helper 全部落在 `Packages/VitalModels/`，app target 仅做 UI 展示。改动涉及 VitalModels 时必须 `swift build && swift test` 验证，禁止 xcodebuild。✅
- **Principle IV（XcodeGen SoT）**: 新增文件走既有目录源引用，无需改 `project.yml`（VitalModels 已注册）。✅
- **Principle VI（I18n xcstrings 单源）**: 所有新 UI 字符串（"Estimated 1RM"、趋势标题、估算 caveat）用 `String(localized:)` 引用 `Localizable.xcstrings`。✅
- **Quality Bar I（Test Coverage）**: `estimatedOneRepMax` / `isOneRepMaxCandidate` / `bestEstimatedOneRepMax` 为新 public API，必须有单测；新 SwiftUI view ≥ 2 个 Preview。✅
- **Quality Bar G（I18n）**: 无硬编码用户可见字符串。✅
- **无 ADR 需求**：纯 extension，不新增 package、不改架构。
- **无健康隐私（Bar B）关切**：仅涉及训练数据（weight/reps），非 HealthKit 数值。

## Project Structure

### Documentation (this feature)

```text
specs/008-one-rep-max/
├── spec.md              # 已存在（/speckit-specify 输出）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
Packages/VitalModels/Sources/VitalModels/
├── Models/
│   ├── ExerciseSet.swift            # 现有：weight / reps / setType(SetType.working)
│   └── WorkoutExercise.swift        # 现有：新增 bestEstimatedOneRepMax computed 属性
└── Extensions/
    └── ExerciseSet+OneRepMax.swift  # 新建：estimatedOneRepMax + isOneRepMaxCandidate

Packages/VitalModels/Tests/VitalModelsTests/
└── OneRepMaxTests.swift             # 新建：Epley 公式 + 候选边界单测

VitalStride/Sources/
├── WorkoutDetailView.swift          # P1：每个 exercise section 展示 estimated 1RM
└── OneRepMaxTrendView.swift         # 新建（P2）：Swift Charts per-exercise 趋势曲线

VitalStride/Resources/
└── Localizable.xcstrings            # 新增 1RM / 趋势 / caveat 字符串（i18n 单源）
```

**Structure Decision**: 沿用现有分层——计算逻辑住 `Packages/VitalModels/`（Principle III），平台 UI 住 app target。新建 `Extensions/` 子目录承载 `ExerciseSet+OneRepMax.swift`（VitalModels 现有 `Models/` `Enums/` `Persistence/` 结构下增补 `Extensions/`）。`WorkoutExercise.bestEstimatedOneRepMax` 作为 computed 属性直接加在现有 `WorkoutExercise.swift`。P1（详情展示）与 P2（趋势视图）分别落在 app target 的独立文件，互不阻塞。

## Complexity Tracking

> 无。纯 extension + 现有查询复用，无 Constitution 违背需要豁免。
