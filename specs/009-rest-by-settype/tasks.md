---
description: "Task list for 009-rest-by-settype (Multica MY-866)"
---

# Tasks: RestTimer 按 setType 自动切换休息时长

**Input**: Design documents from `/specs/009-rest-by-settype/`

**Prerequisites**: [plan.md](./plan.md)（required）, [spec.md](./spec.md)（user stories）

**Tests**: 已请求。`defaultRestDuration` 是新 public API，按 Quality Bar I 必须有 round-trip/映射测试；手动优先级是核心正确性（SC-002），必须单测。

**Organization**: 按 user story 分组。US1（P1）= MVP；US2（P3）= 可选增强。

## Format: `- [ ] T### [P?] [US#] Description`

- **[P]**：可并行（不同文件、无依赖）
- **[US#]**：所属 user story
- 描述含真实文件路径

---

## Phase 1: Setup（共享前置，确认锚点）

**Purpose**：核实改动落点，避免接线错位。无代码产出。

- [ ] T001 确认 `SetType` 四个 case 与拼写：`Packages/VitalModels/Sources/VitalModels/Enums/SetType.swift`（working/warmup/dropSet/pyramid）。
- [ ] T002 确认 RestTimer start caller 签名与调用点：`VitalStride/Sources/RestTimerController.swift:36` `startRest(duration:)`，实际调用在 `VitalStride/Sources/ActiveWorkoutView.swift:323` 的 `onSetCompleted` 闭包（当前无参 `startRest()`）。
- [ ] T003 确认完成组信息来源与断链点：`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:14` 的 `onSetCompleted: () -> Void` 当前不携带完成组的 setType/restDuration；确认 `RestLiveActivityManager` 已接受 duration 参数（`VitalStride/Sources/RestLiveActivityManager.swift`，无需改动）。

**Checkpoint**：三处锚点确认，US1 接线路径清晰。

---

## Phase 2: Foundational（VitalModels 纯映射，阻塞 US1）

**Purpose**：`SetType.defaultRestDuration` 纯映射 —— 所有 story 的时长来源依赖它。

**⚠️ CRITICAL**：US1 无法在此前接线。

- [ ] T004 [US1] 新建 `Packages/VitalModels/Sources/VitalModels/Extensions/SetType+RestDuration.swift`（含新建 `Extensions/` 目录）：`public var defaultRestDuration: TimeInterval` 纯 `switch` 映射 warmup 45 / working 120 / dropSet 15 / pyramid 75（草案值以常量表达，禁止散落魔法数）（FR-001, FR-004）。验证：`cd Packages/VitalModels && swift build && swift test`。

**Checkpoint**：映射就绪，US1 可接线。

---

## Phase 3: User Story 1 - 休息时长按组类型自动调整（Priority: P1）🎯 MVP

**Goal**：完成某组时，RestTimer 按 `exerciseSet.restDuration ?? setType.defaultRestDuration` 启动（手动优先，缺省 fallback setType 默认）。

**Independent Test**：完成一个 dropSet 组 → RestTimer 约 15s；完成一个 working 组 → 约 120s；手动设过 restDuration 的组 → 用手动值。

### Tests for User Story 1 ⚠️（先写、先 FAIL）

- [ ] T005 [P] [US1] 新建 `Packages/VitalModels/Tests/VitalModelsTests/SetTypeRestDurationTests.swift`：断言四个 case 的 `defaultRestDuration`（warmup 45 / working 120 / dropSet 15 / pyramid 75），映射穷尽（可用 `SetType.allCases` 断言无遗漏）（SC-001, SC-003）。
- [ ] T006 [P] [US1] 在同一测试文件补手动优先级逻辑单测：`restDuration ?? setType.defaultRestDuration` —— 有手动值取手动、`nil` 取 setType 默认；覆盖 edge case「setType 变更后已设手动 restDuration 不被默认覆盖」（SC-002，spec Edge Cases）。验证：`cd Packages/VitalModels && swift test`。

### Implementation for User Story 1

- [ ] T007 [US1] 扩展 `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`：让 `onSetCompleted` 携带完成组的时长来源信息（把该 `exerciseSet` 的 setType/restDuration 上抛，`onToggleCompleted` 完成分支透传），保持不动其它闭包语义。
- [ ] T008 [US1] 改 `VitalStride/Sources/ActiveWorkoutView.swift:323` 的 `onSetCompleted` 闭包：改为 `restTimer.startRest(duration: exerciseSet.restDuration ?? exerciseSet.setType.defaultRestDuration)`，取代当前无参 `startRest()`（FR-002，手动优先 SC-002）。`RestTimerController.startRest(duration:)` 与 `RestLiveActivityManager` 不改。

**Checkpoint**：US1 完整可用 —— 各 setType 完成组给对应默认时长、手动值优先。MVP 可交付。

---

## Phase 4: User Story 2 - 设置页自定义各 setType 休息偏好（Priority: P3，可选）

**Goal**：设置页可调各 setType 默认休息时长。

**标注**：**P3 / 可选**。默认值已覆盖多数场景（US2 非 MVP）；US1 不依赖本 phase，可独立跳过交付。

**Independent Test**：设置页把 working 默认改为 90s → 之后完成未手动设时长的 working 组 → RestTimer 约 90s。

### Tests for User Story 2 ⚠️

- [ ] T009 [P] [US2] 为 per-setType 偏好读取/回退逻辑补单测（自定义值存在时优先于草案默认、缺失时回退草案值），落在 VitalModels 偏好解析层或 app target 对应测试目录（视 T010 落点）。

### Implementation for User Story 2

- [ ] T010 [US2] 在 `VitalStride/Sources/SettingsView.swift` 增各 setType 休息时长偏好区块（`@AppStorage` 本地存储，非健康数据），并让 T008 的时长来源在 `restDuration` 为 `nil` 时改读该偏好（偏好缺失再回退 `defaultRestDuration`）（FR-003）。
- [ ] T011 [P] [US2] 设置页新增用户可见字符串走 `String(localized:)` 引用 `VitalStride/Resources/Localizable.xcstrings`，补 zh+en（FR-005，Principle VI / Quality Bar G）。

**Checkpoint**：US1 + US2 均独立可用。

---

## Phase 5: Polish & Cross-Cutting

- [ ] T012 [P] 复核所有新增用户可见字符串已在 `VitalStride/Resources/Localizable.xcstrings` 补齐 zh+en，无与 xcstrings 同名 `.strings`（Principle VI / Quality Bar F/G）。
- [ ] T013 复核 VitalModels 无回归：`cd Packages/VitalModels && swift build && swift test`（Quality Bar I）。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**：无依赖，先行。
- **Foundational（Phase 2 / T004）**：依赖 Setup；阻塞 US1、US2（时长来源根节点）。
- **US1（Phase 3）**：依赖 T004；MVP。
- **US2（Phase 4）**：依赖 T004；可在 US1 之上或独立开发；P3 可跳过。
- **Polish（Phase 5）**：依赖已交付的 story。

### User Story Dependencies

- **US1（P1）**：仅依赖 Foundational，独立可测可交付。
- **US2（P3）**：仅依赖 Foundational；在 T008 时长来源基础上插入偏好优先级，但 US1 不依赖 US2。

### Within Each Story

- 测试先写并 FAIL，再实现（T005/T006 在 T007/T008 前；T009 在 T010 前）。
- 纯映射（T004）先于所有接线。
- T007（上抛完成组信息）先于 T008（消费）。

### Parallel Opportunities

- T005、T006 [P]：同测试文件不同用例，可同批编写。
- US2 的 T009、T011 [P] 与 US1 交付后并行。
- Polish T012 与 T013 可并行。

---

## Parallel Example: User Story 1

```bash
# 先写测试（同批）：
Task: "T005 defaultRestDuration 映射单测 in Packages/VitalModels/Tests/VitalModelsTests/SetTypeRestDurationTests.swift"
Task: "T006 手动优先级 + edge case 单测 in 同文件"
# FAIL 后实现 T007 → T008
```

---

## Implementation Strategy

### MVP First（US1 Only）

1. Phase 1 Setup（确认锚点）
2. Phase 2 Foundational（T004 纯映射，`swift test` 通过）
3. Phase 3 US1（T005/T006 先 FAIL → T007/T008 接线 → 绿）
4. **STOP & VALIDATE**：dropSet≈15s / working≈120s / 手动值优先
5. 交付 MVP

### Incremental Delivery

1. Setup + Foundational → 根就绪
2. US1 → 独立测试 → 交付（MVP）
3. US2（P3，按产品决定是否做）→ 独立测试 → 交付
4. Polish（xcstrings + swift test 复核）

---

## Notes

- [P] = 不同文件/无依赖；[US#] 映射 story 便于追溯。
- VitalModels 任务一律 `cd Packages/VitalModels && swift build && swift test` 验证，禁用 xcodebuild（CLAUDE.md）。
- RestLiveActivityManager / RestTimerController.startRest(duration:) 不改——只换 caller 传入的时长来源。
- 手动 restDuration 永远优先于任何默认（SC-002，spec Edge Cases）。
- Quality Bars：I（新 public API 测试）、G（i18n 硬编码字符串）。
