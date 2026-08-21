# Tasks: 动作选择分区收敛

**Spec**: [spec.md](./spec.md) · **Plan**: [plan.md](./plan.md)

Dependency order: T001 → T002 → T003. 下游实现须在 ADR-0014 的 AI Reviewer + Team Lead 双批准完成后由 TL 派发。

## [T001] [Story] VitalModels 建立稳定 ExerciseSection 语义

**Stage**: 1

**Files in scope**:

- 新增 `Packages/VitalModels/Sources/VitalModels/Enums/ExerciseSection.swift`
- 更新 `Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift`
- 更新 `Packages/VitalModels/Sources/VitalModels/Resources/Localizable.xcstrings`
- 新增 `Packages/VitalModels/Tests/VitalModelsTests/ExerciseSectionTests.swift`

**Files NOT to touch**: app target、catalog/seeder、TelemetryKit、`project.yml`、`.xcodeproj`。

**Public signatures**:

- `ExerciseSection` 为 String raw value、Codable、CaseIterable、Sendable 的 public enum；case 集为 `assisted`、`band`、`barbell`、`bodyweight`、`cable`、`dumbbell`、`ezBarbell`、`kettlebell`、`leverageMachine`、`machine`、`medicineBall`、`rope`、`sledMachine`、`smithMachine`、`stabilityBall`、`weighted`、`other`。
- multiword case 的 raw value 使用 lowercase ASCII snake_case，供 telemetry canonical identifier 直接消费。
- `Equipment.section` 为 public 只读计算属性。
- `Exercise.section` 为 public 只读计算属性，不进入 initializer 或 SwiftData schema。

**Acceptance criteria**:

- [ ] 当前 13 个低频 Equipment cases 全部映射到 `other`；16 个保留 cases 各自映射到对应 section。
- [ ] 29 个 Equipment cases 映射覆盖完整，Codable round-trip 与 Sendable contract 通过。
- [ ] 17 个 section 均有非空英文/简中 label。
- [ ] 17 个 SF Symbol 均非空且完全唯一。
- [ ] `Exercise.section` 始终等于其 `equipment.section`，自定义/preset 行为一致。
- [ ] `Exercise` 持久属性与 initializer 签名不变。

**Verification**:

```bash
swift build --package-path Packages/VitalModels
swift test --package-path Packages/VitalModels
```

**Constitution refs**: §II、§III、§VI、Quality Bar I。

## [T002] [Story] App Logic 提取稳定 section grouping seam

**Stage**: 2

**Blocked by**: T001

**Files in scope**:

- 新增 `VitalStride/Sources/ExercisePickerSectionGrouping.swift`
- 新增 `VitalStrideTests/Sources/ExercisePickerSectionGroupingTests.swift`
- 更新 `VitalStrideTests/Sources/ExercisesJSONTests.swift`，仅增加 section distribution contract

**Files NOT to touch**: `ExercisePickerView.swift`、VitalModels、catalog/generator、seeder、TelemetryKit、`project.yml`、`.xcodeproj`。

**Internal interfaces**:

- 纯 grouping API 接受 exercises、nullable muscle group 与 search text，返回按 `ExerciseSection.allCases` 排序的 section/items。
- catalog contract 只验证完整未过滤目录；生产筛选路径不按当前 visible count 动态改组。

**Acceptance criteria**:

- [ ] 1,558 条 catalog 得到 17 sections，`other=30`，所有 section 数量均 ≥10。
- [ ] 严格 `<10` 的 13 个 equipment buckets 全部且仅映射到 `other`；`rope=10` 保持独立。
- [ ] 搜索与肌群过滤只过滤 items，不改变任一 Exercise 的 section identity。
- [ ] 输出顺序稳定等于 `ExerciseSection.allCases`，空 section 不输出。
- [ ] custom exercise 通过 equipment mapping 进入正确 section。

**Verification**:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisePickerSectionGroupingTests \
  -only-testing:VitalStrideTests/ExercisesJSONTests
```

**Constitution refs**: §II、§III、Quality Bar I。

## [T003] [Story] App UI 改用 section index 与唯一图标

**Stage**: 3

**Blocked by**: T002

**Files in scope**:

- 更新 `VitalStride/Sources/ExercisePickerView.swift`
- 更新 `VitalStride/Resources/Localizable.xcstrings`
- 更新 `VitalStrideTests/Sources/ExercisePickerIndexSyncTests.swift`
- 更新 `VitalStrideTests/Sources/ExercisePickerScrollResetTests.swift`
- 更新 `VitalStrideTests/Sources/ExercisePickerCardGridLayoutTests.swift`
- 更新 `VitalStrideTests/Sources/ExercisePickerNestedLazyRegressionTests.swift`
- 更新 `VitalStrideTests/Sources/ExercisePickerSearchLayoutTests.swift`，仅处理 section type/label 回归

**Files NOT to touch**: VitalModels、catalog/generator、seeder、TelemetryKit、其他 app views、`project.yml`、`.xcodeproj`。

**Internal interfaces**:

- cached groups、visible/dragged state、scroll anchors、index bar、section preview 与 telemetry mapping 全部使用 `ExerciseSection`。
- 沿用现有 `exercisePickerSectionJump` event；from/to 为 section canonical raw value，不新增 telemetry API。

**Acceptance criteria**:

- [ ] 未过滤 picker 只显示 17 个 section/header/index entries，不再显示 29 个 equipment sections。
- [ ] header、右侧索引与拖动预览使用同一 section label/icon；可见图标无重复。
- [ ] index hit target ≥44pt，VoiceOver 朗读本地化 section 名称。
- [ ] 搜索焦点、多选、网格固定 inset、滚动重置、highlight dedup、drag-vs-scroll race suppression 全部保持。
- [ ] section jump telemetry 继续成功构造 canonical identifiers，且不记录动作名称或自由文本。
- [ ] iPhone 16 Simulator light/dark 截图确认 17-section 索引可读且不遮挡网格。

**Verification**:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExercisePickerIndexSyncTests \
  -only-testing:VitalStrideTests/ExercisePickerScrollResetTests \
  -only-testing:VitalStrideTests/ExercisePickerCardGridLayoutTests \
  -only-testing:VitalStrideTests/ExercisePickerNestedLazyRegressionTests \
  -only-testing:VitalStrideTests/ExercisePickerSearchLayoutTests
```

**Constitution refs**: §II、§III、§VI、Quality Bars H/I/K。
