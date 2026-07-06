# Implementation Plan: 训练中 AI 智能替代动作 (Substitute Exercise)

**Branch**: `003-substitute-exercise` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-substitute-exercise/spec.md`

**Constitution Version**: 2.0.0

---

## Summary

在训练进行中的动作 `⋮` Menu 里新增「智能替代」入口（置于现有「替换动作」上方）。点击后复用现有 `AIProviderChain`，以当前动作的名称 / 主肌群 / 器材构造 prompt，请求 3 个同主肌群的替代建议（各带一行推荐理由）。AI 返回结构化 JSON（`[{exerciseId, reason}]`），按 `exerciseId` 反查本地 SwiftData `Exercise`（新增 `ExerciseSeeder.findByPresetId(_:)` helper）。用户在 `ExerciseSubstituteSheet` 里点选一张 card 即把 `workoutExercise.exercise` 替换为所选、dismiss、触发 haptic。任何 AI 失败（无 provider / 网络失败 / JSON 解析失败 / 反查失败 / 有效候选 < 1）MUST graceful degrade：inline 错误提示 + 一键跳到现有 `ExercisePickerView`（预选当前 `muscleGroup`），不静默失败、不崩溃。

核心是「决策辅助优化」：现有全量 picker 始终作为可用 fallback 保留，本 feature 不替换它，只在其上加一层 AI 推荐。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**:
- `AIService`（复用 `AIProviderChain` — **不新建 provider、不引第三方 SDK**，Constitution V）
- SwiftUI（`ExerciseSubstituteSheet` 新视图 + Menu entry）
- `VitalModels`（复用 `Exercise.muscleGroup` / `.equipment` / `.presetId`，无新模型）

**Storage**: 无新增。复用现有 `Exercise` 元数据字段；反查走内存 / SwiftData `FetchDescriptor`，不新增 schema，不触碰 HealthCache。

**Testing**: XCTest（`VitalStrideTests/Sources/`）——覆盖 JSON 解析（合法 / 畸形 / <3 / 含当前动作）、`findByPresetId` 反查（命中 / 未命中）、以及 AI 不可用时 fallback 路径可达（SC-003）。

**Target Platform**: iOS 18+（训练中界面为 iOS app target；`ActiveExerciseSection` 已抽出到 `ActiveWorkout/`）。

**Project Type**: Mobile app（iOS app target 上的 UI 功能，AI 逻辑复用既有 SPM package）。

**Performance Goals**: 交互层面无硬指标。目标 SC-001：训练中 3 次点击内完成「动作 → 智能替代 → 选定新动作」。

**Constraints**: 复用现有 AI 基础设施，零新增依赖；解析与日志不得泄露健康数值（Constitution I，本功能仅用动作元数据）。

**Scale/Scope**: 单动作替代路径。1 个新视图 + 1 个反查 helper + 1 个 Menu entry + 请求/响应模型与解析 + prompt builder。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 宪法条目 | 判定 | 说明 |
|---------|------|------|
| **Principle V**（AI 本地优先 + 国内 fallback，无第三方 SDK） | ✅ PASS | 复用 `AIProviderChain.makeDefault`（Apple Intelligence 主 + Zhipu fallback）。**不新建 provider、不引第三方 SDK**。仅新增一个 prompt builder + 响应解析器，不触碰 provider 链。 |
| **Bar D 错误处理（P0 Ship Blocker）** | ✅ PASS（设计约束） | AI 不可用 MUST graceful degrade 到手动 `ExercisePickerView`（FR-004 / SC-003）。禁止 `fatalError` / `try!` / `as!`；所有 AI 调用、JSON 解析、反查失败均走 fallback，不静默失败。 |
| **Principle I 健康数据隐私（NON-NEGOTIABLE）/ Bar B（P0）** | ✅ PASS | 本功能仅使用动作元数据（名称 / muscleGroup / equipment），天然不含健康数值。解析 / 错误日志 MUST NOT 打印用户健康数值（FR-007）——日志只记 provider 名 / 错误类别 / 候选数量，不记原始响应内容。 |
| **Principle VI I18n（NON-NEGOTIABLE）/ Bar F（P0）、Bar G（P1）** | ✅ PASS | 所有新用户可见字符串走 `String(localized:)` → `Localizable.xcstrings`（FR-006），不新增同名 `.strings`。 |
| **Bar I 测试覆盖（P1）** | ✅ PASS（设计约束） | 新增解析器 / 反查 helper 提供 round-trip 单测；`ExerciseSubstituteSheet` 至少 2 个 Preview（有结果 / 错误态）。 |

无违规项，Complexity Tracking 留空。

## Project Structure

### Documentation (this feature)

```text
specs/003-substitute-exercise/
├── plan.md              # 本文件
├── spec.md              # 已存在（US1 P1 + FR-001..007）
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
VitalStride/Sources/
├── ActiveWorkout/
│   └── ActiveExerciseSection.swift     # ⋮ Menu 所在（:89-100 Menu / :72-85 contextMenu）
│                                       #   → 新增「智能替代」Button（「替换动作」上方），
│                                       #     经新 onSubstitute 回调上抛
├── ActiveWorkoutView.swift             # session 级视图，持有 replace sheet
│                                       #   :83-87 现有 .sheet(item: $exerciseToReplace) → ExercisePickerView（fallback 目标）
│                                       #   → 新增 substitute 状态 + .sheet 呈现 ExerciseSubstituteSheet；
│                                       #     选中回调写 workoutExercise.exercise + haptic
├── ExerciseSubstituteSheet.swift       # 【新增】3 张推荐 card（name + muscleGroup + reason）；
│                                       #   loading / 结果 / 错误（内嵌跳 picker）三态
├── ExercisePickerView.swift            # 现有全量 picker（fallback 目标，预选 muscleGroup）
└── ExerciseSeeder.swift                # → 新增 findByPresetId(_:context:) 反查 helper（FR-003）

Packages/AIService/Sources/AIService/
├── AIProviderChain.swift               # 复用 .chat(messages:model:)，不改动
└── Models.swift                        # 复用 ChatMessage(role:content:) / ChatResponse

VitalStride/Resources/
└── Localizable.xcstrings               # 新增「智能替代」等 UI 字符串（FR-006）

VitalStrideTests/Sources/
├── ExerciseSubstituteParseTests.swift  # 【新增】JSON 解析 + 过滤单测
└── ExerciseSeederFindTests.swift       # 【新增】findByPresetId 反查单测
```

新增的「substitute request/response 模型 + JSON 解析器 + prompt builder」建议就近放在 app target（如 `ExerciseSubstituteSheet.swift` 同目录的小文件，或 `ActiveWorkout/` 下），保持高内聚小文件；不下沉到 `AIService` package——package 只提供通用 provider 链，业务 prompt / 解析属于 app 层。

**Structure Decision**: Mobile app target 内实现。⋮ Menu 与 sheet 呈现分处两文件——Menu entry 落在已抽出的 `ActiveWorkout/ActiveExerciseSection.swift`（现有「替换动作」的真实位置），sheet 状态与 `workoutExercise.exercise` 写入落在持有 session 状态的 `ActiveWorkoutView.swift`（与现有 `exerciseToReplace` replace sheet 并列）。AI prompt / 解析 / 反查为纯 app 层逻辑，复用 `AIProviderChain` 与 `Exercise`，不新增 package、不改 provider 链。

## Complexity Tracking

> 无宪法违规，本节留空（完全复用既有 AI / 数据基础设施）。
