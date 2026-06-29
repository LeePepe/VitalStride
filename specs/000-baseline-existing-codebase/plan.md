# Implementation Plan: VitalStride Baseline (Audit + Gap Analysis)

**Spec**: [`spec.md`](./spec.md)

**Created**: 2026-06-25

**Status**: Living document (audit, not a build plan)

**Constitution Version**: 1.0.0

---

## Purpose

This is NOT a forward-looking build plan. VitalStride V1 已经在线运行约 7 个月（48+ Swift 源文件 + 5 个 SPM packages + iOS/macOS/watchOS 三平台）。本 plan 用 spec-kit existing-project 模式跑"Plan as Gap Analysis"：

1. 记录 baseline spec 的实现路径（每个 FR 对应哪些代码位置）
2. 列出与 Constitution 不一致的现存 gap（要补的事项）
3. 不发起完整 implement——gap 自然分流到后续 issue / ADR / feature spec

---

## Current State Inventory

### Tech Stack（与 Constitution Principle II/III/V 对齐）

- Swift 6.0, strict concurrency
- iOS 18.0+ / macOS 15.0+ / watchOS 11.0+
- XcodeGen + 5 local SPM packages (VitalModels / HealthKitService / AIService / VitalUI / TelemetryKit)
- SwiftData 双 ModelConfiguration（Training CloudKit-synced + HealthCache local-only）
- ActivityKit (Rest Timer Live Activity), Swift Charts (Data Tab 趋势图)
- AI: Apple Intelligence Foundation Models 主 + 智谱 GLM-4-Flash fallback
- Multica daemon executes; FS/TL/Reviewer pipeline；project UUID `7adf8b88`，issue prefix `MY-*`

### Module Map (FR → 代码位置)

| FR | 实现位置 |
|----|----------|
| FR-001 (platform versions) | `project.yml options.deploymentTarget` |
| FR-002 (training data CloudKit-synced) | `Packages/VitalModels/` — Workout/WorkoutExercise/ExerciseSet/Exercise/WorkoutTemplate/TemplateExercise |
| FR-003 (HealthCache local-only) | `Packages/VitalModels/` HealthCacheEntry + `ModelConfiguration("HealthCache", cloudKitDatabase: .none)` |
| FR-004/005 (L1/L2 缓存策略) | `Packages/HealthKitService/` — HealthDataCache (L1 actor), L2 ↔ HealthCacheEntry; TTL/hydrate/persistInBackground |
| FR-006 (撤权清空) | `Packages/HealthKitService/` 中权限观察 + `invalidateAll()`/`removeAllAnchors()` ⚠️ 当前缺自动化测试 |
| FR-007/008/009 (Data Tab UI) | `VitalStride/Sources/DataView.swift` + `DataSections.swift` (app target, 因 platform-specific) |
| FR-010/011/012 (AI provider chain) | `Packages/AIService/` — AIProvider, ZhipuProvider, ChatMessage/Response; Apple Intelligence 接入主流程 |
| FR-013 (Rest Timer Live Activity) | iOS app target + ActivityKit Widget extension |
| FR-014 (i18n) | `Localizable.xcstrings` (Resources/) + SwiftLint `no_hardcoded_chinese` |
| FR-015 (TelemetryKit) | `Packages/TelemetryKit/` |
| FR-016 (no-PR git workflow) | `scripts/hooks/pre-commit`, `scripts/hooks/pre-push`, `AGENTS.md` §Git Workflow |

### Key View Files

详见 `vitalstride` skill 速查表，主要有：
- `VitalStride/Sources/ExercisePickerView.swift` — 选动作
- `VitalStride/Sources/ActiveWorkoutView.swift` — 训练进行中
- `VitalStride/Sources/WorkoutDetailView.swift` — 训练详情
- `VitalStride/Sources/WorkoutListView.swift` — 训练列表
- `VitalStride/Sources/StartWorkoutView.swift` — 开始训练
- `VitalStride/Sources/OverviewView.swift` — 主总览
- `VitalStride/Sources/OnboardingView.swift` — Onboarding
- `VitalStride/Sources/SettingsView.swift` — 设置
- `VitalStride/Sources/ExerciseSeeder.swift` + `VitalStride/Resources/exercises.json` — 动作种子

---

## Gap Analysis (vs Constitution v1.0.0)

下面是 baseline 与 Constitution 不完全对齐的地方。每条标记预期处理路径（issue / ADR / feature spec / skill）。

### G-01 HealthKit 撤权→清空 缺自动化测试

- **来源**: Constitution Principle I + FR-006
- **现状**: 业务逻辑已实现，但只能人工 QA 验证。每次 release 都靠 reviewer 记得跑一遍。
- **风险**: 高（隐私 P0）。任何重构 cache 层都可能悄悄破坏清除路径。
- **处理路径**: 新 Multica issue（标题示例：`[T??? ] [BASELINE] HealthKit 撤权完整清除自动化测试`），用 mock HKAuthorizationStatus 模拟撤权，断言 L1/L2/anchor/telemetry 全部清空。
- **优先级**: P1（不是 ship blocker，但越早越好）

### G-02 训练中断 → 显式恢复 UI 缺失

- **来源**: Spec Edge Cases + Out-of-Scope #7
- **现状**: SwiftData 保留 in-progress workout 草稿，但下次启动没有提示，用户可能丢失上下文。
- **处理路径**: 后续 feature spec — `specs/001-workout-resume-prompt/`，含 UX mock + 状态机。
- **优先级**: P2

### G-03 HealthKit 写入未实现

- **来源**: Out-of-Scope (V1 仅 read)
- **现状**: V1 完全 read-only；若产品要 "完成训练自动写入 HKWorkout"，需要新 feature。
- **处理路径**: 后续 feature spec — `specs/002-healthkit-workout-write/`，含权限请求、payload schema、隐私 review。
- **优先级**: P2（产品决策，暂搁置）

### G-04 Observer Query / 后台 sync 未实现

- **来源**: Out-of-Scope (V1 read-on-demand)
- **现状**: app 进入前台时才查 HealthKit；后台数据更新不会主动 push 缓存。
- **处理路径**: 后续 feature spec — `specs/003-healthkit-observer-query/`，含 BGProcessingTask + 配额评估。
- **优先级**: P3

### G-05 watchOS / macOS 独立 feature

- **来源**: ADR-0002 + Constitution Principle VII
- **现状**: 仅 companion；不立项。
- **处理路径**: 暂不动；重启时新 ADR 推翻 ADR-0002 + 新 feature spec。

### G-06 CONTEXT.md 数据架构细节与 Constitution / ADR 部分重复

- **来源**: 文档碎片化
- **现状**: HealthKit 缓存隐私约束在 CONTEXT.md + Constitution Principle I + ADR-0003 三个地方分别表述，措辞略有差异。
- **风险**: 三处不同步时 reviewer/agent 不知道以哪个为准。
- **处理路径**: 文档整理 issue — 用 Constitution 作 SoT，CONTEXT.md/ADR 引用 Constitution 章节而非重述；保留 ADR 历史 context 但删除约束重述。
- **优先级**: P2

### G-07 Pre-existing tech-debt：HealthKit 部分权限 UX

- **来源**: Spec Edge Cases
- **现状**: 受限数据显示 "未授权"，但 UI 没有 actionable 跳系统设置的入口。
- **处理路径**: 小型 UX issue（不需新 spec）。
- **优先级**: P2

### G-08 AI 失败时的 retry 风暴防护

- **来源**: Spec US3 Acceptance Scenario 3
- **现状**: 当前依赖 user-triggered，不主动重试；但若加自动 retry，需 backoff 策略。
- **处理路径**: 加 retry 时再写；当前 baseline OK。
- **优先级**: P3

### G-09 OverviewHealthSnapshotTests.loadAllMetrics flaky

- **来源**: 2026-06-26 MY-867 ship gate 卡两次（同时阻塞 MY-863 整条键盘 epic）
- **现状**: `VitalStrideTests/Sources/OverviewHealthSnapshotTests.swift:171-235` 的 `loadAllMetrics` 测试只 stub 了 5 个 `HealthSampleType.allCases` 中的 case（stepCount/heartRate/sleepAnalysis/bodyMass/activeEnergyBurned），其余 case **未注入 `AnchoredQueryResult`**，依赖 mock 默认行为。`load(cache:service:)` 并发查询多 type 时，未 stub 的 type 返回顺序非确定性可影响其它 type 的 cache fill 时序，导致 `state.snapshot.todaySteps == nil` 偶发。
- **正确修法**: 调用 `setupEmptyResults(for: mock, except: nil)`（如需扩展该 helper 支持 nil）或显式枚举所有 `HealthSampleType.allCases` 补空 stub，与 `loadAuthorizedNoData`（行 144-167）的覆盖方式一致。
- **风险**: 任何无关 ship 都可能被 quarantine（详 AGENTS.md §Pipeline Recovery），消耗 Hermes 配额。
- **处理路径**: 单独开 `[Flake]` issue 修测试 stub；不耦合到任何 feature PR。Constitution PR-4 保证 quarantine 期间不阻塞业务 patch。
- **优先级**: P1

---

## Phase Plan (existing-project audit pattern)

按 spec-kit existing-project 模式，每个 phase 是 audit + 补全，不重做：

### Phase 1: Specify (DONE — this commit)
- ✅ Constitution v1.0.0 落地
- ✅ Baseline spec.md 记录已实现状态
- ✅ Plan.md（本文）gap 分析
- ⏭️ 不生成 tasks.md — baseline 不需要 implementation tasks；gap 通过 G-XX 分流

### Phase 2: Gap → Issue 转化（异步）
- 把 G-01、G-02、G-06、G-07 在 Multica project `7adf8b88` 各开一个 issue（按需，不强制现在批量）
- 标题格式：`[BASELINE-G##] <Gap title>`
- 描述链接到本 plan 对应 G-XX 段落

### Phase 3: 后续 feature spec（新需求时）
- 任何新功能写在 `specs/NNN-<name>/`（`001`+ 起步）
- 走完整 spec-kit pipeline：`/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → 交 Multica（不跑 `/speckit-implement`）
- spec 必须 reference Constitution 章节而非重述约束

### Phase 4: Quarterly ADR / Spec Drift Review
- 每季度（或重大重构后）确认：
  - 所有 ADR 仍 load-bearing（否则新 ADR 推翻）
  - Constitution Quality Bars 与实际 reviewer 行为一致
  - Spec FR 与代码一致（受 SC-007 约束）
- 不一致时：先改文档（spec/constitution/ADR），再改代码

---

## Constitution Compliance Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. 健康数据隐私零妥协 | ⚠️ Mostly | G-01 缺自动化测试 |
| II. Swift 6 Strict Concurrency | ✅ | `project.yml settings.base SWIFT_VERSION: 6.0` |
| III. SPM Package 优先 | ✅ | 5 packages 实现 |
| IV. XcodeGen 是 SoT | ✅ | `project.yml` + `DEVELOPMENT_TEAM` 在 settings.base |
| V. AI 本地优先 + 国内 fallback | ✅ | Apple Intelligence + Zhipu |
| VI. I18n xcstrings 单源 | ✅ | 已迁移完（MY-882 后） |
| VII. 范围克制 watchOS/macOS companion | ✅ | ADR-0002 enforced |

---

## Not Doing

- 不跑 `/speckit-tasks` for baseline（不需要——已经 built）
- 不跑 `/speckit-implement` for baseline（更不需要）
- 不批量回创 issue —— gap 按需创建，由用户决定优先级

---

## References

- Spec: [spec.md](./spec.md)
- Constitution: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)
- ADRs: [docs/adr/](../../docs/adr/)
- 代码细节: [CONTEXT.md](../../CONTEXT.md)
- Agent 操作手册: [AGENTS.md](../../AGENTS.md)
