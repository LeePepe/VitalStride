# Implementation Plan: 训练 SetRow 上次重量提示 (Previous)

**Branch**: `004-previous-set-hint` | **Date**: 2026-07-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-previous-set-hint/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

训练进行中，`SetRow` 在有历史数据时展示灰字（tertiary caption）"上次 {重量}{单位} × {次数}"，让用户照练或微调渐进负荷，而不用切训练历史或凭记忆（US1/P1）。

技术路径：抽一个可测试的独立 helper `PreviousSetLookup`——用 `FetchDescriptor<Workout>`（`fetchLimit` 有界、按 `startDate` 倒序、`endDate != nil` 且排除当前 workout）找该 exercise 上一次已完成训练的同 index 组，返回 `ExerciseSet?`。`ActiveExerciseSection` 在 `ForEach` 内按 index 查一次并把 `previousSet` 注入 `SetRow`；`SetRow` 新增 `previousSet: ExerciseSet?` 输入，按当前 `WeightUnit` 偏好换算后渲染 caption，首次/越界优雅缺省。无新数据模型——只查现有 `Workout`/`WorkoutExercise`/`ExerciseSet`。本 feature 是 MY-1041（006 Smart Progression）的前置：先建"per-exercise 历史查询 + 展示"，Smart Progression 在其上加"建议层"复用 `PreviousSetLookup`。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency，Constitution Principle II）

**Primary Dependencies**: SwiftUI + SwiftData；`VitalModels` package（`Workout`/`WorkoutExercise`/`ExerciseSet`/`Exercise` 模型、`WeightUnit`）

**Storage**: SwiftData（现有 Training 默认 ModelConfiguration，CloudKit-synced）；本 feature 只读查询，**不新增 model / 不改 schema**

**Testing**: XCTest（app target `VitalStrideTests/`）；`PreviousSetLookup` 若能不依赖 app-only 符号则可 `swift test`，否则随 app target 走 `xcodebuild test`

**Target Platform**: iOS 18.0+ / macOS 15.0+（macOS companion 复用同视图，Principle VII）

**Project Type**: Mobile（iOS app target + 6 SPM packages）

**Performance Goals**: 历史查询须 `fetchLimit` / 按 exercise 过滤，避免无界遍历全部训练历史（FR-005，呼应 MY-1077 无上限 `@Query` 性能项）；查询在大量历史下无可感知卡顿（SC-002）

**Constraints**: 训练数据（非 HealthKit），无隐私零日志约束；查询有界；i18n 单源

**Scale/Scope**: per-exercise 单次历史查询；改动集中在 `ActiveWorkout/` 两个视图文件 + 1 个新 helper + xcstrings + 单测

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 / Quality Bar | 判定 | 说明 |
|--------------------|------|------|
| Principle I 健康数据隐私零妥协 | N/A | 只查训练数据（`Workout`/`ExerciseSet`），非 HealthKit 数值——不触发零日志 / CloudKit 隔离约束 |
| Principle II Swift 6 Strict Concurrency | PASS | helper 用值语义 / `@MainActor` 查询上下文，不引入 `@unchecked Sendable` 等绕过 |
| Principle III SPM Package 优先 | PASS（例外记录见 Structure Decision） | `PreviousSetLookup` 放 app target——它对 app-level `Workout` 历史做 `FetchDescriptor` 查询、与 `ActiveWorkout` 视图强耦合；`VitalModels` 模型为只读输入 |
| Principle VI I18n xcstrings 单源 | PASS | 新增 "上次 …" 字符串走 `String(localized:)` 引用 `Localizable.xcstrings`（FR-006） |
| Quality Bar G I18n | PASS | 无硬编码用户可见字符串 |
| Quality Bar I Test Coverage | PASS（有任务保障） | 新 public API `PreviousSetLookup` 需 round-trip 单测（找到/未找到/越界/单位换算，SC-003）；`SetRow` 需 ≥2 Preview |

无违规预期。

## Project Structure

### Documentation (this feature)

```text
specs/004-previous-set-hint/
├── spec.md              # 源真理（User Stories, FR-001..007, Reference Map）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
VitalStride/Sources/
├── ActiveWorkout/
│   ├── SetRow.swift                 # 新增 previousSet: ExerciseSet? 输入 + tertiary caption 渲染
│   │                                #   （历史 SetRow 已从 ActiveWorkoutView L694-954 抽出，MY-874）
│   └── ActiveExerciseSection.swift  # ForEach 内按 index 调 PreviousSetLookup，注入 previousSet
├── PreviousSetLookup.swift          # 新增：可测试的历史查询 helper（fetchLimit 有界）
└── ActiveWorkoutView.swift          # addSet 复制逻辑（正交，不改）

VitalStride/Resources/
└── Localizable.xcstrings            # 新增 "上次 {weight}{unit} × {reps}" 字符串（FR-006）

Packages/VitalModels/Sources/VitalModels/Models/   # 只读输入，不改
├── Workout.swift            # endDate / exercises / startDate
├── WorkoutExercise.swift    # exercise / sets
├── ExerciseSet.swift        # order / weight / reps / isUnilateral / weightRight
└── Exercise.swift           # 用于按 exercise 过滤历史

VitalStrideTests/Sources/
└── PreviousSetLookupTests.swift     # 新增单测（SC-003）
```

**Structure Decision**: 采用现有 Mobile 结构（app target + SPM packages）。`PreviousSetLookup` 落在 **app target**（`VitalStride/Sources/`）而非 package——理由：它用 `modelContext` + `FetchDescriptor<Workout>` 对 app-level 训练历史查询，且服务于 `ActiveWorkout/` 视图流；`VitalModels` 只提供只读模型。这不违反 Principle III"业务逻辑住 Packages"的精神：查询与视图 index 语义（同 index 组、当前 workout 排除）强绑定 UI 上下文，抽包会造成过度泛化。若 006 Smart Progression 需要跨更多入口复用，届时再评估上移到 package（新 ADR）。`SetRow` / `ActiveExerciseSection` 沿用 MY-874 抽出后的 `ActiveWorkout/` 子目录位置（spec Reference Map 的 `ActiveWorkoutView.swift L694-954` 为抽出前锚点）。

## Complexity Tracking

> No constitution violations — table empty.
