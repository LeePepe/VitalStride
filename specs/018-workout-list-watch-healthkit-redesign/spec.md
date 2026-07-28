# Feature Spec: WorkoutListView — Watch / HealthKit 训练数据重设计

**Spec ID**: 018-workout-list-watch-healthkit-redesign
**Status**: Ready for planning review (round 2 — durability + DoR repair)
**Origin**: Multica MY-1356 (parent) → planning gate MY-1357 → sub-tasks MY-1358 / MY-1359
**Constitution refs**: §I 健康隐私（禁数值日志）、§IV XcodeGen 生成物（pbxproj 不手改）、§V DesignKit token、Cross-cutting: L10n / a11y / Previews

---

## 1. Background & Motivation

用户反馈：「现在训练 list 页面，没有从 Watch 或者健康的训练数据，这个需要重新设计一下。」

`WorkoutListView`（`VitalStride/Sources/WorkoutListView.swift`）的当前实现把训练列表**分成两段**：
先「VitalStride 训练」段，后「Apple 健康训练」段。HK 段视觉弱、来源徽标缺失、无平均心率、
四态（加载/空/失败/未授权）挤在一起。用户体感 = 「看不到 Watch 数据」。

## 2. Evidence — 呈现问题（非数据缺失）

| # | Observation | File:line |
|---|---|---|
| E1 | HK 训练**有**被拉取：`healthDataCache.workoutData()` → `[HealthWorkoutRecord]` | `VitalStride/Sources/WorkoutListView.swift:55` |
| E2 | Dedup 逻辑**有**：`WorkoutListMerger.merge` 按 `healthKitUUID` 去重 | `VitalStride/Sources/WorkoutListMerger.swift:11-18` |
| E3 | Merger **合并后又拆开**：`partitionBySource` 分成 `.app` / `.healthKit` | `VitalStride/Sources/WorkoutListMerger.swift:32-44` |
| E4 | List UI **走两段** Section：App 段在上，HK 段在下（视觉割裂） | `VitalStride/Sources/WorkoutListView.swift:123-199` |
| E5 | HK 行**不显示**来源徽标（无 Apple Watch 标识） | `VitalStride/Sources/HealthKitWorkoutRowView.swift:9-52` |
| E6 | HK 行**不显示**平均心率（列表层无 HR 信息） | 同上 |
| E7 | `HealthWorkoutRecord` **无** `averageHeartRate` / `sourceDeviceKind` 字段 | `Packages/HealthKitService/Sources/HealthKitService/HealthWorkoutRecord.swift:19-51` |
| E8 | 未授权态**未独立**：`isLoadingHealthKit` / `healthKitLoadFailed` 有分支，`authorizationNotDetermined` 归入 `healthKitLoadFailed` 混合展示 | `VitalStride/Sources/WorkoutListView.swift:91-121` |

**结论**：这是**呈现问题**，不是数据管线问题。数据在，只是被两段布局 + 无来源徽标 + 无 HR 弱化了。

## 3. Validation plan（无真机数据时）

FS 交付前须在 issue comment 贴出**至少一条**下列证据之一：

1. 真机复现：Apple Watch 账号打开 List 页，截图显示 HK 段可见 / 不可见 / 空。
2. **Fixture 注入复现**（deterministic）：在 `VitalStrideTests/WorkoutListRenderingTests.swift` 中构造 3 条
   `HealthWorkoutRecord` fixture（其中一条 sourceDeviceKind `.appleWatch`，一条 `.iPhone`），用
   `WorkoutListMerger.merge` + 现有 partition 分支跑一次 → assert 输出中 HK 段独立、无徽标（现状），
   然后把断言换成新设计的「单 section + 徽标 + avgHR」，红→绿证明重设计生效。

## 4. Scope

### 4.1 In scope

- Layer 1 (HealthKitService, MY-1358)：`HealthWorkoutRecord` 新增 `averageHeartRate: Int?` /
  `sourceDeviceKind: SourceDeviceKind?` / `isUserEntered: Bool`；`HealthKitService.convertToWorkoutRecord`
  采集三字段；新增 `averageHeartRate(for:) async -> Int?` helper。
- Layer 2 (App target, MY-1359)：`WorkoutListView` 合并为**单一时间线**（不再 `partitionBySource`）；
  `HealthKitWorkoutRowView` + `WorkoutRowView` 各自加**来源徽标**；HK 行加 avg HR；四态
  （loading/empty/failed/unauthorized）**互不混淆**，unauthorized 提供 "打开设置" deep-link。
- Layer 2 pre-merge design gate (合并入 MY-1359)：before/after 截图 ≥4 张（浅/深色 × normal/Large Mode）
  存 `docs/reports/018-workout-list-redesign-screenshots.md`；design review comment 落在 T2 PR 上。

### 4.2 Out of scope

- 日历模式 (`WorkoutCalendarView`) — 不重设计。
- 详情页 `HealthKitWorkoutDetailView` — 已有心率/HRR，不改。
- 实时训练 `WorkoutSessionManager` — 不动。
- HealthKit **写入** workout 路径 — 不动。
- Widget / Watch app UI — 独立 issue。
- SwiftData 迁移 — `HealthWorkoutRecord` 通过 Codable 存 `HealthCacheEntry`，向后兼容默认值处理即可，
  不动 SwiftData schema。

## 5. Direction — 合并单一时间线 + 来源徽标

与用户抱怨语义最贴合：单 Section，按 `startDate` 倒序排；每行来源徽标；HK 行 avg HR；四态独立。

## 6. Data model changes（Layer 1）

```swift
public enum SourceDeviceKind: String, Sendable, Codable, CaseIterable {
    case appleWatch, iPhone, iPad, mac, other
}

public struct HealthWorkoutRecord: Sendable, Identifiable, Codable, Equatable {
    // existing
    public let id: UUID
    public let activityTypeRawValue: UInt
    public let duration: TimeInterval
    public let totalEnergyBurned: Double?
    public let totalDistance: Double?
    public let startDate: Date
    public let endDate: Date
    public let sourceName: String?
    // new — nil / false default preserves Codable backward compat
    public let averageHeartRate: Int?
    public let sourceDeviceKind: SourceDeviceKind?
    public let isUserEntered: Bool
}
```

Codable 反解：三字段 `decodeIfPresent`，缺省 nil/false。回归 `HealthWorkoutCacheTests` 老 payload 应仍能解。

## 7. UI acceptance bars — Constitution G/H/I（Layer 2）

MY-1359 引入两个新 SwiftUI 视图 (`WorkoutSourceBadge`, `WorkoutListStateBanner`) 与新用户可见文案，
必须满足以下**验收锁**：

- **G. Localization**：新增所有用户可见字符串走 `String(localized: "...", comment: "...")`；
  禁 `no_hardcoded_chinese` 违规；每条新字符串在 `Localizable.xcstrings` 或对应 catalog 里有条目。
- **H. Dynamic Type + hit target**：
  - Row / Banner 在 `.dynamicTypeSize(.xSmall...accessibility5)` 下不截断关键指标（activityType、duration、
    avg HR、source badge 的图标+文字之一），Preview 覆盖 `.large` 与 `.accessibility3`。
  - 交互元素（Banner "打开设置" 按钮、Row NavigationLink 命中区）≥ 44×44pt。
- **I. Accessibility**：
  - 装饰图标（活动类型图标、心形图标、设备图标）`.accessibilityHidden(true)`；
  - Badge 文本进入 combined `.accessibilityLabel` 里（"Apple Watch，跑步，30 分钟，平均心率 145"）；
  - Banner "打开设置" 按钮有独立 `.accessibilityLabel` + `.accessibilityHint`。
- **Previews**：每个新增 View **≥2 个 Preview**：{light, dark} × 至少一个 Dynamic Type 变体。
  `WorkoutListView` 需新增 fixture Preview 覆盖 4 态（loading / empty / failed / unauthorized）+
  「混合 App + HK 项」正常态。

## 8. Acceptance / Verification

### 8.1 Layer 1（MY-1358）

- Codable 向后兼容：旧 payload 缺三字段仍能解，`HealthWorkoutCacheTests` 全绿。
- `convertToWorkoutRecord` 采集 `sourceDeviceKind`：`sourceRevision.productType` 前缀
  `Watch` → `.appleWatch`，`iPhone` → `.iPhone`，`iPad` → `.iPad`，`Mac` → `.mac`，其它 → `.other`；
  每个 case ≥1 条 fixture 单测。
- `convertToWorkoutRecord` 采集 `isUserEntered`：`metadata[HKMetadataKeyWasUserEntered] as? Bool == true`
  → true；单测覆盖。
- `averageHeartRate(for:)` 通过 `HKStatisticsQuery` `discreteAverage` 得整数 bpm；失败/无样本 → nil；不抛。
- **§I 隐私红线**：avg HR / kcal / distance / duration 数值**禁**进 `os_log` / `print` / SDK 上报；
  test 里用 `#file` grep 或专用 lint helper 断言新代码行无 `logger.*\(record\.averageHeartRate\)` 等模式。
- **验证命令**：
  ```
  Working directory: <repo root>/Packages/HealthKitService
  swift build && swift test
  ```

### 8.2 Layer 2（MY-1359）

- FS 交付前贴出 Validation plan §3 中的 fixture-based 复现证据。
- List 只有**一个** data Section 遍历 `unified`（`startDate` 倒序）；App/HK 段割裂消失。
- 每行 `WorkoutSourceBadge`：`.app` = "App"，`.healthKit` 按 `sourceDeviceKind` 映射设备名，
  nil 时 fallback 到 `sourceName`。
- HK 行显示 avg HR（`record.averageHeartRate != nil`）：心形图标 + `xx bpm` + a11y label。
- 四态互不混淆：`.loading` / `.failed` / `.unauthorized` / 空态独立 UI；`WorkoutListStateBannerTests`
  覆盖 4 case。
- 未授权 banner "打开设置" 按钮 deep-link `UIApplication.openSettingsURLString`。
- Dedup 零回归：`WorkoutListMergerTests` 新增 mixed fixture（同 `healthKitUUID`）→ HK 不重复；
  既有 case 全通过。
- 分页保持 MY-1077 语义：`.app` 项 ≤ `initialWorkoutDisplayLimit` (50)，"Load more" `+ workoutDisplayIncrement`；
  HK 项全展示（体量小）。
- L10n / Dynamic Type / a11y / Previews 满足 §7。
- **Pre-merge design gate（原 MY-1360 折入）**：
  - `docs/reports/018-workout-list-redesign-screenshots.md` 含 ≥4 张对比图
    （浅/深 × normal/Large Mode），fixture 至少含 1 条 Apple Watch 来源 HK 训练。
  - Design review comment 落在 T2 PR 上，无 critical/high blocker（有则回 T2 修）。
- **验证命令**：
  ```
  Working directory: <repo root>
  xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
    -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation

  xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
    -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation
  ```

## 9. Red lines

- §I 健康隐私：心率/能量/距离/时长数值禁进任何 log / telemetry。
- §V DesignKit token：配色/圆角/间距/字号走 token，禁 magic number 与 hex literal。
- §IV pbxproj：不手改 `VitalStride.xcodeproj/project.pbxproj`；`project.yml` + `xcodegen generate`。
- Swift 6 strict concurrency：新类型 `Sendable`；`@MainActor` 域清晰。
- 不 checkout 主 repo；在 daemon workdir 内作业。
- **pre-push hook 必须跑**：`--no-verify` 不是允许的 workaround；hook 超时/失败按 Constitution failure-classification 路径处理（分层看 layer/path/kind，先在本地或 CI 里根因修复；不通过则 comment 升级到 planning gate，不 bypass）。

## 10. Open Questions — none

所有决策已在本 spec 与 sub-issue DoR 中固定。
