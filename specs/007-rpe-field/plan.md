# Implementation Plan: ExerciseSet RPE 字段

**Branch**: `007-rpe-field` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-rpe-field/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

为 `ExerciseSet` 增加可选字段 `rpe: Int?`（主观努力度，有效 1-10，`nil` = 未标注），完整同步 Codable 四件套（CodingKeys / init / encode / decode），保证旧数据 decode 默认 `nil` 的向后兼容（FR-001、FR-004）。UI 侧在 SetRow Menu 增加 RPE picker（暴露 6-10 + "未标注"，避免全 1-10 列表造成选择茫然，FR-002）。AI 侧 `AIPromptBuilder.SetSnapshot` 携带 `rpe`，仅当非 `nil` 时在 set 描述追加 `@ RPE{n}`（FR-003）。这是训练量化基础设施——下游 MY-1041（Smart Progression）、MY-866（RestTimer 按 RPE 调节）在此字段就绪后增强，本 feature 不含它们。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**: SwiftData（`@Model ExerciseSet` in VitalModels package）+ SwiftUI（SetRow Menu picker）

**Storage**: SwiftData model field addition。新增 `rpe: Int?` 为**可选属性（optional，无默认非 nil 值）**——这是本 feature 唯一的关键技术决策：SwiftData 对"新增可选属性且默认 `nil`"视为 additive / lightweight schema 变更，无需显式 migration plan（新列对旧 store 记录读出即 `nil`）。JSON/Codable 层同样通过 `decodeIfPresent` 让缺字段的旧数据 decode 为 `nil`（FR-004），与既有 `weightRight` / `isUnilateral` 的向后兼容模式一致。若后续 SwiftData 版本对此提出显式迁移要求，则回退到 Constitution IV 走 XcodeGen / 迁移评估——当前评估为不需要。

**Testing**: XCTest（Swift Testing `@Suite`）—— `ExerciseSetTests` 扩充 rpe 编解码 round-trip + 旧数据缺字段默认 `nil` 用例。`cd Packages/VitalModels && swift build && swift test`，无需 xcodebuild / 模拟器。

**Target Platform**: iOS 18+（macOS/watchOS 为 companion，本 feature 不新增其专属逻辑）

**Project Type**: Mobile app（XcodeGen 主 app target + 6 个 local SPM packages）

**Performance Goals**: N/A（单字段增补，无性能敏感路径）

**Constraints**: 旧无 RPE 数据 100% 兼容、无迁移崩溃（SC-002）；HealthKit 数值隐私约束不涉及（RPE 为训练主观值，非健康隐私数据）

**Scale/Scope**: 4 个文件改动（1 模型 + 1 模型测试 + 1 SetRow UI + 1 AIPromptBuilder）+ xcstrings

## Constitution Check

*GATE: Phase 0 前必过，Phase 1 设计后复检。*

- **Principle III/IV（SPM Package 优先 / XcodeGen 是配置真理之源）**：模型字段落在既有 `VitalModels` 包内，是**既有 `@Model` 上加一个字段**——不新增 package、不新增 `@Model`、不改 `project.yml` target 结构。已显式评估 Principle III/IV：**不需要 ADR**（ADR 仅在新增 package / 新 `@Model` / 反转架构决策时要求）。数据层验证用 `swift build/test`，不动 xcodebuild。
- **Principle VI（I18n xcstrings 单源）**：SetRow 新增的 RPE picker label / "未标注" 等用户可见字符串必须走 `String(localized:)` 引用 `Localizable.xcstrings`，禁止硬编码（FR-006）。SetRow.swift 顶部现有 file-scope `no_hardcoded_chinese` 豁免为 MY-874 搬迁遗留，**新增字符串不得依赖该豁免**，必须本地化。
- **Quality Bar I（Test Coverage）**：新 public API（`ExerciseSet.rpe` + 其 Codable 行为）必须有 round-trip 测试（FR-005、SC-002）。
- **Quality Bar G（I18n）**：见 Principle VI；硬编码用户可见字符串为 P1。
- **Quality Bar H（Accessibility）**：picker 复用既有 Menu 44pt hit target，新增 picker 项需可被 VoiceOver 读到。

**结论**：无 Constitution 违规，无需 ADR。

## Project Structure

### Documentation (this feature)

```text
specs/007-rpe-field/
├── spec.md              # Feature spec（已有）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
Packages/VitalModels/
├── Sources/VitalModels/Models/
│   └── ExerciseSet.swift          # 新增 rpe: Int? + CodingKeys/init/encode/decode
│                                  #   (锚点 :5-14 属性块、:37-75 Codable extension)
└── Tests/VitalModelsTests/
    └── ExerciseSetTests.swift     # 新增 rpe round-trip + 旧数据默认 nil 用例

VitalStride/Sources/
├── ActiveWorkout/
│   └── SetRow.swift               # Menu 内新增 RPE picker（:122-187 Menu 块）
│                                  #   注：SetRow 已由 MY-874 从 ActiveWorkoutView.swift
│                                  #   拆到 ActiveWorkout/SetRow.swift（spec Reference Map
│                                  #   中的 ActiveWorkoutView.swift:829-879 为搬迁前锚点）
└── AIPromptBuilder.swift          # SetSnapshot 加 rpe (:26-30)；set 描述追加
                                   #   "@ RPE{n}" (:95)；构造点补 rpe (:264)

VitalStride/Resources/
└── Localizable.xcstrings          # RPE picker label / "未标注" 等新字符串单源
```

**Structure Decision**: 遵循既有分层——SwiftData 模型 + 编解码逻辑在 `VitalModels` 包内（可 `swift test` 独立验证，无需 xcodebuild）；平台相关 UI（SetRow）与 AI prompt 组装（AIPromptBuilder）在 app target（`VitalStride/Sources/`）。SetRow 已是独立文件（`VitalStride/Sources/ActiveWorkout/SetRow.swift`），本 feature 只在其 Menu 块内增补 picker，不改文件结构。i18n 走 `Localizable.xcstrings` 单源。

## Complexity Tracking

> 无 Constitution 违规，本节留空。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无） | — | — |
