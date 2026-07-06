# Implementation Plan: RestTimer 按 setType 自动切换休息时长

**Branch**: `009-rest-by-settype` | **Date**: 2026-07-04 | **Spec**: [./spec.md](./spec.md)

**Input**: Feature specification from `./spec.md`（Multica MY-866）

**Constitution Version**: 2.0.0

---

## Summary

给 `SetType` 加一个纯映射计算属性 `defaultRestDuration`（warmup 45 / working 120 / dropSet 15 / pyramid 75 秒，草案可调）。完成某组、启动 RestTimer 时，休息时长来源改为 `exerciseSet.restDuration ?? setType.defaultRestDuration`——手动值优先，缺省时 fallback 到该组 setType 的默认时长。RestTimer 基础设施（`RestTimerController.startRest(duration:)` → `RestLiveActivityManager`）已接受 duration 参数，本 feature 只改 caller 传入的时长来源，不动 Live Activity / 通知调度逻辑。

- **US1（P1，MVP）**：完成组自动按 setType 给休息时长，手动 > 默认。
- **US2（P3，可选）**：设置页自定义各 setType 休息偏好；默认值已覆盖多数场景，非必需。

映射是纯函数，落在 VitalModels（Principle III），可 `swift test` 秒级验证，无需 xcodebuild。

## Technical Context

**Language/Version**: Swift 6.0（strict concurrency）

**Primary Dependencies**: VitalModels（纯 enum extension，`SetType`/`ExerciseSet` 已在包内）；现有 `RestLiveActivityManager`（ActivityKit）与 `RestTimerController`（app target），均已接受 duration 参数，无改造

**Storage**: 无新增。复用 `ExerciseSet.restDuration: TimeInterval?`（已随 Training 数据 CloudKit 同步）；US2 若落地则新增 per-setType 偏好走 `@AppStorage`（本地，非健康数据）

**Testing**: XCTest — `SetType.defaultRestDuration` 纯映射单测 + 手动优先级逻辑单测，`cd Packages/VitalModels && swift test`

**Target Platform**: iOS 18+（RestTimer 为 iOS app target 特性）

**Project Type**: Mobile app（iOS 主 target + VitalModels SPM 包）

**Performance Goals**: N/A（纯查表，无热路径）

**Constraints**: 映射必须纯、可单测（FR-004）；新增用户可见字符串走 xcstrings（Principle VI）

**Scale/Scope**: 4 个 setType case；1 个新 extension 文件 + 1 处 caller 时长来源改动；US2 可选一个设置区块

## Constitution Check

*GATE：Phase 0 前必须通过；Phase 1 设计后复检。*

- **Principle III（SPM Package 优先）** ✅：`defaultRestDuration` 是纯逻辑，放 `Packages/VitalModels/`，`swift build/test` 验证，不进 app target。
- **Principle IV（XcodeGen SoT）** ✅：新文件在 VitalModels 包目录内，SPM 自动纳入 sources，无需改 `project.yml`；不直接改 `.xcodeproj`。
- **Principle VI（I18n xcstrings 单源）** ✅：US2 设置页任何用户可见字符串走 `String(localized:)` 引用 `Localizable.xcstrings`（FR-005）；不新增 `.strings`。US1 无新增用户可见字符串（纯数值行为）。
- **Quality Bar I（Test Coverage）** ✅：新 public API `defaultRestDuration` 提供映射单测；手动优先级逻辑提供单测（SC-002/SC-003）。
- **无 ADR 需求**：无架构反转、无 `@preconcurrency`/`nonisolated(unsafe)`。
- **无隐私关切**：不涉及 HealthKit 数值（Principle I 不触发）；休息时长偏好非健康数据。

**结论**：无违规，Complexity Tracking 留空。

## Project Structure

### Documentation (this feature)

```text
specs/009-rest-by-settype/
├── spec.md              # 已存在（/speckit-specify 输出）
├── plan.md              # 本文件
└── tasks.md             # /speckit-tasks 输出
```

### Source Code (repository root)

```text
Packages/VitalModels/Sources/VitalModels/
├── Enums/
│   └── SetType.swift                          # 现有 enum（working/warmup/dropSet/pyramid）— 不改
├── Extensions/                                # 新建目录
│   └── SetType+RestDuration.swift             # 新建：defaultRestDuration 纯映射（FR-001/FR-004）
└── Models/
    └── ExerciseSet.swift                      # 现有 restDuration/setType 字段 — 不改

Packages/VitalModels/Tests/VitalModelsTests/
└── SetTypeRestDurationTests.swift             # 新建：映射 + 手动优先级单测（SC-002/SC-003）

VitalStride/Sources/
├── RestTimerController.swift                  # startRest(duration:) — 时长来源 caller 变更点（FR-002）
├── ActiveWorkoutView.swift                    # :323 onSetCompleted 闭包，当前调用 startRest() 无参
├── ActiveWorkout/
│   └── ActiveExerciseSection.swift            # onSetCompleted 触发点，需把完成组的 setType/restDuration 透传上来
├── RestLiveActivityManager.swift             # 现有，接受 duration 参数 — 不改
└── SettingsView.swift                         # US2（P3，可选）：per-setType 休息偏好区块

VitalStride/Resources/
└── Localizable.xcstrings                      # US2 设置页字符串单源（zh+en）
```

**Anchors（已核实真实路径）**：

- 新映射落点：`Packages/VitalModels/Sources/VitalModels/Extensions/SetType+RestDuration.swift`（`Extensions/` 为新建目录）。
- `SetType` 定义：`Packages/VitalModels/Sources/VitalModels/Enums/SetType.swift`（cases 已确认：working/warmup/dropSet/pyramid）。
- `ExerciseSet.restDuration`/`setType`：`Packages/VitalModels/Sources/VitalModels/Models/ExerciseSet.swift:9-10`。
- RestTimer start caller：`VitalStride/Sources/RestTimerController.swift:36` `startRest(duration:)`；实际调用点在 `VitalStride/Sources/ActiveWorkoutView.swift:323`（`onSetCompleted` 闭包，当前无参调用）。
- 完成组来源：`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:14` `onSetCompleted: () -> Void`（`onToggleCompleted` 处触发，需把该 `exerciseSet` 的 setType/restDuration 带上来）。
- Live Activity 基础设施：`VitalStride/Sources/RestLiveActivityManager.swift`（已接受 `totalDuration`，本 feature 不改）。

**Structure Decision**：纯逻辑（映射）下沉 VitalModels，符合 Principle III，可脱离 Xcode 快速验证；行为接线（把完成组的时长来源接到 `startRest(duration:)`）留在 app target，因 RestTimer 是 iOS-specific view 层。`onSetCompleted` 闭包当前不携带完成组信息，US1 需将其签名扩展为携带 setType（或 restDuration），是本 feature 唯一的接线改动。RestLiveActivityManager 保持不变——它已按传入 duration 工作。

## Complexity Tracking

*无 Constitution 违规，无需填写。*
