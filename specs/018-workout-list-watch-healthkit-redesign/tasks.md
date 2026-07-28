# Tasks: WorkoutListView redesign (spec 018)

**Spec**: `specs/018-workout-list-watch-healthkit-redesign/spec.md`
**Plan**: `specs/018-workout-list-watch-healthkit-redesign/plan.md`

Legend: `[P]` = 可与同层其它 `[P]` 任务并行；无标记 = 串行。层间**强串行**（Stage N+1 rebase 到 Stage N 已合并的分支）。

---

## Stage 1 — HealthKitService layer (issue MY-1358)

**Working directory**: `Packages/HealthKitService`

### T018-01 — `HealthWorkoutRecord` 新增字段 + `SourceDeviceKind` enum
- File: `Sources/HealthKitService/HealthWorkoutRecord.swift`
- Add:
  - `public enum SourceDeviceKind: String, Sendable, Codable, CaseIterable { case appleWatch, iPhone, iPad, mac, other }`
  - `public let averageHeartRate: Int?`
  - `public let sourceDeviceKind: SourceDeviceKind?`
  - `public let isUserEntered: Bool`
- Codable: 三字段 `decodeIfPresent`，缺省 nil/false。

### T018-02 — `HealthWorkoutRecordTests` 覆盖 Codable 兼容 + case 覆盖 [P after T018-01]
- File: `Tests/HealthKitServiceTests/HealthWorkoutRecordTests.swift`
- 新增：
  - `decodeLegacyPayload_missingNewFields_defaultsNilAndFalse`
  - `roundTrip_preservesAllFields`（每个 `SourceDeviceKind` case ≥1 条 fixture）

### T018-03 — `HealthWorkoutCacheTests` L2 缓存回归 [P after T018-01]
- File: `Tests/HealthKitServiceTests/HealthWorkoutCacheTests.swift`
- 断言：将老 payload 塞入 `HealthCacheEntry`，重新 fetch → 新 record 三字段 nil/false，其它字段无损。

### T018-04 — `convertToWorkoutRecord` 采集 sourceDeviceKind / isUserEntered
- File: `Sources/HealthKitService/HealthKitService.swift:684-706`
- 通过 `workout.sourceRevision.productType` 前缀映射到 `SourceDeviceKind`（`Watch*` → `.appleWatch` 等）。
- 通过 `workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool` 采 `isUserEntered`。
- 新增 unit test（同 T018-02 test file）覆盖每个 productType 前缀。

### T018-05 — `averageHeartRate(for:)` helper + fetch pipeline hook
- File: `Sources/HealthKitService/HealthKitService.swift`
- 新增 `private func averageHeartRate(for workout: HKWorkout) async -> Int?`：
  用 `HKStatisticsQuery` (`.discreteAverage`) 在 `HKQuantityType(.heartRate)` 上限定 workout 时间段；
  失败/无样本 → nil，不抛。
- 修改 `convertToWorkoutRecord`：`averageHeartRate` 用并发 `TaskGroup` 与其它 statistics 并行拉取；
  或改成 `async` helper，`fetchWorkouts` 用 `withThrowingTaskGroup` 并发装配。选一种，写入 diff。
- 新增 test file `Tests/HealthKitServiceTests/HealthWorkoutAvgHRTests.swift`（用 fixture / 测试替身）：
  - `avgHR_valid_returnsInteger`
  - `avgHR_noSamples_returnsNil`
  - `avgHR_queryFails_returnsNil_doesNotThrow`

### T018-06 — 隐私红线 log 断言
- File: `Tests/HealthKitServiceTests/PrivacyLogAuditTests.swift`（新增，或复用已有）
- 在 test 中读取 `HealthKitService.swift` 源文本，`grep` 断言无
  `logger.*averageHeartRate|logger.*totalEnergyBurned|logger.*totalDistance|logger.*duration.*= .*record\.`
  等模式。若 repo 已有此模式的 audit test，附加 record 三字段规则。

### T018-Verify — Layer 1 verification
```
Working directory: <repo root>/Packages/HealthKitService
swift build && swift test
```

---

## Stage 2 — App target UI + pre-merge design gate (issue MY-1359)

**Depends on**: MY-1358 merged (Stage 1 fields available).
**Working directory**: `<repo root>`

### T018-10 — `SourceDeviceKind` 派生属性挂到 `UnifiedWorkout`
- File: `VitalStride/Sources/Models/UnifiedWorkout.swift`
- `var sourceDeviceKind: SourceDeviceKind?`：`.app` → nil；`.healthKit(let r)` → `r.sourceDeviceKind`

### T018-11 — `WorkoutSourceBadge` 新组件 [P]
- File: `VitalStride/Sources/WorkoutSourceBadge.swift` (new)
- API: `init(kind: SourceDeviceKind?, sourceName: String?, isApp: Bool)`
- 视觉：DesignKit token（primary/neutrals），SF Symbol 图标 + 文本 chip；hit target 无（display only）。
- 装饰 icon `.accessibilityHidden(true)`；文本可读；Previews ≥2（light/dark + Dynamic Type large + accessibility3）。

### T018-12 — `WorkoutListStateBanner` 新组件 + 四态 [P]
- File: `VitalStride/Sources/WorkoutListStateBanner.swift` (new)
- API:
  ```swift
  enum LoadState { case loading, failed, unauthorized }
  struct WorkoutListStateBanner: View { let state: LoadState; let onOpenSettings: () -> Void }
  ```
- `.unauthorized` 时显示 "打开设置" 按钮（≥44×44pt），`.accessibilityLabel` + `.accessibilityHint`。
- 装饰 icon `.accessibilityHidden(true)`；文案走 `String(localized:)`。
- Previews ≥3（三个 state × light/dark）。

### T018-13 — `HealthKitWorkoutRowView` 消费新字段
- File: `VitalStride/Sources/HealthKitWorkoutRowView.swift`
- 追加：右侧列 avg HR（心形 icon + `xx bpm`，`record.averageHeartRate != nil` 时）；
  行末挂 `WorkoutSourceBadge(kind: record.sourceDeviceKind, sourceName: record.sourceName, isApp: false)`。
- 更新 a11y label 组合含 badge 与 avg HR。
- Preview 覆盖：{Apple Watch fixture, iPhone fixture, no HR} × light/dark。

### T018-14 — `WorkoutRowView` 挂 App source badge
- File: `VitalStride/Sources/WorkoutRowView.swift`（读现有实现，最小 diff）
- 行末：`WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: true)`
- 若 badge 已存在（App 侧曾做过），保留现有实现，仅确保视觉与 HK 侧统一。

### T018-15 — `WorkoutListView` 合并单一时间线 + 四态
- File: `VitalStride/Sources/WorkoutListView.swift`
- 变更：
  1. 删除 `partitionBySource(unifiedWorkouts)` 的**使用**；直接消费 `unified` 排序后的 `[UnifiedWorkout]`。
  2. List 单 Section 遍历 `unified`；`if case .app / .healthKit` 分派 row。
  3. 分页语义保持：`.app` 项 ≤ `initialWorkoutDisplayLimit`；`.healthKit` 项全展示。
  4. 新增 `@State private var authState: LoadState?`（互斥于 `isLoadingHealthKit` / `healthKitLoadFailed`）。
  5. `loadHealthKitWorkouts()` catch `HealthKitServiceError.authorizationNotDetermined` → `authState = .unauthorized`。
  6. 顶部渲染 `WorkoutListStateBanner(state:)` 独立 Section（loading / failed / unauthorized）。
- L10n：所有新增可见文案 `String(localized:)`；`Localizable.xcstrings` 加条目。
- 分层 log audit：`logger` 语句不含健康数值。

### T018-16 — `WorkoutListMerger` 移除 partition 使用点
- File: `VitalStride/Sources/WorkoutListMerger.swift`
- `partitionBySource` 保留（若既有测试引用），加 `@available(*, deprecated, message: "unified timeline supersedes partitioned display")`。
- 若无外部引用，直接删并同步删对应老测试。

### T018-17 — `WorkoutListMergerTests` 单 Section 断言 + dedup 回归 [P]
- File: `VitalStrideTests/WorkoutListMergerTests.swift`
- 新增：
  - `merge_producesSingleSortedTimeline_byStartDateDesc`
  - `merge_dedupsHealthKitByUUID_noDuplicateRows`（同 `healthKitUUID` fixture）

### T018-18 — `WorkoutListRenderingTests` fixture 复现证据 [P]
- File: `VitalStrideTests/WorkoutListRenderingTests.swift` (new)
- fixture：3 条 record（`.appleWatch` × 1、`.iPhone` × 1、无 device × 1）+ 2 条 `Workout`。
- 断言：merged 顺序（按 startDate 倒序混合），无 partitioned 分段；render snapshot 或 view-inspector 覆盖。
- 这份 test 同时充当 Validation plan §3 中的「fixture-based deterministic 复现证据」。

### T018-19 — `WorkoutListStateBannerTests` 四态断言 [P]
- File: `VitalStrideTests/WorkoutListStateBannerTests.swift` (new)
- 覆盖：`.loading`（含 progress a11y label）、`.failed`（含错误文案）、
  `.unauthorized`（含 "打开设置" 按钮 a11y label + tap → onOpenSettings 回调）。

### T018-20 — 截图 + design review report
- File: `docs/reports/018-workout-list-redesign-screenshots.md` (new)
- 内容：
  - 场景说明（fixture 覆盖：App + Apple Watch + iPhone HK + 无 HR）
  - Before/After ≥4 张：{light, dark} × {normal, Large Mode(`.large`)}；至少 1 张 fixture 含 Apple Watch 徽标 + avg HR。
  - 设计要点检查（DesignKit token 使用、四态区分、来源徽标可辨、avg HR 可见、a11y label 组合）
  - Design review comment 摘要（reviewer 在 T2 PR 上留言）；无 critical/high blocker。

### T018-Verify — Stage 2 verification
```
Working directory: <repo root>
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation
```
Design gate：T2 PR 描述含截图或链接到 `docs/reports/018-workout-list-redesign-screenshots.md`；
design reviewer comment 表示通过。

---

## Parallelism map

- Stage 1 内：T018-01 → {T018-02[P], T018-03[P], T018-04}；T018-04 → T018-05 → T018-06；T018-Verify 最后。
- Stage 2 内：T018-10 → {T018-11[P], T018-12[P]} → T018-13 → T018-14 → T018-15 → T018-16 →
  {T018-17[P], T018-18[P], T018-19[P]} → T018-20 → T018-Verify。
- Stage 1 ↔ Stage 2 强串行。

## Cross-cutting checkpoints (per PR)

- [ ] 无健康数值 log（§I）
- [ ] DesignKit token（§V）
- [ ] `no_hardcoded_chinese` lint 通过（G）
- [ ] Preview ≥2 per new View + WorkoutListView 5 场景（G/H/I）
- [ ] hit target ≥44pt（H）
- [ ] 装饰 icon `.accessibilityHidden(true)`，combined label 含关键 metric（I）
- [ ] pbxproj 未手改（§IV）
- [ ] pre-push hook 必须通过（禁 `--no-verify`；hook 超时/失败按 Constitution failure-classification 路径处理，先根因修复，不 bypass）
