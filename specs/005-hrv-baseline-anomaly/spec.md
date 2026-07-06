# Feature Specification: HRV 基线 + 异常检测 + 晨间提醒

**Feature Branch**: `005-hrv-baseline-anomaly`

**Created**: 2026-07-04

**Status**: Draft

**Input**: Multica MY-1042（[PM][Athlytic] HRV baseline + 异常检测 + 晨间提醒）。Athlytic 对标——数据页有 HRV chart 但无个人基线 + 异常检测，用户 HRV 显著低于基线（过训/病前兆/睡眠不足信号）时不主动提醒。000-baseline 未覆盖（grep `baseline/anomaly` 0 功能匹配），故立 feature spec。

**Related Issue**: [MY-1042](multica://issue/MY-1042)

**隐私说明**：晨间提醒是 **local push**（`UNUserNotificationCenter`，无远程/APNs，不离设备），不违反 Constitution Principle I（"HealthKit 数值不离设备"）。设备内使用 HRV 数值合规。

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 个人化 HRV 基线 + 数据页异常可视化 (Priority: P1)

用户打开数据页 HRV chart 时，希望看到自己的滚动基线（30 天均值）和"今日相对基线偏多少"，而非只看孤立数值——因为 HRV 个体差异极大（30 vs 80ms 都正常），只有相对偏差有意义。

**Why this priority**: 这是本 feature 的核心且最小可行部分——基线计算 + 数据页可视化不依赖后台/通知，可独立落地，是异常检测的数据基础。

**Independent Test**: 有 ≥14 天 HRV 数据 → 数据页 HRV chart 显示基线横线（RuleMark）+ 显著低区阴影 + 今日相对偏差。

**Acceptance Scenarios**:

1. **Given** 用户有 ≥14 天 HRV 数据，**When** 打开数据页 HRV chart，**Then** 显示 30 天滚动基线横线 + 异常区域阴影，标示今日相对偏差。
2. **Given** 用户 HRV 样本 < 14 天，**When** 查看 HRV，**Then** 不显示基线/不触发异常判定（避免新用户误报）。

### User Story 2 - HRV 异常晨间本地提醒 (Priority: P2)

用户希望在 HRV 显著低于基线时，早晨主动收到本地提醒建议调整训练强度，而非等自己想起来打开 app。

**Why this priority**: 主动提醒比被动展示价值高，但依赖后台调度/通知，比 US1 复杂，故 P2。可在 US1 之后迭代。

**Acceptance Scenarios**:

1. **Given** 今日 HRV 相对基线偏差达 `.significantLow`(-20~-30%) 或 `.critical`(<-30%)，**When** 晨间检测触发，**Then** 发本地 push 建议休息/降强度。
2. **Given** 用户在设置关闭"HRV 异常提醒"，**When** 出现异常，**Then** 不发 push（数据页仍可显示）。
3. **Given** 偏差为 `.mildLow`(-10~-20%)，**When** 检测，**Then** 仅数据页 banner 提示，不发 push。

### Edge Cases

- 样本不足（<14）：不触发任何 alert。
- HRV 单点测量噪声：severity 分级 + 可选多指标（RHR/睡眠）关联降低误报。
- iOS 后台限制：`BGAppRefreshTask` 不保证准时——初版可"用户早于 10:00 打开 app 时"检测并 in-app banner，push 作增强。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST 提供 HRV 基线计算（滚动 30 天均值 ± std + sampleCount），`sampleCount < 14` 时基线不可信、不触发 alert。
- **FR-002**: MUST 提供异常检测：按今日 HRV 相对基线的 percentDeviation 分级 `.normal / .mildLow / .significantLow / .critical`（阈值 -10/-20/-30%，草案可调）。
- **FR-003**: 数据页 HRV chart MUST 叠加基线横线（RuleMark）+ 显著低区阴影。
- **FR-004**: 晨间提醒 MUST 用**本地通知**（`UNUserNotificationCenter`，复用现有 infra），MUST NOT 使用远程推送（保持"数值不离设备"，Constitution I）。
- **FR-005**: push 文案 MUST NOT 含具体 HRV 数值（如"25ms"），只用定性描述（"显著偏低/略偏低"）——避免锁屏泄露（issue 作者的产品决策，比红线更保守）。
- **FR-006**: 设置页 MUST 提供"HRV 异常提醒"开关（默认开，可关）。
- **FR-007**: HRV 数值 MUST NOT 进日志（os_log/print），仅可记 severity/时间范围等元数据（Constitution I 零日志）。
- **FR-008**: 若新增 SwiftData `@Model` 或新 SPM package（如 `RecoveryKit`），MUST 走 ADR（Constitution III/IV）。
- **FR-009**: 新增 UI/通知字符串 MUST 走 `String(localized:)` 引用 xcstrings（Constitution VI），提供 zh + en。
- **FR-010 [optional]**: 异常触发时 MAY 调 `AIProviderChain` 生成个性化建议（结合训练量/睡眠/RHR），fallback 用模板文案；MUST 复用 chain 不引第三方 SDK（Constitution V）。

### Key Entities

- **HRVBaseline**（Sendable）：rollingMean / rollingStdDev / sampleCount / referenceDate。
- **HRVAnomaly**（Sendable）：today / baseline / percentDeviation / severity / suggestionKey。
- **HRVBaselineService**（actor）：`computeBaseline()` / `detectAnomaly()`——新增于 `HealthKitService` 或新 SPM（需 ADR）。
- **MorningHealthCheckScheduler**：晨间检测 + 触发本地通知。

## Success Criteria *(mandatory)*

- **SC-001**: ≥14 天数据的用户，数据页正确显示基线 + 今日相对偏差。
- **SC-002**: HRV 显著低于基线时收到本地提醒（或 in-app banner），文案不含具体数值。
- **SC-003**: 关闭开关后不再收到提醒。
- **SC-004**: 新用户（<14 天）不产生误报。
- **SC-005**: 全流程无任何 HRV 数值进入日志（可 grep 验证）。

## Assumptions

- HRV 数据（`heartRateVariabilitySDNN`）已采集、数据页已有 chart，本 feature 在其上加基线/异常层。
- 本地通知 infra（`RestNotificationScheduler`，已请求 .alert/.sound 权限）可复用。
- 最小可行版本 = US1（基线 + 数据页可视化）；晨间 push（US2）作后续迭代。
- 与 MY-885（训练详情心率区间）正交；比综合 Recovery Score（HRV+RHR+sleep+strain）更窄、更早可落地。

## Reference Map

| 主题 | 代码锚点 |
|------|------|
| HRV 数据采集 | `Packages/HealthKitService/.../HealthSampleType.swift`（heartRateVariabilitySDNN） |
| 数据页 HRV chart | `VitalStride/Sources/DataSections/HealthSampleTypeInfo.swift:33` |
| 本地通知 infra | `VitalStride/Sources/RestNotificationScheduler.swift`（UNUserNotificationCenter） |
| AI 文案（可选） | `Packages/AIService/.../AIProviderChain.swift` |
| 隐私约束（数值不离设备/不入日志） | `.specify/memory/constitution.md` Principle I |
| 新 package/model 需 ADR | Constitution Principle III/IV；`docs/adr/` |
| i18n 单源 | `VitalStride/Resources/Localizable.xcstrings`（Constitution VI） |
