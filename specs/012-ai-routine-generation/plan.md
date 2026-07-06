# Implementation Plan: AI 训练建议一键生成可执行 routine

**Branch**: `012-ai-routine-generation` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-ai-routine-generation/spec.md`

**Constitution**: 2.0.0

## Summary

把现有「今日训练建议」从纯文本升级为可一键开始的 routine。核心做法：

1. **扩展 AI 输出模型** — `TrainingRecommendation` 新增可选 `routineExercises: [RecommendedExercise]?`（name / targetSets / targetReps / targetWeight / note），同时保留原 `exercises: [String]` 以兼容旧缓存（FR-001）。
2. **prompt 升级** — `buildTrainingAdviceMessages` 要求 AI 返回 3-6 个动作，每个带组数/次数/可选重量/备注，动作名优先命中本地动作库（FR-002）。
3. **新增物化层** — `AIRoutineMaterializer` 按动作名反查本地 `Exercise`（`nameEn`/`nameZh` 双语匹配），构建可执行 `Workout` 或 `WorkoutTemplate`（FR-003）。
4. **卡片入口** — `AITrainingAdviceCard` 增加「开始这次训练」与「存为模板」两个入口（FR-004）。
5. **优雅降级** — 动作名无法匹配本地库时仅展示不自动加入；AI 返回旧格式或不可用时沿用现有处理，不崩溃、不静默丢弃（FR-006、边界场景）。

全程复用 `AIProviderChain`，不引第三方 SDK（FR-005 / Constitution V）；不新增 `@Model`，物化写入已有的 `Workout` / `WorkoutTemplate`。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**: AIService（复用 `AIProviderChain`，无第三方 SDK）+ VitalModels（`Exercise` / `Workout` / `WorkoutTemplate`）+ SwiftUI

**Storage**: 通过物化层写入已有 `Workout` / `WorkoutTemplate`（SwiftData 现有模型，不新增 `@Model`）；AI 输出模型为纯值类型（Codable / Sendable）

**Testing**: XCTest — `RecommendedExercise` Codable 往返、旧缓存无 `routineExercises` 的向后兼容解码、`AIRoutineMaterializer` 命中/未命中反查

**Target Platform**: iOS 18+

**Project Type**: Mobile app（iOS，XcodeGen + 6 个 SPM local packages）

**Performance Goals**: 物化为同步内存转换，无额外网络往返；沿用 AI 建议既有加载路径

**Constraints**: 健康数值禁止进日志；AI 只经 `AIProviderChain`；新增 UI 字符串走 xcstrings 单源

**Scale/Scope**: 单一 P1 用户故事；改动集中在 1 个 SPM 模型文件 + 4 个 app 源文件 + xcstrings

## Constitution Check

*GATE: 必须在 Phase 0 前通过，Phase 1 设计后复检。*

- **Principle V（AI 无第三方 SDK）— PASS（重点）**：物化只消费 `AIProviderChain` 现有输出，不新增任何供应商 SDK；prompt 变更仍走既有 provider 链路。
- **Bar D（优雅降级，P0）— PASS（重点）**：
  - 动作名无法匹配本地库 → 展示但不自动加入（show-not-add，FR-006），不崩溃、不静默丢弃。
  - AI 返回旧格式（仅 `exercises: [String]`）→ fallback 兼容，UI 在存在 `routineExercises` 时优先使用（FR-001、边界场景）。
  - AI 不可用 → 沿用 `AITrainingAdviceCard` 现有错误处理路径，不崩溃。
- **Principle VI（I18n）— PASS**：所有新增 UI 文案经 `String(localized:)` 引用 `Localizable.xcstrings`（FR-007）。
- **Bar I（测试）— PASS**：新增 `RecommendedExercise` Codable 往返测试、旧缓存向后兼容解码测试、物化命中/未命中测试。

初检通过，无违规项；Phase 1 设计后复检维持通过。

## Project Structure

### Documentation (this feature)

```text
specs/012-ai-routine-generation/
├── plan.md              # 本文件
├── spec.md              # 功能规格（已存在）
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
Packages/AIService/Sources/AIService/
└── TrainingRecommendation.swift        # + routineExercises?（可选）+ 新增 RecommendedExercise（Codable/Sendable）

VitalStride/Sources/
├── AIAnalysisPrompts.swift             # buildTrainingAdviceMessages：要求 3-6 动作 + sets/reps/weight/note
├── AIRoutineMaterializer.swift         # 新建：动作名 → 本地 Exercise 反查 → 构建 Workout / WorkoutTemplate
├── AITrainingAdviceCard.swift          # +「开始这次训练」+「存为模板」入口 + 旧格式 fallback
└── StartWorkoutView.swift              # 物化目标（WorkoutStartSource.fromWorkout / fromTemplate）

VitalStride/Resources/
└── Localizable.xcstrings               # 新增 UI 字符串（Constitution VI）

Packages/AIService/Tests/AIServiceTests/
└── TrainingRecommendationTests.swift   # Codable 往返 + 向后兼容解码

VitalStrideTests/
└── AIRoutineMaterializerTests.swift    # 反查命中/未命中物化
```

**Structure Decision**: 沿用现有分层——AI 输出模型留在 `Packages/AIService`（纯值类型，可 `swift build/test` 秒级验证），物化层与 UI 入口留在 app target（依赖 `VitalModels` 的 SwiftData 模型与 `StartWorkoutView` 入口枚举）。物化层 `AIRoutineMaterializer` 独立成文件，保持高内聚、可单测。不新增 `@Model`，复用 `Workout` / `WorkoutTemplate` / `Exercise`。

## Complexity Tracking

*无违规项——本 feature 完全复用现有 AI infra、`StartWorkoutView` 入口与既有 SwiftData 模型，无需引入新架构或第三方依赖。*
