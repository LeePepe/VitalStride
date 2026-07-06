# Implementation Plan: WorkoutTemplate 预估训练时长

**Branch**: `010-template-duration` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `specs/010-template-duration/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

给 `WorkoutTemplate` 增加纯函数 `estimatedDuration(historicalAverage:)`：有历史平均时长时优先用历史值（更准），否则按经验公式估算 `totalSets × 90s + 5min 过渡`。`StartWorkoutView` 的模板列表在"X 个动作"旁展示可读的"约 X 分钟"，帮用户按时间空档选模板。空模板（无动作/无组）退化为 0，展示"—"。

无 schema 变更、无隐私数据、无 ADR：核心是 VitalModels 里一个可单测的纯计算 extension + app target 的一行展示改动。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**: VitalModels（纯计算 extension，无新依赖）+ SwiftUI（模板列表展示）

**Storage**: 无新增存储。估算本身是纯计算；历史平均为可选增强，若做则走现有 `Workout` 查询并以 `fetchLimit` 约束（FR-003），不落新表、不改 model

**Testing**: XCTest（`swift test`）——`estimatedDuration` 纯函数单测，含空模板边界（SC-003）与历史优先 vs 经验估算两条路径（SC-002）

**Target Platform**: iOS 18+

**Project Type**: Mobile（iOS app + 本地 SPM packages）

**Performance Goals**: N/A（列表渲染期的 O(动作数) 纯计算）

**Constraints**: 估算须为纯函数、无副作用、可离线（FR-004）

**Scale/Scope**: 单个 extension 文件 + 一处模板列表展示 + xcstrings 一条字符串

## Constitution Check

*GATE：Phase 0 前必过；Phase 1 设计后复查。*

- **Principle III / IV（SPM Package 优先）**：估算逻辑落在 `Packages/VitalModels/` 的 `WorkoutTemplate+Duration.swift`，app target 只做展示。✅ 对齐
- **Principle VI（I18n xcstrings 单源）**：新增"约 X 分钟"用户可见字符串必须 `String(localized:)` 引用 `Localizable.xcstrings`，禁止硬编码（FR-005）。✅ 计划遵守
- **Quality Bar I（Test Coverage）**：新 public API（`estimatedDuration`）必须有单测，含空模板边界；模板行展示补 Preview。✅ 计划覆盖
- **隐私（Principle I / Bar B）**：不涉及 HealthKit 数值，无隐私面。✅ N/A
- **ADR**：无架构决策，纯函数 + 展示，不需要 ADR。

初步与再评估结论一致：无 Constitution 违规，无需 Complexity Tracking。

## Project Structure

### Documentation (this feature)

```text
specs/010-template-duration/
├── spec.md              # Feature 规格（已存在）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
Packages/VitalModels/
├── Sources/VitalModels/
│   ├── Models/
│   │   ├── WorkoutTemplate.swift          # 现有 model（name + exercises: [TemplateExercise]?）
│   │   └── TemplateExercise.swift         # 现有（targetSets 提供 totalSets 求和源）
│   └── WorkoutTemplate+Duration.swift     # 新建：estimatedDuration(historicalAverage:) 纯函数
└── Tests/VitalModelsTests/
    └── WorkoutTemplateDurationTests.swift # 新建：纯函数单测（空模板 + 历史 vs 经验）

VitalStride/
├── Sources/
│   └── StartWorkoutView.swift             # 模板列表 TemplateRow 增加"约 X 分钟"展示
└── Resources/
    └── Localizable.xcstrings              # 新增"约 X 分钟"字符串（Constitution VI 单源）
```

**Structure Decision**: 遵循 Constitution Principle III——业务计算（`estimatedDuration`）住 `Packages/VitalModels/`，与现有 `WorkoutTemplate`/`TemplateExercise` model 同包；平台 UI 展示留在 app target `StartWorkoutView.swift`。历史平均查询（若实现）由 app target 侧组装并把结果作为参数注入纯函数，保持 VitalModels 无 UI/无 SwiftData 查询耦合、可独立 `swift test`。

## Complexity Tracking

无 Constitution 违规，本节留空。
