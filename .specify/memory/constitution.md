# VitalStride Constitution

VitalStride 是一个**健康数据收集 + AI 分析** iOS/macOS/watchOS App（个人项目）。本宪法是 audit 性的——每条原则都对应代码库已落地的事实，违反会被 hook / reviewer block。

---

## Core Principles

### I. 健康数据隐私零妥协 (NON-NEGOTIABLE)

HealthKit 数值不离设备、不入日志、权限撤销即清除。

- **本地隔离**：HealthKit L2 缓存（`HealthCacheEntry`）必须 `ModelConfiguration(cloudKitDatabase: .none)`，禁止参与 iCloud/CloudKit 同步。仅训练数据（`Workout`/`WorkoutExercise`/`ExerciseSet`/`Exercise`/`WorkoutTemplate`/`TemplateExercise`）允许 CloudKit-synced。
- **零日志**：os_log / print / 第三方 SDK 禁止输出实际健康数值（心率值、体重值、步数值、睡眠时长等）。仅可记录 sample type / 数量 / 时间范围等元数据。
- **撤销即清**：用户撤销 HealthKit 权限后必须立即完整清除 — `HealthDataCache.invalidateAll()` + 删除全部 `HealthCacheEntry` + `HealthKitAnchorStore.removeAllAnchors()` + 清零持久化 telemetry 计数器。

参考：ADR-0003 (HealthKit + SwiftData 双数据源)、CONTEXT.md §缓存层隐私合规约束。

### II. Swift 6 Strict Concurrency (NON-NEGOTIABLE)

`SWIFT_VERSION: 6.0` + strict concurrency，全 package 与 app target。引入新代码不得通过 `@preconcurrency` / `nonisolated(unsafe)` / `@unchecked Sendable` 绕过——必须用 actor / Sendable struct / MainActor isolation 表达。

例外仅限：Apple 系统 API 边界（HealthKit/CloudKit 旧签名）+ 必须在 ADR 中显式记录原因。

### III. SPM Package 优先 (NON-NEGOTIABLE)

业务逻辑住在 `Packages/`，app target 只放平台入口和 UI。

| Package | 职责 | 依赖 |
|---------|------|------|
| VitalModels | SwiftData models, enums, ModelContainerConfiguration | — |
| HealthKitService | HealthKit 查询、Anchor、HealthDataPoint、缓存 | VitalModels |
| AIService | AIProvider 协议、ZhipuProvider、ChatMessage/Response | — |
| VitalUI | 共享 UI 组件 | VitalModels |
| TelemetryKit | TelemetryEvent、TelemetryProvider、Console/Service | — |
| DesignKit | 设计语言：seed 配色 token（Seed/PrimaryPalette/Theme）+ SwiftUI 组件 | — |

**规则**：
- App target 不互相依赖，只依赖 packages。
- 新 AI provider = 在 `AIService` 实现 `AIProvider` 协议，不新建包。
- 改动仅涉及 `Packages/<X>/` 时，**必须**用 `swift build && swift test` 验证；禁止用 xcodebuild（慢且无意义）。
- 新增 package 需 ADR 并更新 `project.yml` + 本宪法表格。

参考：ADR-0004 (本地 SPM 包拆分)、ADR-0007 (TelemetryKit 独立包)、ADR-0008 (DesignKit 设计系统包)。

### IV. XcodeGen 是配置真理之源 (NON-NEGOTIABLE)

`project.yml` 是 Source of Truth；`VitalStride.xcodeproj/project.pbxproj` 是生成物。

- 任何长期 build setting（DEVELOPMENT_TEAM、签名、entitlements、target 配置）**必须**落在 `project.yml`。
- 禁止在 Xcode UI 改设置——任意 `xcodegen generate` 都会 reset。
- 改动 target 配置后必须 `xcodegen generate` 并 commit `.xcodeproj` 同步变更。
- 测试目录用目录源引用，新增测试文件无需 pbxproj 手动维护。

参考：vitalstride skill §"Xcode 项目配置"（账户/team reset 反复教训）。

### V. AI 用本地优先 + 国内 fallback，无第三方 SDK

AI provider chain：**Apple Intelligence Foundation Models 优先**（On-device, iOS 18.1+），**智谱 GLM-4-Flash fallback**（OpenAI-compatible REST via URLSession）。

- 禁止引入 OpenAI/Anthropic/Google **AI** SDK 等第三方包。
- API key 仅存 Keychain，不得硬编码。
- 新增 provider = 在 `AIService` 实现 `AIProvider` 协议接入 chain，不替换。
- **Telemetry 例外（narrow）**：允许引入**隐私合规的第三方 telemetry SDK**，当前限 **TelemetryDeck**，且只能作为 `TelemetryProvider` 消费强类型 `TelemetryEvent`（DEBUG 不发、EU 托管、标识符发送前哈希）；§I 健康隐私红线对该 provider 全额适用，不得引入任何接受自由字符串 / 原始健康数值的 API。AI provider 的「无第三方 SDK」约束不变。详见 [ADR-0011](../../docs/adr/0011-telemetrydeck-first-production-provider.md)。
- **诊断通道例外（narrow）**：崩溃 / 挂起（hang）诊断由 **Apple MetricKit** 采集，经**同一个** TelemetryDeck 通道上报——不引入第二个第三方 SDK。「typed-event-only」被收窄而非取消：新增**封闭类型** `TelemetryDiagnostic`（结构化 payload：诊断类别 + OS/版本元数据 + 由 `MXCallStackTree` 派生的 `frames: [String]` 符号列表），provider 仅新增 `record(_:)` sink 消费该封闭类型，**仍不接受**调用点传入的任意字符串。栈经 `DiagnosticSanitizer` 纯函数强制清洗（只留符号帧 + 偏移），§I 健康隐私红线全额适用，配 allow-list/fuzz 测试锁死。DEBUG 不发。详见 [ADR-0012](../../docs/adr/0012-metrickit-diagnostics-via-telemetrydeck.md)。

参考：ADR-0005 (AI ProviderChain)、ADR-0011 (TelemetryDeck 首个生产 telemetry provider)、ADR-0012 (MetricKit 诊断经 TelemetryDeck 上报)。

### VI. I18n：xcstrings 单源 + 无硬编码 (NON-NEGOTIABLE)

- UI 字符串必须用 `String(localized: "key", comment: ...)` 或 `NSLocalizedString("key", ...)` 引用 catalog。
- `Localizable.xcstrings` 是唯一翻译源，**严禁同名 `.strings` / `.stringsdict` 共存**（Xcode 26 硬错 + pre-push 必失败，详见 ADR-0007 教训 / MY-882）。
- SwiftLint `no_hardcoded_chinese` warning（非阻塞但代码 review 必处理）。
- 工具：`python3 scripts/i18n_extract_hardcoded.py` 找漏迁移；`python3 scripts/i18n_check_lproj_parity.py` 查覆盖率。

参考：AGENTS.md §I18n、`.swiftlint.yml`。

### VII. 范围克制：watchOS/macOS 是 companion

当前阶段：iOS 是主战场，macOS/watchOS 是 companion target，**不立项专属 feature**。

- iOS 全功能；macOS 复用 iOS 视图（SwiftUI 自适应）；watchOS 仅展示训练 + 健康概览。
- 不为 watchOS 写独立 complication / 独立训练流程；不为 macOS 写 menubar / shortcut intent 等。
- **例外（ADR-0010）**：watchOS 实时心率训练流程（Watch `HKWorkoutSession` + `WatchConnectivity` 把实时心率推给 iOS active-workout）已被显式 promote，属 ADR-0002 的 narrow 例外，可立项。此例外仅限该实时心率路径；其余 watchOS/macOS 专属 feature 仍冻结。
- 重启其它 watchOS/macOS 专属 feature 需新 ADR（推翻或再开 ADR-0002 例外）。

参考：ADR-0002 (deferred watchOS / macOS feature work)、ADR-0010 (promote watchOS live heart-rate)。

---

## Module Architecture

```
App targets (iOS / macOS / watchOS)
    │  仅含入口、平台 UI、Live Activity widget
    ↓
VitalUI ←── VitalModels
    │            ↑
    ↓            │
HealthKitService ┘
    AIService    (独立, 无依赖)
    TelemetryKit (独立, 无依赖)
    DesignKit    (独立, 无依赖 — 设计系统 token + 组件)
```

**Rules**：
- 依赖单向：app → packages，packages 之间最多一层依赖（VitalUI → VitalModels，HealthKitService → VitalModels）。
- `DataView` / `DataSections` 保留在 app target（不在 package），因为耦合 platform-specific 行为。
- Rest Timer 用 Live Activity（iOS 16.1+ ActivityKit）渲染——见 ADR-0006。

---

## Data & Persistence

**SwiftData，双 ModelConfiguration**：

| Configuration | Models | CloudKit | 用途 |
|---------------|--------|----------|------|
| Default (Training) | Workout, WorkoutExercise, ExerciseSet, Exercise, WorkoutTemplate, TemplateExercise | ✅ synced | 训练数据多设备同步 |
| `"HealthCache"` | HealthCacheEntry | ❌ `.none` | HealthKit L2 本地缓存 |

**HealthKit 两层缓存**：
- **L1**: `HealthDataCache` actor（纯内存、零延迟热路径，进程生命周期）
- **L2**: `HealthCacheEntry` SwiftData（本地磁盘、跨启动、CloudKit 隔离）
- **TTL**: 默认 1h；stale-serve-then-refresh（过期数据立即返回 + 后台刷新）
- **Anchor**: 通过 `HealthKitAnchorStore` 持久化 HKQueryAnchor，增量查询新数据
- **冷启动**: `hydrate()` 从 L2 预加载 `overviewTypes` 到 L1

**禁止**：使用 NSUbiquitousKeyValueStore / 第三方 iCloud 包装 / 任何 HealthKit 数值参与 CloudKit / 任何健康数值进入 NSUserDefaults。

参考：CONTEXT.md §Data Architecture Decisions、ADR-0003。

---

## Development Workflow

### Git: PR-Required Workflow (NON-NEGOTIABLE)

| 角色 | 推到哪 | 推什么 |
|------|--------|--------|
| Fullstack (FS) | `github` remote | `agent/<issue-key>-<task-id-short>` + 开 PR (`gh pr create`) |
| Team Lead (TL) | `github` remote | 审 CI 绿 + review 后 `gh pr merge` |
| AI Reviewer | （在 PR 上 review） | review PR commits |

所有代码只能经 PR 进 `main`。`main` 受 branch protection 保护：**6 个 required status
check**（`Lint & policy` + 5× `SPM …`）+ **1 个 review** + **enforce_admins=true** —— 红的 CI
或未 review 的改动进不了 main，admin 也不例外。`scripts/hooks/pre-commit` 禁止直接 commit 到
main；`pre-push` 本地跑全量 build/test + lint 作为 PR 前的快速门。详见 [ADR-0009](../../docs/adr/0009-pr-required-workflow.md)、AGENTS.md §Git Workflow。

### Commit Message 约定

- **Agent 分支**：每个 commit **建议**含 `MY-\d+`（issue key），subject 或 body 任一位置（约定，
  非强制 —— pre-push 的 MY-key 强制已移除，见 commit `13505cd`）。
- **工程改动 commit**：用 `chore(...)` / `docs(...)` / `ci(...)` 前缀，无 issue key 时加
  `(retro A-XX)` 占位以保留追溯。
- 历史教训：2026-06 retro 发现 92% commit 缺 issue key —— 保留 MY-key 约定以维持可追溯。

### Build & Test Gate

- **Packages/ 仅改动** → `swift build && swift test`（per package）
- **App target 改动** → `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation`
- pre-push hook 自动选择路径（SPM-only fast path）
- 共享 `<git-common-dir>/derived-data` + `flock` 保护并发 build
- 纯 docs/hooks/scripts 改动 skip build

### 平台 Deployment Target

- iOS 18.0 / macOS 15.0 / watchOS 11.0（`project.yml options.deploymentTarget`）
- 降级需新 ADR + 全 package compatibility 审查

### Issue Tracker / Spec Execution

- **Multica** 项目 UUID `7adf8b88`，issue prefix `MY-*`
- 每个 issue 标题 `[T###] [Story] Brief description`（spec-kit handoff 约定）
- Hermes 端写 spec/plan/tasks，**`/speckit-implement` 不使用**——tasks.md 通过 `multica-quick-issue` 批量入 Multica，TL → Planner → FS → Reviewer pipeline 执行
- 每 feature 一个 Multica project（不要 phase 多项目）

---

## Cross-Cutting Quality Bars

> AI Reviewer / TL 唯一权威 finding 源。task body 引用本节，不重述。

### P0 — Ship Blocker (🔴 FAIL)

- **A. 范围纪律**：PR 只能改 task 的 "Files in scope" + 对应测试。删除/改动 sibling task 的文件 = 🔴 FAIL（关 PR 重派，不 rebase）。
- **B. 健康隐私**：任何 HealthKit 数值进 log / 进 CloudKit / 进 NSUserDefaults = 🔴 FAIL（Principle I）。
- **C. Strict Concurrency**：新增 `@preconcurrency` / `nonisolated(unsafe)` / `@unchecked Sendable` 未在 ADR 记录 = 🔴 FAIL（Principle II）。
- **D. 错误处理**：production 代码新增 `fatalError` / `try!` / `as!` = 🔴 FAIL。HealthKit/AI/网络错误必须 graceful degradation。
- **E. XcodeGen Drift**：直接改 `.xcodeproj` 不改 `project.yml` = 🔴 FAIL（Principle IV）。
- **F. xcstrings 共存**：与 `Localizable.xcstrings` 同名的 `.strings`/`.stringsdict` = 🔴 FAIL（Principle VI）。

### P1 — Must Fix (🟡)

- **G. I18n**：硬编码用户可见字符串（中/英）= P1。功能正确时 → 🟢 PASS WITH FOLLOW-UP + 拆 follow-up sub-issue。
- **H. Accessibility**：Dynamic Type 支持、hit target ≥ 44pt、decorative icon hidden。
- **I. Test Coverage**：新 public API 必须有 round-trip 测试；新 SwiftUI view 至少 2 个 Preview。

### P2 — Nice to Have (ℹ️，never blocks merge)

- 风格、注释优化、命名建议。

### J — Ship-Gate Failure Classification (P0 verdict aggregation modifier)

Ship gate (`xcodebuild test` / `swift test` 在 pre-push hook) 失败时，Reviewer / TL **必须**先判定失败是否由当前 patch 引入：

- **Patch-induced**：失败 test 文件 ∈ `git diff github/main...HEAD --name-only`，或失败 test 所属 module 有源码改动 → 正常 P0 FAIL，回 FS
- **Pre-existing flake**：失败 test 与当前 patch 无源码关联 → **不计入 verdict**，走 AGENTS.md §Pipeline Recovery → Quarantine 路径

把 pre-existing flake 当作 P0 FAIL 阻塞 patch = 宪法违规（reviewer 责任）。

### Verdict Aggregation

- 任意 P0 → 🔴 FAIL
- 无 P0 + 有 P1 + **功能正确** → 🟢 PASS WITH FOLLOW-UP（拆 sub-issue，当前 PR 立即 merge）
- 无 P0 + 有 P1 + **功能 broken** → 🟡 CHANGES REQUESTED（回 FS）
- 仅 P2 / 无 finding → 🟢 PASS

---

## Pipeline Recovery Protocols

> Pipeline 失败时 agent 行为的宪法级约束。具体命令实现见 `AGENTS.md` §Pipeline Recovery。

### PR-1: 禁止 `human_triage` 作为常规状态

`waiting_on=human_triage` 仅在以下场景允许：
- Constitution P0 违规需人判断（例如隐私越界争议、范围争议）
- 自动恢复（Hermes）尝试 3 次后仍 fail 同一根因

其它 infra failure（CLI routing、runtime crash、quarantined flake、限流、网络）一律 Hermes auto-dispatch，TL **禁止**直接打 `human_triage` 标。

### PR-2: Sub-issue 幂等

Planner Lead / TL 创建 sub-issue 前必须查同 parent 的 alive (`todo`/`in_progress`/`in_review`/`blocked`) sub-issue；若 Scope 重合（同 Branch / 同 title trim / files ≥80% 重合）→ 复用而非新建。重复创建 sibling = 宪法违规。

历史教训：MY-857 / MY-859 / MY-999 三胞胎，同一 scope 三条独立 issue 同时被 dispatch，导致并行修改冲突 + run-count 浪费。

### PR-3: Run-Count Guard 区分 `run_attempts` vs `infra_failures`

- `run_attempts`：code-review iterate、patch-induced 测试失败（计 budget，默认 15）
- `infra_failures`：CLI 错误、runtime crash、quarantined flake、auth/network（不计 budget）

把 infra failure 计入 `run_attempts` 浪费 budget 并提早 stall pipeline = 宪法违规。

### PR-4: Ship-Gate Failure Classification

参见 Cross-Cutting Quality Bars §J。

### PR-5: Startup Scan

TL 每次 pipeline 起手前必须扫描：
- `gh pr list --state open`：PR 工作流下 open PR 是正常状态 —— TL 应 review 并推进（CI 绿 +
  review 后 `gh pr merge`），而非视为违规。长时间停滞的 PR 需 comment 跟进。
- 同 parent alive sub-issue（PR-2 前置）

## Governance

本宪法管辖 VitalStride 所有开发工作。所有 AI/人类贡献者（FS/TL/Reviewer，含 Codex/Claude/Hermes 子代理）必须读取并遵守。

- 任何与本宪法冲突的 PR 必须修改 PR 或修宪法（先 ADR）。
- **修改宪法**：新 ADR + 本文件 patch + 版本 bump + 在 PR 描述 link 到 ADR。
- 版本规则（语义化）：
  - MAJOR — 删除/反转原则；MINOR — 新增原则/新 Quality Bar；PATCH — 文字澄清不改语义
- 与本宪法相关：AGENTS.md（agent 操作手册）、CONTEXT.md（数据架构细节）、`docs/adr/`（决策档案）、`scripts/hooks/`（强制规则机器实现）。

**Version**: 2.3.0 | **Ratified**: 2026-06-25 | **Last Amended**: 2026-07-21

> 2.3.0（MINOR，收窄 §V telemetry 例外）：崩溃 / 挂起诊断由 **Apple MetricKit** 采集、经**同一** TelemetryDeck 通道上报（不引第二个 SDK）；「typed-event-only」收窄为允许一个封闭的 `TelemetryDiagnostic` 诊断通道（provider 新增 `record(_:)` sink），栈经 `DiagnosticSanitizer` 强制清洗、§I 全额适用（[ADR-0012](../../docs/adr/0012-metrickit-diagnostics-via-telemetrydeck.md)）。触发自 ADR-0011 自列的 revisit trigger：TestFlight-only app 的所有 Apple 自动诊断管道为空。

> 2.2.0（MINOR，放松 §V 约束）：允许**隐私合规的第三方 telemetry SDK**（narrow 例外，当前限 TelemetryDeck，只能作为 `TelemetryProvider` 消费强类型 `TelemetryEvent`），回答 ADR-0007 遗留的「first real provider」决策（[ADR-0011](../../docs/adr/0011-telemetrydeck-first-production-provider.md)）。§V 的 AI provider「无第三方 SDK」约束与 §I 健康隐私红线均不变。

> 2.1.0（MINOR，放松 §VII 约束）：watchOS 实时心率训练流程被显式 promote 为 ADR-0002 的 narrow 例外（[ADR-0010](../../docs/adr/0010-promote-watchos-live-heart-rate.md)）。companion-first 与「promote 须 ADR」的门槛不变，§I 隐私红线对该路径全额适用。

> 2.0.0（MAJOR，反转原则）：Git 工作流由 no-PR 反转为 PR-required（[ADR-0009](../../docs/adr/0009-pr-required-workflow.md) supersede ADR-0001）。`main` 改由 branch protection（6 required checks + 1 review + enforce_admins）强制，替代已移除的 pre-push main-only / MY-key 强制。
