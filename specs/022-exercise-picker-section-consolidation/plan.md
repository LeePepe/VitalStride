# Implementation Plan: 动作选择分区收敛

**Spec**: [spec.md](./spec.md)

**Constitution**: §II, §III, §VI, §Development Workflow, §Cross-Cutting Quality Bars H/I/K

## Technical Path

把“原始器械”与“picker 分区”拆成两个概念：VitalModels 提供纯值类型 `ExerciseSection` 和 `Exercise.section` 稳定映射；app target 先建立可独立测试的分组模块，再将 `ExercisePickerView` 的 section identity、索引、scroll/drag 状态与 telemetry 全部切到 section。阈值只用于维护当前 catalog 的显式映射，不在运行时按过滤结果动态计算。

不增加 `Exercise` 持久字段，不升级 catalog 版本，不触碰 seeder，避免 CloudKit schema 迁移和已有动作回填。

## Verified Existing Interfaces

- `Exercise` 当前持有 `equipment: Equipment`，picker 通过 `computeEquipmentGroups` 按 equipment 分组。
- `Equipment` 当前有 29 cases；catalog v5 分布中 13 个 cases 少于 10 条，共 30 条。
- `ExercisePickerView` 的 cached groups、visible/dragged state、scroll anchor、index bar 与 telemetry identifier 均以 `Equipment` 为 section ID。
- `exercisePickerSectionJump` 已接受 canonical `TelemetryIdentifier`，不需要修改 TelemetryKit 公共 API。

## Layer Decomposition

| Stage | Task | Layer | Deliverable | Depends on |
|---|---|---|---|---|
| 1 | T001 | VitalModels | `ExerciseSection`、equipment→section 映射、`Exercise.section`、双语资源与 package tests | None |
| 2 | T002 | app target / pure logic | 独立 section grouping seam 与 catalog/过滤稳定性 tests | T001 |
| 3 | T003 | app target / UI wiring | picker section/index/scroll/drag/telemetry 接线与 UI regression tests | T002 |

每个 stage 独立 commit；Stage 2/3 串行，避免同时修改 picker 相关测试。见 AGENTS.md §按 layer 收窄范围。

## Interface Contracts

### VitalModels

- `ExerciseSection`：public、String raw value、Codable、CaseIterable、Sendable；17 个 cases；提供本地化名称和唯一 SF Symbol。
- `Equipment.section`：public 只读计算属性，执行显式稳定映射。
- `Exercise.section`：public 只读计算属性，委托 equipment mapping；不参与持久化 initializer。

### App grouping seam

- internal pure grouping API：输入 exercises、nullable muscle group、search text；输出按 `ExerciseSection.allCases` 顺序排列的 section/items。
- threshold/distribution validator：针对 bundled catalog 验证 17 sections、`other=30`、所有 section ≥10；只作为 contract test，不在用户筛选路径动态归并。

### Picker UI

- section identity、visible/dragged state、scroll anchors、index bar collection 与 section preview 使用 `ExerciseSection`。
- telemetry from/to 使用 section raw value，经现有 `TelemetryIdentifier(validating:)` 路径转换。

## Error and Compatibility Strategy

- 新 enum 为纯值类型；不改 SwiftData schema，不需要数据迁移。
- 未来 catalog 分布改变导致阈值合同失效时，required test 明确失败；维护者必须审查并更新映射，不自动改变现有 UI 分类。
- section icon 不可用或重复由 package contract test 与模拟器验收拦截；不得回退到 equipment 的重复 icon。
- 搜索/筛选为空继续使用既有 graceful empty state。

## Verification

```bash
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests \
  -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests \
  -only-testing:VitalStrideTests/ExercisePickerScrollResetTests \
  -only-testing:VitalStrideTests/ExercisePickerNestedLazyRegressionTests
```

最终交付还须通过完整 App target required check、`claude-review` 与 `codex-review`。

## Files Not to Touch

- `VitalStride/Resources/exercises.json` 与 `scripts/import_mit_exercises.py`
- `VitalStride/Sources/ExerciseSeeder.swift`
- `Packages/TelemetryKit/**`
- `project.yml` 与 `VitalStride.xcodeproj/**`
- `Prototype/Sources/Prototype/**`
- HealthKit / AIService / watchOS / widget targets
