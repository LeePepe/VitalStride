# Feature Specification: VitalStride Baseline (Existing Codebase)

**Feature Branch**: `000-baseline-existing-codebase`

**Created**: 2026-06-25

**Status**: Living document (audit of as-built state, not a prospective build)

**Input**: 已有约 7 个月开发历史的 VitalStride 项目，2026-06-25 接入 spec-kit。本 spec 是 existing-project 模式下的"baseline as documentation"——记录当前已实现的内容、用户旅程、范围边界，作为后续 feature spec 的参照基线。新功能写新 spec（`specs/001-*`、`002-*` ...），不修改本文。

## User Scenarios & Testing

### User Story 1 - 力量训练记录 (Priority: P1)

用户在 iPhone 上完成一次力量训练：选动作 → 记录每组 reps/weight → 完成训练 → 查看历史。

**Why this priority**: 这是 V1 的核心产品价值——HealthKit 无法表达 per-set 训练详情，本 app 填补这个空缺。所有其他 feature 都是这个核心循环的辅助。

**Independent Test**: iPhone 16 模拟器开 `StartWorkoutView` → `ExercisePickerView` 选 3 个动作 → `ActiveWorkoutView` 记 3 组数据 → 完成 → `WorkoutListView` 看到这次训练 + `WorkoutDetailView` 看到 per-set 数据。

**Acceptance Scenarios**:
1. **Given** 没有任何历史训练，**When** 用户选 1 个动作记 1 组完成训练，**Then** `WorkoutListView` 显示这次训练，`WorkoutDetailView` 显示动作 + 组数据。
2. **Given** 模板已存在，**When** 用户从模板开始训练，**Then** 训练自动包含模板中所有动作，可逐组调整 reps/weight。
3. **Given** 用户已登入 iCloud，**When** 完成训练，**Then** 训练数据通过 CloudKit 同步到其他设备（受 iCloud 配额限制）。

---

### User Story 2 - 健康数据 Dashboard (Priority: P1)

用户打开 Data Tab 查看今日/最近的健康数据（步数、心率、睡眠、体重），并下钻查看趋势图。

**Why this priority**: 产品定位是"健康数据收集 + AI 分析"，训练只是一种数据源。Data Tab 是聚合视图，体现产品价值主张。

**Independent Test**: 在已授权 HealthKit 的真机/模拟器上打开 Data Tab → 看到 2×2 Summary Card（步数/静息心率/睡眠/体重）+ 分组列表 → 点 "步数" → Detail Page 显示日/周/月/年趋势图 + 统计（avg/max/min）。

**Acceptance Scenarios**:
1. **Given** 用户已授权全部 HealthKit 读权限，**When** 打开 Data Tab，**Then** Summary Card 显示今日 4 项指标，2 秒内首次填充（L1 hit 路径 < 100ms）。
2. **Given** 用户冷启动 app，**When** Data Tab 首次加载，**Then** L2 hydrate 优先回填，避免显示空白；后台异步 refresh L1。
3. **Given** 用户在系统设置撤销 HealthKit 权限，**When** 返回 app，**Then** 缓存（L1+L2）完整清空 + anchor reset + telemetry 计数器清零（Principle I 隐私强制）。

---

### User Story 3 - AI 分析 (Priority: P2)

用户在训练详情 / 健康数据视图触发 AI 分析，得到一段中文总结/建议。

**Why this priority**: AI 是产品差异化点，但 V1 是辅助而非必需——核心训练 + 数据收集不依赖 AI。

**Independent Test**: 选一次完成的训练 → 触发 AI 分析 → 收到流式返回的中文文本响应（Apple Intelligence 优先；fallback 智谱 GLM-4-Flash）。

**Acceptance Scenarios**:
1. **Given** 用户在 iOS 18.1+ 真机（支持 Apple Intelligence），**When** 触发 AI 分析，**Then** 使用 on-device Foundation Models 生成响应，不发起网络请求。
2. **Given** 设备不支持 Apple Intelligence 或 on-device 失败，**When** 触发 AI 分析，**Then** 自动 fallback 智谱 GLM-4-Flash（OpenAI-compatible REST），key 从 Keychain 读取。
3. **Given** 智谱 API 也失败（网络/quota），**When** 触发 AI 分析，**Then** UI 显示 graceful error message，不 crash、不重试风暴。

---

### User Story 4 - 训练间休息计时器 (Priority: P2)

训练中两组之间需要休息，用户希望计时器在锁屏/后台可见。

**Why this priority**: 实战训练必备，但不阻断核心循环——也可以人工看表。

**Independent Test**: 在 `ActiveWorkoutView` 完成一组 → 启动 Rest Timer → 锁屏 → 在 Live Activity 看到倒计时持续运行。

**Acceptance Scenarios**:
1. **Given** 用户启动 Rest Timer 60 秒，**When** 锁屏，**Then** Lock Screen Live Activity 显示剩余时间，每秒更新。
2. **Given** iOS < 16.1 或用户禁用 Live Activity，**When** 启动 Rest Timer，**Then** 仅 in-app 显示计时器，不调 ActivityKit。

参考：ADR-0006 (Live Activity for Rest Timer)。

---

### User Story 5 - watchOS / macOS Companion (Priority: P3)

用户在 Watch 上查看今日训练 + 健康概览；在 Mac 上查看完整数据（同 iOS 视图）。

**Why this priority**: ADR-0002 明确 watchOS/macOS 是 companion，**不立项专属 feature**。当前阶段只复用 iOS 视图，保持 deployment target 一致即可。

**Independent Test**: Watch Series 模拟器看到训练列表 + 今日步数；Mac 上 app 打开能看到与 iOS 一致的 Tab 结构。

**Acceptance Scenarios**:
1. **Given** Watch 配对了 iPhone，**When** 在 Watch 打开 app，**Then** 看到训练列表 + 今日健康概览（read-only 视图）。
2. **Given** Mac 上启动 app，**When** 打开 Data Tab，**Then** 看到与 iPhone 一致的 Summary Card + 分组列表，可下钻趋势图（macOS 13+ HealthKit read-only via iCloud Health sync）。

---

### Edge Cases

- **HealthKit 部分权限**：用户只授权步数，未授权心率 → 受限数据类型显示 "未授权" 占位，非 crash；其他类型正常。
- **iCloud 配额满**：CloudKit sync 失败 → 训练数据本地保留，UI 提示同步失败，重试可恢复。
- **AI provider 全失败**：Apple Intelligence + 智谱都不可用 → UI 显示 "AI 暂不可用"，不影响其他功能。
- **冷启动 HealthKit 慢响应**：首次 HealthKit fetch 数秒 → L2 hydrate 优先回填，后台 refresh L1，view 不显示空白闪烁。
- **xcstrings 共存冲突**：如果遗留 `.strings`/`.stringsdict` 与 `.xcstrings` 同名 → Xcode 26 硬错（"cannot co-exist"），pre-push xcodebuild test 直接失败（已通过 MY-882 清理；约束写入 Constitution Principle VI）。
- **Multi-set 中 app crash**：未完成训练 → SwiftData 持久化已有 set 数据，下次打开提示是否恢复未完成训练（当前实现仅保留草稿，无 explicit recovery dialog——见 Out-of-Scope）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: App 必须支持 iOS 18.0 / macOS 15.0 / watchOS 11.0 及以上，由 `project.yml` 强制。
- **FR-002**: 训练数据（Workout/Exercise/Set/Template）通过默认 SwiftData ModelConfiguration 持久化，CloudKit-synced。
- **FR-003**: HealthKit L2 缓存（HealthCacheEntry）使用独立 `ModelConfiguration("HealthCache", cloudKitDatabase: .none)`，本地隔离。
- **FR-004**: HealthKit 缓存读取路径：L1 hit → 返回 | L1 miss → L2 load → L1 回填 | L2 miss → HealthKit fetch → L1+L2 回填。
- **FR-005**: HealthKit 缓存 TTL 默认 1h，stale-serve-then-refresh；可配置。
- **FR-006**: HealthKit 权限撤销时必须完整清空 L1/L2/anchor/telemetry（Principle I 强制；hook/test 验证 — 当前缺失自动化测试，记入 Out-of-Scope 补强）。
- **FR-007**: Data Tab Summary Card 显示 4 项：步数（今日）、静息心率（最近）、睡眠（昨晚时长）、体重（最近）。
- **FR-008**: Data Tab 分组：活动（步数、活动能量）/ 心脏（心率）/ 身体测量（体重）/ 睡眠（睡眠分析）。
- **FR-009**: Data Detail Page 包含时间范围 Picker（日/周/月/年）+ Swift Charts 趋势图 + 统计 summary（avg/max/min）。
- **FR-010**: AIService 提供 `AIProvider` 协议，包含 `chat(messages:model:)` 和 `chatStream(messages:model:)`。
- **FR-011**: AI provider chain：Apple Intelligence Foundation Models 优先（iOS 18.1+），智谱 GLM-4-Flash fallback。
- **FR-012**: AI API key 仅存 Keychain，禁止硬编码或 NSUserDefaults。
- **FR-013**: Rest Timer 使用 ActivityKit Live Activity（iOS 16.1+）；不支持时降级为 in-app 计时器。
- **FR-014**: UI 字符串必须用 `String(localized:)` / `NSLocalizedString`，源为 `Localizable.xcstrings`（单源）。
- **FR-015**: TelemetryKit 提供 `TelemetryProvider` 协议；当前实现 `ConsoleTelemetryProvider`；缓存命中/未命中/fetch 耗时/refresh 计数有埋点，**不含任何 HealthKit 数值**。
- **FR-016**: Git 流程为 no-PR workflow：FS push 到 local bare repo `agent/*` 分支；TL rebase 后 push `github main`；pre-push hook 强制 main-only 公共远端 + agent/* 含 `MY-\d+`。

### Non-Functional Requirements

- **NFR-001**: Swift 6 strict concurrency，全 package + app target；新代码不得 `@unchecked Sendable` / `@preconcurrency` 绕过未经 ADR 同意。
- **NFR-002**: HealthKit L1 cache hit 路径 < 100ms（actor 内存读取）。
- **NFR-003**: 冷启动 Data Tab 首次填充 < 2s（L2 hydrate 路径）。
- **NFR-004**: AI Apple Intelligence on-device 响应启动 < 1s（device-capability dependent）。
- **NFR-005**: 所有 HealthKit 数值禁止出现在任何日志（os_log/print/SDK）——Principle I。
- **NFR-006**: pre-push hook 必须在 push 前跑 build + test（SPM-only fast path or full xcodebuild）。

### Key Entities

- **Workout**: 一次训练会话，含 startedAt/endedAt/exercises/notes；CloudKit-synced。
- **WorkoutExercise**: 训练中的一个动作，引用 Exercise；含 sets。
- **ExerciseSet**: 单组数据：reps、weight、rest seconds、isCompleted。
- **Exercise**: 动作字典条目（名称、肌群、类型）；由 `ExerciseSeeder` + `Resources/exercises.json` 初始化。
- **WorkoutTemplate** / **TemplateExercise**: 训练模板，复用动作组合。
- **HealthCacheEntry**: HealthKit L2 缓存条目，按 sample type 分桶；本地隔离（`cloudKitDatabase: .none`）。
- **HealthDataPoint**: 单个健康数据点（value、unit、timestamp、metadata）。
- **HealthKitAnchorStore**: 持久化 HKQueryAnchor 状态，支撑增量查询。
- **ChatMessage** / **ChatResponse** / **ChatStreamChunk**: AIService 消息抽象。
- **TelemetryEvent**: 遥测事件抽象（仅元数据，禁止健康数值 payload）。

## Out-of-Scope (V1 Boundaries)

明确不在 baseline 范围内的项目；后续若需要要新 feature spec：

- HealthKit Observer Query / BGHealthQuery 后台同步（仅 read 时拉取）。
- Data Detail Page 的 raw data point 列表（仅展示趋势 + 统计）。
- HealthKit 写入（仅 read）。
- watchOS 独立训练流程 / 独立 complication（ADR-0002 deferred）。
- macOS menubar / Shortcut Intent / 独立 Mac 体验（ADR-0002 deferred）。
- 第三方 AI SDK 接入（违反 Principle V）。
- 训练中断的显式 recovery dialog（当前仅保留草稿，重启后无恢复 UI）。
- HealthKit 权限撤销→缓存清除的自动化测试（约束在 Principle I，但当前依赖人工 QA，未来 feature 加测）。

## Reference Map

| 主题 | 文件 |
|------|------|
| 数据架构细节 | `CONTEXT.md` |
| 操作手册 / 命令行流程 | `AGENTS.md` |
| Git 流程 | `docs/adr/0001-no-pr-workflow.md` |
| watchOS/macOS 范围 | `docs/adr/0002-defer-watchos-macos-feature-work.md` |
| 双数据源决策 | `docs/adr/0003-healthkit-swiftdata-dual-data-source.md` |
| SPM 包拆分 | `docs/adr/0004-five-local-spm-packages.md` |
| AI provider chain | `docs/adr/0005-ai-provider-chain.md` |
| Rest Timer Live Activity | `docs/adr/0006-live-activity-for-rest-timer.md` |
| TelemetryKit 独立 | `docs/adr/0007-telemetrykit-standalone-spm-package.md` |
| 强制规则机器实现 | `scripts/hooks/pre-commit`、`scripts/hooks/pre-push` |
| 关键 view 文件速查 | `.hermes/skills/vitalstride/vitalstride/SKILL.md` 表格 |

## Success Criteria (audit-style, not aspirational)

以下是 V1 baseline 当前已达成的目标，作为后续 feature 改动的回归基线：

- **SC-001**: iPhone 16 Simulator 上完成一次完整训练循环（选动作 → 记 set → 完成 → 查历史）能跑通；`xcodebuild test` PASS。
- **SC-002**: Data Tab 在已授权 HealthKit 的真机上展示 4 项 Summary + 趋势图。
- **SC-003**: AI 分析在 iOS 18.1+ Apple Intelligence 设备上 on-device 工作；fallback 到智谱 GLM-4-Flash。
- **SC-004**: Rest Timer 锁屏 Live Activity 倒计时正确（iOS 16.1+）。
- **SC-005**: pre-push hook 拦截非 main 的公共 push + 拦截 agent/* 无 issue key commit。
- **SC-006**: Multica project `7adf8b88` 配置正确，TL → FS → Reviewer pipeline 能处理 MY-* issue。
- **SC-007**: 全部 7 个 ADR 文件 + CONTEXT.md + AGENTS.md 内容与代码一致，无 drift（每季度 review）。
